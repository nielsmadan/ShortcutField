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

/// Synthesize a key-down `NSEvent` addressed to `window`, as AppKit delivers a keystroke there.
@MainActor
func keyDown(_ keyCode: Int, _ modifiers: NSEvent.ModifierFlags = [], in window: NSWindow) -> NSEvent {
    NSEvent.keyEvent(
        with: .keyDown, location: .zero, modifierFlags: modifiers, timestamp: 0,
        windowNumber: window.windowNumber, context: nil, characters: "", charactersIgnoringModifiers: "",
        isARepeat: false, keyCode: UInt16(keyCode)
    )!
}

/// Synthesize a mouse `NSEvent` of `type` at `point` (window coordinates) in `window`.
@MainActor
func mouseEvent(
    _ type: NSEvent.EventType, at point: NSPoint, in window: NSWindow,
    _ modifiers: NSEvent.ModifierFlags = []
) -> NSEvent {
    NSEvent.mouseEvent(
        with: type, location: point, modifierFlags: modifiers, timestamp: 0,
        windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1
    )!
}

/// Synthesize a scroll-wheel `NSEvent`: a mouse-wheel notch by default, or one event of a
/// trackpad burst in `phase`, or of its momentum coast in `momentum`.
func scrollEvent(
    deltaY: Int32 = 0,
    deltaX: Int32 = 0,
    phase: NSEvent.Phase = [],
    momentum: NSEvent.Phase = []
) -> NSEvent {
    let cg = CGEvent(scrollWheelEvent2Source: nil,
                     units: .pixel,
                     wheelCount: 2,
                     wheel1: deltaY,
                     wheel2: deltaX,
                     wheel3: 0)!
    // A nil-source CGEvent inherits the live modifier-key state; pin it empty.
    cg.flags = []
    cg.setIntegerValueField(.scrollWheelEventScrollPhase, value: Int64(cgScrollPhase(phase)))
    cg.setIntegerValueField(.scrollWheelEventMomentumPhase, value: Int64(cgMomentumPhase(momentum)))
    return NSEvent(cgEvent: cg)!
}

/// Synthesize a trackpad `.magnify`, `.rotate` or `.smartMagnify` `NSEvent` in `phase`; `value`
/// is the magnification, or the rotation in degrees.
///
/// Built from `CGEvent`'s undocumented gesture event type 29 and fields: 110 is the HID gesture
/// type, 113 the magnification, 114 the rotation and 132 the phase, which uses the scroll-phase
/// encoding.
func gestureEvent(
    _ type: NSEvent.EventType,
    _ value: Double = 0,
    phase: NSEvent.Phase = .changed,
    _ modifiers: NSEvent.ModifierFlags = []
) -> NSEvent {
    let (hidType, valueField): (Int64, UInt32) = switch type {
    case .magnify: (8, 113)
    case .rotate: (5, 114)
    case .smartMagnify: (22, 113)
    default: preconditionFailure("No gesture event of type \(type)")
    }
    let cg = CGEvent(source: nil)!
    cg.type = CGEventType(rawValue: 29)!
    cg.flags = CGEventFlags(rawValue: UInt64(modifiers.rawValue))
    cg.setIntegerValueField(CGEventField(rawValue: 110)!, value: hidType)
    cg.setDoubleValueField(CGEventField(rawValue: valueField)!, value: value)
    if type != .smartMagnify {
        cg.setIntegerValueField(CGEventField(rawValue: 132)!, value: Int64(cgScrollPhase(phase)))
    }
    return NSEvent(cgEvent: cg)!
}

private func cgScrollPhase(_ phase: NSEvent.Phase) -> UInt32 {
    switch phase {
    case .began: CGScrollPhase.began.rawValue
    case .changed: CGScrollPhase.changed.rawValue
    case .ended: CGScrollPhase.ended.rawValue
    case .cancelled: CGScrollPhase.cancelled.rawValue
    case .mayBegin: CGScrollPhase.mayBegin.rawValue
    case []: 0
    default: preconditionFailure("CGEvent has no scroll phase for \(phase)")
    }
}

private func cgMomentumPhase(_ phase: NSEvent.Phase) -> UInt32 {
    switch phase {
    case .began: CGMomentumScrollPhase.begin.rawValue
    case .changed: CGMomentumScrollPhase.continuous.rawValue
    case .ended: CGMomentumScrollPhase.end.rawValue
    case []: 0
    default: preconditionFailure("CGEvent has no momentum phase for \(phase)")
    }
}
