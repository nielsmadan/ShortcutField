import AppKit
import Carbon.HIToolbox
@testable import ShortcutField
import Testing

/// An off-screen window holding a plain text field followed by `recorder` in the key-view loop.
@MainActor
func hostWindow(_ recorder: BaseShortcutRecorderField) -> (window: NSWindow, other: NSTextField) {
    let window = NSWindow(
        contentRect: NSRect(x: -10000, y: -10000, width: 400, height: 80),
        styleMask: [.titled],
        backing: .buffered,
        defer: false
    )
    let other = NSTextField(frame: NSRect(x: 10, y: 40, width: 120, height: 24))
    recorder.frame = NSRect(x: 150, y: 40, width: 200, height: 24)
    window.contentView?.addSubview(other)
    window.contentView?.addSubview(recorder)
    other.nextKeyView = recorder
    return (window, other)
}

/// A key window with a text field on each side of `recorder` in the key-view loop, so a Tab
/// delivered through the app has somewhere to move focus.
@MainActor
struct TabForm {
    let window: NSWindow
    let previous = NSTextField(frame: NSRect(x: 10, y: 40, width: 100, height: 24))
    let next = NSTextField(frame: NSRect(x: 380, y: 40, width: 100, height: 24))

    init(_ recorder: BaseShortcutRecorderField) {
        window = NSWindow(
            contentRect: NSRect(x: -10000, y: -10000, width: 500, height: 80),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        recorder.frame = NSRect(x: 150, y: 40, width: 200, height: 24)
        for view in [previous, recorder, next] {
            window.contentView?.addSubview(view)
        }
        previous.nextKeyView = recorder
        recorder.nextKeyView = next
        next.nextKeyView = previous
        // Set asynchronously once the field is in a window; the test can't wait for that.
        recorder.canBecomeKey = true
        // `orderFront` alone leaves key events undelivered, though the window never reports
        // itself key in a test process.
        window.makeKeyAndOrderFront(nil)
    }

    func close() {
        window.makeFirstResponder(nil)
        window.orderOut(nil)
    }
}

/// A Tab, or Shift-Tab when `backward`, addressed to `window` with the characters AppKit gives it.
@MainActor
func tabKey(backward: Bool, in window: NSWindow) -> NSEvent {
    let characters = backward ? "\u{19}" : "\t"
    return NSEvent.keyEvent(
        with: .keyDown, location: .zero, modifierFlags: backward ? .shift : [], timestamp: 0,
        windowNumber: window.windowNumber, context: nil, characters: characters,
        charactersIgnoringModifiers: characters, isARepeat: false, keyCode: UInt16(kVK_Tab)
    )!
}

/// A left-down at the centre of `field`'s clear (x) button.
@MainActor
func clearButtonClick(
    _ field: BaseShortcutRecorderField, in window: NSWindow, _ modifiers: NSEvent.ModifierFlags = []
) throws -> NSEvent {
    let cell = try #require(field.cell as? NSSearchFieldCell)
    let rect = cell.cancelButtonRect(forBounds: field.bounds)
    let point = field.convert(NSPoint(x: rect.midX, y: rect.midY), to: nil)
    return mouseEvent(.leftMouseDown, at: point, in: window, modifiers)
}
