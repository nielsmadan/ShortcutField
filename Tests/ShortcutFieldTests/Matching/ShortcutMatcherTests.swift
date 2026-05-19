import AppKit
import Carbon.HIToolbox
@testable import ShortcutField
import Testing

@MainActor
@Suite("ShortcutMatcher")
struct ShortcutMatcherTests {
    private func keyDown(_ keyCode: Int, _ modifiers: NSEvent.ModifierFlags = []) -> NSEvent {
        let cg = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(keyCode), keyDown: true)!
        cg.flags = CGEventFlags(rawValue: UInt64(modifiers.rawValue))
        return NSEvent(cgEvent: cg)!
    }

    @Test("discrete shortcut fires through the unified matcher")
    func discreteFires() {
        let matcher = ShortcutMatcher(
            .discrete(DiscreteShortcut(keyCode: UInt16(kVK_ANSI_S), modifiers: .command))
        )
        #expect(matcher.handle(keyDown(kVK_ANSI_S, .command)) == .fired)
    }

    @Test("discrete shortcut ignores a non-matching event")
    func discreteIgnores() {
        let matcher = ShortcutMatcher(
            .discrete(DiscreteShortcut(keyCode: UInt16(kVK_ANSI_S), modifiers: .command))
        )
        #expect(matcher.handle(keyDown(kVK_ANSI_A, .command)) == .ignored)
    }

    @Test("continuous matcher ignores non-gesture events and reset does not crash")
    func continuousIgnoresNonGestureEvent() {
        let matcher = ShortcutMatcher(
            .continuous(ContinuousShortcut(kind: .pinchOut, modifiers: .command, sensitivity: 1.0))
        )
        // Key-down events are not gestures; ContinuousMatcher should ignore them.
        #expect(matcher.handle(keyDown(kVK_ANSI_S, .command)) == .ignored)
        // reset() must not crash for the continuous backing.
        matcher.reset()
    }

    @Test("continuous shortcut fires through the unified matcher")
    func continuousFires() {
        // Gesture NSEvents cannot be synthesized, so we use the internal
        // handle(shape:) test seam on ShortcutMatcher to exercise the
        // .continuous routing path end-to-end. ContinuousMatcherTests covers
        // the matching mechanics; this test confirms ShortcutMatcher wires the
        // continuous backing correctly (routing, not mechanics).
        let matcher = ShortcutMatcher(
            .continuous(ContinuousShortcut(kind: .pinchOut, modifiers: [], sensitivity: 1.0))
        )
        let shape = ContinuousEventShape(type: .magnify, magnification: 0.3)
        #expect(matcher.handle(shape: shape) == .continuousFired(magnitude: 0.3))
    }

    @Test("reset clears in-progress sequence state")
    func resetClears() {
        let matcher = ShortcutMatcher(.discrete(DiscreteShortcut(steps: [
            .init(keyCode: UInt16(kVK_ANSI_K), modifiers: .command),
            .init(keyCode: UInt16(kVK_ANSI_C), modifiers: .command),
        ])))
        _ = matcher.handle(keyDown(kVK_ANSI_K, .command)) // advance
        matcher.reset()
        // After reset, the second step alone should not fire.
        #expect(matcher.handle(keyDown(kVK_ANSI_C, .command)) == .ignored)
    }

    // Guards the fix for hosts that build a matcher directly instead of via `.onShortcut`.
    @Test("direct ShortcutMatcher participates in ShortcutTracking.isActive")
    func directMatcherDrivesShortcutTracking() {
        let baseline = ShortcutTracking.isActive
        let matcher = ShortcutMatcher(.discrete(DiscreteShortcut(steps: [
            .init(keyCode: UInt16(kVK_ANSI_K), modifiers: .command),
            .init(keyCode: UInt16(kVK_ANSI_C), modifiers: .command),
        ])))
        #expect(matcher.handle(keyDown(kVK_ANSI_K, .command)) == .advanced(consumeEvent: false))
        #expect(ShortcutTracking.isActive == true)
        #expect(matcher.handle(keyDown(kVK_ANSI_C, .command)) == .fired)
        #expect(ShortcutTracking.isActive == baseline)
    }

    // Guards the deinit decrement: a matcher dropped mid-sequence must not leak the counter.
    @Test("dropping a matcher mid-sequence decrements ShortcutTracking.activeCount")
    func dropMidSequenceDecrementsTracking() {
        let baseline = ShortcutTracking.isActive
        do {
            let matcher = ShortcutMatcher(.discrete(DiscreteShortcut(steps: [
                .init(keyCode: UInt16(kVK_ANSI_K), modifiers: .command),
                .init(keyCode: UInt16(kVK_ANSI_C), modifiers: .command),
            ])))
            #expect(matcher.handle(keyDown(kVK_ANSI_K, .command)) == .advanced(consumeEvent: false))
            #expect(ShortcutTracking.isActive == true)
        }
        // Matcher dropped here; its deinit should decrement the counter.
        #expect(ShortcutTracking.isActive == baseline)
    }

    // A mismatch on the second step ends tracking, so the beep is not suppressed
    // for the offending key.
    @Test("mid-sequence mismatch resets ShortcutTracking.isActive to baseline")
    func midSequenceMismatchResetsTracking() {
        let baseline = ShortcutTracking.isActive
        let matcher = ShortcutMatcher(.discrete(DiscreteShortcut(steps: [
            .init(keyCode: UInt16(kVK_ANSI_K), modifiers: .command),
            .init(keyCode: UInt16(kVK_ANSI_C), modifiers: .command),
        ])))
        #expect(matcher.handle(keyDown(kVK_ANSI_K, .command)) == .advanced(consumeEvent: false))
        #expect(ShortcutTracking.isActive == true)
        #expect(matcher.handle(keyDown(kVK_ANSI_X, .command)) == .ignored)
        #expect(ShortcutTracking.isActive == baseline)
    }

    // A key that matches no step never raises tracking, so the beep plays
    // immediately for unrelated keys.
    @Test("an unrelated key never raises ShortcutTracking.isActive")
    func unrelatedKeyDoesNotRaiseTracking() {
        let baseline = ShortcutTracking.isActive
        let matcher = ShortcutMatcher(.discrete(DiscreteShortcut(steps: [
            .init(keyCode: UInt16(kVK_ANSI_K), modifiers: .command),
            .init(keyCode: UInt16(kVK_ANSI_C), modifiers: .command),
        ])))
        #expect(matcher.handle(keyDown(kVK_ANSI_A, .command)) == .ignored)
        #expect(ShortcutTracking.isActive == baseline)
    }

    // Two matchers both see every event, mirroring how the dispatcher fans one
    // event to all handlers. When a key resets one matcher and advances another,
    // the global flag must stay raised so the beep is never momentarily allowed.
    @Test("handing off to another shortcut's first step keeps ShortcutTracking.isActive raised")
    func handoffToAnotherShortcutKeepsTrackingRaised() {
        let baseline = ShortcutTracking.isActive
        // Chord A: ⌘K ⌘C    Shortcut B: ⌘X ⌘Y
        let chordA = ShortcutMatcher(.discrete(DiscreteShortcut(steps: [
            .init(keyCode: UInt16(kVK_ANSI_K), modifiers: .command),
            .init(keyCode: UInt16(kVK_ANSI_C), modifiers: .command),
        ])))
        let chordB = ShortcutMatcher(.discrete(DiscreteShortcut(steps: [
            .init(keyCode: UInt16(kVK_ANSI_X), modifiers: .command),
            .init(keyCode: UInt16(kVK_ANSI_Y), modifiers: .command),
        ])))
        _ = chordA.handle(keyDown(kVK_ANSI_K, .command)) // advances chord A
        _ = chordB.handle(keyDown(kVK_ANSI_K, .command))
        #expect(ShortcutTracking.isActive == true)
        _ = chordA.handle(keyDown(kVK_ANSI_X, .command)) // resets chord A, advances chord B
        _ = chordB.handle(keyDown(kVK_ANSI_X, .command))
        #expect(ShortcutTracking.isActive == true)
        _ = chordA.handle(keyDown(kVK_ANSI_Y, .command)) // completes chord B
        _ = chordB.handle(keyDown(kVK_ANSI_Y, .command))
        #expect(ShortcutTracking.isActive == baseline)
    }

    // Continuous shortcuts have no intermediate steps, so they never raise tracking.
    @Test("a continuous matcher never raises ShortcutTracking.isActive")
    func continuousMatcherDoesNotRaiseTracking() {
        let baseline = ShortcutTracking.isActive
        let matcher = ShortcutMatcher(
            .continuous(ContinuousShortcut(kind: .pinchOut, modifiers: [], sensitivity: 1.0))
        )
        _ = matcher.handle(shape: ContinuousEventShape(type: .magnify, magnification: 0.3))
        #expect(ShortcutTracking.isActive == baseline)
    }
}
