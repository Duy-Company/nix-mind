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
        let child = store.selectedID!
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
        check(canvas.editor?.textColor == store.selected!.resolvedText, "Inline editor preserves node text color")
        canvas.finishEditing()
        store.setStructure(.rightToLeft)
        check(canvas.handles(store.selected!).allSatisfy { $0.rect.midX == canvas.rect(store.selected!).minX }, "Right-to-left structure puts both plus controls on the left")
        store.setStructure(.leftToRight)
        check(canvas.handles(store.selected!).allSatisfy { $0.rect.midX == canvas.rect(store.selected!).maxX }, "Left-to-right structure puts both plus controls on the right")
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.03)); document.undoManager?.removeAllActions()
        let beforeConnection = store.map, connectionPan = canvas.pan, connectionScale = canvas.scale
        store.selectConnection(child)
        store.setConnectionStyle {
            $0.shape = .orthogonal; $0.pattern = .dashed; $0.width = 5; $0.label = "Đăng nhập → mở màn hình chính"; $0.end = .arrow; $0.color = "#22AA88FF"
            $0.labelAppearance.fontFamily = "Georgia"; $0.labelAppearance.fontSize = 24; $0.labelAppearance.bold = true; $0.labelAppearance.italic = true
            $0.labelAppearance.underline = true; $0.labelAppearance.strikethrough = true; $0.labelAppearance.alignment = .left
        }
        let connected = store.map
        check(store.inspectingConnection && store.inspectorVisible && store.selectedID == child, "Selecting a connection opens its child-specific inspector")
        check(store.selected!.connectionAppearance.label == "Đăng nhập → mở màn hình chính" && store.selected!.connectionAppearance.shape == .orthogonal, "Connection controls accept arbitrary text")
        check(store.selected!.connectionAppearance.labelAppearance.fontFamily == "Georgia" && store.selected!.connectionAppearance.labelAppearance.fontSize == 24 && store.selected!.connectionAppearance.labelAppearance.bold && store.selected!.connectionAppearance.labelAppearance.alignment == .left, "Connection text controls format labels independently from node text")
        check(store.map.root == beforeConnection.root && store.selected!.style == beforeConnection.topic(child)?.style, "Formatting a line preserves other topics and node styling")
        check(canvas.pan == connectionPan && canvas.scale == connectionScale, "Formatting a line preserves the viewport")
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.03)); document.undoManager?.undo()
        check(store.map == beforeConnection, "One Undo restores all connection formatting and text")
        document.undoManager?.redo()
        check(store.map == connected, "Redo restores connection formatting and text")
        for position in ConnectionArrowPosition.allCases {
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.03))
            let beforePosition = store.map
            store.setConnectionStyle { $0.arrowPosition = position }
            var expectedStyle = beforePosition.topic(child)!.connectionAppearance
            expectedStyle.start = position == .start || position == .both ? .arrow : .none
            expectedStyle.end = position == .end || position == .both ? .arrow : .none
            check(store.selected!.connectionAppearance == expectedStyle && store.map.root == beforePosition.root, "Arrow position \(position) updates only the selected line endings")
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.03)); document.undoManager?.undo()
            check(store.map == beforePosition, "Undo restores the previous arrow position after choosing \(position)")
            document.undoManager?.redo()
            check(store.selected!.connectionAppearance == expectedStyle, "Redo restores arrow position \(position)")
        }
        store.apply(connected, action: "Restore connection after arrow position checks")
        store.setConnectionStyle { $0.labelAppearance = ConnectionStyle().labelAppearance }
        check(store.selected!.connectionAppearance.label == "Đăng nhập → mở màn hình chính" && store.selected!.connectionAppearance.shape == .orthogonal && store.selected!.connectionAppearance.labelAppearance.fontSize == 13 && !store.selected!.connectionAppearance.labelAppearance.bold, "Reset text style keeps arbitrary label content and line formatting")
        store.apply(connected, action: "Restore styled label")
        store.selectedID = firstRoot; store.setConnectionStyle { $0.label = "Invalid root label" }
        check(store.map == connected, "The central topic cannot acquire an incoming connection through controls")
        store.selectedID = child; store.setConnectionStyle { $0.width = .nan }
        check(store.map == connected, "Invalid connection formatting leaves the document unchanged")
        store.setConnectionStyle { $0 = ConnectionStyle() }
        check(store.selected!.connectionAppearance == ConnectionStyle(), "Reset connection restores defaults and removes its label")
        store.apply(connected, action: "Restore formatted connection")
        var inlineMap = store.map; inlineMap.moveSubtree(child, dx: 400, dy: 0)
        store.apply(inlineMap, action: "Make room for the inline label fixture")
        let editableEdge = canvas.prepareScene().edges.first { $0.childID == child }!
        canvas.restoreViewport(pan: CGPoint(x: canvas.bounds.midX - editableEdge.labelRect.midX * 1.25, y: canvas.bounds.midY - editableEdge.labelRect.midY * 1.25), scale: 1.25)
        let beforeInlineLabel = store.map, inlinePan = canvas.pan, inlineScale = canvas.scale
        let textStart = canvas.screen(CGPoint(x: editableEdge.labelRect.minX + 8, y: editableEdge.labelRect.minY + 14))
        let labelClick = NSEvent.mouseEvent(with: .leftMouseDown, location: canvas.convert(textStart, to: nil), modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 0)!
        canvas.mouseDown(with: labelClick)
        check(canvas.editingConnectionID == child && canvas.editingID == nil, "One click on label text opens its own inline editor")
        check(canvas.editor?.drawsBackground == false && canvas.editor?.backgroundColor == .clear, "The inline label field remains transparent")
        check(canvas.editor?.font?.pointSize == 24 * inlineScale && canvas.editor?.alignment == .left, "Inline labels retain their text formatting at the current zoom")
        let labelTextView = canvas.editor?.currentEditor() as! NSTextView
        check(labelTextView.selectedRange().length == 0 && labelTextView.selectedRange().location < 10, "The insertion point follows the click instead of selecting the whole label")
        check(!labelTextView.drawsBackground && labelTextView.backgroundColor == .clear && (labelTextView.typingAttributes[.font] as? NSFont)?.pointSize == 24 * inlineScale, "The shared field editor uses transparent label text styling")
        canvas.editor?.stringValue = "Open settings\nReturn to profile"
        canvas.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: canvas.editor))
        check(canvas.snapshotForSaving().topic(child)?.connectionAppearance.label == "Open settings\nReturn to profile" && store.map == beforeInlineLabel, "Save snapshots capture multiline label drafts while typing leaves the document unchanged")
        check(canvas.snapshotForSaving().topic(child)?.title == beforeInlineLabel.topic(child)?.title, "Label editing never renames its child topic")
        canvas.finishEditing(cancel: true)
        check(store.map == beforeInlineLabel && canvas.editingConnectionID == nil, "Escape cancels the label edit without changing the document")
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.03)); document.undoManager?.removeAllActions()
        canvas.editConnectionLabel(child)
        canvas.editor?.stringValue = "Open settings\nReturn to profile"
        canvas.finishEditing()
        let committedLabel = store.map
        check(store.selected!.connectionAppearance.label == "Open settings\nReturn to profile" && store.selected!.connectionAppearance.labelAppearance == beforeInlineLabel.topic(child)?.connectionAppearance.labelAppearance, "Committing label text preserves all line and text styles")
        check(canvas.pan == inlinePan && canvas.scale == inlineScale, "Inline label editing preserves zoom and pan")
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.03)); document.undoManager?.undo()
        check(store.map == beforeInlineLabel, "One Undo restores the previous inline label")
        document.undoManager?.redo()
        check(store.map == committedLabel, "Redo restores the committed inline label")
        canvas.editConnectionLabel(child); canvas.editor?.stringValue = ""
        canvas.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: canvas.editor))
        check(canvas.editor!.frame.width > 0 && canvas.editor!.frame.height > 0, "An empty label keeps a visible insertion area while editing")
        canvas.finishEditing()
        check(store.selected!.connectionAppearance.label.isEmpty && canvas.prepareScene().edges.first { $0.childID == child }?.label == nil, "Clearing text inline removes the label and its connection gap")
        store.apply(committedLabel, action: "Restore label for keyboard check")
        canvas.editConnectionLabel(child)
        let topicCount = store.map.topics.count
        _ = canvas.control(canvas.editor!, textView: canvas.editor!.currentEditor() as! NSTextView, doCommandBy: #selector(NSResponder.insertTab(_:)))
        check(canvas.editor == nil && store.map.topics.count == topicCount, "Tab commits a label without adding an unrelated topic")
        let beforeDeselect = store.map, deselectPan = canvas.pan, deselectZoom = canvas.scale, deselectRevision = store.mapRevision
        store.clearSelection()
        check(store.selectedID == nil && store.selected == nil && !store.inspectingConnection && canvas.labelResizeRegions().isEmpty, "Deselect clears the selected object, connection mode and resize frame")
        check(store.map == beforeDeselect && store.mapRevision == deselectRevision && canvas.pan == deselectPan && canvas.scale == deselectZoom, "Clearing selection changes neither document data nor viewport")
        store.setStyle { $0.bold.toggle() }; store.setNote("No target"); store.setColor(4); store.setStructure(.rightToLeft)
        store.setConnectionStyle { $0.label = "No target" }; store.deleteSelection(); store.editSelected(); canvas.editSelected()
        check(store.map == beforeDeselect && canvas.editor == nil, "Formatting, Delete and Rename with no selection cannot modify the root or another topic")
        var unselectedChange = beforeDeselect; unselectedChange.topics[0].note = "External edit while deselected"
        store.applyAI(unselectedChange)
        check(store.selectedID == nil, "A document update does not silently reselect the root after deselecting")
        store.apply(beforeDeselect, action: "Restore deselection fixture")
        store.addChild(); canvas.finishEditing()
        check(store.selected?.parentID == firstRoot && store.map.topics.count == beforeDeselect.topics.count + 1, "Add topic without a selection creates and selects a root branch")
        store.apply(beforeDeselect, action: "Restore map after unselected add")
        store.select(child)
        let clearEscape = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil, characters: "\u{1b}", charactersIgnoringModifiers: "\u{1b}", isARepeat: false, keyCode: 53)!
        canvas.keyDown(with: clearEscape)
        check(store.selected == nil && store.map == beforeDeselect, "Escape outside a text edit deselects without changing the map")
        let original = store.workbook
        let second = store.addSheet(title: "Plan")
        check(store.workbook.sheets.count == 2 && store.activeSheet.id == second, "Adding a sheet activates its own root")
        check(store.map.root.id != firstRoot, "Sheets have independent topic trees")
        store.switchSheet(firstID)
        check(store.map.topic(child)?.appearance.shape == .diamond, "Switching sheets retains appearance")
        store.setMode(.outliner); store.select(child); store.editSelected()
        check(store.editingOutlineID == child, "Rename in Outliner targets the selected topic")
        store.addSibling(child)
        let sibling = store.selectedID!
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
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.03))
        canvas.restoreViewport(pan: CGPoint(x: 410, y: 280), scale: 0.85)
        let previousZoom = canvas.scale, previousPan = canvas.pan
        store.selectedID = firstRoot
        for _ in 0..<80 { store.addChild(firstRoot); canvas.finishEditing() }
        check(store.map.children(of: firstRoot).count > 80, "Canvas supports more than six direct root branches")
        check(canvas.scale == previousZoom && store.zoom == previousZoom && canvas.pan == previousPan, "Adding many root branches preserves the current viewport")
        check(store.map.topic(child)?.appearance.fontSize == 27, "Adding branches does not modify existing typography")
        store.load(original)
        let disposable = store.addSheet(title: "Delete check")
        store.deleteSheet(disposable)
        check(store.workbook.sheets.count == 1, "Deleting a sheet retains the remaining tree")
        store.deleteSheet(firstID)
        check(store.workbook.sheets.count == 1, "The last sheet stays protected")
        print("PASS: \(checks) native editor checks")
    }
}
