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
}
