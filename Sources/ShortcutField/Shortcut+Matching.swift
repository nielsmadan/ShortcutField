import AppKit
import Carbon.HIToolbox
import SwiftUI

// MARK: - NSEvent Matching

public extension Shortcut {
    /// Match against an NSEvent.
    ///
    /// Use this for keys like Tab that SwiftUI's focus system intercepts,
    /// requiring an `NSEvent.addLocalMonitorForEvents` to catch.
    func matches(_ event: NSEvent) -> Bool {
        guard event.keyCode == keyCode else { return false }
        let eventMods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            .intersection([.shift, .control, .option, .command])
        return eventMods == modifiers
    }
}

// MARK: - SwiftUI KeyPress Matching

@available(macOS 14.0, *)
extension Shortcut {
    /// Match against a SwiftUI `KeyPress`.
    ///
    /// Handles special keys (Tab, arrows, etc.) where modifiers change `press.characters`,
    /// falling back to keyboard-layout-aware character comparison for regular keys.
    public func matches(_ press: KeyPress) -> Bool {
        let pressModifiers = Self.eventModifiersToNSModifiers(press.modifiers)
        guard pressModifiers == modifiers else { return false }
        return matchesKey(press)
    }

    private func matchesKey(_ press: KeyPress) -> Bool {
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
