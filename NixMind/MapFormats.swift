import Foundation

// Native files and map archives preserve the whole workbook. FreeMind is a single-sheet exchange format.
enum MapFormats {
    static let nativeType = "com.nixmind.map"
    static let archiveType = "org.xmind.workbook"
    static let freeMindType = "org.freemind.map"
    static func decode(_ data: Data, type: String) throws -> MindMap { try decodeBook(data, type: type).activeMap }
    static func decodeBook(_ data: Data, type: String) throws -> MindBook {
        guard data.count <= 64_000_000 else { throw MapError.invalid }
        let book: MindBook
        switch type {
        case archiveType: book = try readArchiveBook(data)
        case freeMindType: book = MindBook(map: try FreeMindReader().read(data))
        default:
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            if json?["sheets"] != nil { book = try JSONDecoder().decode(MindBook.self, from: data) }
            else { book = MindBook(map: try JSONDecoder().decode(MindMap.self, from: data)) }
        }
        try book.validate(); return book
    }
    static func encode(_ map: MindMap, type: String) throws -> Data {
        try map.validate()
        if type == nativeType {
            let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            return try encoder.encode(map)
        }
        return try encodeBook(MindBook(map: map), type: type)
    }
    static func encodeBook(_ book: MindBook, type: String) throws -> Data {
        try book.validate()
        switch type {
        case archiveType: return try writeArchiveBook(book)
        case freeMindType: return writeFreeMind(book.activeMap)
        default:
            let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            return try encoder.encode(book)
        }
    }
    private static func temporary<T>(_ body: (URL) throws -> T) throws -> T {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: url) }
        return try body(url)
    }
    @discardableResult private static func run(_ path: String, _ arguments: [String], directory: URL? = nil) throws -> Data {
        let process = Process(); process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments; process.currentDirectoryURL = directory
        let output = Pipe(); process.standardOutput = output; process.standardError = FileHandle.nullDevice
        try process.run(); let result = output.fileHandleForReading.readDataToEndOfFile(); process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw MapError.archive }; return result
    }
    static func readArchive(_ data: Data) throws -> MindMap { try readArchiveBook(data).activeMap }
    static func readArchiveBook(_ data: Data) throws -> MindBook {
        try temporary { directory in
            let archive = directory.appendingPathComponent("map.xmind"); try data.write(to: archive)
            let listing = try run("/usr/bin/unzip", ["-l", archive.path, "content.json"])
            guard let text = String(data: listing, encoding: .utf8) else { throw MapError.archive }
            let sizes = text.split(separator: "\n").compactMap { line -> Int? in
                let fields = line.split(whereSeparator: \.isWhitespace)
                return fields.last == "content.json" ? fields.first.flatMap { Int($0) } : nil
            }
            guard sizes.count == 1, sizes[0] <= 64_000_000 else { throw MapError.archive }
            let json = try run("/usr/bin/unzip", ["-p", archive.path, "content.json"])
            guard let sheets = try JSONSerialization.jsonObject(with: json) as? [[String: Any]], !sheets.isEmpty, sheets.count <= 500 else { throw MapError.invalid }
            var maps: [MapSheet] = []; var active: String?
            for sheet in sheets {
                guard let root = sheet["rootTopic"] as? [String: Any] else { throw MapError.invalid }
                var topics: [Topic] = []; var missingPositions = false
                func visit(_ object: [String: Any], parent: String?, depth: Int, branch: Int, position: CGPoint) throws {
                    guard depth < 128, topics.count < MindMap.capacity else { throw MapError.invalid }
                    let point = object["position"] as? [String: Double]
                    if point == nil { missingPositions = true }
                    var topic = Topic(id: object["id"] as? String ?? UUID().uuidString, parentID: parent, title: object["title"] as? String ?? "Idea", x: point?["x"] ?? position.x, y: point?["y"] ?? position.y, color: branch % 6)
                    topic.note = ((object["notes"] as? [String: Any])?["plain"] as? [String: String])?["content"] ?? ""
                    let extra = object["nixmind"] as? [String: Any]
                    topic.color = extra?["color"] as? Int ?? topic.color
                    topic.slot = extra?["slot"] as? Int ?? (depth == 1 ? branch : nil)
                    if let style = extra?["style"] as? [String: Any] { topic.style = try JSONDecoder().decode(TopicStyle.self, from: JSONSerialization.data(withJSONObject: style)) }
                    if let value = extra?["structure"] as? String { topic.structure = NodeStructure(rawValue: value) }
                    topics.append(topic)
                    let children = object["children"] as? [String: Any] ?? [:]
                    if ["detached", "summary", "callout"].contains(where: { !(children[$0] as? [Any] ?? []).isEmpty }) || object["image"] != nil || ["boundaries", "relationships", "summaries"].contains(where: { !(object[$0] as? [Any] ?? []).isEmpty }) {
                        throw MapError.unsupported("Images, floating topics, summaries and boundaries are not supported. Import a text topic tree.")
                    }
                    for (i, child) in (children["attached"] as? [[String: Any]] ?? []).enumerated() {
                        let offset = depth == 0 ? MindMap.slots[i % 6] : CGPoint(x: topic.x < 0 ? -300 : 300, y: Double(i) * 100)
                        try visit(child, parent: topic.id, depth: depth + 1, branch: depth == 0 ? i : branch, position: CGPoint(x: topic.x + offset.x, y: topic.y + offset.y))
                    }
                }
                if !(sheet["relationships"] as? [Any] ?? []).isEmpty { throw MapError.unsupported("Relationships are not supported yet. Export a text-only topic tree.") }
                try visit(root, parent: nil, depth: 0, branch: 0, position: .zero)
                var map = MindMap(topics: topics); try map.validate()
                if missingPositions { map.arrange() }
                let item = MapSheet(id: sheet["id"] as? String ?? UUID().uuidString, title: sheet["title"] as? String ?? "Sheet \(maps.count + 1)", map: map)
                maps.append(item)
                if (sheet["nixmind"] as? [String: Any])?["active"] as? Bool == true { active = item.id }
            }
            var book = MindBook(); book.sheets = maps; book.activeSheetID = active ?? maps[0].id
            try book.validate(); return book
        }
    }
    static func writeArchive(_ map: MindMap) throws -> Data { try writeArchiveBook(MindBook(map: map)) }
    static func writeArchiveBook(_ book: MindBook) throws -> Data {
        try temporary { directory in
            let sheets: [[String: Any]] = try book.sheets.map { sheet in
                let children = sheet.map.adjacency
                func object(_ node: Topic) throws -> [String: Any] {
                    var extra: [String: Any] = ["color": node.color]
                    if let slot = node.slot { extra["slot"] = slot }
                    if let style = node.style { extra["style"] = try JSONSerialization.jsonObject(with: JSONEncoder().encode(style)) }
                    if let structure = node.structure { extra["structure"] = structure.rawValue }
                    let style = node.appearance
                    var properties: [String: Any] = ["fo:font-family": style.fontFamily == "System" ? "Helvetica Neue" : style.fontFamily, "fo:font-size": style.fontSize, "fo:font-weight": style.bold ? "bold" : "normal", "fo:font-style": style.italic ? "italic" : "normal", "fo:text-align": style.alignment.rawValue, "svg:fill": node.resolvedFill.hexString, "fo:color": node.resolvedText.hexString, "border-line-color": node.resolvedBorder.hexString, "border-line-width": style.borderWidth]
                    if style.underline { properties["fo:text-decoration"] = "underline" }
                    var result: [String: Any] = ["id": node.id, "class": "topic", "title": node.title, "position": ["x": node.x, "y": node.y], "nixmind": extra, "notes": ["plain": ["content": node.note]], "style": ["properties": properties]]
                    let attached = children[node.id] ?? []
                    if !attached.isEmpty { result["children"] = ["attached": try attached.map(object)] }
                    if node.parentID == nil { result["structureClass"] = node.structure == .leftToRight ? "org.xmind.ui.logic.right" : (node.structure == .rightToLeft ? "org.xmind.ui.logic.left" : "org.xmind.ui.map.unbalanced") }
                    return result
                }
                return ["id": sheet.id, "class": "sheet", "title": sheet.title, "rootTopic": try object(sheet.map.root), "topicPositioning": "fixed", "nixmind": ["active": sheet.id == book.activeSheetID]]
            }
            let files: [String: Any] = ["content.json": sheets, "metadata.json": ["creator": ["name": "Nix Mind", "version": "1.0.3"]], "manifest.json": ["file-entries": ["content.json": [:], "metadata.json": [:]]]]
            for (name, object) in files { try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]).write(to: directory.appendingPathComponent(name)) }
            let archive = directory.appendingPathComponent("map.xmind")
            try run("/usr/bin/zip", ["-q", archive.path, "content.json", "metadata.json", "manifest.json"], directory: directory)
            return try Data(contentsOf: archive)
        }
    }
    static func writeFreeMind(_ map: MindMap) -> Data {
        func escape(_ text: String) -> String {
            text.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "\"", with: "&quot;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\n", with: "&#10;").replacingOccurrences(of: "\r", with: "&#13;").replacingOccurrences(of: "\t", with: "&#9;")
        }
        let children = map.adjacency
        func node(_ topic: Topic) -> String {
            let note = topic.note.isEmpty ? "" : "<richcontent TYPE=\"NOTE\"><html><head/><body><p>\(escape(topic.note))</p></body></html></richcontent>"
            let style = topic.style.flatMap { try? JSONEncoder().encode($0).base64EncodedString() } ?? ""
            return "<node ID=\"\(escape(topic.id))\" TEXT=\"\(escape(topic.title))\" POSITION=\"\(map.direction(of: topic.id) < 0 ? "left" : "right")\" NIX_X=\"\(topic.x)\" NIX_Y=\"\(topic.y)\" NIX_COLOR=\"\(topic.color)\" NIX_SLOT=\"\(topic.slot ?? -1)\" NIX_STYLE=\"\(style)\" NIX_STRUCTURE=\"\(topic.structure?.rawValue ?? "")\">\(note)\((children[topic.id] ?? []).map(node).joined())</node>"
        }
        return Data("<?xml version=\"1.0\" encoding=\"UTF-8\"?><map version=\"1.0.1\">\(node(map.root))</map>".utf8)
    }
}
private final class FreeMindReader: NSObject, XMLParserDelegate {
    var topics: [Topic] = []
    var stack: [String] = []
    var richType: String?
    var richText = ""
    var inBody = false
    var failure: Error?
    func read(_ data: Data) throws -> MindMap {
        let parser = XMLParser(data: data); parser.delegate = self; parser.shouldResolveExternalEntities = false
        guard parser.parse(), failure == nil, !topics.isEmpty else { throw failure ?? MapError.invalid }
        return MindMap(topics: topics)
    }
    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String]) {
        if name == "node" {
            guard stack.count < 128, topics.count < MindMap.capacity else { failure = MapError.invalid; parser.abortParsing(); return }
            let parent = stack.last
            let parentNode = topics.first { $0.id == parent }
            let siblings = topics.filter { $0.parentID == parent }.count
            let branch = parentNode?.parentID == nil ? siblings : (parentNode?.color ?? 0)
            let offset = parent == nil ? CGPoint.zero : (parentNode?.parentID == nil ? MindMap.slots[siblings % 6] : CGPoint(x: (parentNode!.x < 0 ? -260 : 260), y: Double(siblings) * 96))
            var x = (parentNode?.x ?? 0) + offset.x
            if let side = attributes["POSITION"] { x = abs(x) * (side == "left" ? -1 : 1) }
            let slot = Int(attributes["NIX_SLOT"] ?? "")
            topics.append(Topic(id: attributes["ID"] ?? UUID().uuidString, parentID: parent, title: attributes["TEXT"] ?? "Idea", x: Double(attributes["NIX_X"] ?? "") ?? x, y: Double(attributes["NIX_Y"] ?? "") ?? ((parentNode?.y ?? 0) + offset.y), color: Int(attributes["NIX_COLOR"] ?? "") ?? branch % 6, slot: slot == -1 ? nil : (slot ?? (parentNode?.parentID == nil ? siblings : nil))))
            if let value = attributes["NIX_STYLE"], let data = Data(base64Encoded: value) { topics[topics.count - 1].style = try? JSONDecoder().decode(TopicStyle.self, from: data) }
            if let value = attributes["NIX_STRUCTURE"] { topics[topics.count - 1].structure = NodeStructure(rawValue: value) }
            stack.append(topics.last!.id)
        } else if name == "richcontent" { richType = attributes["TYPE"]; richText = "" }
        else if name == "body" { inBody = true }
        else if name == "br", inBody { richText += "\n" }
    }
    func parser(_ parser: XMLParser, foundCharacters string: String) { if richType != nil && inBody { richText += string } }
    func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
        if name == "node" { _ = stack.popLast() }
        else if name == "body" { inBody = false }
        else if name == "p", inBody { richText += "\n" }
        else if name == "richcontent" {
            if let index = topics.firstIndex(where: { $0.id == stack.last }) {
                if richType == "NOTE" { topics[index].note = richText.trimmingCharacters(in: .newlines) }
                if richType == "NODE" { topics[index].title = richText.trimmingCharacters(in: .whitespacesAndNewlines) }
            }
            richType = nil
        }
    }
}
