import Foundation
import AppKit

@main struct CoreTests {
    static var count = 0
    static func check(_ value: @autoclosure () -> Bool, _ label: String) {
        guard value() else { fatalError("FAIL: \(label)") }; count += 1; print("✓ \(label)")
    }
    static func rejects(_ label: String, _ body: () throws -> Void) {
        do { try body(); fatalError("Expected rejection: \(label)") } catch { count += 1; print("✓ \(label)") }
    }
    static func patch(_ ops: [[String: Any]], on map: MindMap) throws -> MapPatch {
        try JSONDecoder().decode(MapPatch.self, from: JSONSerialization.data(withJSONObject: ["version": 1, "documentID": map.root.id, "baseFingerprint": AIMap.fingerprint(map), "operations": ops]))
    }
    static func sameMap(_ a: MindMap, _ b: MindMap) -> Bool {
        a.root.id == b.root.id && a.topics.count == b.topics.count && a.topics.allSatisfy { node in
            b.topic(node.id) == node && a.children(of: node.id).map(\.id) == b.children(of: node.id).map(\.id)
        }
    }
    static func sameBook(_ a: MindBook, _ b: MindBook) -> Bool {
        a.activeSheetID == b.activeSheetID && a.sheets.count == b.sheets.count && zip(a.sheets,b.sheets).allSatisfy { x,y in x.id == y.id && x.title == y.title && sameMap(x.map,y.map) }
    }
    static func main() throws {
        let executable = "/Applications/Nix Mind.app/Contents/MacOS/Nix Mind"
        for format in MCPClientFormat.allCases {
            let text = MCPConfiguration.json(executable: executable, format: format)
            let object = try JSONSerialization.jsonObject(with: Data(text.utf8)) as! [String: Any]
            let key = format == .vscode ? "servers" : "mcpServers"
            let servers = object[key] as! [String: [String: Any]]
            check(servers.count == 1 && servers["nix-mind"] != nil, "\(format.rawValue) puts the server directly in \(key)")
            let entry = servers["nix-mind"]!
            check(entry["command"] as? String == executable && entry["args"] as? [String] == ["--mcp"], "\(format.rawValue) preserves executable paths with spaces")
            check(entry["url"] == nil && object[format == .vscode ? "mcpServers" : "servers"] == nil, "\(format.rawValue) does not nest another client format or invent an HTTP URL")
            if format == .vscode { check(entry["type"] as? String == "stdio", "VS Code explicitly launches a stdio server") }
        }
        var map = MindMap.blank(); let root = map.root.id
        check(map.topics.count == 1, "New map contains one central topic")
        for _ in 0..<120 { _ = map.addChild(to: root)! }
        check(map.children(of: root).count == 120, "Central topic grows beyond six branches to 120")
        check(Set(map.topics.map { "\($0.x),\($0.y)" }).count == 121, "Layout gives all branches distinct positions")
        let branches = map.children(of: root)
        var overlaps = false
        for i in branches.indices { for j in branches.indices where j > i {
            let a = branches[i], b = branches[j]
            let r1 = CGRect(x: a.x - a.layoutSize.width / 2, y: a.y - a.layoutSize.height / 2, width: a.layoutSize.width, height: a.layoutSize.height)
            let r2 = CGRect(x: b.x - b.layoutSize.width / 2, y: b.y - b.layoutSize.height / 2, width: b.layoutSize.width, height: b.layoutSize.height)
            if r1.intersects(r2) { overlaps = true }
        } }
        check(!overlaps, "Automatic root layout avoids overlapping cards")
        let first = branches[0].id, second = branches[1].id
        let child = map.addChild(to: first)!, grandchild = map.addChild(to: map.children(of: first)[0].id)!
        let sibling = map.addSibling(to: child)!
        check(map.topic(sibling)!.parentID == first, "Sibling shares its parent's ID")
        let before = map; map.moveSubtree(first, dx: 80, dy: -25)
        check(map.topic(grandchild)!.x == before.topic(grandchild)!.x + 80 && map.topic(grandchild)!.y == before.topic(grandchild)!.y - 25, "Dragging moves the complete subtree")
        check(map.topic(second) == before.topic(second), "Dragging preserves unrelated branches")
        let firstIndex = map.topics.firstIndex { $0.id == first }!
        map.topics[firstIndex].structure = .rightToLeft; map.arrange(around: first)
        check(map.direction(of: first) == -1 && map.children(of: first).allSatisfy { $0.x < map.topic(first)!.x }, "Right-to-left structure places children and controls on the left")
        map.topics[firstIndex].structure = .leftToRight; map.arrange(around: first)
        check(map.direction(of: first) == 1 && map.children(of: first).allSatisfy { $0.x > map.topic(first)!.x }, "Left-to-right structure places children and controls on the right")
        var rootLayout = map; rootLayout.topics[0].structure = .rightToLeft; rootLayout.arrange()
        check(rootLayout.children(of: root).allSatisfy { $0.x < rootLayout.root.x }, "Root structure can put all 120 branches on the left")
        rootLayout.topics[0].structure = .leftToRight; rootLayout.arrange()
        check(rootLayout.children(of: root).allSatisfy { $0.x > rootLayout.root.x }, "Root structure can put all branches on the right")
        var styled = map
        let index = styled.topics.firstIndex { $0.id == child }!
        styled.topics[index].title = "Tiếng Việt & <ideas> \"new\" 🧠\nSecond line"
        styled.topics[index].note = "Notes & <markup>\nAnother line"
        var appearance = TopicStyle(); appearance.fontFamily = "Georgia"; appearance.fontSize = 28; appearance.bold = true; appearance.italic = true; appearance.underline = true; appearance.strikethrough = true; appearance.alignment = .right; appearance.shape = .diamond; appearance.fillColor = "#224466DD"; appearance.textColor = "#FFFFEEFF"; appearance.borderColor = "#EF4466FF"; appearance.borderWidth = 4.5
        styled.topics[index].style = appearance; styled.topics[index].structure = .rightToLeft
        try styled.validate()
        check(styled.topics[index].resolvedFill.hexString == "#224466DD", "RGBA fill is preserved exactly")
        check(styled.topics[index].textAttributes()[.underlineStyle] as? Int == NSUnderlineStyle.single.rawValue, "Underline is part of rendered text attributes")
        check(styled.topics[index].font().pointSize == 28, "Selected font size is used by native rendering")
        let fontSize = styled.topics[index].appearance.fontSize; styled.arrange()
        check(styled.topics[index].appearance.fontSize == fontSize, "Auto layout preserves user-selected font size")
        for type in [MapFormats.nativeType, MapFormats.archiveType, MapFormats.freeMindType] {
            let roundtrip = try MapFormats.decode(MapFormats.encode(styled, type: type), type: type)
            check(sameMap(roundtrip, styled), "\(type): full topic, Unicode, structure and style round-trip")
        }
        var book = MindBook(map: styled)
        let other = MapSheet(title: "Research", map: .blank()); book.sheets.append(other); book.activeSheetID = other.id
        for type in [MapFormats.nativeType, MapFormats.archiveType] {
            let decoded = try MapFormats.decodeBook(MapFormats.encodeBook(book, type: type), type: type)
            check(sameBook(decoded, book), "\(type): all sheets, names, IDs and active sheet round-trip")
        }
        let legacy = try MapFormats.encode(styled, type: MapFormats.nativeType)
        let migrated = try MapFormats.decodeBook(legacy, type: MapFormats.nativeType)
        check(migrated.sheets.count == 1 && migrated.activeMap == styled, "Legacy single-map files migrate without losing data")
        let mm = try MapFormats.decodeBook(MapFormats.encodeBook(book, type: MapFormats.freeMindType), type: MapFormats.freeMindType)
        check(mm.sheets.count == 1 && mm.activeMap == other.map, "FreeMind exports only the chosen active sheet")
        let simple = Data("<map version=\"1.0.1\"><node TEXT=\"External map\"><node TEXT=\"Left\" POSITION=\"left\"><node TEXT=\"Child\"/></node></node></map>".utf8)
        check(tryDecode(simple).topics[1].x < 0, "Standard external FreeMind input remains readable")
        let data = try MapFormats.encodeBook(book, type: MapFormats.nativeType)
        let object = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        check(object["version"] as? Int == 2 && object["sheets"] != nil, "New native files explicitly store workbook version 2")
        var bad = book; bad.activeSheetID = "missing"
        rejects("Unknown active sheet is rejected") { try bad.validate() }
        bad = book; bad.sheets.append(bad.sheets[0])
        rejects("Duplicate sheet IDs are rejected") { try bad.validate() }
        var broken = styled; broken.topics[1].parentID = "missing"
        rejects("Missing topic parent is rejected") { try broken.validate() }
        broken = styled; broken.topics[1].parentID = broken.topics[1].id
        rejects("Disconnected cyclic trees are rejected") { try broken.validate() }
        var invalidStyle = appearance; invalidStyle.fontSize = -1
        rejects("Negative font sizes are rejected") { try invalidStyle.validate() }
        invalidStyle = appearance; invalidStyle.borderColor = "not a color"
        rejects("Invalid custom colors are rejected") { try invalidStyle.validate() }
        rejects("Malformed JSON is rejected") { _ = try MapFormats.decodeBook(Data("{}".utf8), type: MapFormats.nativeType) }
        rejects("Invalid map archive is rejected") { _ = try MapFormats.decodeBook(Data("zip?".utf8), type: MapFormats.archiveType) }
        let aiBase = styled
        let addition = try patch([["action": "addTopic", "id": "mcp-new-root", "parentID": root, "title": "Branch 121", "style": ["fontSize": 24, "bold": true], "structure": "rightToLeft"]], on: aiBase)
        let preview = try AIMap.preview(addition, on: aiBase)
        check(preview.map.children(of: root).count == 121 && aiBase.topic("mcp-new-root") == nil, "MCP preview adds branch 121 without mutating original")
        check(preview.map.topic("mcp-new-root")!.appearance.fontSize == 24 && preview.map.direction(of: "mcp-new-root") == -1, "MCP accepts partial style and structure on new topics")
        rejects("Stale MCP edits are rejected") { _ = try AIMap.preview(addition, on: preview.map) }
        let stylePatch = try patch([["action": "updateTopic", "id": child, "style": ["fontSize": 32, "shape": "ellipse"]]], on: aiBase)
        let styledPatch = try AIMap.preview(stylePatch, on: aiBase).map.topic(child)!
        check(styledPatch.appearance.fontSize == 32 && styledPatch.appearance.bold && styledPatch.appearance.fillColor == appearance.fillColor && styledPatch.appearance.shape == .ellipse, "Partial MCP style updates preserve all unrelated formatting")
        let invalid = try patch([["action": "updateTopic", "id": child, "title": "Should not apply"], ["action": "deleteTopic", "id": root]], on: aiBase)
        rejects("Invalid MCP batches are atomic") { _ = try AIMap.preview(invalid, on: aiBase) }
        check(styled == aiBase, "Rejected patch leaves original data unchanged")
        let badStyle = try patch([["action": "updateTopic", "id": child, "style": ["fontSize": 999]]], on: aiBase)
        rejects("MCP validates font size limits") { _ = try AIMap.preview(badStyle, on: aiBase) }
        let cyclic = try patch([["action": "reparentTopic", "id": first, "parentID": grandchild]], on: aiBase)
        rejects("MCP reparenting cannot create cycles") { _ = try AIMap.preview(cyclic, on: aiBase) }
        let reparent = try patch([["action": "reparentTopic", "id": child, "parentID": root]], on: aiBase)
        check(tryPreview(reparent, on: aiBase).topic(child)?.parentID == root, "MCP can reparent into a root with more than six branches")
        check(AIMap.markdown(book).contains("Research") && AIMap.markdown(book).contains(other.id), "Workbook Markdown includes all sheet names and IDs")
        var removed = styled; removed.remove(first)
        check(removed.topic(grandchild) == nil && removed.topic(second) != nil, "Deleting a branch removes only its subtree")
        removed.remove(removed.root.id); check(removed.topics.count > 0, "The central topic cannot be deleted")
        let folder = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("build/v2-fixtures")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try MapFormats.encodeBook(book, type: MapFormats.nativeType).write(to: folder.appendingPathComponent("Styled workbook.nixmap"))
        try MapFormats.encodeBook(book, type: MapFormats.archiveType).write(to: folder.appendingPathComponent("Styled workbook.xmind"))
        print("PASS: \(count) checks")
    }
    static func tryDecode(_ data: Data) -> MindMap { try! MapFormats.decode(data, type: MapFormats.freeMindType) }
    static func tryPreview(_ patch: MapPatch, on map: MindMap) -> MindMap { try! AIMap.preview(patch, on: map).map }
}
