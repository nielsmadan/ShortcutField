import AppKit
import Carbon.HIToolbox
import ShortcutField
import Testing

// UCKeyTranslate is not thread-safe; run display-string tests serially.
// `@MainActor` at struct level also serializes against other @MainActor suites
// that use UCKeyTranslate via `Shortcut.Step.displayString`.
@MainActor
@Suite(.serialized) struct ShortcutDisplayStringTests {
    // MARK: - Keyboard

    @Test func key_specialKeyOnly() {
        let s = Shortcut(keyCode: UInt16(kVK_Return), modifiers: [])
        #expect(s.displayString == "↩")
    }

    @Test func key_modifierWithSpecialKey() {
        let s = Shortcut(keyCode: UInt16(kVK_Return), modifiers: .command)
        #expect(s.displayString == "⌘↩")
    }

    @Test func key_letterOnly() {
        let s = Shortcut(keyCode: 1, modifiers: [])
        #expect(s.displayString == "s")
    }

    @Test func key_modifierWithLetter() {
        let s = Shortcut(keyCode: 38, modifiers: [.command, .shift])
        let display = s.displayString
        #expect(display.contains("⇧"))
        #expect(display.contains("⌘"))
    }

    // MARK: - Mouse buttons

    @Test func mouseButton_left_noModifiers() {
        let s = Shortcut(kind: .mouseButton(number: 0), modifiers: [])
        #expect(s.displayString == "Left Click")
    }

    @Test func mouseButton_right_noModifiers() {
        let s = Shortcut(kind: .mouseButton(number: 1), modifiers: [])
        #expect(s.displayString == "Right Click")
    }

    @Test func mouseButton_middle_noModifiers() {
        let s = Shortcut(kind: .mouseButton(number: 2), modifiers: [])
        #expect(s.displayString == "Middle Click")
    }

    @Test func mouseButton_extraButton_displaysOneIndexed() {
        let s = Shortcut(kind: .mouseButton(number: 3), modifiers: [])
        #expect(s.displayString == "Mouse4")
    }

    @Test func mouseButton_withModifier() {
        let s = Shortcut(kind: .mouseButton(number: 1), modifiers: .control)
        #expect(s.displayString == "⌃Right Click")
    }

    // MARK: - Scroll

    @Test func scroll_up_noModifiers() {
        let s = Shortcut(kind: .scroll(direction: .up), modifiers: [])
        #expect(s.displayString == "Scroll Up")
    }

    @Test func scroll_down_noModifiers() {
        let s = Shortcut(kind: .scroll(direction: .down), modifiers: [])
        #expect(s.displayString == "Scroll Down")
    }

    @Test func scroll_left_noModifiers() {
        let s = Shortcut(kind: .scroll(direction: .left), modifiers: [])
        #expect(s.displayString == "Scroll Left")
    }

    @Test func scroll_right_noModifiers() {
        let s = Shortcut(kind: .scroll(direction: .right), modifiers: [])
        #expect(s.displayString == "Scroll Right")
    }

    @Test func scroll_withShift() {
        let s = Shortcut(kind: .scroll(direction: .up), modifiers: .shift)
        #expect(s.displayString == "⇧Scroll Up")
    }

    // MARK: - Trackpad gestures

    @Test func pinchIn_noModifiers() {
        let s = Shortcut(kind: .pinchIn, modifiers: [])
        #expect(s.displayString == "Pinch In")
    }

    @Test func pinchOut_noModifiers() {
        let s = Shortcut(kind: .pinchOut, modifiers: [])
        #expect(s.displayString == "Pinch Out")
    }

    @Test func rotateClockwise_noModifiers() {
        let s = Shortcut(kind: .rotateClockwise, modifiers: [])
        #expect(s.displayString == "Rotate CW")
    }

    @Test func rotateCounterClockwise_noModifiers() {
        let s = Shortcut(kind: .rotateCounterClockwise, modifiers: [])
        #expect(s.displayString == "Rotate CCW")
    }

    @Test func smartMagnify_noModifiers() {
        let s = Shortcut(kind: .smartMagnify, modifiers: [])
        #expect(s.displayString == "Smart Magnify")
    }

    @Test func pinchIn_withCommand() {
        let s = Shortcut(kind: .pinchIn, modifiers: .command)
        #expect(s.displayString == "⌘Pinch In")
    }

    @Test func smartMagnify_withControlOption() {
        let s = Shortcut(kind: .smartMagnify, modifiers: [.control, .option])
        // Order in `symbolicRepresentation` follows Apple convention: ⌃ ⌥ ⇧ ⌘
        #expect(s.displayString == "⌃⌥Smart Magnify")
    }

    // MARK: - keyToCharacter (UCKeyTranslate; serialized along with display-string tests)

    @Test func keyToCharacter_knownKeys() {
        #expect(Shortcut.keyToCharacter(keyCode: 0)?.lowercased() == "a")
        #expect(Shortcut.keyToCharacter(keyCode: 1)?.lowercased() == "s")
    }
}
