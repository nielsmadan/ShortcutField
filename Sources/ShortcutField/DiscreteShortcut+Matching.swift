import AppKit
import Carbon.HIToolbox
import SwiftUI

// MARK: - Step Matching

public extension DiscreteShortcut.Step {
    /// Match this step against an NSEvent.
    func matches(_ event: NSEvent) -> Bool {
        let eventMods = DiscreteShortcut.canonicalModifiers(event.modifierFlags)
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
        case .scroll, .pinchIn, .pinchOut, .rotateClockwise, .rotateCounterClockwise, .smartMagnify:
            return matches(ShortcutEventShape(event))
        }
    }
}

extension DiscreteShortcut.Step {
    /// The single definition of the scroll and gesture thresholds, shared by
    /// `matches(_ event: NSEvent)` and `ContinuousMatcher`.
    func matches(_ shape: ShortcutEventShape) -> Bool {
        let eventMods = DiscreteShortcut.canonicalModifiers(shape.modifierFlags)
        guard eventMods == modifiers else { return false }

        switch kind {
        case let .scroll(direction):
            guard shape.type == .scrollWheel else { return false }
            return DiscreteShortcut.scrollDirection(
                dx: shape.scrollDeltaX, dy: shape.scrollDeltaY
            ) == direction
        case .pinchIn:
            guard shape.type == .magnify else { return false }
            return shape.magnification < -DiscreteShortcut.magnifyEventThreshold
        case .pinchOut:
            guard shape.type == .magnify else { return false }
            return shape.magnification > DiscreteShortcut.magnifyEventThreshold
        case .rotateCounterClockwise:
            guard shape.type == .rotate else { return false }
            return shape.rotation > DiscreteShortcut.rotateEventThreshold
        case .rotateClockwise:
            guard shape.type == .rotate else { return false }
            return shape.rotation < -DiscreteShortcut.rotateEventThreshold
        case .smartMagnify:
            return shape.type == .smartMagnify
        case .key, .mouseButton:
            return false
        }
    }
}

// MARK: - Scroll direction helper

extension DiscreteShortcut {
    static func scrollDirection(from event: NSEvent) -> ScrollDirection? {
        scrollDirection(dx: Double(event.scrollingDeltaX), dy: Double(event.scrollingDeltaY))
    }

    /// Core scroll-direction logic shared by discrete and continuous matching.
    /// Returns nil if the dominant axis delta is below the noise threshold.
    static func scrollDirection(dx: Double, dy: Double) -> ScrollDirection? {
        let threshold = 0.5
        if abs(dy) >= abs(dx) {
            guard abs(dy) >= threshold else { return nil }
            return dy > 0 ? .up : .down
        } else {
            guard abs(dx) >= threshold else { return nil }
            return dx > 0 ? .left : .right
        }
    }
}

// MARK: - SwiftUI KeyPress Matching

@available(macOS 14.0, *)
public extension DiscreteShortcut.Step {
    /// Match this step against a SwiftUI `KeyPress`.
    ///
    /// Only valid for `.key` steps; returns `false` for any other kind.
    /// Handles special keys (Tab, arrows, etc.) where modifiers change `press.characters`,
    /// falling back to keyboard-layout-aware character comparison for regular keys.
    func matches(_ press: KeyPress) -> Bool {
        guard case let .key(keyCode) = kind else { return false }
        let pressModifiers = Self.eventModifiersToNSModifiers(press.modifiers)
        guard pressModifiers == modifiers else { return false }
        return matchesKey(press, keyCode: keyCode)
    }

    private func matchesKey(_ press: KeyPress, keyCode: UInt16) -> Bool {
        if let keyEquivalent = Self.specialKeyEquivalent(keyCode: keyCode) {
            return press.key == keyEquivalent
        }
        return DiscreteShortcut.keyToCharacter(keyCode: keyCode)?.lowercased() == press.characters.lowercased()
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
