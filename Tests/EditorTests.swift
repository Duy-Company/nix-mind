import AppKit

@main struct EditorTests {
    @MainActor static func main() throws {
        _ = NSApplication.shared
        var checks = 0
        func check(_ condition: @autoclosure () -> Bool, _ message: String) {
            precondition(condition(), message); checks += 1; print("✓ \(message)")
        }
        let document = MapDocument()
        let store = document.store
        let canvas = MindMapCanvas(store: store)
        canvas.frame = NSRect(x: 0, y: 0, width: 900, height: 600)
        canvas.layout()
        let window = NSWindow(contentRect: canvas.bounds, styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = canvas
        check(canvas.clipsToBounds && canvas.layer?.masksToBounds == true, "Canvas clips all drawing beneath app chrome")
        let firstID = store.activeSheet.id
        let firstRoot = store.map.root.id
        store.addChild(firstRoot)
        let child = store.selectedID
        check(canvas.editor?.drawsBackground == false, "Inline title field has no white background")
        check(canvas.editor?.backgroundColor == .clear, "Inline field background stays transparent")
        if let editor = canvas.editor, let fieldEditor = window.fieldEditor(true, for: editor) as? NSTextView {
            canvas.controlTextDidBeginEditing(Notification(name: NSControl.textDidBeginEditingNotification, object: editor))
            let activeEditor = editor.currentEditor() as? NSTextView ?? fieldEditor
            check(!activeEditor.drawsBackground && activeEditor.backgroundColor == .clear, "Shared AppKit text editor also keeps the node background visible")
        } else { preconditionFailure("Missing AppKit field editor") }
        canvas.editor?.stringValue = "A new idea"
        check(canvas.snapshotForSaving().topic(child)?.title == "A new idea", "Saving captures uncommitted canvas edits")
        canvas.finishEditing()
        check(store.map.topic(child)?.title == "A new idea", "Canvas commits edited text")
        store.setStyle { $0.fontFamily = "Georgia"; $0.fontSize = 27; $0.bold = true; $0.italic = true; $0.underline = true; $0.fillColor = "#AABBCCFF"; $0.borderWidth = 3; $0.alignment = .left; $0.shape = .diamond }
        canvas.editSelected()
        check(canvas.editor?.font?.pointSize == 27 * canvas.scale, "Inline editor uses selected font size")
        check(canvas.editor?.alignment == .left, "Inline editor uses selected alignment")
        check(canvas.editor?.textColor == store.selected.resolvedText, "Inline editor preserves node text color")
        canvas.finishEditing()
        store.setStructure(.rightToLeft)
        check(canvas.handles(store.selected).allSatisfy { $0.rect.midX == canvas.rect(store.selected).minX }, "Right-to-left structure puts both plus controls on the left")
        store.setStructure(.leftToRight)
        check(canvas.handles(store.selected).allSatisfy { $0.rect.midX == canvas.rect(store.selected).maxX }, "Left-to-right structure puts both plus controls on the right")
        let original = store.workbook
        let second = store.addSheet(title: "Plan")
        check(store.workbook.sheets.count == 2 && store.activeSheet.id == second, "Adding a sheet activates its own root")
        check(store.map.root.id != firstRoot, "Sheets have independent topic trees")
        store.switchSheet(firstID)
        check(store.map.topic(child)?.appearance.shape == .diamond, "Switching sheets retains appearance")
        store.setMode(.outliner); store.select(child); store.editSelected()
        check(store.editingOutlineID == child, "Rename in Outliner targets the selected topic")
        store.addSibling(child)
        let sibling = store.selectedID
        check(store.editingOutlineID == sibling && canvas.editor == nil, "Outliner adds a sibling and keeps text editing in Outliner")
        store.indent(sibling)
        check(store.map.topic(sibling)?.parentID == child, "Outliner indent updates hierarchy")
        store.outdent(sibling)
        check(store.map.topic(sibling)?.parentID == firstRoot, "Outliner outdent updates hierarchy")
        store.setMode(.mindMap)
        check(store.mode == .mindMap && store.editingOutlineID == nil, "Switching back retains tree and exits outline editing")
        // Exercise the default event-grouping manager across separate run-loop turns.
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.03))
        document.undoManager?.removeAllActions()
        var changed = store.map
        changed.topics[0].title = "MCP root"
        store.applyAI(changed)
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.03))
        document.undoManager?.undo()
        check(store.map.root.title != "MCP root", "MCP changes undo through the native document manager")
        document.undoManager?.redo()
        check(store.map.root.title == "MCP root", "Native redo restores MCP changes")
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.03))
        store.addSheet(title: "After MCP")
        check(store.workbook.sheets.count == 3, "A later sheet operation keeps the Undo manager valid")
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.03))
        document.undoManager?.undo()
        check(store.workbook.sheets.count == 2, "Adding a sheet is undoable")
        document.undoManager?.redo()
        check(store.workbook.sheets.count == 3, "Adding a sheet is redoable")
        store.switchSheet(firstID)
        store.selectedID = firstRoot
        for _ in 0..<80 { store.addChild(firstRoot); canvas.finishEditing() }
        check(store.map.children(of: firstRoot).count > 80, "Canvas supports more than six direct root branches")
        check(canvas.scale < 1, "Canvas automatically zooms out as root branches grow")
        check(store.map.topic(child)?.appearance.fontSize == 27, "Zooming out does not modify saved typography")
        store.load(original)
        let disposable = store.addSheet(title: "Delete check")
        store.deleteSheet(disposable)
        check(store.workbook.sheets.count == 1, "Deleting a sheet retains the remaining tree")
        store.deleteSheet(firstID)
        check(store.workbook.sheets.count == 1, "The last sheet stays protected")
        print("PASS: \(checks) native editor checks")
    }
}
