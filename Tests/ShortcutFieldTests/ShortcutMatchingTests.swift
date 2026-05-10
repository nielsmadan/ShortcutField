import AppKit
import Carbon.HIToolbox
@testable import ShortcutField
import Testing

private func makeKeyEvent(keyCode: UInt16, modifiers: NSEvent.ModifierFlags = []) -> NSEvent {
    let event = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: true)!
    event.flags = CGEventFlags(rawValue: UInt64(modifiers.rawValue))
    return NSEvent(cgEvent: event)!
}

// CGEvent is not thread-safe — run these serially to avoid crashes in CI.
// `@MainActor` at struct level also serializes against other @MainActor suites
// that touch CGEvent / NSSearchField / global ShortcutRecordingState.
@MainActor
@Suite(.serialized) struct ShortcutMatchingTests {
    // MARK: - Keyboard

    @Test func key_matchesEvent_sameKeyAndModifiers_returnsTrue() {
        let step = Shortcut.Step(keyCode: UInt16(kVK_Tab), modifiers: [.command, .shift])
        let event = makeKeyEvent(keyCode: UInt16(kVK_Tab), modifiers: [.command, .shift])
        #expect(step.matches(event))
    }

    @Test func key_matchesEvent_wrongModifiers_returnsFalse() {
        let step = Shortcut.Step(keyCode: UInt16(kVK_Tab), modifiers: [.command])
        let event = makeKeyEvent(keyCode: UInt16(kVK_Tab), modifiers: [.command, .shift])
        #expect(!step.matches(event))
    }

    @Test func key_matchesEvent_wrongKey_returnsFalse() {
        let step = Shortcut.Step(keyCode: UInt16(kVK_Tab), modifiers: [.command])
        let event = makeKeyEvent(keyCode: UInt16(kVK_Return), modifiers: [.command])
        #expect(!step.matches(event))
    }

    @Test func key_matchesEvent_ignoresNonShortcutFlags() {
        let step = Shortcut.Step(keyCode: UInt16(kVK_Tab), modifiers: [.command])
        let event = makeKeyEvent(keyCode: UInt16(kVK_Tab), modifiers: [.command, .capsLock, .numericPad])
        #expect(step.matches(event))
    }

    @Test func key_matchesEvent_noModifiers() {
        let step = Shortcut.Step(keyCode: UInt16(kVK_Tab), modifiers: [])
        let event = makeKeyEvent(keyCode: UInt16(kVK_Tab), modifiers: [])
        #expect(step.matches(event))
    }

    // MARK: - Pinch (via gesture event shape)

    @Test func pinchIn_matchesNegativeMagnification() {
        let step = Shortcut.Step(kind: .pinchIn, modifiers: [])
        let event = GestureEventShape(type: .magnify, magnification: -0.05)
        #expect(step.matchesGesture(event))
    }

    @Test func pinchIn_doesNotMatchPositiveMagnification() {
        let step = Shortcut.Step(kind: .pinchIn, modifiers: [])
        let event = GestureEventShape(type: .magnify, magnification: 0.05)
        #expect(!step.matchesGesture(event))
    }

    @Test func pinchOut_matchesPositiveMagnification() {
        let step = Shortcut.Step(kind: .pinchOut, modifiers: [])
        let event = GestureEventShape(type: .magnify, magnification: 0.05)
        #expect(step.matchesGesture(event))
    }

    @Test func pinch_subThresholdDoesNotMatch() {
        let step = Shortcut.Step(kind: .pinchIn, modifiers: [])
        let event = GestureEventShape(type: .magnify, magnification: -0.001)
        #expect(!step.matchesGesture(event))
    }

    @Test func pinch_modifierMismatchDoesNotMatch() {
        let step = Shortcut.Step(kind: .pinchIn, modifiers: .command)
        let event = GestureEventShape(type: .magnify, modifierFlags: [], magnification: -0.05)
        #expect(!step.matchesGesture(event))
    }

    @Test func pinch_modifierMatchMatches() {
        let step = Shortcut.Step(kind: .pinchIn, modifiers: .command)
        let event = GestureEventShape(type: .magnify, modifierFlags: .command, magnification: -0.05)
        #expect(step.matchesGesture(event))
    }

    @Test func pinch_doesNotMatchOtherEventType() {
        let step = Shortcut.Step(kind: .pinchIn, modifiers: [])
        let event = GestureEventShape(type: .rotate, rotation: 5)
        #expect(!step.matchesGesture(event))
    }

    // MARK: - Rotate

