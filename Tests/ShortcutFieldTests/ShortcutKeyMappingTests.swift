import AppKit
import Carbon.HIToolbox
import ShortcutField
import Testing

// MARK: - Special Key Strings

@Test func specialKeyString_returnKey() {
    #expect(Shortcut.specialKeyString(keyCode: UInt16(kVK_Return)) == "↩")
}

@Test func specialKeyString_deleteKey() {
    #expect(Shortcut.specialKeyString(keyCode: UInt16(kVK_Delete)) == "⌫")
}

@Test func specialKeyString_forwardDeleteKey() {
    #expect(Shortcut.specialKeyString(keyCode: UInt16(kVK_ForwardDelete)) == "⌦")
}

@Test func specialKeyString_escapeKey() {
    #expect(Shortcut.specialKeyString(keyCode: UInt16(kVK_Escape)) == "⎋")
}

@Test func specialKeyString_spaceKey() {
    #expect(Shortcut.specialKeyString(keyCode: UInt16(kVK_Space)) == "Space")
}

@Test func specialKeyString_tabKey() {
    #expect(Shortcut.specialKeyString(keyCode: UInt16(kVK_Tab)) == "Tab")
}

@Test func specialKeyString_arrowKeys() {
    #expect(Shortcut.specialKeyString(keyCode: UInt16(kVK_UpArrow)) == "↑")
    #expect(Shortcut.specialKeyString(keyCode: UInt16(kVK_DownArrow)) == "↓")
    #expect(Shortcut.specialKeyString(keyCode: UInt16(kVK_LeftArrow)) == "←")
    #expect(Shortcut.specialKeyString(keyCode: UInt16(kVK_RightArrow)) == "→")
}

@Test func specialKeyString_homeEndPageKeys() {
    #expect(Shortcut.specialKeyString(keyCode: UInt16(kVK_Home)) == "↖")
    #expect(Shortcut.specialKeyString(keyCode: UInt16(kVK_End)) == "↘")
    #expect(Shortcut.specialKeyString(keyCode: UInt16(kVK_PageUp)) == "⇞")
    #expect(Shortcut.specialKeyString(keyCode: UInt16(kVK_PageDown)) == "⇟")
}

@Test func specialKeyString_functionKeys() {
    #expect(Shortcut.specialKeyString(keyCode: UInt16(kVK_F1)) == "F1")
    #expect(Shortcut.specialKeyString(keyCode: UInt16(kVK_F12)) == "F12")
}

@Test func specialKeyString_unknownKey_returnsNil() {
    #expect(Shortcut.specialKeyString(keyCode: 0) == nil)
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

// keyToCharacter tests live in `ShortcutDisplayStringTests` (its serialized suite
// also covers display-string round-trips that internally call UCKeyTranslate).
