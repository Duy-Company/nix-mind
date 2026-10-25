import SwiftUI
import AppKit

/// Native focus and text commands keep Cmd+F, IME composition and arrow navigation
/// independent of SwiftUI presentation timing and the canvas's first responder.
struct TopicSearchInput: NSViewRepresentable {
    @Binding var query: String
    let focusRequest: UUID
    let moveSelection: (Int) -> Void
    let submit: () -> Void
    let dismiss: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> SearchInputField {
        let field = SearchInputField()
        field.isBezeled = false; field.drawsBackground = false; field.focusRingType = .none
        field.font = .systemFont(ofSize: 19); field.textColor = Palette.ink
        field.placeholderString = "Search topics and notes…"
        field.setAccessibilityLabel("Search topics and notes")
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        field.delegate = context.coordinator
        return field
    }
    func updateNSView(_ field: SearchInputField, context: Context) {
        context.coordinator.parent = self
        if field.stringValue != query { field.stringValue = query }
        if context.coordinator.focusRequest != focusRequest {
            context.coordinator.focusRequest = focusRequest
            if let window = field.window { window.makeFirstResponder(field); field.selectText(nil) }
        }
    }
    @MainActor final class SearchInputField: NSTextField {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let window { window.makeFirstResponder(self) }
        }
    }
    @MainActor final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: TopicSearchInput
        var focusRequest: UUID?
        init(_ parent: TopicSearchInput) { self.parent = parent }
        func controlTextDidChange(_ notification: Notification) {
            if let field = notification.object as? NSTextField {
                parent.query = String(field.stringValue.prefix(128))
            }
        }
        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            // Let the input method consume Return/arrows while composing marked text.
            guard !textView.hasMarkedText() else { return false }
            switch commandSelector {
            case #selector(NSResponder.moveDown(_:)): parent.moveSelection(1)
            case #selector(NSResponder.moveUp(_:)): parent.moveSelection(-1)
            case #selector(NSResponder.insertNewline(_:)): parent.submit()
            case #selector(NSResponder.cancelOperation(_:)): parent.dismiss()
            default: return false
            }
            return true
        }
    }
}
