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
/// ```
public struct ContinuousShortcutRecorderView: View {
    @Binding var shortcut: ContinuousShortcut?
    @Environment(\.isEnabled) private var isEnabled

    /// Slider value owned by the view, decoupled from the bound shortcut. Survives
    /// recorder re-records and adjustments made before any shortcut is bound.
    @State private var sensitivity: Double

    private var placeholderText: String = "Record Continuous"
    private var recordingPlaceholderText: String = "Scroll / pinch / rotate\u{2026}"
    private var textColorValue: NSColor?
    private var minimumWidthValue: CGFloat?
    private var labelStyleValue: ShortcutLabelStyle = .text
    private var sensitivityModeValue: SensitivityMode = .discrete
    private var sensitivityPositionValue: SensitivityPosition = .below

    /// Create a continuous-shortcut recorder bound to the given value.
    public init(_ shortcut: Binding<ContinuousShortcut?>) {
        _shortcut = shortcut
        _sensitivity = State(initialValue: shortcut.wrappedValue?.sensitivity ?? 0.0)
    }

    @ViewBuilder
    public var body: some View {
        // NSSearchField's native disabled state is barely visible — apply an
        // explicit opacity dim so disabled fields are clearly distinguishable.
        layout
            .opacity(isEnabled ? 1.0 : 0.5)
            .onChange(of: shortcut) { newValue in
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
            shortcut: $shortcut,
            sensitivity: sensitivity,
            placeholderText: placeholderText,
            recordingPlaceholderText: recordingPlaceholderText,
            textColorValue: textColorValue,
            minimumWidthValue: minimumWidthValue,
            labelStyleValue: labelStyleValue
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
                if let s = shortcut {
                    shortcut = ContinuousShortcut(
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
    @Binding var shortcut: ContinuousShortcut?
    var sensitivity: Double
    var placeholderText: String
    var recordingPlaceholderText: String
    var textColorValue: NSColor?
    var minimumWidthValue: CGFloat?
    var labelStyleValue: ShortcutLabelStyle

    func makeNSView(context: Context) -> ContinuousShortcutRecorderField {
        let field = ContinuousShortcutRecorderField()
        field.lastSensitivity = sensitivity
        field.shortcut = shortcut
        field.defaultPlaceholder = placeholderText
        field.recordingPlaceholder = recordingPlaceholderText
        field.fieldTextColor = textColorValue
        field.labelStyle = labelStyleValue
        if let minimumWidthValue { field.minimumWidth = minimumWidthValue }
        field.isEnabled = context.environment.isEnabled
        field.onShortcutChange = { newValue in
            DispatchQueue.main.async {
                shortcut = newValue
            }
        }
        return field
    }

    func updateNSView(_ nsView: ContinuousShortcutRecorderField, context: Context) {
        guard !nsView.isRecording else { return }
        // Push the SwiftUI view's slider value into the field so a fresh recording
        // (or chevron-menu pick) uses the user's last-set sensitivity.
        nsView.lastSensitivity = sensitivity
        nsView.shortcut = shortcut
        nsView.defaultPlaceholder = placeholderText
        nsView.recordingPlaceholder = recordingPlaceholderText
        nsView.fieldTextColor = textColorValue
        nsView.labelStyle = labelStyleValue
        if let minimumWidthValue { nsView.minimumWidth = minimumWidthValue }
        nsView.isEnabled = context.environment.isEnabled
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

    /// Set the text color of the shortcut display.
    func textColor(_ color: Color) -> ContinuousShortcutRecorderView {
        var view = self
        view.textColorValue = NSColor(color)
        return view
    }

    /// Override the field's minimum intrinsic width. SwiftUI's `.frame(width:)`
    /// still wins over this; the floor only matters when no explicit frame is set.
    func minimumWidth(_ width: CGFloat) -> ContinuousShortcutRecorderView {
        var view = self
        view.minimumWidthValue = width
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

    /// Choose how the recorded shortcut is displayed: verbose ``ShortcutLabelStyle/text``
    /// (default) or compact ``ShortcutLabelStyle/compact`` (SF Symbols, with the full text
    /// as the field's tooltip). Also styles the chevron kind-picker menu.
    ///
    /// Named `shortcutLabelStyle` (not `labelStyle`) to avoid colliding with SwiftUI's
    /// generic `View.labelStyle(_:)`.
    func shortcutLabelStyle(_ style: ShortcutLabelStyle) -> ContinuousShortcutRecorderView {
        var view = self
        view.labelStyleValue = style
        return view
    }
}
