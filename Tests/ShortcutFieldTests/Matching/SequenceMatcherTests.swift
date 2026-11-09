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
        let matcher = SequenceMatcher(stepTimeout: 0.01)
        // The global tracking count can't be compared across the await: other suites move it.
        var states: [Bool] = []
        matcher.trackingStateDidChange = { states.append($0) }
        matcher.configure(
            shortcut: DiscreteShortcut(steps: [
                .init(keyCode: UInt16(kVK_ANSI_K), modifiers: .command),
                .init(keyCode: UInt16(kVK_ANSI_C), modifiers: .command),
            ])
        )
        #expect(matcher.handle(keyDown(kVK_ANSI_K, .command)) == .advanced(consumeEvent: false))
        // Await the timeout task itself rather than racing a wall-clock sleep.
        await matcher.pendingTimeoutTask?.value
        // Tracking must end too, or a later unrelated key stays beep-suppressed.
        #expect(states == [true, false])
        #expect(matcher.handle(keyDown(kVK_ANSI_C, .command)) == .ignored)
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

    // MARK: - Restarts and key repeat

    private static let commandKThenC = DiscreteShortcut(steps: [
        .init(keyCode: UInt16(kVK_ANSI_K), modifiers: .command),
        .init(keyCode: UInt16(kVK_ANSI_C), modifiers: .command),
    ])

    @Test("a key that breaks the sequence is tried again as its first step")
    func pressingFirstStepTwiceRestarts() {
        let matcher = SequenceMatcher()
        matcher.configure(shortcut: Self.commandKThenC)
        #expect(matcher.handle(keyDown(kVK_ANSI_K, .command)) == .advanced(consumeEvent: false))
        #expect(matcher.handle(keyDown(kVK_ANSI_K, .command)) == .advanced(consumeEvent: false))
        #expect(matcher.handle(keyDown(kVK_ANSI_C, .command)) == .fired)
    }

    @Test("holding the first step's key keeps the sequence waiting for the next step", arguments: [1, 2, 3])
    func heldFirstStepStillCompletes(repeats: Int) {
        let matcher = SequenceMatcher()
        matcher.configure(shortcut: Self.commandKThenC)
        #expect(matcher.handle(keyDown(kVK_ANSI_K, .command)) == .advanced(consumeEvent: false))
        for _ in 0 ..< repeats {
            #expect(matcher.handle(keyDown(kVK_ANSI_K, .command, isRepeat: true)) == .advanced(consumeEvent: false))
        }
        #expect(matcher.handle(keyDown(kVK_ANSI_C, .command)) == .fired)
    }

    @Test("restarting a sequence reports one tracking change, not an end and a new start")
    func restartReportsTrackingOnce() {
        let matcher = SequenceMatcher()
        var states: [Bool] = []
        matcher.trackingStateDidChange = { states.append($0) }
        matcher.configure(shortcut: Self.commandKThenC)
        _ = matcher.handle(keyDown(kVK_ANSI_K, .command))
        _ = matcher.handle(keyDown(kVK_ANSI_K, .command))
        _ = matcher.handle(keyDown(kVK_ANSI_C, .command))
        #expect(states == [true, false])
    }

    @Test("a held Tab step keeps consuming its repeats so focus doesn't move")
    func heldTabStepConsumesRepeats() {
        let matcher = SequenceMatcher()
        matcher.configure(shortcut: DiscreteShortcut(steps: [
            .init(keyCode: UInt16(kVK_Tab), modifiers: []),
            .init(keyCode: UInt16(kVK_ANSI_X), modifiers: []),
        ]))
        #expect(matcher.handle(keyDown(kVK_Tab)) == .advanced(consumeEvent: true))
        #expect(matcher.handle(keyDown(kVK_Tab, isRepeat: true)) == .advanced(consumeEvent: true))
        #expect(matcher.handle(keyDown(kVK_ANSI_X)) == .fired)
    }

    @Test("a key that matches no step, not even the first, ends the sequence")
    func unmatchedRestartEndsTracking() {
        let matcher = SequenceMatcher()
        var states: [Bool] = []
        matcher.trackingStateDidChange = { states.append($0) }
        matcher.configure(shortcut: Self.commandKThenC)

        #expect(matcher.handle(keyDown(kVK_ANSI_K, .command)) == .advanced(consumeEvent: false))
        #expect(matcher.handle(keyDown(kVK_ANSI_X, .command)) == .ignored)

        #expect(states == [true, false])
        #expect(!matcher.isTracking)
    }

    @Test("a held step's repeat restarts the step timeout")
    func heldStepRepeatRestartsTimeout() async {
        let matcher = SequenceMatcher(stepTimeout: 2)
        matcher.configure(shortcut: Self.commandKThenC)
        _ = matcher.handle(keyDown(kVK_ANSI_K, .command))
        let armedByThePress = matcher.pendingTimeoutTask

        _ = matcher.handle(keyDown(kVK_ANSI_K, .command, isRepeat: true))
        await armedByThePress?.value

        #expect(matcher.isTracking)
        #expect(matcher.handle(keyDown(kVK_ANSI_C, .command)) == .fired)
    }

    @Test("a repeat of some other key ends the sequence")
    func otherKeyRepeatResets() {
        let matcher = SequenceMatcher()
        matcher.configure(shortcut: Self.commandKThenC)
        _ = matcher.handle(keyDown(kVK_ANSI_K, .command))
        #expect(matcher.handle(keyDown(kVK_ANSI_X, .command, isRepeat: true)) == .ignored)
        #expect(!matcher.isTracking)
        #expect(matcher.handle(keyDown(kVK_ANSI_C, .command)) == .ignored)
    }

    @Test("a key repeat never completes a later step")
    func repeatNeverMatchesLaterStep() {
        let matcher = SequenceMatcher()
        let k = DiscreteShortcut.Step(keyCode: UInt16(kVK_ANSI_K), modifiers: .command)
        matcher.configure(shortcut: DiscreteShortcut(steps: [k, k]))
        #expect(matcher.handle(keyDown(kVK_ANSI_K, .command)) == .advanced(consumeEvent: false))
        #expect(matcher.handle(keyDown(kVK_ANSI_K, .command, isRepeat: true)) == .advanced(consumeEvent: false))
        #expect(matcher.handle(keyDown(kVK_ANSI_K, .command)) == .fired)
    }

    // MARK: - Trackpad bursts

    @Test("a scroll step fires once per trackpad burst and consumes the rest of it and its momentum")
    func phasedScrollBurstFiresOnce() {
        let matcher = SequenceMatcher()
        matcher.configure(shortcut: DiscreteShortcut(kind: .scroll(direction: .up), modifiers: []))
        let consumed = ShortcutMatchResult.advanced(consumeEvent: true)

        #expect(matcher.handle(scrollEvent(deltaY: 10, phase: .began)) == .fired)
        #expect(matcher.handle(scrollEvent(deltaY: 10, phase: .changed)) == consumed)
        #expect(matcher.handle(scrollEvent(deltaY: -3, phase: .changed)) == consumed)
        #expect(matcher.handle(scrollEvent(phase: .ended)) == .ignored)
        #expect(matcher.handle(scrollEvent(deltaY: 10, momentum: .began)) == consumed)
        #expect(matcher.handle(scrollEvent(deltaY: 4, momentum: .changed)) == consumed)
        #expect(matcher.handle(scrollEvent(momentum: .ended)) == consumed)
        #expect(matcher.handle(scrollEvent(deltaY: 10, momentum: .began)) == .ignored)
        #expect(matcher.handle(scrollEvent(deltaY: 10, phase: .began)) == .fired)
    }

    @Test("a trackpad burst that matches no step passes through with its momentum")
    func unmatchedScrollBurstPassesThrough() {
        let matcher = SequenceMatcher()
        matcher.configure(shortcut: DiscreteShortcut(kind: .scroll(direction: .up), modifiers: []))

        #expect(matcher.handle(scrollEvent(deltaY: -10, phase: .began)) == .ignored)
        #expect(matcher.handle(scrollEvent(phase: .ended)) == .ignored)
        #expect(matcher.handle(scrollEvent(deltaY: -10, momentum: .began)) == .ignored)
        #expect(matcher.handle(scrollEvent(momentum: .ended)) == .ignored)
    }

    @Test("a pinch burst and a rotate burst in progress together each keep their own claim")
    func overlappingBurstsKeepTheirOwnClaims() {
        let matcher = SequenceMatcher()
        matcher.configure(shortcut: DiscreteShortcut(steps: [
            .init(kind: .pinchIn, modifiers: []),
            .init(kind: .rotateClockwise, modifiers: []),
        ]))

        #expect(matcher.handle(gestureEvent(.magnify, 0, phase: .began)) == .ignored)
        #expect(matcher.handle(gestureEvent(.magnify, -0.2)) == .advanced(consumeEvent: false))
        #expect(matcher.handle(gestureEvent(.rotate, 0, phase: .began)) == .ignored)
        #expect(matcher.handle(gestureEvent(.rotate, -10)) == .fired)
        #expect(matcher.handle(gestureEvent(.magnify, -0.2)) == .ignored)
        #expect(matcher.handle(gestureEvent(.rotate, -10)) == .advanced(consumeEvent: true))
    }

    @Test("two scroll steps need two trackpad bursts")
    func twoScrollStepsNeedTwoBursts() {
        let matcher = SequenceMatcher()
        let up = DiscreteShortcut.Step(kind: .scroll(direction: .up), modifiers: [])
        matcher.configure(shortcut: DiscreteShortcut(steps: [up, up]))

        // The step's own event reaches the view beneath, so the rest of the burst does too.
        #expect(matcher.handle(scrollEvent(deltaY: 10, phase: .began)) == .advanced(consumeEvent: false))
        #expect(matcher.handle(scrollEvent(deltaY: 10, phase: .changed)) == .ignored)
        #expect(matcher.handle(scrollEvent(phase: .ended)) == .ignored)
        #expect(matcher.handle(scrollEvent(deltaY: 10, momentum: .began)) == .ignored)
        #expect(matcher.handle(scrollEvent(deltaY: 10, phase: .began)) == .fired)
    }

    @Test("a fired burst whose end never arrives doesn't swallow the next burst or a wheel notch")
    func burstWithoutEndDoesNotStick() {
        let matcher = SequenceMatcher()
        matcher.configure(shortcut: DiscreteShortcut(kind: .scroll(direction: .up), modifiers: []))

        #expect(matcher.handle(scrollEvent(deltaY: 10, phase: .began)) == .fired)
        #expect(matcher.handle(scrollEvent(deltaY: 10)) == .fired)
        #expect(matcher.handle(scrollEvent(deltaY: -10, phase: .began)) == .ignored)
        #expect(matcher.handle(scrollEvent(deltaY: -10, phase: .changed)) == .ignored)
    }

    @Test("a new burst ends the coast of an earlier fired one, even if its own end never arrives")
    func newBurstStopsCoast() {
        let matcher = SequenceMatcher()
        matcher.configure(shortcut: DiscreteShortcut(kind: .scroll(direction: .up), modifiers: []))

        #expect(matcher.handle(scrollEvent(deltaY: 10, phase: .began)) == .fired)
        #expect(matcher.handle(scrollEvent(phase: .ended)) == .ignored)
        #expect(matcher.handle(scrollEvent(deltaY: 10, momentum: .began)) == .advanced(consumeEvent: true))
        #expect(matcher.handle(scrollEvent(deltaY: -10, phase: .began)) == .ignored)
        #expect(matcher.handle(scrollEvent(deltaY: -10, momentum: .began)) == .ignored)
    }

    @Test("reset ends a coast")
    func resetStopsCoast() {
        let matcher = SequenceMatcher()
        matcher.configure(shortcut: DiscreteShortcut(kind: .scroll(direction: .up), modifiers: []))
        _ = matcher.handle(scrollEvent(deltaY: 10, phase: .began))
        _ = matcher.handle(scrollEvent(phase: .ended))
        matcher.reset()
        #expect(matcher.handle(scrollEvent(deltaY: 10, momentum: .began)) == .ignored)
    }

    @Test("the rest of a burst can't start the sequence again after a later step fires")
    func burstOutlivesTheSequenceItStarted() {
        let matcher = SequenceMatcher()
        matcher.configure(shortcut: DiscreteShortcut(steps: [
            .init(kind: .scroll(direction: .up), modifiers: []),
            .init(keyCode: UInt16(kVK_ANSI_C), modifiers: .command),
        ]))
        #expect(matcher.handle(scrollEvent(deltaY: 10, phase: .began)) == .advanced(consumeEvent: false))
        #expect(matcher.handle(keyDown(kVK_ANSI_C, .command)) == .fired)
        #expect(matcher.handle(scrollEvent(deltaY: 10, phase: .changed)) == .ignored)
        #expect(!matcher.isTracking)
    }
}
