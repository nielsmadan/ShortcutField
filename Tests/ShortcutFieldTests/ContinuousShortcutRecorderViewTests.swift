import AppKit
@testable import ShortcutField
import SwiftUI
import Testing

@MainActor
@Suite(.serialized)
struct ContinuousShortcutRecorderViewTests {
    @MainActor
    final class Model: ObservableObject {
        @Published var shortcut: ContinuousShortcut?
        @Published var disabled = false
    }

    private struct Harness: View {
        @ObservedObject var model: Model

        var body: some View {
            ContinuousShortcutRecorderView($model.shortcut)
                .disabled(model.disabled)
        }
    }

    private func mount(_ model: Model) -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: -10000, y: -10000, width: 400, height: 120),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: Harness(model: model))
        window.orderFront(nil)
        window.contentView?.layoutSubtreeIfNeeded()
        return window
    }

    private func unmount(_ window: NSWindow) {
        window.orderOut(nil)
        window.contentView = nil
    }

    /// Lets SwiftUI apply pending updates, including the binding writes it defers.
    private func settle() {
        RunLoop.current.run(until: Date().addingTimeInterval(0.2))
    }

    private func firstSubview<T: NSView>(_: T.Type, in root: NSView?) -> T? {
        guard let root else { return nil }
        if let match = root as? T {
            return match
        }
        return root.subviews.lazy.compactMap { firstSubview(T.self, in: $0) }.first
    }

    @Test func savedSensitivity_isNotRewrittenOnAppear() throws {
        let model = Model()
        model.shortcut = ContinuousShortcut(kind: .pinchIn, modifiers: [], sensitivity: 0.3)
        let window = mount(model)
        defer { unmount(window) }
        let slider = try #require(firstSubview(NSSlider.self, in: window.contentView))

        settle()

        #expect(model.shortcut?.sensitivity == 0.3)
        #expect(slider.doubleValue == SensitivityMode.discrete.snap(0.3))
    }

    @Test func externallySetSensitivity_isNotRewritten() throws {
        let model = Model()
        let window = mount(model)
        defer { unmount(window) }
        let slider = try #require(firstSubview(NSSlider.self, in: window.contentView))

        model.shortcut = ContinuousShortcut(kind: .rotateClockwise, modifiers: [], sensitivity: 0.7)
        settle()

        #expect(model.shortcut?.sensitivity == 0.7)
        #expect(slider.doubleValue == SensitivityMode.discrete.snap(0.7))
    }

    @Test func newRecording_usesTheSensitivityTheSliderShows() throws {
        let model = Model()
        model.shortcut = ContinuousShortcut(kind: .pinchIn, modifiers: [], sensitivity: 0.3)
        let window = mount(model)
        defer { unmount(window) }
        let field = try #require(firstSubview(ContinuousShortcutRecorderField.self, in: window.contentView))
        settle()

        model.shortcut = nil
        settle()

        #expect(field.lastSensitivity == SensitivityMode.discrete.snap(0.3))
    }

    @Test func disablingTheView_endsRecording() throws {
        let model = Model()
        let window = mount(model)
        defer { unmount(window) }
        let field = try #require(firstSubview(ContinuousShortcutRecorderField.self, in: window.contentView))
        field.startRecording()
        defer { field.endRecording() }

        model.disabled = true
        window.contentView?.needsLayout = true
        window.contentView?.layoutSubtreeIfNeeded()

        #expect(!field.isEnabled)
        #expect(!field.isRecording)
    }

    @Test func sensitivitySlider_isLabelledAndReadsAsAPercentage() throws {
        let model = Model()
        model.shortcut = ContinuousShortcut(kind: .pinchIn, modifiers: [], sensitivity: 0.25)
        let window = mount(model)
        defer { unmount(window) }
        let slider = try #require(firstSubview(NSSlider.self, in: window.contentView))
        // The element VoiceOver reads: AppKit ignores the view and exposes its cell.
        let element = try #require(NSAccessibility.unignoredDescendant(of: slider) as? NSCell)
        let percent = { (value: Double) in value.formatted(.percent.precision(.fractionLength(0))) }
        settle()

        #expect(element.accessibilityLabel() == "Sensitivity")
        #expect(element.accessibilityValueDescription() == percent(0.25))

        slider.doubleValue = 0.75
        slider.sendAction(slider.action, to: slider.target)
        settle()

        #expect(element.accessibilityValueDescription() == percent(0.75))

        model.shortcut = ContinuousShortcut(kind: .pinchIn, modifiers: [], sensitivity: 0.5)
        settle()

        #expect(element.accessibilityValueDescription() == percent(0.5))
    }
}
