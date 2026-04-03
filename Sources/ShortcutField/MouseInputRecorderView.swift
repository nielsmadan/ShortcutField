import SwiftUI

/// A SwiftUI view that lets users record a mouse button or scroll wheel input.
///
/// ```swift
/// @State private var mouseInput: MouseInput?
///
/// MouseInputRecorderView($mouseInput)
///     .placeholder("Record Mouse")
///     .style(.rounded)
/// ```
public struct MouseInputRecorderView: View {
    @Binding var mouseInput: MouseInput?

    private var placeholderText: String = "Record Mouse"
    private var recordingPlaceholderText: String = "Click or scroll\u{2026}"
    private var style: ShortcutRecorderStyle = .rounded
    private var textColorValue: NSColor?
    private var backgroundColorValue: NSColor?
    private var sensitivityModeValue: ScrollSensitivityMode = .discrete
    private var sensitivityPositionValue: ScrollSensitivityPosition = .below

    /// Create a mouse input recorder bound to the given value.
    public init(_ mouseInput: Binding<MouseInput?>) {
        _mouseInput = mouseInput
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
            mouseInput: $mouseInput,
            placeholderText: placeholderText,
            recordingPlaceholderText: recordingPlaceholderText,
            style: style,
            textColorValue: textColorValue,
            backgroundColorValue: backgroundColorValue
        )
    }

    private var showSensitivity: Bool {
        guard sensitivityModeValue != .hidden else { return false }
        if case .scroll = mouseInput?.kind { return true }
        return false
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
            get: { mouseInput?.scrollSensitivity ?? 0.0 },
            set: { newValue in
                guard let input = mouseInput, case .scroll = input.kind else { return }
                mouseInput = MouseInput(
                    kind: input.kind, modifiers: input.modifiers, scrollSensitivity: newValue
                )
            }
        )
    }
}

private struct SensitivitySliderRepresentable: NSViewRepresentable {
    @Binding var value: Double
    var snapToTicks: Bool

    func makeNSView(context: Context) -> NSSlider {
        let slider = NSSlider(
            value: value,
            minValue: 0.0,
            maxValue: 1.0,
            target: context.coordinator,
            action: #selector(Coordinator.changed(_:))
        )
        slider.numberOfTickMarks = 5
        slider.tickMarkPosition = .below
        slider.allowsTickMarkValuesOnly = snapToTicks
        slider.controlSize = .small
        return slider
    }

    func updateNSView(_ nsView: NSSlider, context: Context) {
        context.coordinator.value = $value
        nsView.allowsTickMarkValuesOnly = snapToTicks

        let desired: Double
        if snapToTicks {
            let ticks = ScrollSensitivityMode.discreteValues
            desired = ticks[ScrollSensitivityMode.discreteIndex(for: value)]
            if abs(desired - value) > 0.001 {
                let binding = $value
                DispatchQueue.main.async { binding.wrappedValue = desired }
            }
        } else {
            desired = value
        }

        if abs(nsView.doubleValue - desired) > 0.001 {
            nsView.doubleValue = desired
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(value: $value)
    }

    @MainActor
    final class Coordinator: NSObject {
        var value: Binding<Double>

        init(value: Binding<Double>) {
            self.value = value
        }

        @objc func changed(_ sender: NSSlider) {
            value.wrappedValue = sender.doubleValue
        }
    }
}

private struct FieldRepresentable: NSViewRepresentable {
    @Binding var mouseInput: MouseInput?
    var placeholderText: String
    var recordingPlaceholderText: String
    var style: ShortcutRecorderStyle
    var textColorValue: NSColor?
    var backgroundColorValue: NSColor?

    func makeNSView(context _: Context) -> MouseInputRecorderField {
        let field = MouseInputRecorderField()
        field.mouseInput = mouseInput
        field.defaultPlaceholder = placeholderText
        field.recordingPlaceholder = recordingPlaceholderText
        field.applyRecorderStyle(style)
        field.fieldTextColor = textColorValue
        field.fieldBackgroundColor = backgroundColorValue
        field.onMouseInputChange = { newInput in
            DispatchQueue.main.async {
                mouseInput = newInput
            }
        }
        return field
    }

    func updateNSView(_ nsView: MouseInputRecorderField, context _: Context) {
        // Don't update while recording — the async binding update from onMouseInputChange
        // can set stringValue on the field editor, triggering controlTextDidEndEditing
        // and prematurely stopping the recording session.
        guard !nsView.isRecording else { return }
        nsView.mouseInput = mouseInput
        nsView.defaultPlaceholder = placeholderText
        nsView.recordingPlaceholder = recordingPlaceholderText
        nsView.applyRecorderStyle(style)
        nsView.fieldTextColor = textColorValue
        nsView.fieldBackgroundColor = backgroundColorValue
    }
}

// MARK: - Modifiers

public extension MouseInputRecorderView {
    /// Set the placeholder text shown when no mouse input is recorded.
    func placeholder(_ text: String) -> MouseInputRecorderView {
        var view = self
        view.placeholderText = text
        return view
    }

    /// Set the placeholder text shown during recording.
    func recordingPlaceholder(_ text: String) -> MouseInputRecorderView {
        var view = self
        view.recordingPlaceholderText = text
        return view
    }

    /// Set the visual style of the recorder.
    func style(_ style: ShortcutRecorderStyle) -> MouseInputRecorderView {
        var view = self
        view.style = style
        return view
    }

    /// Set the text color of the mouse input display.
    func textColor(_ color: NSColor) -> MouseInputRecorderView {
        var view = self
        view.textColorValue = color
        return view
    }

    /// Set the background color of the field.
    func fieldBackgroundColor(_ color: NSColor) -> MouseInputRecorderView {
        var view = self
        view.backgroundColorValue = color
        return view
    }

    /// Set how scroll sensitivity is presented in the recorder.
    func sensitivityMode(_ mode: ScrollSensitivityMode) -> MouseInputRecorderView {
        var view = self
        view.sensitivityModeValue = mode
        return view
    }

    /// Set where the scroll sensitivity control appears relative to the field.
    func sensitivityPosition(_ position: ScrollSensitivityPosition) -> MouseInputRecorderView {
        var view = self
        view.sensitivityPositionValue = position
        return view
    }
}
