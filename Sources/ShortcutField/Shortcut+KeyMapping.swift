import AppKit
import Carbon.HIToolbox

// MARK: - Display String

public extension Shortcut {
    /// Human-readable representation, e.g. "⌘⇧K" or "⌃Tab".
    var displayString: String {
        let modifierString = modifiers.symbolicRepresentation

        if let specialKeyString = Self.specialKeyString(keyCode: keyCode) {
            return modifierString + specialKeyString
        }

        if let char = Self.keyToCharacter(keyCode: keyCode) {
            return modifierString + char
        }

        return modifierString + "?"
    }
}

// MARK: - Special Key Names

extension Shortcut {
    private static let specialKeyNames: [Int: String] = [
        kVK_Return: "↩",
        kVK_Delete: "⌫",
        kVK_ForwardDelete: "⌦",
        kVK_End: "↘",
        kVK_Escape: "⎋",
        kVK_Home: "↖",
        kVK_Space: "Space",
        kVK_Tab: "Tab",
        kVK_PageUp: "⇞",
        kVK_PageDown: "⇟",
        kVK_UpArrow: "↑",
        kVK_RightArrow: "→",
        kVK_DownArrow: "↓",
        kVK_LeftArrow: "←",
        kVK_F1: "F1",
        kVK_F2: "F2",
        kVK_F3: "F3",
        kVK_F4: "F4",
        kVK_F5: "F5",
        kVK_F6: "F6",
        kVK_F7: "F7",
        kVK_F8: "F8",
        kVK_F9: "F9",
        kVK_F10: "F10",
        kVK_F11: "F11",
        kVK_F12: "F12"
    ]

    /// Returns a display string for special keys, or nil for regular keys.
    public static func specialKeyString(keyCode: UInt16) -> String? {
        specialKeyNames[Int(keyCode)]
    }
}

// MARK: - UCKeyTranslate

public extension Shortcut {
    /// Converts a virtual key code to the character it produces on the current keyboard layout.
    static func keyToCharacter(keyCode: UInt16) -> String? {
        guard
            let source = TISCopyCurrentASCIICapableKeyboardLayoutInputSource()?.takeRetainedValue(),
            let layoutDataPointer = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData)
        else {
            return nil
        }

        let layoutData = unsafeBitCast(layoutDataPointer, to: CFData.self)
        guard let bytePtr = CFDataGetBytePtr(layoutData) else { return nil }
        let keyLayout = unsafeBitCast(bytePtr, to: UnsafePointer<UCKeyboardLayout>.self)
        var deadKeyState: UInt32 = 0
        let maxLength = 4
        var length = 0
        var characters = [UniChar](repeating: 0, count: maxLength)

        let error = UCKeyTranslate(
            keyLayout,
            keyCode,
            UInt16(kUCKeyActionDisplay),
            0,
            UInt32(LMGetKbdType()),
            OptionBits(kUCKeyTranslateNoDeadKeysBit),
            &deadKeyState,
            maxLength,
            &length,
            &characters
        )

        guard error == noErr, length > 0 else {
            return nil
        }

        return String(utf16CodeUnits: characters, count: length)
    }
}

// MARK: - Modifier Flags Extension

public extension NSEvent.ModifierFlags {
    /// Symbolic representation of modifier flags, e.g. "⌃⌥⇧⌘".
    var symbolicRepresentation: String {
        var result = ""
        if contains(.control) { result += "⌃" }
        if contains(.option) { result += "⌥" }
        if contains(.shift) { result += "⇧" }
        if contains(.command) { result += "⌘" }
        return result
    }
}
