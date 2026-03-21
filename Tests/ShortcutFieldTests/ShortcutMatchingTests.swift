import AppKit
import Carbon.HIToolbox
import ShortcutField
import Testing

private func makeKeyEvent(keyCode: UInt16, modifiers: NSEvent.ModifierFlags = []) -> NSEvent {
    let event = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: true)!
    event.flags = CGEventFlags(rawValue: UInt64(modifiers.rawValue))
    return NSEvent(cgEvent: event)!
}

// MARK: - NSEvent Matching

@Test func matchesEvent_sameKeyAndModifiers_returnsTrue() {
    let shortcut = Shortcut(keyCode: UInt16(kVK_Tab), modifiers: [.command, .shift])
    let event = makeKeyEvent(keyCode: UInt16(kVK_Tab), modifiers: [.command, .shift])
    #expect(shortcut.matches(event))
}

@Test func matchesEvent_wrongModifiers_returnsFalse() {
    let shortcut = Shortcut(keyCode: UInt16(kVK_Tab), modifiers: [.command])
    let event = makeKeyEvent(keyCode: UInt16(kVK_Tab), modifiers: [.command, .shift])
    #expect(!shortcut.matches(event))
}

@Test func matchesEvent_wrongKey_returnsFalse() {
    let shortcut = Shortcut(keyCode: UInt16(kVK_Tab), modifiers: [.command])
    let event = makeKeyEvent(keyCode: UInt16(kVK_Return), modifiers: [.command])
    #expect(!shortcut.matches(event))
}

@Test func matchesEvent_ignoresNonShortcutFlags() {
    let shortcut = Shortcut(keyCode: UInt16(kVK_Tab), modifiers: [.command])
    let event = makeKeyEvent(keyCode: UInt16(kVK_Tab), modifiers: [.command, .capsLock, .numericPad])
    #expect(shortcut.matches(event))
}

@Test func matchesEvent_noModifiers() {
    let shortcut = Shortcut(keyCode: UInt16(kVK_Tab), modifiers: [])
    let event = makeKeyEvent(keyCode: UInt16(kVK_Tab), modifiers: [])
    #expect(shortcut.matches(event))
}
