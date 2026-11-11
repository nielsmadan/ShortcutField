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
        @Published var tag = 0
    }

    @MainActor
    final class ActionCounter {
        var fires = 0
    }

    /// Records the most recent `tag` an action closure fired with, plus how many
    /// times the harness body has been evaluated.
    @MainActor
    final class TagRecorder {
        var firedTag = -1
        var renderCount = 0
    }

    private struct Harness: View {
        @ObservedObject var model: ShortcutModel
        let counter: ActionCounter

        var body: some View {
            Text("shortcut-host")
                .onShortcut(model.shortcut.map(Shortcut.discrete)) {
                    counter.fires += 1
                }
        }
    }

    /// The action closure captures `tag` by value from each body evaluation, so
    /// a stale registered closure would keep firing the original tag.
    private struct StaleActionHarness: View {
        @ObservedObject var model: ShortcutModel
        let recorder: TagRecorder

        var body: some View {
            recorder.renderCount += 1
            let tag = model.tag
            return Text("stale-action-host")
                .onShortcut(model.shortcut.map(Shortcut.discrete)) {
                    recorder.firedTag = tag
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
            if condition() {
                return true
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.02))
        }
        return condition()
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

        // This is where the macOS-13 stale-`self` bug failed.
        model.shortcut = DiscreteShortcut(keyCode: UInt16(kVK_ANSI_S), modifiers: .command)
        #expect(pump { dispatcher.handlerCount == baseline + 1 })

        _ = dispatcher.handleEvent(keyDown(kVK_ANSI_S, .command))
        #expect(counter.fires == 1)

        _ = dispatcher.handleEvent(keyDown(kVK_ANSI_A, .command))
        #expect(counter.fires == 1)
    }

    @Test("the action closure is refreshed when the view re-renders without a shortcut change")
    func actionClosureRefreshesOnRerender() {
        let dispatcher = ShortcutEventDispatcher.shared
        let baseline = dispatcher.handlerCount

        let model = ShortcutModel()
        let recorder = TagRecorder()
        let window = NSWindow(
            contentRect: NSRect(x: -10000, y: -10000, width: 80, height: 40),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = NSHostingView(rootView: StaleActionHarness(model: model, recorder: recorder))
        window.orderFront(nil)
        defer {
            window.orderOut(nil)
            window.contentView = nil
            pump { dispatcher.handlerCount == baseline }
        }

        model.shortcut = DiscreteShortcut(keyCode: UInt16(kVK_ANSI_S), modifiers: .command)
        #expect(pump { dispatcher.handlerCount == baseline + 1 })

        _ = dispatcher.handleEvent(keyDown(kVK_ANSI_S, .command))
        #expect(recorder.firedTag == 0)

        // Changing `tag` (not `shortcut`) re-renders the body without re-running
        // `install()`. The fired action must still see the new tag.
        let rendersBefore = recorder.renderCount
        model.tag = 42
        #expect(pump { recorder.renderCount > rendersBefore })

        _ = dispatcher.handleEvent(keyDown(kVK_ANSI_S, .command))
        #expect(recorder.firedTag == 42)
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

    // MARK: - Scope

    @MainActor
    final class ScopeModel: ObservableObject {
        @Published var scope: ShortcutScope
        init(_ scope: ShortcutScope) {
            self.scope = scope
        }
    }

    private struct ScopedHarness: View {
        @ObservedObject var model: ScopeModel
        let shortcut: Shortcut
        let counter: ActionCounter

        var body: some View {
            Text("scoped-host")
                .onShortcut(shortcut, scope: model.scope) {
                    counter.fires += 1
                }
        }
    }

    final class BindingModel: ObservableObject {
        @Published var shortcut: Shortcut = "cmd+s"
        @Published var scope: ShortcutScope = .app
    }

    private struct BindingHarness: View {
        @ObservedObject var model: BindingModel
        let counter: ActionCounter

        var body: some View {
            Text("binding-host")
                .onShortcut(model.shortcut, scope: model.scope) {
                    counter.fires += 1
                }
        }
    }

    private static func offscreenWindow() -> NSWindow {
        NSWindow(
            contentRect: NSRect(x: -10000, y: -10000, width: 80, height: 40),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
    }

    private func mountScoped(
        _ scope: ShortcutScope,
        shortcut: Shortcut = "cmd+s"
    ) -> (counter: ActionCounter, window: NSWindow, model: ScopeModel) {
        let counter = ActionCounter()
        let model = ScopeModel(scope)
        let window = Self.offscreenWindow()
        window.contentView = NSHostingView(rootView: ScopedHarness(model: model, shortcut: shortcut, counter: counter))
        window.orderFront(nil)
        return (counter, window, model)
    }

    @Test("an app-scoped shortcut fires in every window")
    func appScopeFiresEverywhere() {
        let dispatcher = ShortcutEventDispatcher.shared
        let baseline = dispatcher.handlerCount
        let first = mountScoped(.app)
        let second = mountScoped(.app)
        defer {
            for window in [first.window, second.window] {
                window.orderOut(nil)
                window.contentView = nil
            }
            pump { dispatcher.handlerCount == baseline }
        }
        #expect(pump { dispatcher.handlerCount == baseline + 2 })

        _ = dispatcher.handleEvent(keyDown(kVK_ANSI_S, .command, in: first.window))
        #expect(first.counter.fires == 1)
        #expect(second.counter.fires == 1)
    }

    @Test("a window-scoped shortcut fires only for events sent to its own window")
    func windowScopeFiresOnlyInItsWindow() {
        let dispatcher = ShortcutEventDispatcher.shared
        let baseline = dispatcher.handlerCount
        let first = mountScoped(.window)
        let second = mountScoped(.window)
        defer {
            for window in [first.window, second.window] {
                window.orderOut(nil)
                window.contentView = nil
            }
            pump { dispatcher.handlerCount == baseline }
        }
        #expect(pump { dispatcher.handlerCount == baseline + 2 })

        _ = dispatcher.handleEvent(keyDown(kVK_ANSI_S, .command, in: first.window))
        #expect(first.counter.fires == 1)
        #expect(second.counter.fires == 0)

        _ = dispatcher.handleEvent(keyDown(kVK_ANSI_S, .command, in: second.window))
        #expect(first.counter.fires == 1)
        #expect(second.counter.fires == 1)

        // A keystroke with no window reaches neither.
        _ = dispatcher.handleEvent(keyDown(kVK_ANSI_S, .command))
        #expect(first.counter.fires == 1)
        #expect(second.counter.fires == 1)
    }

    @Test("changing the scope takes effect for later events")
    func scopeChangeTakesEffect() {
        let dispatcher = ShortcutEventDispatcher.shared
        let baseline = dispatcher.handlerCount
        let host = mountScoped(.window)
        let other = Self.offscreenWindow()
        other.orderFront(nil)
        defer {
            for window in [host.window, other] {
                window.orderOut(nil)
                window.contentView = nil
            }
            pump { dispatcher.handlerCount == baseline }
        }
        #expect(pump { dispatcher.handlerCount == baseline + 1 })

        _ = dispatcher.handleEvent(keyDown(kVK_ANSI_S, .command, in: other))
        #expect(host.counter.fires == 0)

        host.model.scope = .app
        pump(timeout: 0.25) { false }
        _ = dispatcher.handleEvent(keyDown(kVK_ANSI_S, .command, in: other))
        #expect(host.counter.fires == 1)

        host.model.scope = .window
        pump(timeout: 0.25) { false }
        _ = dispatcher.handleEvent(keyDown(kVK_ANSI_S, .command, in: other))
        #expect(host.counter.fires == 1)
        _ = dispatcher.handleEvent(keyDown(kVK_ANSI_S, .command, in: host.window))
        #expect(host.counter.fires == 2)
    }

    @Test("a key press in another window ends a window-scoped sequence")
    func otherWindowPressEndsSequence() {
        let dispatcher = ShortcutEventDispatcher.shared
        let baseline = dispatcher.handlerCount
        let host = mountScoped(.window, shortcut: "cmd+k cmd+c")
        let other = Self.offscreenWindow()
        other.orderFront(nil)
        defer {
            for window in [host.window, other] {
                window.orderOut(nil)
                window.contentView = nil
            }
            pump { dispatcher.handlerCount == baseline }
        }
        #expect(pump { dispatcher.handlerCount == baseline + 1 })

        _ = dispatcher.handleEvent(keyDown(kVK_ANSI_K, .command, in: host.window))
        _ = dispatcher.handleEvent(keyDown(kVK_ANSI_X, .command, in: other))
        _ = dispatcher.handleEvent(keyDown(kVK_ANSI_C, .command, in: host.window))
        #expect(host.counter.fires == 0)

        _ = dispatcher.handleEvent(keyDown(kVK_ANSI_K, .command, in: host.window))
        _ = dispatcher.handleEvent(keyDown(kVK_ANSI_C, .command, in: host.window))
        #expect(host.counter.fires == 1)
    }

    @Test("a window-scoped shortcut whose view is in no window ignores windowless events")
    func windowScopeWithoutHostWindow() {
        let dispatcher = ShortcutEventDispatcher.shared
        let baseline = dispatcher.handlerCount
        let counter = ActionCounter()
        let host = NSHostingView(rootView: ScopedHarness(
            model: ScopeModel(.window),
            shortcut: "cmd+s",
            counter: counter
        ))
        host.layoutSubtreeIfNeeded()
        defer {
            // A windowless host never disappears; mount it briefly so its handler unregisters.
            let window = Self.offscreenWindow()
            window.contentView = host
            pump(timeout: 0.2) { false }
            window.contentView = nil
            #expect(pump { dispatcher.handlerCount == baseline })
        }
        #expect(pump { dispatcher.handlerCount == baseline + 1 })
        _ = dispatcher.handleEvent(keyDown(kVK_ANSI_S, .command))
        #expect(counter.fires == 0)
    }

    @Test("a window-scoped shortcut follows its view into another window")
    func windowScopeFollowsMovedView() {
        let dispatcher = ShortcutEventDispatcher.shared
        let baseline = dispatcher.handlerCount
        let first = mountScoped(.window)
        let other = Self.offscreenWindow()
        other.orderFront(nil)
        defer {
            for window in [first.window, other] {
                window.orderOut(nil)
                window.contentView = nil
            }
            pump { dispatcher.handlerCount == baseline }
        }
        #expect(pump { dispatcher.handlerCount == baseline + 1 })
        let host = first.window.contentView
        first.window.contentView = NSView()
        other.contentView = host
        #expect(pump { dispatcher.handlerCount == baseline + 1 })
        _ = dispatcher.handleEvent(keyDown(kVK_ANSI_S, .command, in: other))
        #expect(first.counter.fires == 1)
    }

    @Test("changing the shortcut and the scope together binds the new pair")
    func shortcutAndScopeChangeTogether() {
        let dispatcher = ShortcutEventDispatcher.shared
        let baseline = dispatcher.handlerCount
        let model = BindingModel()
        let counter = ActionCounter()
        let window = Self.offscreenWindow()
        window.contentView = NSHostingView(rootView: BindingHarness(model: model, counter: counter))
        window.orderFront(nil)
        defer {
            window.orderOut(nil)
            window.contentView = nil
            pump { dispatcher.handlerCount == baseline }
        }
        #expect(pump { dispatcher.handlerCount == baseline + 1 })

        model.shortcut = "cmd+d"
        model.scope = .window
        pump(timeout: 0.25) { false }

        _ = dispatcher.handleEvent(keyDown(kVK_ANSI_S, .command, in: window))
        #expect(counter.fires == 0)
        _ = dispatcher.handleEvent(keyDown(kVK_ANSI_D, .command, in: window))
        #expect(counter.fires == 1)
        #expect(dispatcher.handlerCount == baseline + 1)
    }

    @Test("ownership suppresses standalone shortcuts while other windows keep working")
    func ownershipAllowsOtherWindows() {
        let dispatcher = ShortcutEventDispatcher.shared
        let baseline = dispatcher.handlerCount
        let host = mountScoped(.app, shortcut: "cmd+k cmd+c")
        let other = Self.offscreenWindow()
        defer {
            host.window.orderOut(nil)
            host.window.contentView = nil
            pump { dispatcher.handlerCount == baseline }
        }
        #expect(pump { dispatcher.handlerCount == baseline + 1 })
        _ = dispatcher.handleEvent(keyDown(kVK_ANSI_K, .command, in: host.window))
        let token = dispatcher.acquireKeyboardOwnership(for: host.window)
        let completion = keyDown(kVK_ANSI_C, .command, in: host.window)
        #expect(dispatcher.handleEvent(completion) === completion)
        #expect(host.counter.fires == 0)
        _ = dispatcher.handleEvent(keyDown(kVK_ANSI_K, .command, in: other))
        _ = dispatcher.handleEvent(keyDown(kVK_ANSI_C, .command, in: other))
        #expect(host.counter.fires == 1)
        token.release()
        _ = dispatcher.handleEvent(completion)
        #expect(host.counter.fires == 1)
        _ = dispatcher.handleEvent(keyDown(kVK_ANSI_K, .command, in: host.window))
        _ = dispatcher.handleEvent(completion)
        #expect(host.counter.fires == 2)
    }

    @Test("ownership discards a standalone sequence without a window change")
    func ownershipResetsStandaloneMatcherInSameWindow() {
        let dispatcher = ShortcutEventDispatcher.shared
        let baseline = dispatcher.handlerCount
        let host = mountScoped(.app, shortcut: "cmd+k cmd+c")
        defer {
            host.window.orderOut(nil)
            host.window.contentView = nil
            pump { dispatcher.handlerCount == baseline }
        }
        #expect(pump { dispatcher.handlerCount == baseline + 1 })
        let prefix = keyDown(kVK_ANSI_K, .command, in: host.window)
        let completion = keyDown(kVK_ANSI_C, .command, in: host.window)
        _ = dispatcher.handleEvent(prefix)
        let token = dispatcher.acquireKeyboardOwnership(for: host.window)
        token.release()
        _ = dispatcher.handleEvent(completion)
        #expect(host.counter.fires == 0)
        _ = dispatcher.handleEvent(prefix)
        _ = dispatcher.handleEvent(completion)
        #expect(host.counter.fires == 1)
    }
}
