import SwiftUI

/// A SwiftUI view that lets users record a keyboard shortcut.
///
/// ```swift
/// @State private var shortcut: Shortcut?
///
/// ShortcutRecorderView($shortcut)
///     .placeholder("Record Shortcut")
///     .style(.rounded)
/// ```
public struct ShortcutRecorderView: NSViewRepresentable {
    @Binding var shortcut: Shortcut?

    private var placeholderText: String = "Record Shortcut"
    private var recordingPlaceholderText: String = "Press shortcut..."
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
        field.applyStyle(style)
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
        nsView.applyStyle(style)
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
