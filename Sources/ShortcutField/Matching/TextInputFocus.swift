import AppKit

@MainActor
enum TextInputFocus {
    /// Test seam: replaces the live key-window lookup while non-nil. A unit-test
    /// process has no key window, so the live lookup always reports no focus.
    static var responderOverride: (() -> NSResponder?)?

    static var isEditingText: Bool {
        if let responderOverride { return isTextEditing(responderOverride()) }
        return isTextEditing(NSApp?.keyWindow?.firstResponder)
    }

    /// AppKit installs a text field's *field editor* — an `NSTextView` — as the
    /// first responder, so this single check covers `NSTextField`, `NSSearchField`,
    /// `NSTextView`, and the SwiftUI controls backed by them. Buttons and other
    /// non-text responders are excluded, so a shortcut still fires when focus
    /// rests on one.
    ///
    /// A `WKWebView` holding a focused `contenteditable` node reports `false`:
    /// detecting it needs an asynchronous `evaluateJavaScript` round trip, and
    /// this is called synchronously from inside an `NSEvent` monitor.
    static func isTextEditing(_ responder: NSResponder?) -> Bool {
        guard let textView = responder as? NSTextView else { return false }
        return textView.isEditable
    }
}
