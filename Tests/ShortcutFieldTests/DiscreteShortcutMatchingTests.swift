import AppKit
import Carbon.HIToolbox
@testable import ShortcutField
import Testing

// CGEvent is not thread-safe — run these serially to avoid crashes in CI.
// `@MainActor` at struct level also serializes against other @MainActor suites
// that touch CGEvent / NSSearchField / global ShortcutRecordingState.
@MainActor
@Suite(.serialized) struct DiscreteShortcutMatchingTests {
    // MARK: - Keyboard

    @Test func key_matchesEvent_sameKeyAndModifiers_returnsTrue() {
        let step = DiscreteShortcut.Step(keyCode: UInt16(kVK_Tab), modifiers: [.command, .shift])
        let event = keyDown(kVK_Tab, [.command, .shift])
        #expect(step.matches(event))
    }

    @Test func key_matchesEvent_wrongModifiers_returnsFalse() {
        let step = DiscreteShortcut.Step(keyCode: UInt16(kVK_Tab), modifiers: [.command])
        let event = keyDown(kVK_Tab, [.command, .shift])
        #expect(!step.matches(event))
    }

    @Test func key_matchesEvent_wrongKey_returnsFalse() {
        let step = DiscreteShortcut.Step(keyCode: UInt16(kVK_Tab), modifiers: [.command])
        let event = keyDown(kVK_Return, [.command])
        #expect(!step.matches(event))
    }

    @Test func key_matchesEvent_ignoresNonShortcutFlags() {
        let step = DiscreteShortcut.Step(keyCode: UInt16(kVK_Tab), modifiers: [.command])
        let event = keyDown(kVK_Tab, [.command, .capsLock, .numericPad])
        #expect(step.matches(event))
    }

    @Test func key_matchesEvent_noModifiers() {
        let step = DiscreteShortcut.Step(keyCode: UInt16(kVK_Tab), modifiers: [])
        let event = keyDown(kVK_Tab, [])
        #expect(step.matches(event))
    }

    // MARK: - Pinch (via gesture event shape)

    @Test func pinchIn_matchesNegativeMagnification() {
        let step = DiscreteShortcut.Step(kind: .pinchIn, modifiers: [])
        let event = ShortcutEventShape(type: .magnify, magnification: -0.05)
        #expect(step.matches(event))
    }

    @Test func pinchIn_doesNotMatchPositiveMagnification() {
        let step = DiscreteShortcut.Step(kind: .pinchIn, modifiers: [])
        let event = ShortcutEventShape(type: .magnify, magnification: 0.05)
        #expect(!step.matches(event))
    }

    @Test func pinchOut_matchesPositiveMagnification() {
        let step = DiscreteShortcut.Step(kind: .pinchOut, modifiers: [])
        let event = ShortcutEventShape(type: .magnify, magnification: 0.05)
        #expect(step.matches(event))
    }

    @Test func pinch_subThresholdDoesNotMatch() {
        let step = DiscreteShortcut.Step(kind: .pinchIn, modifiers: [])
        let event = ShortcutEventShape(type: .magnify, magnification: -0.001)
        #expect(!step.matches(event))
    }

    @Test func pinch_modifierMismatchDoesNotMatch() {
        let step = DiscreteShortcut.Step(kind: .pinchIn, modifiers: .command)
        let event = ShortcutEventShape(type: .magnify, modifierFlags: [], magnification: -0.05)
        #expect(!step.matches(event))
    }

    @Test func pinch_modifierMatchMatches() {
        let step = DiscreteShortcut.Step(kind: .pinchIn, modifiers: .command)
        let event = ShortcutEventShape(type: .magnify, modifierFlags: .command, magnification: -0.05)
        #expect(step.matches(event))
    }

    @Test func pinch_doesNotMatchOtherEventType() {
        let step = DiscreteShortcut.Step(kind: .pinchIn, modifiers: [])
        let event = ShortcutEventShape(type: .rotate, rotation: 5)
        #expect(!step.matches(event))
    }

    // MARK: - Rotate

