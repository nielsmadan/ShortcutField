import AppKit
import Carbon.HIToolbox
@testable import ShortcutField
import Testing

/// UCKeyTranslate is not thread-safe; run display-string tests serially.
/// `@MainActor` at struct level also serializes against other @MainActor suites
/// that use UCKeyTranslate via `DiscreteShortcut.Step.displayString`.
@MainActor
@Suite(.serialized) struct DiscreteShortcutDisplayStringTests {
    // MARK: - Keyboard

    @Test func key_specialKeyOnly() {
        let s = DiscreteShortcut(keyCode: UInt16(kVK_Return), modifiers: [])
        #expect(s.displayString == "↩")
    }

    @Test func key_modifierWithSpecialKey() {
        let s = DiscreteShortcut(keyCode: UInt16(kVK_Return), modifiers: .command)
        #expect(s.displayString == "⌘↩")
    }

    @Test func key_letterOnly_showsTheLayoutCharacter() throws {
        let s = DiscreteShortcut(keyCode: 1, modifiers: [])
        let character = try #require(DiscreteShortcut.keyToCharacter(keyCode: 1))
        #expect(s.displayString == character)
        #expect(character == character.lowercased() && character != character.uppercased())
    }

    @Test func key_untranslatableKey_namesTheKeyCode() {
        #expect(DiscreteShortcut(keyCode: 200, modifiers: .command).displayString == "⌘Key 200")
    }

    @Test func key_functionKeyBeyondF12_isNamed() {
        #expect(DiscreteShortcut(keyCode: UInt16(kVK_F13), modifiers: .command).displayString == "⌘F13")
    }

    @Test func key_modifierWithLetter() throws {
        let s = DiscreteShortcut(keyCode: 38, modifiers: [.command, .shift])
        let character = try #require(DiscreteShortcut.keyToCharacter(keyCode: 38))
        #expect(s.displayString == "⇧⌘" + character)
    }

    // MARK: - Mouse buttons

    @Test func mouseButton_left_noModifiers() {
        let s = DiscreteShortcut(kind: .mouseButton(number: 0), modifiers: [])
        #expect(s.displayString == "Left Click")
    }

    @Test func mouseButton_right_noModifiers() {
        let s = DiscreteShortcut(kind: .mouseButton(number: 1), modifiers: [])
        #expect(s.displayString == "Right Click")
    }

    @Test func mouseButton_middle_noModifiers() {
        let s = DiscreteShortcut(kind: .mouseButton(number: 2), modifiers: [])
        #expect(s.displayString == "Middle Click")
    }

    @Test func mouseButton_extraButton_displaysOneIndexed() {
        let s = DiscreteShortcut(kind: .mouseButton(number: 3), modifiers: [])
        #expect(s.displayString == "Mouse4")
    }

    @Test func mouseButton_withModifier() {
        let s = DiscreteShortcut(kind: .mouseButton(number: 1), modifiers: .control)
        #expect(s.displayString == "⌃Right Click")
    }

    // MARK: - Scroll

    @Test func scroll_up_noModifiers() {
        let s = DiscreteShortcut(kind: .scroll(direction: .up), modifiers: [])
        #expect(s.displayString == "Scroll Up")
    }

    @Test func scroll_down_noModifiers() {
        let s = DiscreteShortcut(kind: .scroll(direction: .down), modifiers: [])
        #expect(s.displayString == "Scroll Down")
    }

    @Test func scroll_left_noModifiers() {
        let s = DiscreteShortcut(kind: .scroll(direction: .left), modifiers: [])
        #expect(s.displayString == "Scroll Left")
    }

    @Test func scroll_right_noModifiers() {
        let s = DiscreteShortcut(kind: .scroll(direction: .right), modifiers: [])
        #expect(s.displayString == "Scroll Right")
    }

    @Test func scroll_withShift() {
        let s = DiscreteShortcut(kind: .scroll(direction: .up), modifiers: .shift)
        #expect(s.displayString == "⇧Scroll Up")
    }

    // MARK: - Trackpad gestures

    @Test func pinchIn_noModifiers() {
        let s = DiscreteShortcut(kind: .pinchIn, modifiers: [])
        #expect(s.displayString == "Pinch In")
    }

    @Test func pinchOut_noModifiers() {
        let s = DiscreteShortcut(kind: .pinchOut, modifiers: [])
        #expect(s.displayString == "Pinch Out")
    }

    @Test func rotateClockwise_noModifiers() {
        let s = DiscreteShortcut(kind: .rotateClockwise, modifiers: [])
        #expect(s.displayString == "Rotate CW")
    }

    @Test func rotateCounterClockwise_noModifiers() {
        let s = DiscreteShortcut(kind: .rotateCounterClockwise, modifiers: [])
        #expect(s.displayString == "Rotate CCW")
    }

    @Test func smartMagnify_noModifiers() {
        let s = DiscreteShortcut(kind: .smartMagnify, modifiers: [])
        #expect(s.displayString == "Smart Magnify")
    }

    @Test func pinchIn_withCommand() {
        let s = DiscreteShortcut(kind: .pinchIn, modifiers: .command)
        #expect(s.displayString == "⌘Pinch In")
    }

    @Test func smartMagnify_withControlOption() {
        let s = DiscreteShortcut(kind: .smartMagnify, modifiers: [.control, .option])
        // Order in `symbolicRepresentation` follows Apple convention: ⌃ ⌥ ⇧ ⌘
        #expect(s.displayString == "⌃⌥Smart Magnify")
    }

    // MARK: - keyToCharacter

    @Test func keyToCharacter_letterKeys_produceOnePrintableCharacter() throws {
        for keyCode: UInt16 in [0, 1] {
            let character = try #require(DiscreteShortcut.keyToCharacter(keyCode: keyCode))
            #expect(character.count == 1)
            #expect(character.unicodeScalars.allSatisfy { $0.properties.generalCategory != .control })
            #expect(DiscreteShortcut.keyToCharacter(keyCode: keyCode, shifted: true) == character.uppercased())
        }
    }
}
