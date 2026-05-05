import SwiftUI

/// A SwiftUI view that lets users record any in-app shortcut (key, mouse button,
/// scroll, or trackpad gesture).
///
/// ```swift
/// @State private var shortcut: Shortcut?
///
/// ShortcutRecorderView($shortcut)
///     .placeholder("Record")
///     .style(.rounded)
/// ```
public struct ShortcutRecorderView: View {
    @Binding var shortcut: Shortcut?

    private var placeholderText: String = "Record Shortcut"
    private var recordingPlaceholderText: String = "Press / click / scroll / gesture\u{2026}"
    private var style: ShortcutRecorderStyle = .rounded
    private var textColorValue: NSColor?
    private var backgroundColorValue: NSColor?
    private var sensitivityModeValue: SensitivityMode = .discrete
    private var sensitivityPositionValue: SensitivityPosition = .below

    /// Create a shortcut recorder bound to the given shortcut value.
    public init(_ shortcut: Binding<Shortcut?>) {
        _shortcut = shortcut
    }

    public var body: some View {
        if showSensitivity {
            sensitivityLayout
        } else {
            fieldView
        }
    }

    @ViewBuilder
    private var sensitivityLayout: some View {
        switch sensitivityPositionValue {
        case .below:
            VStack(spacing: 6) {
                fieldView
                sensitivityControl
            }
        case .left:
            HStack(alignment: .center, spacing: 10) {
                sensitivityControl
                fieldView
            }
        case .right:
            HStack(alignment: .center, spacing: 10) {
                fieldView
                sensitivityControl
            }
        }
    }

    private var fieldView: some View {
        FieldRepresentable(
            shortcut: $shortcut,
            placeholderText: placeholderText,
            recordingPlaceholderText: recordingPlaceholderText,
            style: style,
            textColorValue: textColorValue,
            backgroundColorValue: backgroundColorValue
        )
    }

    private var showSensitivity: Bool {
        guard sensitivityModeValue != .hidden else { return false }
        guard let kind = shortcut?.kind else { return false }
        return Shortcut.isContinuous(kind)
    }

    private var sensitivityControl: some View {
        VStack(spacing: 2) {
            SensitivitySliderRepresentable(
                value: sensitivityBinding,
                snapToTicks: sensitivityModeValue == .discrete
            )
            .frame(width: 130, height: 18)
            Text("Sensitivity")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    private var sensitivityBinding: Binding<Double> {
        Binding(
            get: { shortcut?.sensitivity ?? 0.0 },
            set: { newValue in
                guard let s = shortcut, Shortcut.isContinuous(s.kind) else { return }
                shortcut = Shortcut(kind: s.kind, modifiers: s.modifiers, sensitivity: newValue)
            }
        )
    }
}

private struct FieldRepresentable: NSViewRepresentable {
    @Binding var shortcut: Shortcut?
    var placeholderText: String
    var recordingPlaceholderText: String
    var style: ShortcutRecorderStyle
    var textColorValue: NSColor?
    var backgroundColorValue: NSColor?

    func makeNSView(context _: Context) -> ShortcutRecorderField {
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

    func updateNSView(_ nsView: ShortcutRecorderField, context _: Context) {
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

    /// Set how sensitivity is presented in the recorder. Only shown for
    /// continuous kinds (scroll, pinch, rotate).
    func sensitivityMode(_ mode: SensitivityMode) -> ShortcutRecorderView {
        var view = self
        view.sensitivityModeValue = mode
        return view
    }

    /// Set where the sensitivity control appears relative to the field.
    func sensitivityPosition(_ position: SensitivityPosition) -> ShortcutRecorderView {
        var view = self
        view.sensitivityPositionValue = position
        return view
    }
}
