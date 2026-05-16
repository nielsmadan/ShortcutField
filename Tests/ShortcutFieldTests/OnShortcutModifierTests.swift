import AppKit
import Carbon.HIToolbox
@testable import ShortcutField
import SwiftUI
import Testing

/// Integration tests for the `OnShortcutModifier` SwiftUI glue.
///
/// These mount the real `.onShortcut` modifier in an `NSHostingView` + window
/// and pump the run loop so `.onAppear` / `.onChange` actually fire — the layer
/// pure matcher/dispatcher unit tests can't reach. This is exactly where the
/// macOS-13 `onChange(of:perform:)` stale-`self` bug lived: `.onChange` fired
/// with the correct new value, but `install()` read a stale `self.shortcut ==
/// nil` and never registered a handler.
///
/// `@MainActor` serializes this suite against the other `@MainActor` suites
/// (notably `ShortcutEventDispatcherTests`): `OnShortcutModifier` always talks
/// to `ShortcutEventDispatcher.shared`, so there is no seam to inject an
/// isolated dispatcher into the real modifier. Every assertion is relative to a
/// captured `baseline` handler count rather than an absolute zero.
@MainActor
@Suite(.serialized)
struct OnShortcutModifierTests {
    @MainActor
    final class ShortcutModel: ObservableObject {
        @Published var shortcut: DiscreteShortcut?
    }

    @MainActor
    final class ActionCounter {
        var count = 0
    }

    private struct Harness: View {
        @ObservedObject var model: ShortcutModel
        let counter: ActionCounter

        var body: some View {
            Text("shortcut-host")
                .onShortcut(model.shortcut.map(Shortcut.discrete)) {
                    counter.count += 1
                }
        }
    }

    /// Mounts `Harness` in an off-screen borderless window so SwiftUI runs its
    /// real view lifecycle.
    private func mountHarness() -> (model: ShortcutModel, counter: ActionCounter, window: NSWindow) {
        let model = ShortcutModel()
        let counter = ActionCounter()
        let window = NSWindow(
            contentRect: NSRect(x: -10000, y: -10000, width: 80, height: 40),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = NSHostingView(rootView: Harness(model: model, counter: counter))
        window.orderFront(nil)
        return (model, counter, window)
    }

    /// Pumps the main run loop until `condition` holds or `timeout` elapses;
    /// returns the final value of `condition`. SwiftUI lifecycle callbacks
    /// (`.onAppear`, `.onChange`) only fire across run-loop turns.
    @discardableResult
    private func pump(timeout: TimeInterval = 2.0, until condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.02))
        }
        return condition()
    }

    private func keyDown(_ keyCode: Int, _ modifiers: NSEvent.ModifierFlags) -> NSEvent {
        let cg = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(keyCode), keyDown: true)!
        cg.flags = CGEventFlags(rawValue: UInt64(modifiers.rawValue))
        return NSEvent(cgEvent: cg)!
    }

    @Test("recording a shortcut wires up a dispatcher handler that fires the action")
    func recordingWiresUpAndFires() {
        let dispatcher = ShortcutEventDispatcher.shared
        let baseline = dispatcher.handlerCount

        let (model, counter, window) = mountHarness()
        defer {
            window.orderOut(nil)
            window.contentView = nil
            pump { dispatcher.handlerCount == baseline }
        }

        // While the bound shortcut is nil, `.onAppear` must not register a
        // handler. (Robust to timing: `install(nil)` is a no-op regardless.)
        RunLoop.current.run(until: Date().addingTimeInterval(0.25))
        #expect(dispatcher.handlerCount == baseline)

        // Recording a shortcut must register a handler. The macOS-13
        // `onChange(of:perform:)` stale-`self` bug failed exactly here.
        model.shortcut = DiscreteShortcut(keyCode: UInt16(kVK_ANSI_S), modifiers: .command)
        #expect(pump { dispatcher.handlerCount == baseline + 1 })

        // The registered handler matches the bound shortcut and fires the action.
        _ = dispatcher.handleEvent(keyDown(kVK_ANSI_S, .command))
        #expect(counter.count == 1)

        // A non-matching event does not fire it.
        _ = dispatcher.handleEvent(keyDown(kVK_ANSI_A, .command))
        #expect(counter.count == 1)
    }

    @Test("unmounting the view unregisters its handler")
    func unmountingTearsDown() {
        let dispatcher = ShortcutEventDispatcher.shared
        let baseline = dispatcher.handlerCount

        let (model, _, window) = mountHarness()
        model.shortcut = DiscreteShortcut(keyCode: UInt16(kVK_ANSI_S), modifiers: .command)
        #expect(pump { dispatcher.handlerCount == baseline + 1 })

        window.orderOut(nil)
        window.contentView = nil
        #expect(pump { dispatcher.handlerCount == baseline })
    }
}
