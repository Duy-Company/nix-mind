import AppKit
import Combine

@MainActor final class MCPState: ObservableObject {
    static let shared = MCPState()
    @Published private(set) var enabled: Bool
    @Published private(set) var running = false
    @Published private(set) var lastActivity = ""
    @Published private(set) var error: String?
    private let service = LocalMCPService()
    private init() { enabled = UserDefaults.standard.object(forKey: "localMCPEnabled") as? Bool ?? true }
    func start() {
        guard enabled else { return }
        do { try service.start(); running = true; error = nil } catch { self.error = error.localizedDescription; running = false }
    }
    func setEnabled(_ value: Bool) {
        enabled = value; UserDefaults.standard.set(value, forKey: "localMCPEnabled")
        if value { start() } else { stop() }
    }
    func stop() { service.stop(); running = false }
    func activity(_ text: String) { lastActivity = text }
    func configuration(for format: MCPClientFormat) -> String {
        let executable = Bundle.main.executableURL?.path ?? "/Applications/Nix Mind.app/Contents/MacOS/Nix Mind"
        return MCPConfiguration.json(executable: executable, format: format)
    }
}

@MainActor enum MCPAppBridge {
    static func document(_ request: [String: Any]) throws -> MapDocument {
        if let id = request["document_id"] as? String {
            guard let doc = NSDocumentController.shared.documents.compactMap({ $0 as? MapDocument }).first(where: { $0.sessionID == id }) else { throw AIError("This document session is no longer open. Call list_documents again.") }
            return doc
        }
        guard let doc = NSDocumentController.shared.currentDocument as? MapDocument else { throw AIError("No current document. Call list_documents or create_map.") }
        return doc
    }
    static func sheetSummary(_ sheet: MapSheet, in book: MindBook) -> [String: Any] {
        ["id": sheet.id, "title": sheet.title, "rootID": sheet.map.root.id, "topicCount": sheet.map.topics.count, "active": sheet.id == book.activeSheetID]
    }
    static func summary(_ doc: MapDocument) -> [String: Any] {
        ["id": doc.sessionID, "documentID": doc.store.map.root.id, "title": doc.store.map.root.title,
         "filePath": doc.fileURL?.path as Any? ?? NSNull(), "hasUnsavedChanges": doc.isDocumentEdited,
         "topicCount": doc.store.map.topics.count, "sheetCount": doc.store.workbook.sheets.count, "activeSheetID": doc.store.workbook.activeSheetID]
    }
    static func sheet(_ request: [String: Any], in doc: MapDocument) throws -> MapSheet {
        let id = request["sheet_id"] as? String ?? doc.store.workbook.activeSheetID
        guard let sheet = doc.store.workbook.sheets.first(where: { $0.id == id }) else { throw AIError("Sheet not found. Call list_sheets for fresh IDs.") }
        return sheet
    }
    static func context(_ map: MindMap, sheet: MapSheet) throws -> [String: Any] {
        var value = try AIMap.context(map); value["sheetID"] = sheet.id; value["sheetTitle"] = sheet.title; return value
    }
    static func path(_ request: [String: Any]) throws -> URL {
        guard let path = request["path"] as? String, path.hasPrefix("/"), !path.contains("\0") else { throw AIError("Provide an absolute local file path.") }
        return URL(fileURLWithPath: path).standardizedFileURL
    }
    static func handle(_ request: [String: Any]) async throws -> [String: Any] {
        guard MCPState.shared.enabled else { throw AIError("Local MCP is disabled in Nix Mind.") }
        let action = request["action"] as? String ?? ""
        if action == "ping" { return ["app": "Nix Mind", "version": "1.0.5", "executable": Bundle.main.executableURL?.path ?? ""] }
        if action == "list_documents" {
            MCPState.shared.activity("Client read open documents")
            return ["documents": NSDocumentController.shared.documents.compactMap { ($0 as? MapDocument).map(summary) }]
        }
        if action == "create_map" {
            let doc = MapDocument(); doc.fileType = MapFormats.nativeType
            if let title = request["title"] as? String {
                guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, title.count <= 10000 else { throw MapError.invalid }
                doc.store.map.topics[0].title = title
            }
            NSDocumentController.shared.addDocument(doc); doc.makeWindowControllers(); doc.showWindows(); doc.updateChangeCount(.changeDone)
            MCPState.shared.activity("Client created a document")
            return ["document": summary(doc), "map": try context(doc.store.map, sheet: doc.store.activeSheet)]
        }
        if action == "open_map" {
            let url = try path(request)
            guard let type = ["nixmap": MapFormats.nativeType, "xmind": MapFormats.archiveType, "mm": MapFormats.freeMindType][url.pathExtension.lowercased()] else { throw AIError("Open a Nix Mind workbook, compatible mind map archive, or FreeMind file.") }
            if let existing = NSDocumentController.shared.document(for: url) as? MapDocument { existing.showWindows(); return ["document": summary(existing)] }
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            guard (attributes[.size] as? NSNumber)?.intValue ?? Int.max <= 64_000_000 else { throw MapError.invalid }
            let doc = try MapDocument(contentsOf: url, ofType: type)
            NSDocumentController.shared.addDocument(doc); doc.makeWindowControllers(); doc.showWindows(); doc.store.canvas?.fit()
            return ["document": summary(doc), "map": try context(doc.store.map, sheet: doc.store.activeSheet)]
        }
        let doc = try document(request)
        if action == "list_sheets" { return ["document": summary(doc), "sheets": doc.store.workbook.sheets.map { sheetSummary($0, in: doc.store.workbook) }] }
        if action == "create_sheet" {
            let title = request["title"] as? String
            if let title, title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || title.count > 500 { throw AIError("Sheet titles must contain 1 to 500 characters.") }
            guard doc.store.workbook.sheets.count < 500 else { throw MapError.invalid }
            doc.store.addSheet(title: title)
            return ["document": summary(doc), "sheet": sheetSummary(doc.store.activeSheet, in: doc.store.workbook), "map": try context(doc.store.map, sheet: doc.store.activeSheet)]
        }
        let target = try sheet(request, in: doc)
        switch action {
        case "select_sheet":
            doc.store.switchSheet(target.id)
            return ["document": summary(doc), "sheet": sheetSummary(target, in: doc.store.workbook)]
        case "rename_sheet":
            guard let title = request["title"] as? String, !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, title.count <= 500 else { throw AIError("Provide a non-empty sheet title up to 500 characters.") }
            doc.store.renameSheet(target.id, title: title)
            return ["document": summary(doc), "sheets": doc.store.workbook.sheets.map { sheetSummary($0, in: doc.store.workbook) }]
        case "delete_sheet":
            guard doc.store.workbook.sheets.count > 1 else { throw AIError("Keep at least one sheet in the document.") }
            doc.store.deleteSheet(target.id)
            return ["document": summary(doc), "deletedSheetID": target.id]
        default: break
        }
        let map = target.id == doc.store.activeSheet.id ? (doc.store.canvas?.snapshotForSaving() ?? target.map) : target.map
        switch action {
        case "read_map":
            MCPState.shared.activity("Client read \(target.title)")
            return ["document": summary(doc), "map": try context(map, sheet: target), "selectedTopicID": target.id == doc.store.activeSheet.id ? doc.store.selectedID as Any : NSNull(), "markdown": AIMap.markdown(map)]
        case "read_topic":
            guard let id = request["topic_id"] as? String, let topic = map.topic(id) else { throw AIError("Topic ID not found in this sheet.") }
            var ancestors: [Topic] = []; var parent = topic.parentID
            while let id = parent, let node = map.topic(id) { ancestors.insert(node, at: 0); parent = node.parentID }
            return ["sheetID": target.id, "topic": try AIMap.object(topic), "ancestors": try AIMap.object(ancestors), "children": try AIMap.object(map.children(of: id)), "baseFingerprint": AIMap.fingerprint(map)]
        case "preview_patch", "apply_patch":
            guard let object = request["patch"] as? [String: Any] else { throw AIError("Provide a patch object.") }
            let patch = try JSONDecoder().decode(MapPatch.self, from: JSONSerialization.data(withJSONObject: object))
            var proposal = try AIMap.preview(patch, on: map)
            if action == "apply_patch" {
                doc.store.canvas?.finishEditing()
                let latest = try sheet(request, in: doc)
                proposal = try AIMap.preview(patch, on: latest.map)
                doc.store.applyAI(proposal.map, sheetID: target.id)
                if target.id == doc.store.activeSheet.id { doc.store.canvas?.fit(onlyShrink: true) }
                MCPState.shared.activity("Client updated \(target.title)")
                doc.store.showToast("MCP changes applied. Use ⌘Z to undo.")
            }
            return ["applied": action == "apply_patch", "sheetID": target.id, "changes": proposal.changes, "map": try context(proposal.map, sheet: target)]
        case "save_map", "export_map":
            let url: URL
            if action == "save_map", request["path"] == nil, let current = doc.fileURL { url = current } else { url = try path(request) }
            let ext = url.pathExtension.lowercased()
            if action == "save_map", ext != "nixmap" { throw AIError("save_map requires .nixmap. Use export_map for exchange formats.") }
            guard ["nixmap", "xmind", "mm", "md"].contains(ext) else { throw AIError("Use a Nix Mind workbook, compatible mind map archive, FreeMind, or Markdown output path.") }
            let currentFile = action == "save_map" && doc.fileURL?.standardizedFileURL == url
            if FileManager.default.fileExists(atPath: url.path), !currentFile, request["overwrite"] as? Bool != true { throw AIError("File exists. Choose another path or explicitly set overwrite=true.") }
            doc.store.canvas?.finishEditing()
            if action == "save_map" {
                try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                    doc.save(to: url, ofType: MapFormats.nativeType, for: currentFile ? .saveOperation : .saveAsOperation) { error in
                        if let error { continuation.resume(throwing: error) } else { continuation.resume() }
                    }
                }
            } else {
                var book = doc.store.workbook
                if request["sheet_id"] != nil { book.sheets = [try sheet(request, in: doc)]; book.activeSheetID = target.id }
                let data = ext == "md" ? Data(AIMap.markdown(book).utf8) : try MapFormats.encodeBook(book, type: ["nixmap": MapFormats.nativeType, "xmind": MapFormats.archiveType, "mm": MapFormats.freeMindType][ext]!)
                try data.write(to: url, options: .atomic)
            }
            MCPState.shared.activity(action == "save_map" ? "Client saved this workbook" : "Client exported this workbook")
            return ["path": url.path, "document": summary(doc)]
        default: throw AIError("Unknown local action.")
        }
    }
}
