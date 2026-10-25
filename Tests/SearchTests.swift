import AppKit
import SwiftUI

@main struct SearchTests {
    @MainActor static func main() throws {
        _ = NSApplication.shared
        var checks = 0
        func check(_ condition: @autoclosure () -> Bool, _ message: String) {
            precondition(condition(), message); checks += 1; print("✓ \(message)")
        }
        let root = Topic(id: "root", title: "Project ideas", x: 0, y: 0)
        let topics = [root,
                      Topic(id: "exact", parentID: "root", title: "Search", x: 300, y: 0),
                      Topic(id: "prefix", parentID: "root", title: "Search engine", x: 300, y: 80),
                      Topic(id: "contains", parentID: "root", title: "Research notes", x: 300, y: 160),
                      Topic(id: "accent", parentID: "root", title: "Đổi tiếng Việt 🇻🇳", x: 300, y: 240),
                      Topic(id: "acronym", parentID: "root", title: "Model Context Protocol", x: 300, y: 320),
                      Topic(id: "multi", parentID: "root", title: "Canvas performance tuning", x: 300, y: 400),
                      Topic(id: "repeat", parentID: "root", title: "Plan a plan", x: 300, y: 480),
                      Topic(id: "unicode", parentID: "root", title: "👨‍👩‍👧‍👦 Cafe\u{301} Straße ＡＰＩ", x: 300, y: 560),
                      Topic(id: "notes", parentID: "root", title: "Delivery", note: "Prepare " + String(repeating: "a long note ", count: 50) + "release checklist and verification", x: 300, y: 640),
                      Topic(id: "deep", parentID: "acronym", title: "Search client", x: 600, y: 320)]
        var book = MindBook(map: MindMap(topics: topics), title: "Ideas")
        let firstSheet = book.activeSheetID
        let other = MapSheet(title: "Other plans", map: MindMap(topics: [Topic(id: "other-root", title: "Search elsewhere", x: 0, y: 0)]))
        book.sheets.append(other)
        let index = TopicSearchIndex(book: book, sheetID: firstSheet)
        func ids(_ query: String) -> [String] { index.search(query).results.map(\.topicID) }
        func highlight(_ text: String, _ ranges: [NSRange]) -> [String] { ranges.map { (text as NSString).substring(with: $0) } }
        check(index.search("   \n").results.isEmpty, "Whitespace-only search produces no unbounded result list")
        check(ids("SEARCH").first == "exact", "Exact case-insensitive title ranks first")
        check(ids("search").firstIndex(of: "prefix")! < ids("search").firstIndex(of: "contains")!, "Word prefix outranks a substring inside a word")
        check(ids("doi tieng viet") == ["accent"], "Vietnamese search ignores accents and maps đ to d")
        let accent = index.search("tieng").results.first!
        check(highlight(accent.titlePreview, accent.titleHighlights) == ["tiếng"], "Highlight ranges preserve the original accented text")
        check(ids("tuning canvas").contains("multi"), "Multiple words can match in any order")
        check(ids("canvas impossibleword").isEmpty, "Every query token is required")
        check(ids("mcp").contains("acronym"), "Initials match multiword acronyms")
        let acronym = index.search("mcp").results.first { $0.topicID == "acronym" }!
        check(acronym.isFuzzy && highlight(acronym.titlePreview, acronym.titleHighlights) == ["M", "C", "P"], "Acronym highlights identify the original initials")
        check(ids("serach").contains("exact"), "Adjacent transposition typo is recognized")
        check(ids("serach").first == "exact", "Corrected whole-title matches outrank corrected words in longer titles")
        check(!ids("serach").contains("multi"), "Subsequence matching does not span unrelated sentence words")
        check(ids("searh").contains("exact"), "A missing character is tolerated")
        check(ids("perfrmance").contains("multi"), "Longer words tolerate small edit distances")
        check(ids("zzzzzzzzzzzz").isEmpty, "Unrelated words do not become loose fuzzy matches")
        let repeatMatch = index.search("plan").results.first { $0.topicID == "repeat" }!
        check(highlight(repeatMatch.titlePreview, repeatMatch.titleHighlights) == ["Plan", "plan"], "Every repeated occurrence is highlighted")
        let unicode = index.search("cafe strasse api").results.first!
        check(unicode.topicID == "unicode", "Canonical accents, expanding case folds and full-width letters match")
        check(highlight(unicode.titlePreview, unicode.titleHighlights) == ["Cafe\u{301}", "Straße", "ＡＰＩ"], "Unicode highlight offsets preserve grapheme boundaries after emoji")
        let note = index.search("release checklist").results.first!
        check(note.topicID == "notes" && note.notePreview.hasPrefix("…"), "Note matches produce a relevant window rather than truncating before the hit")
        check(highlight(note.notePreview, note.noteHighlights).joined(separator: " ") == "release checklist", "Note snippet highlights retain valid shifted ranges")
        check(index.search("release").results.first?.titleHighlights.isEmpty == true, "Note-only matches do not mark unrelated title letters")
        check(!ids("search").contains("other-root"), "Default scope searches only the current sheet")
        check(TopicSearchIndex(book: book).search("search").results.contains { $0.sheetID == other.id }, "All-sheets scope includes other trees")
        check(index.search("client").results.first?.breadcrumb.contains("Model Context Protocol") == true, "Nested matches retain parent context")
        let capped = index.search("search", limit: 2)
        check(capped.results.count == 2 && capped.total > 2, "Results are bounded while the full match count is preserved")
        check(index.search("search").results.map(\.id) == index.search("search").results.map(\.id), "Equal scores retain stable document ordering")
        check(index.search("search", limit: 0).results.isEmpty, "A zero result limit is safe")
        let document = MapDocument(); document.store.load(book)
        let store = document.store
        let canvas = MindMapCanvas(store: store)
        canvas.frame = CGRect(x: 0, y: 0, width: 900, height: 600); canvas.layout()
        store.select("exact"); canvas.editSelected(); canvas.editor?.stringValue = "Search revised"
        store.showSearch()
        check(store.searchVisible && store.map.topic("exact")?.title == "Search revised" && canvas.editor == nil, "Opening search commits any pending inline title edit")
        let renameKey = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil, characters: "e", charactersIgnoringModifiers: "e", isARepeat: false, keyCode: 14)!
        canvas.keyDown(with: renameKey)
        check(canvas.editor == nil, "Canvas ignores stale key events while Search owns focus")
        let result = index.search("protocol").results.first!
        canvas.setZoom(0.05)
        check(store.revealSearchResult(result) && !store.searchVisible && store.selectedID == "acronym", "Choosing a result closes search and selects its topic")
        check(canvas.scale >= 0.75, "Search navigation restores a readable canvas zoom")
        let position = canvas.screen(store.selected.point)
        check(abs(position.x - canvas.bounds.midX) < 1 && abs(position.y - canvas.bounds.midY) < 1, "Search centers the selected node")
        store.setMode(.outliner)
        canvas.keyDown(with: renameKey)
        check(canvas.editor == nil, "Hidden canvas cannot start editing from Outliner key events")
        let otherResult = TopicSearchIndex(book: book).search("elsewhere").results.first!
        store.showSearch(); store.revealSearchResult(otherResult)
        check(store.activeSheet.id == other.id && store.mode == .outliner && store.outlineRevealRequest?.id == "other-root", "Cross-sheet navigation preserves Outliner and requests scroll/reveal")
        store.switchSheet(firstSheet)
        check(store.ancestorIDs(of: "deep") == ["root", "acronym"], "Outliner can expand only the selected result's ancestors")
        var removed = store.map; removed.remove("acronym"); store.apply(removed, action: "Test removal")
        store.showSearch()
        check(!store.revealSearchResult(result) && store.searchVisible, "A result deleted by a concurrent edit is rejected safely")
        check(!TopicSearchIndex(book: store.workbook).search("protocol").results.contains { $0.topicID == "acronym" }, "A fresh index reflects concurrent document edits")
        let longTitle = String(repeating: "🙂 filler ", count: 50) + "specialneedle" + String(repeating: " tail", count: 50)
        let longBook = MindBook(map: MindMap(topics: [Topic(title: longTitle, x: 0, y: 0)]))
        let longResult = TopicSearchIndex(book: longBook).search("specialneedle").results.first!
        check(longResult.titlePreview.hasPrefix("…") && highlight(longResult.titlePreview, longResult.titleHighlights) == ["specialneedle"], "Long titles display the matching region with safe Unicode offsets")
        var input = "", moved = 0, submitted = false, dismissed = false
        let nativeInput = TopicSearchInput(query: Binding(get: { input }, set: { input = $0 }), focusRequest: UUID(),
                                           moveSelection: { moved += $0 }, submit: { submitted = true }, dismiss: { dismissed = true })
        let coordinator = nativeInput.makeCoordinator()
        let field = NSTextField(string: "Đổi tiếng Việt")
        coordinator.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: field))
        check(input == "Đổi tiếng Việt", "Native search input preserves composed Vietnamese text")
        let editor = NSTextView()
        _ = coordinator.control(field, textView: editor, doCommandBy: #selector(NSResponder.moveDown(_:)))
        _ = coordinator.control(field, textView: editor, doCommandBy: #selector(NSResponder.insertNewline(_:)))
        _ = coordinator.control(field, textView: editor, doCommandBy: #selector(NSResponder.cancelOperation(_:)))
        check(moved == 1 && submitted && dismissed, "Native arrow, Return and Escape commands navigate without editing topics")
        submitted = false
        editor.setMarkedText("tiếng", selectedRange: NSRange(location: 5, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
        let consumed = coordinator.control(field, textView: editor, doCommandBy: #selector(NSResponder.insertNewline(_:)))
        check(!consumed && !submitted, "Input-method composition consumes Return before search navigation")
        check(!coordinator.control(field, textView: NSTextView(), doCommandBy: #selector(NSResponder.moveLeft(_:))), "Left/right caret editing stays native")
        if CommandLine.arguments.count > 1 {
            let data = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))
            let fixture = try MapFormats.decodeBook(data, type: MapFormats.nativeType)
            let start = Date()
            let fixtureIndex = TopicSearchIndex(book: fixture)
            let needle = String(fixture.activeMap.root.title.prefix(30))
            let found = fixtureIndex.search(needle)
            check(found.results.contains { $0.topicID == fixture.activeMap.root.id }, "Real-world fixture root is found without changing the file")
            print("Fixture index + search: \(Int(Date().timeIntervalSince(start) * 1000)) ms, \(fixture.sheets.reduce(0) { $0 + $1.map.topics.count }) topics")
        }
        print("PASS: \(checks) search checks")
    }
}
