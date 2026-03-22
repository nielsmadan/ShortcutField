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

// MARK: - Display String (serialized — UCKeyTranslate is not thread-safe)

@Suite(.serialized) struct DisplayStringTests {

@Test func displayString_specialKeyOnly() {
    let shortcut = Shortcut(keyCode: UInt16(kVK_Return), modifiers: [])
    #expect(shortcut.displayString == "↩")
}

@Test func displayString_modifierWithSpecialKey() {
    let shortcut = Shortcut(keyCode: UInt16(kVK_Return), modifiers: .command)
    #expect(shortcut.displayString == "⌘↩")
}

@Test func displayString_letterOnly() {
    let shortcut = Shortcut(keyCode: 1, modifiers: [])
    #expect(shortcut.displayString == "s")
}

@Test func displayString_modifierWithLetter() {
    let shortcut = Shortcut(keyCode: 38, modifiers: [.command, .shift])
    let display = shortcut.displayString
    #expect(display.contains("⇧"))
    #expect(display.contains("⌘"))
}

@Test func keyToCharacter_knownKeys() {
    #expect(Shortcut.keyToCharacter(keyCode: 0)?.lowercased() == "a")
    #expect(Shortcut.keyToCharacter(keyCode: 1)?.lowercased() == "s")
}

}
