import SwiftUI

/// A SwiftUI view that lets users record a fire-once shortcut.
///
/// The user can record a single keystroke / mouse click / scroll / gesture, or a
/// multi-step sequence — the recorder captures whatever they perform. Recording
/// finalizes after a 1-second pause OR on a bare left-click anywhere (no
/// modifiers).
///
/// ```swift
/// @State private var shortcut: Shortcut?
///
/// ShortcutRecorderView($shortcut)
///     .placeholder("Record")
///     .style(.rounded)
/// ```
///
/// For sensitivity-bearing throttled continuous fire (scroll-to-zoom etc.),
/// use ``ContinuousShortcutRecorderView``.
public struct ShortcutRecorderView: NSViewRepresentable {
    @Binding var shortcut: Shortcut?

    private var placeholderText: String = "Record Shortcut"
    private var recordingPlaceholderText: String = "Record shortcut\u{2026}"
    private var style: ShortcutRecorderStyle = .rounded
    private var textColorValue: NSColor?
    private var backgroundColorValue: NSColor?

    /// Create a shortcut recorder bound to the given shortcut value.
    public init(_ shortcut: Binding<Shortcut?>) {
        _shortcut = shortcut
    }

    public func makeNSView(context _: Context) -> ShortcutRecorderField {
        let field = ShortcutRecorderField()
        field.shortcut = shortcut
        field.defaultPlaceholder = placeholderText
        field.recordingPlaceholder = recordingPlaceholderText
        field.applyRecorderStyle(style)
        field.fieldTextColor = textColorValue
        field.fieldBackgroundColor = backgroundColorValue
        field.onShortcutChange = { newShortcut in
            DispatchQueue.main.async {
                shortcut = newShortcut
            }
        }
        return field
    }

    public func updateNSView(_ nsView: ShortcutRecorderField, context _: Context) {
        // Don't update while recording — the async binding update from onShortcutChange
        // can set stringValue on the field editor, triggering controlTextDidEndEditing
        // and prematurely stopping the recording session.
        guard !nsView.isRecording else { return }
        nsView.shortcut = shortcut
        nsView.defaultPlaceholder = placeholderText
        nsView.recordingPlaceholder = recordingPlaceholderText
        nsView.applyRecorderStyle(style)
        nsView.fieldTextColor = textColorValue
        nsView.fieldBackgroundColor = backgroundColorValue
    }
}

// MARK: - Modifiers

public extension ShortcutRecorderView {
    /// Set the placeholder text shown when no shortcut is recorded.
    func placeholder(_ text: String) -> ShortcutRecorderView {
        var view = self
        view.placeholderText = text
        return view
    }

    /// Set the placeholder text shown during recording.
    func recordingPlaceholder(_ text: String) -> ShortcutRecorderView {
        var view = self
        view.recordingPlaceholderText = text
        return view
    }

    /// Set the visual style of the recorder.
    func style(_ style: ShortcutRecorderStyle) -> ShortcutRecorderView {
        var view = self
        view.style = style
        return view
    }

    /// Set the text color of the shortcut display.
    func textColor(_ color: NSColor) -> ShortcutRecorderView {
        var view = self
        view.textColorValue = color
        return view
    }

    /// Set the background color of the field.
    func fieldBackgroundColor(_ color: NSColor) -> ShortcutRecorderView {
        var view = self
        view.backgroundColorValue = color
        return view
    }
}
