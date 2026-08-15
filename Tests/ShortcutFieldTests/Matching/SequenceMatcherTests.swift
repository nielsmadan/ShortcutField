import AppKit
import Carbon.HIToolbox
@testable import ShortcutField
import Testing

@MainActor
@Suite("SequenceMatcher")
struct SequenceMatcherTests {
    @Test("single-step discrete shortcut fires on its event")
    func singleStepFires() {
        let matcher = SequenceMatcher()
        matcher.configure(
            shortcut: DiscreteShortcut(keyCode: UInt16(kVK_ANSI_S), modifiers: .command)
        )
        let result = matcher.handle(keyDown(kVK_ANSI_S, .command))
        #expect(result == .fired)
    }

    @Test("non-matching event is ignored")
    func nonMatchingIgnored() {
        let matcher = SequenceMatcher()
        matcher.configure(
            shortcut: DiscreteShortcut(keyCode: UInt16(kVK_ANSI_S), modifiers: .command)
        )
        let result = matcher.handle(keyDown(kVK_ANSI_A, .command))
        #expect(result == .ignored)
    }

    @Test("multi-step shortcut advances then fires")
    func multiStepAdvancesThenFires() {
        let matcher = SequenceMatcher()
        matcher.configure(
            shortcut: DiscreteShortcut(steps: [
                .init(keyCode: UInt16(kVK_ANSI_K), modifiers: .command),
                .init(keyCode: UInt16(kVK_ANSI_C), modifiers: .command),
            ])
        )
        #expect(matcher.handle(keyDown(kVK_ANSI_K, .command)) == .advanced(consumeEvent: false))
        #expect(matcher.handle(keyDown(kVK_ANSI_C, .command)) == .fired)
    }

    @Test("a mismatch mid-sequence resets to the start")
    func midSequenceMissResets() {
        let matcher = SequenceMatcher()
        matcher.configure(
            shortcut: DiscreteShortcut(steps: [
                .init(keyCode: UInt16(kVK_ANSI_K), modifiers: .command),
                .init(keyCode: UInt16(kVK_ANSI_C), modifiers: .command),
            ])
        )
        #expect(matcher.handle(keyDown(kVK_ANSI_K, .command)) == .advanced(consumeEvent: false))
        #expect(matcher.handle(keyDown(kVK_ANSI_X, .command)) == .ignored)
        // Back at step 0: the first step advances again rather than firing.
        #expect(matcher.handle(keyDown(kVK_ANSI_K, .command)) == .advanced(consumeEvent: false))
    }

    @Test("an unfinished sequence resets after the step timeout")
    func timeoutResetsSequence() async {
        let baseline = ShortcutTracking.isActive
        let matcher = SequenceMatcher(stepTimeout: 0.01)
        matcher.configure(
            shortcut: DiscreteShortcut(steps: [
                .init(keyCode: UInt16(kVK_ANSI_K), modifiers: .command),
                .init(keyCode: UInt16(kVK_ANSI_C), modifiers: .command),
            ])
        )
        #expect(matcher.handle(keyDown(kVK_ANSI_K, .command)) == .advanced(consumeEvent: false))
        #expect(ShortcutTracking.isActive == true)
        // Await the timeout task itself rather than racing a wall-clock sleep.
        await matcher.pendingTimeoutTask?.value
        // Tracking must end too, or a later unrelated key stays beep-suppressed.
        #expect(matcher.handle(keyDown(kVK_ANSI_C, .command)) == .ignored)
        #expect(ShortcutTracking.isActive == baseline)
    }

    @Test("an intermediate Tab step consumes the event")
    func tabStepConsumesEvent() {
        let matcher = SequenceMatcher()
        matcher.configure(
            shortcut: DiscreteShortcut(steps: [
                .init(keyCode: UInt16(kVK_Tab), modifiers: []),
                .init(keyCode: UInt16(kVK_ANSI_C), modifiers: .command),
            ])
        )
        // Tab as an intermediate step is consumed so it doesn't also drive focus.
        #expect(matcher.handle(keyDown(kVK_Tab, [])) == .advanced(consumeEvent: true))
    }

    @Test("trackingStateDidChange is forwarded on advance and completion")
    func trackingStateDidChangeForwarded() {
        let matcher = SequenceMatcher()
        var states: [Bool] = []
        matcher.trackingStateDidChange = { states.append($0) }
        matcher.configure(
            shortcut: DiscreteShortcut(steps: [
                .init(keyCode: UInt16(kVK_ANSI_K), modifiers: .command),
                .init(keyCode: UInt16(kVK_ANSI_C), modifiers: .command),
            ])
        )
        _ = matcher.handle(keyDown(kVK_ANSI_K, .command))
        _ = matcher.handle(keyDown(kVK_ANSI_C, .command))
        #expect(states == [true, false])
    }
}
