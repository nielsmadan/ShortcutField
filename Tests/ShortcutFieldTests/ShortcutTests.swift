import AppKit
import Carbon.HIToolbox
import ShortcutField
import Testing

@Test func shortcut_storesKeyCodeAndModifiers() {
    let shortcut = Shortcut(keyCode: 38, modifiers: [.command, .shift])
    #expect(shortcut.keyCode == 38)
    #expect(shortcut.modifiers.contains(.command))
    #expect(shortcut.modifiers.contains(.shift))
}

@Test func shortcut_equatable_sameValues_areEqual() {
    let a = Shortcut(keyCode: 38, modifiers: [.command])
    let b = Shortcut(keyCode: 38, modifiers: [.command])
    #expect(a == b)
}

@Test func shortcut_equatable_differentKey_areNotEqual() {
    let a = Shortcut(keyCode: 38, modifiers: [.command])
    let b = Shortcut(keyCode: 1, modifiers: [.command])
    #expect(a != b)
}

@Test func shortcut_equatable_differentModifiers_areNotEqual() {
    let a = Shortcut(keyCode: 38, modifiers: [.command])
    let b = Shortcut(keyCode: 38, modifiers: [.shift])
    #expect(a != b)
}

@Test func shortcut_codableRoundtrip() throws {
    let original = Shortcut(keyCode: 38, modifiers: [.command, .shift])
    let data = try JSONEncoder().encode(original)
    let decoded = try JSONDecoder().decode(Shortcut.self, from: data)
    #expect(decoded == original)
}

@Test func shortcut_codableRoundtrip_noModifiers() throws {
    let original = Shortcut(keyCode: 36, modifiers: [])
    let data = try JSONEncoder().encode(original)
    let decoded = try JSONDecoder().decode(Shortcut.self, from: data)
    #expect(decoded == original)
}
