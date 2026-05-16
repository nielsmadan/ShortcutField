import AppKit
import Carbon.HIToolbox
@testable import ShortcutField
import Testing

// MARK: - Special Key Strings

@Test func specialKeyString_returnKey() {
    #expect(DiscreteShortcut.specialKeyString(keyCode: UInt16(kVK_Return)) == "↩")
}

@Test func specialKeyString_deleteKey() {
    #expect(DiscreteShortcut.specialKeyString(keyCode: UInt16(kVK_Delete)) == "⌫")
}

@Test func specialKeyString_forwardDeleteKey() {
    #expect(DiscreteShortcut.specialKeyString(keyCode: UInt16(kVK_ForwardDelete)) == "⌦")
}

@Test func specialKeyString_escapeKey() {
    #expect(DiscreteShortcut.specialKeyString(keyCode: UInt16(kVK_Escape)) == "⎋")
}

@Test func specialKeyString_spaceKey() {
    #expect(DiscreteShortcut.specialKeyString(keyCode: UInt16(kVK_Space)) == "Space")
}

@Test func specialKeyString_tabKey() {
    #expect(DiscreteShortcut.specialKeyString(keyCode: UInt16(kVK_Tab)) == "Tab")
}

@Test func specialKeyString_arrowKeys() {
    #expect(DiscreteShortcut.specialKeyString(keyCode: UInt16(kVK_UpArrow)) == "↑")
    #expect(DiscreteShortcut.specialKeyString(keyCode: UInt16(kVK_DownArrow)) == "↓")
    #expect(DiscreteShortcut.specialKeyString(keyCode: UInt16(kVK_LeftArrow)) == "←")
    #expect(DiscreteShortcut.specialKeyString(keyCode: UInt16(kVK_RightArrow)) == "→")
}

@Test func specialKeyString_homeEndPageKeys() {
    #expect(DiscreteShortcut.specialKeyString(keyCode: UInt16(kVK_Home)) == "↖")
    #expect(DiscreteShortcut.specialKeyString(keyCode: UInt16(kVK_End)) == "↘")
    #expect(DiscreteShortcut.specialKeyString(keyCode: UInt16(kVK_PageUp)) == "⇞")
    #expect(DiscreteShortcut.specialKeyString(keyCode: UInt16(kVK_PageDown)) == "⇟")
}

@Test func specialKeyString_functionKeys() {
    #expect(DiscreteShortcut.specialKeyString(keyCode: UInt16(kVK_F1)) == "F1")
    #expect(DiscreteShortcut.specialKeyString(keyCode: UInt16(kVK_F12)) == "F12")
}

@Test func specialKeyString_unknownKey_returnsNil() {
    #expect(DiscreteShortcut.specialKeyString(keyCode: 0) == nil)
}

// MARK: - Modifier Symbolic Representation

@Test func symbolicRepresentation_command() {
    let flags: NSEvent.ModifierFlags = .command
    #expect(flags.symbolicRepresentation == "⌘")
}

@Test func symbolicRepresentation_allModifiers() {
    let flags: NSEvent.ModifierFlags = [.control, .option, .shift, .command]
    #expect(flags.symbolicRepresentation == "⌃⌥⇧⌘")
}

@Test func symbolicRepresentation_empty() {
    let flags: NSEvent.ModifierFlags = []
    #expect(flags.symbolicRepresentation == "")
}

// keyToCharacter tests live in `DiscreteShortcutDisplayStringTests` (its serialized suite
// also covers display-string round-trips that internally call UCKeyTranslate).
