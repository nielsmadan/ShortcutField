import AppKit
import Carbon.HIToolbox
@testable import ShortcutField
import Testing

private func makeKeyEvent(keyCode: UInt16, modifiers: NSEvent.ModifierFlags = []) -> NSEvent {
    let event = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: true)!
    event.flags = CGEventFlags(rawValue: UInt64(modifiers.rawValue))
    return NSEvent(cgEvent: event)!
}

// CGEvent is not thread-safe — run these serially to avoid crashes in CI
@Suite(.serialized) struct ShortcutMatchingTests {
    // MARK: - Keyboard

    @Test func key_matchesEvent_sameKeyAndModifiers_returnsTrue() {
        let s = Shortcut(keyCode: UInt16(kVK_Tab), modifiers: [.command, .shift])
        let event = makeKeyEvent(keyCode: UInt16(kVK_Tab), modifiers: [.command, .shift])
        #expect(s.matches(event))
    }

    @Test func key_matchesEvent_wrongModifiers_returnsFalse() {
        let s = Shortcut(keyCode: UInt16(kVK_Tab), modifiers: [.command])
        let event = makeKeyEvent(keyCode: UInt16(kVK_Tab), modifiers: [.command, .shift])
        #expect(!s.matches(event))
    }

    @Test func key_matchesEvent_wrongKey_returnsFalse() {
        let s = Shortcut(keyCode: UInt16(kVK_Tab), modifiers: [.command])
        let event = makeKeyEvent(keyCode: UInt16(kVK_Return), modifiers: [.command])
        #expect(!s.matches(event))
    }

    @Test func key_matchesEvent_ignoresNonShortcutFlags() {
        let s = Shortcut(keyCode: UInt16(kVK_Tab), modifiers: [.command])
        let event = makeKeyEvent(keyCode: UInt16(kVK_Tab), modifiers: [.command, .capsLock, .numericPad])
        #expect(s.matches(event))
    }

    @Test func key_matchesEvent_noModifiers() {
        let s = Shortcut(keyCode: UInt16(kVK_Tab), modifiers: [])
        let event = makeKeyEvent(keyCode: UInt16(kVK_Tab), modifiers: [])
        #expect(s.matches(event))
    }

    // MARK: - Pinch (via gesture event shape)

    @Test func pinchIn_matchesNegativeMagnification() {
        let s = Shortcut(kind: .pinchIn, modifiers: [])
        let event = GestureEventShape(type: .magnify, magnification: -0.05)
        #expect(s.matchesGesture(event))
    }

    @Test func pinchIn_doesNotMatchPositiveMagnification() {
        let s = Shortcut(kind: .pinchIn, modifiers: [])
        let event = GestureEventShape(type: .magnify, magnification: 0.05)
        #expect(!s.matchesGesture(event))
    }

    @Test func pinchOut_matchesPositiveMagnification() {
        let s = Shortcut(kind: .pinchOut, modifiers: [])
        let event = GestureEventShape(type: .magnify, magnification: 0.05)
        #expect(s.matchesGesture(event))
    }

    @Test func pinch_subThresholdDoesNotMatch() {
        let s = Shortcut(kind: .pinchIn, modifiers: [])
        let event = GestureEventShape(type: .magnify, magnification: -0.001)
        #expect(!s.matchesGesture(event))
    }

    @Test func pinch_modifierMismatchDoesNotMatch() {
        let s = Shortcut(kind: .pinchIn, modifiers: .command)
        let event = GestureEventShape(type: .magnify, modifierFlags: [], magnification: -0.05)
        #expect(!s.matchesGesture(event))
    }

    @Test func pinch_modifierMatchMatches() {
        let s = Shortcut(kind: .pinchIn, modifiers: .command)
        let event = GestureEventShape(type: .magnify, modifierFlags: .command, magnification: -0.05)
        #expect(s.matchesGesture(event))
    }

    @Test func pinch_doesNotMatchOtherEventType() {
        let s = Shortcut(kind: .pinchIn, modifiers: [])
        let event = GestureEventShape(type: .rotate, rotation: 5)
        #expect(!s.matchesGesture(event))
    }

    // MARK: - Rotate

    @Test func rotateCCW_matchesPositiveRotation() {
        let s = Shortcut(kind: .rotateCounterClockwise, modifiers: [])
        let event = GestureEventShape(type: .rotate, rotation: 5)
        #expect(s.matchesGesture(event))
    }

    @Test func rotateCW_matchesNegativeRotation() {
        let s = Shortcut(kind: .rotateClockwise, modifiers: [])
        let event = GestureEventShape(type: .rotate, rotation: -5)
        #expect(s.matchesGesture(event))
    }

    @Test func rotate_subThresholdDoesNotMatch() {
        let s = Shortcut(kind: .rotateClockwise, modifiers: [])
        let event = GestureEventShape(type: .rotate, rotation: -0.1)
        #expect(!s.matchesGesture(event))
    }

    @Test func rotate_modifierMismatchDoesNotMatch() {
        let s = Shortcut(kind: .rotateClockwise, modifiers: .command)
        let event = GestureEventShape(type: .rotate, modifierFlags: [], rotation: -5)
        #expect(!s.matchesGesture(event))
    }

    @Test func rotate_modifierMatchMatches() {
        let s = Shortcut(kind: .rotateClockwise, modifiers: .command)
        let event = GestureEventShape(type: .rotate, modifierFlags: .command, rotation: -5)
        #expect(s.matchesGesture(event))
    }

    @Test func rotate_doesNotMatchOtherEventType() {
        let s = Shortcut(kind: .rotateClockwise, modifiers: [])
        let event = GestureEventShape(type: .magnify, magnification: -0.05)
        #expect(!s.matchesGesture(event))
    }

    // MARK: - Smart magnify

    @Test func smartMagnify_matchesEvent() {
        let s = Shortcut(kind: .smartMagnify, modifiers: [])
        let event = GestureEventShape(type: .smartMagnify)
        #expect(s.matchesGesture(event))
    }

    @Test func smartMagnify_doesNotMatchPinch() {
        let s = Shortcut(kind: .smartMagnify, modifiers: [])
        let event = GestureEventShape(type: .magnify, magnification: 0.05)
        #expect(!s.matchesGesture(event))
    }

    @Test func smartMagnify_modifierMismatchDoesNotMatch() {
        let s = Shortcut(kind: .smartMagnify, modifiers: .command)
        let event = GestureEventShape(type: .smartMagnify, modifierFlags: [])
        #expect(!s.matchesGesture(event))
    }

    @Test func smartMagnify_modifierMatchMatches() {
        let s = Shortcut(kind: .smartMagnify, modifiers: .command)
        let event = GestureEventShape(type: .smartMagnify, modifierFlags: .command)
        #expect(s.matchesGesture(event))
    }

    // MARK: - Cross-kind: gesture shortcut should not match key event

    @Test func gestureShortcut_doesNotMatchKeyEvent() {
        let s = Shortcut(kind: .pinchIn, modifiers: [])
        let event = makeKeyEvent(keyCode: UInt16(kVK_Tab))
        #expect(!s.matches(event))
    }

    @Test func keyShortcut_doesNotMatchOtherEventType() {
        // matches() should require .keyDown for key kinds
        let s = Shortcut(keyCode: UInt16(kVK_Tab), modifiers: [])
        let event = GestureEventShape(type: .magnify, magnification: -0.05)
        #expect(!s.matchesGesture(event))
    }
}