    @Test func rotateCCW_matchesPositiveRotation() {
        let step = DiscreteShortcut.Step(kind: .rotateCounterClockwise, modifiers: [])
        let event = ShortcutEventShape(type: .rotate, rotation: 5)
        #expect(step.matches(event))
    }

    @Test func rotateCW_matchesNegativeRotation() {
        let step = DiscreteShortcut.Step(kind: .rotateClockwise, modifiers: [])
        let event = ShortcutEventShape(type: .rotate, rotation: -5)
        #expect(step.matches(event))
    }

    @Test func rotate_subThresholdDoesNotMatch() {
        let step = DiscreteShortcut.Step(kind: .rotateClockwise, modifiers: [])
        let event = ShortcutEventShape(type: .rotate, rotation: -0.1)
        #expect(!step.matches(event))
    }

    @Test func rotate_modifierMismatchDoesNotMatch() {
        let step = DiscreteShortcut.Step(kind: .rotateClockwise, modifiers: .command)
        let event = ShortcutEventShape(type: .rotate, modifierFlags: [], rotation: -5)
        #expect(!step.matches(event))
    }

    @Test func rotate_modifierMatchMatches() {
        let step = DiscreteShortcut.Step(kind: .rotateClockwise, modifiers: .command)
        let event = ShortcutEventShape(type: .rotate, modifierFlags: .command, rotation: -5)
        #expect(step.matches(event))
    }

    @Test func rotate_doesNotMatchOtherEventType() {
        let step = DiscreteShortcut.Step(kind: .rotateClockwise, modifiers: [])
        let event = ShortcutEventShape(type: .magnify, magnification: -0.05)
        #expect(!step.matches(event))
    }

    // MARK: - Smart magnify

    @Test func smartMagnify_matchesEvent() {
        let step = DiscreteShortcut.Step(kind: .smartMagnify, modifiers: [])
        let event = ShortcutEventShape(type: .smartMagnify)
        #expect(step.matches(event))
    }

    @Test func smartMagnify_doesNotMatchPinch() {
        let step = DiscreteShortcut.Step(kind: .smartMagnify, modifiers: [])
        let event = ShortcutEventShape(type: .magnify, magnification: 0.05)
        #expect(!step.matches(event))
    }

    @Test func smartMagnify_modifierMismatchDoesNotMatch() {
        let step = DiscreteShortcut.Step(kind: .smartMagnify, modifiers: .command)
        let event = ShortcutEventShape(type: .smartMagnify, modifierFlags: [])
        #expect(!step.matches(event))
    }

    @Test func smartMagnify_modifierMatchMatches() {
        let step = DiscreteShortcut.Step(kind: .smartMagnify, modifiers: .command)
        let event = ShortcutEventShape(type: .smartMagnify, modifierFlags: .command)
        #expect(step.matches(event))
    }

    // MARK: - Cross-kind: gesture step should not match key event

    @Test func gestureStep_doesNotMatchKeyEvent() {
        let step = DiscreteShortcut.Step(kind: .pinchIn, modifiers: [])
        let event = keyDown(kVK_Tab)
        #expect(!step.matches(event))
    }

    @Test func keyStep_doesNotMatchGestureEvent() {
        let step = DiscreteShortcut.Step(keyCode: UInt16(kVK_Tab), modifiers: [])
        let event = ShortcutEventShape(type: .magnify, magnification: -0.05)
        #expect(!step.matches(event))
    }

    // MARK: - ContinuousShortcut.matches reuses step matching

    @Test func continuousShortcut_matches_scrollUp_returnsTrue() {
        let cs = ContinuousShortcut(kind: .scroll(direction: .up), modifiers: [])
        #expect(cs.matches(scrollEvent(deltaY: 10)))
    }

    @Test func continuousShortcut_matches_scrollDown_doesNotMatchUp() {
        let cs = ContinuousShortcut(kind: .scroll(direction: .up), modifiers: [])
        #expect(!cs.matches(scrollEvent(deltaY: -10)))
    }

    @Test func continuousShortcut_matches_modifierMismatch_returnsFalse() {
        let cs = ContinuousShortcut(kind: .scroll(direction: .up), modifiers: .command)
        #expect(!cs.matches(scrollEvent(deltaY: 10)))
    }
}
