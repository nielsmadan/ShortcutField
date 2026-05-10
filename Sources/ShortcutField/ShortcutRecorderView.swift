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
/// ```
///
/// For sensitivity-bearing throttled continuous fire (scroll-to-zoom etc.),
/// use ``ContinuousShortcutRecorderView``.
public struct ShortcutRecorderView: View {
    @Binding var shortcut: Shortcut?
    @Environment(\.isEnabled) private var isEnabled

    private var placeholderText: String = "Record Shortcut"
    private var recordingPlaceholderText: String = "Record shortcut\u{2026}"
    private var textColorValue: NSColor?
    private var minimumWidthValue: CGFloat?

    /// Create a shortcut recorder bound to the given shortcut value.
    public init(_ shortcut: Binding<Shortcut?>) {
        _shortcut = shortcut
    }

    public var body: some View {
        // NSSearchField's native disabled state is barely visible — apply an
        // explicit opacity dim so disabled fields are clearly distinguishable.
        FieldRepresentable(
            shortcut: $shortcut,
            placeholderText: placeholderText,
            recordingPlaceholderText: recordingPlaceholderText,
            textColorValue: textColorValue,
            minimumWidthValue: minimumWidthValue
        )
        .opacity(isEnabled ? 1.0 : 0.5)
    }
}

private struct FieldRepresentable: NSViewRepresentable {
    @Binding var shortcut: Shortcut?

    var placeholderText: String
    var recordingPlaceholderText: String
    var textColorValue: NSColor?
    var minimumWidthValue: CGFloat?

    func makeNSView(context: Context) -> ShortcutRecorderField {
        let field = ShortcutRecorderField()
        field.shortcut = shortcut
        field.defaultPlaceholder = placeholderText
        field.recordingPlaceholder = recordingPlaceholderText
        field.fieldTextColor = textColorValue
        if let minimumWidthValue { field.minimumWidth = minimumWidthValue }
        field.isEnabled = context.environment.isEnabled
        field.onShortcutChange = { newShortcut in
            DispatchQueue.main.async {
                shortcut = newShortcut
            }
        }
        return field
    }

    public func updateNSView(_ nsView: ShortcutRecorderField, context: Context) {
        // Don't update while recording — the async binding update from onShortcutChange
        // can set stringValue on the field editor, triggering controlTextDidEndEditing
        // and prematurely stopping the recording session.
        guard !nsView.isRecording else { return }
        nsView.shortcut = shortcut
        nsView.defaultPlaceholder = placeholderText
        nsView.recordingPlaceholder = recordingPlaceholderText
        nsView.fieldTextColor = textColorValue
        if let minimumWidthValue { nsView.minimumWidth = minimumWidthValue }
        nsView.isEnabled = context.environment.isEnabled
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

    /// Set the text color of the shortcut display.
    func textColor(_ color: NSColor) -> ShortcutRecorderView {
        var view = self
        view.textColorValue = color
        return view
    }

    /// Override the field's minimum intrinsic width. SwiftUI's `.frame(width:)`
    /// still wins over this; the floor only matters when no explicit frame is set.
    func minimumWidth(_ width: CGFloat) -> ShortcutRecorderView {
        var view = self
        view.minimumWidthValue = width
        return view
    }
}
