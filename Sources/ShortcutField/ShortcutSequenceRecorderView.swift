import SwiftUI

/// A SwiftUI view that lets users record a sequential keyboard shortcut.
///
/// ```swift
/// @State private var sequence: ShortcutSequence?
///
/// ShortcutSequenceRecorderView($sequence)
///     .placeholder("Record Sequence")
///     .style(.rounded)
/// ```
public struct ShortcutSequenceRecorderView: NSViewRepresentable {
    @Binding var shortcutSequence: ShortcutSequence?

    private var placeholderText: String = "Record Sequence"
    private var recordingPlaceholderText: String = "Press keys..."
    private var style: ShortcutRecorderStyle = .rounded
    private var textColorValue: NSColor?
    private var backgroundColorValue: NSColor?

    /// Create a sequence recorder bound to the given sequence value.
    public init(_ shortcutSequence: Binding<ShortcutSequence?>) {
        _shortcutSequence = shortcutSequence
    }

    public func makeNSView(context _: Context) -> ShortcutSequenceRecorderField {
        let field = ShortcutSequenceRecorderField()
        field.shortcutSequence = shortcutSequence
        field.defaultPlaceholder = placeholderText
        field.recordingPlaceholder = recordingPlaceholderText
        field.applyRecorderStyle(style)
        field.fieldTextColor = textColorValue
        field.fieldBackgroundColor = backgroundColorValue
        field.onShortcutSequenceChange = { newSequence in
            DispatchQueue.main.async {
                shortcutSequence = newSequence
            }
        }
        return field
    }

    public func updateNSView(_ nsView: ShortcutSequenceRecorderField, context _: Context) {
        guard !nsView.isRecording else { return }
        nsView.shortcutSequence = shortcutSequence
        nsView.defaultPlaceholder = placeholderText
        nsView.recordingPlaceholder = recordingPlaceholderText
        nsView.applyRecorderStyle(style)
        nsView.fieldTextColor = textColorValue
        nsView.fieldBackgroundColor = backgroundColorValue
    }
}

// MARK: - Modifiers

public extension ShortcutSequenceRecorderView {
    /// Set the placeholder text shown when no sequence is recorded.
    func placeholder(_ text: String) -> ShortcutSequenceRecorderView {
        var view = self
        view.placeholderText = text
        return view
    }

    /// Set the placeholder text shown during recording.
    func recordingPlaceholder(_ text: String) -> ShortcutSequenceRecorderView {
        var view = self
        view.recordingPlaceholderText = text
        return view
    }

    /// Set the visual style of the recorder.
    func style(_ style: ShortcutRecorderStyle) -> ShortcutSequenceRecorderView {
        var view = self
        view.style = style
        return view
    }

    /// Set the text color of the sequence display.
    func textColor(_ color: NSColor) -> ShortcutSequenceRecorderView {
        var view = self
        view.textColorValue = color
        return view
    }

    /// Set the background color of the field.
    func fieldBackgroundColor(_ color: NSColor) -> ShortcutSequenceRecorderView {
        var view = self
        view.backgroundColorValue = color
        return view
    }
}