    @Test func rotateCCW_matchesPositiveRotation() {
        let step = Shortcut.Step(kind: .rotateCounterClockwise, modifiers: [])
        let event = GestureEventShape(type: .rotate, rotation: 5)
        #expect(step.matchesGesture(event))
    }

    @Test func rotateCW_matchesNegativeRotation() {
        let step = Shortcut.Step(kind: .rotateClockwise, modifiers: [])
        let event = GestureEventShape(type: .rotate, rotation: -5)
        #expect(step.matchesGesture(event))
    }

    @Test func rotate_subThresholdDoesNotMatch() {
        let step = Shortcut.Step(kind: .rotateClockwise, modifiers: [])
        let event = GestureEventShape(type: .rotate, rotation: -0.1)
        #expect(!step.matchesGesture(event))
    }

    @Test func rotate_modifierMismatchDoesNotMatch() {
        let step = Shortcut.Step(kind: .rotateClockwise, modifiers: .command)
        let event = GestureEventShape(type: .rotate, modifierFlags: [], rotation: -5)
        #expect(!step.matchesGesture(event))
    }

    @Test func rotate_modifierMatchMatches() {
        let step = Shortcut.Step(kind: .rotateClockwise, modifiers: .command)
        let event = GestureEventShape(type: .rotate, modifierFlags: .command, rotation: -5)
        #expect(step.matchesGesture(event))
    }

    @Test func rotate_doesNotMatchOtherEventType() {
        let step = Shortcut.Step(kind: .rotateClockwise, modifiers: [])
        let event = GestureEventShape(type: .magnify, magnification: -0.05)
        #expect(!step.matchesGesture(event))
    }

    // MARK: - Smart magnify

    @Test func smartMagnify_matchesEvent() {
        let step = Shortcut.Step(kind: .smartMagnify, modifiers: [])
        let event = GestureEventShape(type: .smartMagnify)
        #expect(step.matchesGesture(event))
    }

    @Test func smartMagnify_doesNotMatchPinch() {
        let step = Shortcut.Step(kind: .smartMagnify, modifiers: [])
        let event = GestureEventShape(type: .magnify, magnification: 0.05)
        #expect(!step.matchesGesture(event))
    }

    @Test func smartMagnify_modifierMismatchDoesNotMatch() {
        let step = Shortcut.Step(kind: .smartMagnify, modifiers: .command)
        let event = GestureEventShape(type: .smartMagnify, modifierFlags: [])
        #expect(!step.matchesGesture(event))
    }

    @Test func smartMagnify_modifierMatchMatches() {
        let step = Shortcut.Step(kind: .smartMagnify, modifiers: .command)
        let event = GestureEventShape(type: .smartMagnify, modifierFlags: .command)
        #expect(step.matchesGesture(event))
    }

    // MARK: - Cross-kind: gesture step should not match key event

    @Test func gestureStep_doesNotMatchKeyEvent() {
        let step = Shortcut.Step(kind: .pinchIn, modifiers: [])
        let event = makeKeyEvent(keyCode: UInt16(kVK_Tab))
        #expect(!step.matches(event))
    }

    @Test func keyStep_doesNotMatchGestureEvent() {
        let step = Shortcut.Step(keyCode: UInt16(kVK_Tab), modifiers: [])
        let event = GestureEventShape(type: .magnify, magnification: -0.05)
        #expect(!step.matchesGesture(event))
    }

    // MARK: - ContinuousShortcut.matches reuses step matching

    /// Build a scroll-wheel NSEvent — this is the only continuous kind we can
    /// construct via CGEvent in tests (`magnify` / `rotate` events have no
    /// CGEvent constructor).
    private func makeScrollEvent(deltaY: Int32) -> NSEvent {
        let cg = CGEvent(scrollWheelEvent2Source: nil,
                         units: .pixel,
                         wheelCount: 1,
                         wheel1: deltaY,
                         wheel2: 0,
                         wheel3: 0)!
        return NSEvent(cgEvent: cg)!
    }

    @Test func continuousShortcut_matches_scrollUp_returnsTrue() {
        let cs = ContinuousShortcut(kind: .scroll(direction: .up), modifiers: [])
        #expect(cs.matches(makeScrollEvent(deltaY: 10)))
    }

    @Test func continuousShortcut_matches_scrollDown_doesNotMatchUp() {
        let cs = ContinuousShortcut(kind: .scroll(direction: .up), modifiers: [])
        #expect(!cs.matches(makeScrollEvent(deltaY: -10)))
    }

    @Test func continuousShortcut_matches_modifierMismatch_returnsFalse() {
        let cs = ContinuousShortcut(kind: .scroll(direction: .up), modifiers: .command)
        #expect(!cs.matches(makeScrollEvent(deltaY: 10)))
    }
}
