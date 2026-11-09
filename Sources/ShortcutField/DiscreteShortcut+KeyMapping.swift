// `keyToCharacter(keyCode:)` and `NSEvent.ModifierFlags.symbolicRepresentation`
// are adapted from KeyboardShortcuts (https://github.com/sindresorhus/KeyboardShortcuts).
//
// MIT License
//
// Copyright (c) Sindre Sorhus <sindresorhus@gmail.com> (https://sindresorhus.com)
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in all
// copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.

import AppKit
import Carbon.HIToolbox

// MARK: - Special Key Names

extension DiscreteShortcut {
    /// F1 through F20, in order.
    static let functionKeyCodes = [
        kVK_F1, kVK_F2, kVK_F3, kVK_F4, kVK_F5, kVK_F6, kVK_F7, kVK_F8, kVK_F9, kVK_F10,
        kVK_F11, kVK_F12, kVK_F13, kVK_F14, kVK_F15, kVK_F16, kVK_F17, kVK_F18, kVK_F19, kVK_F20,
    ]

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
        kVK_ANSI_KeypadEnter: "⌤",
        kVK_ANSI_KeypadClear: "⌧",
        kVK_Help: "Help",
        kVK_VolumeUp: "Volume Up",
        kVK_VolumeDown: "Volume Down",
        kVK_Mute: "Mute",
        kVK_JIS_Eisu: "英数",
        kVK_JIS_Kana: "かな",
    ].merging(zip(functionKeyCodes, 1...).map { ($0, "F\($1)") }) { named, _ in named }

    /// Returns a display string for special keys, or nil for regular keys.
    static func specialKeyString(keyCode: UInt16) -> String? {
        specialKeyNames[Int(keyCode)]
    }
}

// MARK: - UCKeyTranslate

extension DiscreteShortcut {
    /// Converts a virtual key code to the character it produces on the current keyboard layout,
    /// with Shift held when `shifted`; `nil` when it produces nothing or only control characters.
    static func keyToCharacter(keyCode: UInt16, shifted: Bool = false) -> String? {
        guard
            let source = TISCopyCurrentASCIICapableKeyboardLayoutInputSource()?.takeRetainedValue(),
            let layoutDataPointer = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData)
        else {
            return nil
        }

        let layoutData = unsafeBitCast(layoutDataPointer, to: CFData.self)
        guard let bytePtr = CFDataGetBytePtr(layoutData) else { return nil }
        var deadKeyState: UInt32 = 0
        let maxLength = 4
        var length = 0
        var characters = [UniChar](repeating: 0, count: maxLength)

        let error = bytePtr.withMemoryRebound(to: UCKeyboardLayout.self, capacity: 1) { keyLayout in
            UCKeyTranslate(
                keyLayout,
                keyCode,
                UInt16(kUCKeyActionDisplay),
                shifted ? UInt32(shiftKey >> 8) & 0xFF : 0,
                UInt32(LMGetKbdType()),
                OptionBits(kUCKeyTranslateNoDeadKeysBit),
                &deadKeyState,
                maxLength,
                &length,
                &characters
            )
        }

        guard error == noErr else { return nil }
        return displayableString(characters.prefix(length))
    }

    /// The UTF-16 output of a key translation as a string; `nil` when it is empty or holds
    /// only control characters (F-keys, forward delete, keypad Enter translate to those).
    static func displayableString(_ units: some Collection<UniChar>) -> String? {
        let string = String(decoding: units, as: UTF16.self)
        guard !string.isEmpty, !string.unicodeScalars.allSatisfy({ $0.properties.generalCategory == .control })
        else { return nil }
        return string
    }
}

// MARK: - Modifier Flags Extension

extension NSEvent.ModifierFlags {
    /// Symbolic representation of modifier flags, e.g. "⌃⌥⇧⌘".
    var symbolicRepresentation: String {
        var result = ""
        if contains(.control) {
            result += "⌃"
        }
        if contains(.option) {
            result += "⌥"
        }
        if contains(.shift) {
            result += "⇧"
        }
        if contains(.command) {
            result += "⌘"
        }
        return result
    }
}
