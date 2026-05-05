import AppKit
import Carbon.HIToolbox
import SwiftUI

/// Internal shape used by the matcher so unit tests can synthesize gesture events
/// without needing to construct real `NSEvent` gesture instances. Keyboard / mouse
/// events can be constructed directly via `CGEvent`, so this is gesture-only.
struct GestureEventShape: Equatable {
    var type: NSEvent.EventType
    var modifierFlags: NSEvent.ModifierFlags
    var magnification: Double
    var rotation: Double // degrees

    init(
        type: NSEvent.EventType,
        modifierFlags: NSEvent.ModifierFlags = [],
        magnification: Double = 0,
        rotation: Double = 0
    ) {
        self.type = type
        self.modifierFlags = modifierFlags
        self.magnification = magnification
        self.rotation = rotation
    }

    init(_ event: NSEvent) {
        type = event.type
        modifierFlags = event.modifierFlags
        magnification = (event.type == .magnify) ? Double(event.magnification) : 0
        rotation = (event.type == .rotate) ? Double(event.rotation) : 0
    }
}

// MARK: - NSEvent Matching

public extension Shortcut {
    /// Match against an NSEvent. Dispatches to per-kind logic.
    func matches(_ event: NSEvent) -> Bool {
        let eventMods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            .intersection([.shift, .control, .option, .command])
        guard eventMods == modifiers else { return false }

        switch kind {
        case let .key(keyCode):
            return event.type == .keyDown && event.keyCode == keyCode
        case let .mouseButton(number):
            guard event.type == .leftMouseDown || event.type == .rightMouseDown
                || event.type == .otherMouseDown
            else {
                return false
            }
            return event.buttonNumber == number
        case let .scroll(direction):
            guard event.type == .scrollWheel else { return false }
            return Self.scrollDirection(from: event) == direction
        case .pinchIn, .pinchOut, .rotateClockwise, .rotateCounterClockwise, .smartMagnify:
            return matchesGesture(GestureEventShape(event))
        }
    }

    /// Determine the discrete scroll direction from a scroll wheel event.
    /// Returns nil if the scroll deltas are below the noise threshold.
    static func scrollDirection(from event: NSEvent) -> ScrollDirection? {
        let dx = event.scrollingDeltaX
        let dy = event.scrollingDeltaY
        let threshold: CGFloat = 0.5

        if abs(dy) >= abs(dx) {
            guard abs(dy) >= threshold else { return nil }
            return dy > 0 ? .up : .down
        } else {
            guard abs(dx) >= threshold else { return nil }
            return dx > 0 ? .left : .right
        }
    }
}

// MARK: - Gesture Event Shape (test seam)

extension Shortcut {
    /// Match against a synthesized gesture event shape — used by tests and by
    /// `matches(_ event: NSEvent)` for gesture kinds.
    func matchesGesture(_ event: GestureEventShape) -> Bool {
        let eventMods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            .intersection([.shift, .control, .option, .command])
        guard eventMods == modifiers else { return false }

        switch kind {
        case .pinchIn:
            guard event.type == .magnify else { return false }
            return event.magnification < -Self.magnifyEventThreshold
        case .pinchOut:
            guard event.type == .magnify else { return false }
            return event.magnification > Self.magnifyEventThreshold
        case .rotateCounterClockwise:
            guard event.type == .rotate else { return false }
            return event.rotation > Self.rotateEventThreshold
        case .rotateClockwise:
            guard event.type == .rotate else { return false }
            return event.rotation < -Self.rotateEventThreshold
        case .smartMagnify:
            return event.type == .smartMagnify
        case .key, .mouseButton, .scroll:
            return false
        }
    }
}

// MARK: - SwiftUI KeyPress Matching

@available(macOS 14.0, *)
extension Shortcut {
    /// Match against a SwiftUI `KeyPress`.
    ///
    /// Only valid for `.key` shortcuts; returns `false` for any other kind.
    /// Handles special keys (Tab, arrows, etc.) where modifiers change `press.characters`,
    /// falling back to keyboard-layout-aware character comparison for regular keys.
    public func matches(_ press: KeyPress) -> Bool {
        guard case let .key(keyCode) = kind else { return false }
        let pressModifiers = Self.eventModifiersToNSModifiers(press.modifiers)
        guard pressModifiers == modifiers else { return false }
        return matchesKey(press, keyCode: keyCode)
    }

    private func matchesKey(_ press: KeyPress, keyCode: UInt16) -> Bool {
        if let keyEquivalent = Self.specialKeyEquivalent(keyCode: keyCode) {
            return press.key == keyEquivalent
        }
        return Self.keyToCharacter(keyCode: keyCode)?.lowercased() == press.characters.lowercased()
    }

    private static func specialKeyEquivalent(keyCode: UInt16) -> KeyEquivalent? {
        switch Int(keyCode) {
        case kVK_Tab: .tab
        case kVK_Return: .return
        case kVK_Delete: .delete
        case kVK_Escape: .escape
        case kVK_Space: .space
        case kVK_UpArrow: .upArrow
        case kVK_DownArrow: .downArrow
        case kVK_LeftArrow: .leftArrow
        case kVK_RightArrow: .rightArrow
        case kVK_Home: .home
        case kVK_End: .end
        case kVK_PageUp: .pageUp
        case kVK_PageDown: .pageDown
        default: nil
        }
    }

    private static func eventModifiersToNSModifiers(_ modifiers: SwiftUI.EventModifiers) -> NSEvent.ModifierFlags {
        var flags = NSEvent.ModifierFlags()
        if modifiers.contains(.command) { flags.insert(.command) }
        if modifiers.contains(.option) { flags.insert(.option) }
        if modifiers.contains(.control) { flags.insert(.control) }
        if modifiers.contains(.shift) { flags.insert(.shift) }
        return flags
    }
}
