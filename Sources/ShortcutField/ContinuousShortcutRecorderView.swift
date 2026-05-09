import SwiftUI

/// A SwiftUI view that lets users record a sensitivity-bearing continuous shortcut
/// (scroll, pinch, or rotate gesture) with a sensitivity slider for tuning the
/// throttle rate.
///
/// ```swift
/// @State private var continuous: ContinuousShortcut?
///
/// ContinuousShortcutRecorderView($continuous)
///     .placeholder("Record")
///     .style(.rounded)
/// ```
public struct ContinuousShortcutRecorderView: View {
    @Binding var continuousShortcut: ContinuousShortcut?

    /// Slider value owned by the view, decoupled from the bound shortcut. Survives
    /// recorder re-records and adjustments made before any shortcut is bound.
    @State private var sensitivity: Double

    private var placeholderText: String = "Record Continuous"
    private var recordingPlaceholderText: String = "Scroll / pinch / rotate\u{2026}"
    private var style: ShortcutRecorderStyle = .rounded
    private var textColorValue: NSColor?
    private var backgroundColorValue: NSColor?
    private var sensitivityModeValue: SensitivityMode = .discrete
    private var sensitivityPositionValue: SensitivityPosition = .below

    /// Create a continuous-shortcut recorder bound to the given value.
    public init(_ continuousShortcut: Binding<ContinuousShortcut?>) {
        _continuousShortcut = continuousShortcut
        _sensitivity = State(initialValue: continuousShortcut.wrappedValue?.sensitivity ?? 0.0)
    }

    @ViewBuilder
    public var body: some View {
        layout
            .onChange(of: continuousShortcut) { newValue in
                // Sync from external/programmatic changes; ignore in-flight changes
                // we caused ourselves (sensitivity already matches).
                if let newValue, abs(newValue.sensitivity - sensitivity) > 0.001 {
                    sensitivity = newValue.sensitivity
                }
            }
    }

    @ViewBuilder
    private var layout: some View {
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
            continuousShortcut: $continuousShortcut,
            sensitivity: sensitivity,
            placeholderText: placeholderText,
            recordingPlaceholderText: recordingPlaceholderText,
            style: style,
            textColorValue: textColorValue,
            backgroundColorValue: backgroundColorValue
        )
    }

    @ViewBuilder
    private var sensitivityControl: some View {
        // In .below mode the label sits beneath the slider. In .left/.right mode
        // we drop the label so the slider's vertical center aligns with the field.
        if sensitivityPositionValue == .below {
            VStack(spacing: 2) {
                slider
                Text("Sensitivity")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        } else {
            slider
        }
    }

    private var slider: some View {
        SensitivitySliderRepresentable(
            value: sensitivityBinding,
            snapToTicks: sensitivityModeValue == .discrete
        )
        .frame(width: 130, height: 18)
    }

    private var sensitivityBinding: Binding<Double> {
        Binding(
            get: { sensitivity },
            set: { newValue in
                sensitivity = newValue
                if let s = continuousShortcut {
                    continuousShortcut = ContinuousShortcut(
                        kind: s.kind,
                        modifiers: s.modifiers,
                        sensitivity: newValue
                    )
                }
            }
        )
    }
}

private struct FieldRepresentable: NSViewRepresentable {
    @Binding var continuousShortcut: ContinuousShortcut?
    var sensitivity: Double
    var placeholderText: String
    var recordingPlaceholderText: String
    var style: ShortcutRecorderStyle
    var textColorValue: NSColor?
    var backgroundColorValue: NSColor?

    func makeNSView(context _: Context) -> ContinuousShortcutRecorderField {
        let field = ContinuousShortcutRecorderField()
        field.lastSensitivity = sensitivity
        field.shortcut = continuousShortcut
        field.defaultPlaceholder = placeholderText
        field.recordingPlaceholder = recordingPlaceholderText
        field.applyRecorderStyle(style)
        field.fieldTextColor = textColorValue
        field.fieldBackgroundColor = backgroundColorValue
        field.onShortcutChange = { newValue in
            DispatchQueue.main.async {
                continuousShortcut = newValue
            }
        }
        return field
    }

    func updateNSView(_ nsView: ContinuousShortcutRecorderField, context _: Context) {
        guard !nsView.isRecording else { return }
        // Push the SwiftUI view's slider value into the field so a fresh recording
        // (or chevron-menu pick) uses the user's last-set sensitivity.
        nsView.lastSensitivity = sensitivity
        nsView.shortcut = continuousShortcut
        nsView.defaultPlaceholder = placeholderText
        nsView.recordingPlaceholder = recordingPlaceholderText
        nsView.applyRecorderStyle(style)
        nsView.fieldTextColor = textColorValue
        nsView.fieldBackgroundColor = backgroundColorValue
    }
}

// MARK: - Modifiers

public extension ContinuousShortcutRecorderView {
    /// Set the placeholder text shown when no shortcut is recorded.
    func placeholder(_ text: String) -> ContinuousShortcutRecorderView {
        var view = self
        view.placeholderText = text
        return view
    }

    /// Set the placeholder text shown during recording.
    func recordingPlaceholder(_ text: String) -> ContinuousShortcutRecorderView {
        var view = self
        view.recordingPlaceholderText = text
        return view
    }

    /// Set the visual style of the recorder.
    func style(_ style: ShortcutRecorderStyle) -> ContinuousShortcutRecorderView {
        var view = self
        view.style = style
        return view
    }

    /// Set the text color of the shortcut display.
    func textColor(_ color: NSColor) -> ContinuousShortcutRecorderView {
        var view = self
        view.textColorValue = color
        return view
    }

    /// Set the background color of the field.
    func fieldBackgroundColor(_ color: NSColor) -> ContinuousShortcutRecorderView {
        var view = self
        view.backgroundColorValue = color
        return view
    }

    /// Set how sensitivity is presented in the recorder.
    func sensitivityMode(_ mode: SensitivityMode) -> ContinuousShortcutRecorderView {
        var view = self
        view.sensitivityModeValue = mode
        return view
    }

    /// Set where the sensitivity control appears relative to the field.
    func sensitivityPosition(_ position: SensitivityPosition) -> ContinuousShortcutRecorderView {
        var view = self
        view.sensitivityPositionValue = position
        return view
    }
}
