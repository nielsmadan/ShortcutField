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
    /// Only valid for `.key` steps; returns `false` for any other kind, and for key-up
    /// presses. Special keys (Tab, arrows, F1–F20, Forward Delete, Help, keypad Enter and
    /// Clear) compare by `press.key`; other keys compare `press.characters` with the
    /// character the current keyboard layout produces, which for a step holding Shift may
    /// be the shifted or the unshifted character.
    func matches(_ press: KeyPress) -> Bool {
        matches(key: press.key, characters: press.characters, modifiers: press.modifiers, phase: press.phase)
    }
}

@available(macOS 14.0, *)
extension DiscreteShortcut.Step {
    /// Test seam for ``matches(_:)-(KeyPress)``: `KeyPress` has no public initializer.
    /// `layoutCharacter(keyCode, shifted)` gives the character the keyboard layout produces.
    func matches(
        key: KeyEquivalent, characters: String, modifiers pressModifiers: SwiftUI.EventModifiers,
        phase: KeyPress.Phases,
        layoutCharacter: (UInt16, Bool) -> String? = { DiscreteShortcut.keyToCharacter(keyCode: $0, shifted: $1) }
    ) -> Bool {
        guard case let .key(keyCode) = kind, phase != .up,
              Self.eventModifiersToNSModifiers(pressModifiers) == modifiers else { return false }
        if let keyEquivalent = Self.specialKeyEquivalent(keyCode: keyCode) {
            return key == keyEquivalent
        }
        let expected = [
            layoutCharacter(keyCode, false),
            modifiers.contains(.shift) ? layoutCharacter(keyCode, true) : nil,
        ]
        return expected.contains { $0?.lowercased() == characters.lowercased() }
    }

    private static let specialKeyEquivalents: [Int: KeyEquivalent] = {
        let named: [Int: KeyEquivalent] = [
            kVK_Tab: .tab,
            kVK_Return: .return,
            kVK_Delete: .delete,
            kVK_Escape: .escape,
            kVK_Space: .space,
            kVK_UpArrow: .upArrow,
            kVK_DownArrow: .downArrow,
            kVK_LeftArrow: .leftArrow,
            kVK_RightArrow: .rightArrow,
            kVK_Home: .home,
            kVK_End: .end,
            kVK_PageUp: .pageUp,
            kVK_PageDown: .pageDown,
            kVK_ForwardDelete: .deleteForward,
            kVK_ANSI_KeypadClear: .clear,
            kVK_ANSI_KeypadEnter: KeyEquivalent("\u{03}"),
        ]
        let functionKeys = zip(DiscreteShortcut.functionKeyCodes, NSF1FunctionKey...) + [(kVK_Help, NSHelpFunctionKey)]
        let functionKeyEquivalents = functionKeys.compactMap { keyCode, unicode in
            Unicode.Scalar(UInt32(unicode)).map { (keyCode, KeyEquivalent(Character($0))) }
        }
        return named.merging(functionKeyEquivalents) { named, _ in named }
    }()

    private static func specialKeyEquivalent(keyCode: UInt16) -> KeyEquivalent? {
        specialKeyEquivalents[Int(keyCode)]
    }

    private static func eventModifiersToNSModifiers(_ modifiers: SwiftUI.EventModifiers) -> NSEvent.ModifierFlags {
        var flags = NSEvent.ModifierFlags()
        if modifiers.contains(.command) {
            flags.insert(.command)
        }
        if modifiers.contains(.option) {
            flags.insert(.option)
        }
        if modifiers.contains(.control) {
            flags.insert(.control)
        }
        if modifiers.contains(.shift) {
            flags.insert(.shift)
        }
        return flags
    }
}
