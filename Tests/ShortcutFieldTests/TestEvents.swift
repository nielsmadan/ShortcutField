import AppKit
import Carbon.HIToolbox

/// Synthesize a key-down `NSEvent` carrying exactly `modifiers`, never the live modifier-key state;
/// `isRepeat` makes it an auto-repeat of a held key.
func keyDown(_ keyCode: Int, _ modifiers: NSEvent.ModifierFlags = [], isRepeat: Bool = false) -> NSEvent {
    let cg = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(keyCode), keyDown: true)!
    cg.flags = CGEventFlags(rawValue: UInt64(modifiers.rawValue))
    cg.setIntegerValueField(.keyboardEventAutorepeat, value: isRepeat ? 1 : 0)
    return NSEvent(cgEvent: cg)!
}

/// Synthesize a scroll-wheel `NSEvent` with no phase information (mouse-wheel-style).
///
/// `CGEvent` doesn't expose `phase`, `magnification`, or `rotation`, so trackpad-burst
/// scroll suppression and gesture sequences (`.magnify` / `.rotate`) cannot be driven
/// through the matcher in tests.
func scrollEvent(deltaY: Int32 = 0, deltaX: Int32 = 0) -> NSEvent {
    let cg = CGEvent(scrollWheelEvent2Source: nil,
                     units: .pixel,
                     wheelCount: 2,
                     wheel1: deltaY,
                     wheel2: deltaX,
                     wheel3: 0)!
    // A nil-source CGEvent inherits the live modifier-key state; pin it empty.
    cg.flags = []
    return NSEvent(cgEvent: cg)!
}
