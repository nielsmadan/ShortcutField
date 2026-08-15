import SwiftUI

/// Internal slider used by recorder views to expose a 0.0-1.0 sensitivity value.
/// Snaps to 5 discrete tick marks when `snapToTicks` is true; otherwise behaves as
/// a continuous slider.
struct SensitivitySliderRepresentable: NSViewRepresentable {
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

        let desired = snapToTicks ? SensitivityMode.discrete.snap(value) : value
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
