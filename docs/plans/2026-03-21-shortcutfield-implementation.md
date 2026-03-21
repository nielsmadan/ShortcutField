# ShortcutField Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Build and publish ShortcutField, a SwiftUI/AppKit keyboard shortcut recorder library for macOS.

**Architecture:** Extract from Juggler's `LocalShortcut` + `LocalShortcutRecorderView`, removing persistence/notifications, adding SwiftUI modifier-based styling and an `.onShortcut()` view modifier. Split into model, matching, key mapping, recorder (AppKit + SwiftUI), styles, and matching modifier.

**Tech Stack:** Swift 6.2, SwiftUI, AppKit, Carbon.HIToolbox (UCKeyTranslate), Swift Testing

**Design doc:** `docs/plans/2026-03-21-shortcutfield-library-design.md`

---

### Task 1: Package.swift and Project Tooling

Set up the package manifest, linting, formatting, Justfile, CI, and git config.

**Files:**
- Modify: `Package.swift`
- Create: `Justfile`
- Create: `.swiftlint.yml`
- Create: `.swiftformat`
- Create: `.spi.yml`
- Create: `.github/workflows/ci.yml`
- Modify: `.gitignore`
- Create: `CLAUDE.md`
- Create: `LICENSE`
- Delete: `Sources/ShortcutField/ShortcutField.swift` (template placeholder)
- Delete: `Tests/ShortcutFieldTests/ShortcutFieldTests.swift` (template placeholder)

**Step 1: Update Package.swift**

```swift
// swift-tools-version:6.2
import PackageDescription

let package = Package(
    name: "ShortcutField",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(name: "ShortcutField", targets: ["ShortcutField"])
    ],
    targets: [
        .target(name: "ShortcutField"),
        .testTarget(name: "ShortcutFieldTests", dependencies: ["ShortcutField"])
    ]
)
```

**Step 2: Create Justfile**

```just
[private]
default:
    @just --list

build:
    @swift build

test:
    @swift test

lint *files:
    @swiftlint {{ if files == "" { "." } else { files } }}

lint-fix *files:
    @swiftlint --fix {{ if files == "" { "." } else { files } }}

format *files:
    @swiftformat {{ if files == "" { "." } else { files } }}

clean:
    @rm -rf .build
    @echo "Build directory cleaned."

# Usage: just tag-release-patch, just tag-release-minor, just tag-release-major
tag-release-patch:
    @just tag-release patch

tag-release-minor:
    @just tag-release minor

tag-release-major:
    @just tag-release major

tag-release bump:
    #!/usr/bin/env bash
    set -euo pipefail
    LATEST_TAG=$(git tag --sort=-v:refname | head -1 | sed 's/^v//')
    if [ -z "$LATEST_TAG" ]; then
        VERSION="0.1.0"
        case "{{bump}}" in
            patch) VERSION="0.0.1" ;;
            minor) VERSION="0.1.0" ;;
            major) VERSION="1.0.0" ;;
        esac
    else
        MAJOR=$(echo "$LATEST_TAG" | cut -d. -f1)
        MINOR=$(echo "$LATEST_TAG" | cut -d. -f2)
        PATCH=$(echo "$LATEST_TAG" | cut -d. -f3)
        case "{{bump}}" in
            patch) PATCH=$((PATCH + 1)) ;;
            minor) MINOR=$((MINOR + 1)); PATCH=0 ;;
            major) MAJOR=$((MAJOR + 1)); MINOR=0; PATCH=0 ;;
            *) echo "Error: bump must be patch, minor, or major"; exit 1 ;;
        esac
        VERSION="$MAJOR.$MINOR.$PATCH"
    fi
    echo "Tagging v$VERSION..."
    git tag "v$VERSION" && git push origin main "v$VERSION" && \
    echo "Tagged and pushed v$VERSION"
```

**Step 3: Create `.swiftlint.yml`**

Same as Juggler's config (from `/Users/nielsmadan/wrksp/juggler/app/.swiftlint.yml`), with paths adjusted:

```yaml
disabled_rules:
  - trailing_whitespace
  - line_length
  - type_body_length
  - file_length

opt_in_rules:
  - empty_count
  - explicit_init
  - first_where
  - toggle_bool
  - unavailable_function

excluded:
  - .build

identifier_name:
  min_length: 1
  max_length: 50

type_name:
  min_length: 2
  max_length: 50

cyclomatic_complexity:
  warning: 15
  error: 30

function_body_length:
  warning: 80
  error: 150

function_parameter_count:
  warning: 8
  error: 10

nesting:
  type_level: 2

large_tuple:
  warning: 3
```

**Step 4: Create `.swiftformat`**

```
--indent 4
--indentcase false
--trimwhitespace always
--voidtype void
--semicolons inline
--swiftversion 6.0
--maxwidth 120
```

**Step 5: Create `.spi.yml`**

```yaml
version: 1
builder:
  configs:
    - documentation_targets: ['ShortcutField']
```

**Step 6: Create `.github/workflows/ci.yml`**

```yaml
name: CI

on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

permissions:
  contents: read

jobs:
  build-and-test:
    runs-on: macos-26
    timeout-minutes: 10
    steps:
      - uses: actions/checkout@v4

      - name: Build
        run: swift build

      - name: Test
        run: swift test

  lint:
    runs-on: macos-26
    steps:
      - uses: actions/checkout@v4

      - name: Install SwiftLint
        run: brew install swiftlint

      - name: Lint
        run: swiftlint .
```

**Step 7: Update `.gitignore`**

```
.DS_Store
/.build
/Packages
xcuserdata/
DerivedData/
.swiftpm/xcode/package.xcworkspace/contents.xcworkspacedata
```

**Step 8: Create `LICENSE`**

MIT license with `Copyright (c) 2026 Niels Madan`.

**Step 9: Create `CLAUDE.md`**

```markdown
# CLAUDE.md

## Build & Run

\```bash
just build    # Build the package
just test     # Run tests
just lint     # Run SwiftLint
just format   # Run SwiftFormat
just clean    # Remove build directory
\```

## Architecture

ShortcutField is a Swift package providing a keyboard shortcut recorder for macOS apps. It handles recording, displaying, and matching in-app keyboard shortcuts — including special keys like Tab.

**Source structure:**
- `Shortcut.swift` — Model: keyCode + modifiers, Codable, Equatable, Sendable
- `Shortcut+Matching.swift` — matches(NSEvent) and matches(KeyPress)
- `Shortcut+KeyMapping.swift` — UCKeyTranslate, special keys, display strings
- `ShortcutRecorderView.swift` — SwiftUI recorder (NSViewRepresentable)
- `ShortcutRecorderField.swift` — AppKit NSSearchField subclass
- `ShortcutRecorderStyle.swift` — .rounded, .plain, .borderless styles
- `OnShortcutModifier.swift` — .onShortcut() view modifier

## Code Style

- SwiftLint and SwiftFormat configured
- 4-space indentation, 120 char max width
- Swift Testing framework (@Test, #expect)
- macOS 13+ minimum deployment target
```

**Step 10: Delete template placeholders**

Delete `Sources/ShortcutField/ShortcutField.swift` and `Tests/ShortcutFieldTests/ShortcutFieldTests.swift`.

**Step 11: Verify build**

Run: `just build`
Expected: Build succeeds (empty target, no sources yet — swift allows this for a library with no source files, or create an empty placeholder if needed)

**Step 12: Commit**

```bash
git add -A
git commit -m "chore: set up package tooling, CI, and linting"
```

---

### Task 2: Shortcut Model

Extract the core `Shortcut` struct from Juggler's `LocalShortcut`, without persistence.

**Files:**
- Create: `Sources/ShortcutField/Shortcut.swift`
- Create: `Tests/ShortcutFieldTests/ShortcutTests.swift`

**Step 1: Write the failing tests**

Create `Tests/ShortcutFieldTests/ShortcutTests.swift`:

```swift
import AppKit
import Carbon.HIToolbox
import ShortcutField
import Testing

@Test func shortcut_storesKeyCodeAndModifiers() {
    let shortcut = Shortcut(keyCode: 38, modifiers: [.command, .shift])
    #expect(shortcut.keyCode == 38)
    #expect(shortcut.modifiers.contains(.command))
    #expect(shortcut.modifiers.contains(.shift))
}

@Test func shortcut_equatable_sameValues_areEqual() {
    let a = Shortcut(keyCode: 38, modifiers: [.command])
    let b = Shortcut(keyCode: 38, modifiers: [.command])
    #expect(a == b)
}

@Test func shortcut_equatable_differentKey_areNotEqual() {
    let a = Shortcut(keyCode: 38, modifiers: [.command])
    let b = Shortcut(keyCode: 1, modifiers: [.command])
    #expect(a != b)
}

@Test func shortcut_equatable_differentModifiers_areNotEqual() {
    let a = Shortcut(keyCode: 38, modifiers: [.command])
    let b = Shortcut(keyCode: 38, modifiers: [.shift])
    #expect(a != b)
}

@Test func shortcut_codableRoundtrip() throws {
    let original = Shortcut(keyCode: 38, modifiers: [.command, .shift])
    let data = try JSONEncoder().encode(original)
    let decoded = try JSONDecoder().decode(Shortcut.self, from: data)
    #expect(decoded == original)
}

@Test func shortcut_codableRoundtrip_noModifiers() throws {
    let original = Shortcut(keyCode: 36, modifiers: [])
    let data = try JSONEncoder().encode(original)
    let decoded = try JSONDecoder().decode(Shortcut.self, from: data)
    #expect(decoded == original)
}
```

**Step 2: Run tests to verify they fail**

Run: `just test`
Expected: FAIL — `Shortcut` type not found

**Step 3: Write the Shortcut model**

Create `Sources/ShortcutField/Shortcut.swift`:

```swift
import AppKit

/// A keyboard shortcut defined by a key code and modifier flags.
///
/// Use with ``ShortcutRecorderView`` to let users record shortcuts,
/// and ``Shortcut/matches(_:)-NSEvent`` or ``Shortcut/matches(_:)-KeyPress``
/// to detect when they're pressed.
public struct Shortcut: Sendable, Equatable {
    /// The virtual key code (e.g., `kVK_Tab` from Carbon.HIToolbox).
    public let keyCode: UInt16

    /// The modifier flags (Command, Shift, Option, Control).
    public let modifiers: NSEvent.ModifierFlags

    public init(keyCode: UInt16, modifiers: NSEvent.ModifierFlags) {
        self.keyCode = keyCode
        // Store only the four shortcut-relevant modifiers
        self.modifiers = modifiers.intersection([.shift, .control, .option, .command])
    }
}

// MARK: - Codable

extension Shortcut: Codable {
    enum CodingKeys: String, CodingKey {
        case keyCode
        case modifiers
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        keyCode = try container.decode(UInt16.self, forKey: .keyCode)
        let rawModifiers = try container.decode(UInt.self, forKey: .modifiers)
        modifiers = NSEvent.ModifierFlags(rawValue: rawModifiers)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(keyCode, forKey: .keyCode)
        try container.encode(modifiers.rawValue, forKey: .modifiers)
    }
}
```

Note: Juggler stores `modifiers` as `UInt` (raw value). We keep the same Codable wire format for compatibility, but the property type is `NSEvent.ModifierFlags` — cleaner public API, no need for a separate `modifierFlags` computed property.

**Step 4: Run tests to verify they pass**

Run: `just test`
Expected: All 6 tests PASS

**Step 5: Commit**

```bash
git add -A
git commit -m "feat: add Shortcut model with Codable and Equatable"
```

---

### Task 3: Key Mapping and Display Strings

Extract UCKeyTranslate, special key names, modifier symbols, and `displayString`.

**Files:**
- Create: `Sources/ShortcutField/Shortcut+KeyMapping.swift`
- Create: `Tests/ShortcutFieldTests/ShortcutKeyMappingTests.swift`

**Step 1: Write the failing tests**

Create `Tests/ShortcutFieldTests/ShortcutKeyMappingTests.swift`:

```swift
import AppKit
import Carbon.HIToolbox
import ShortcutField
import Testing

// MARK: - Special Key Strings

@Test func specialKeyString_returnKey() {
    #expect(Shortcut.specialKeyString(keyCode: UInt16(kVK_Return)) == "↩")
}

@Test func specialKeyString_deleteKey() {
    #expect(Shortcut.specialKeyString(keyCode: UInt16(kVK_Delete)) == "⌫")
}

@Test func specialKeyString_forwardDeleteKey() {
    #expect(Shortcut.specialKeyString(keyCode: UInt16(kVK_ForwardDelete)) == "⌦")
}

@Test func specialKeyString_escapeKey() {
    #expect(Shortcut.specialKeyString(keyCode: UInt16(kVK_Escape)) == "⎋")
}

@Test func specialKeyString_spaceKey() {
    #expect(Shortcut.specialKeyString(keyCode: UInt16(kVK_Space)) == "Space")
}

@Test func specialKeyString_tabKey() {
    #expect(Shortcut.specialKeyString(keyCode: UInt16(kVK_Tab)) == "Tab")
}

@Test func specialKeyString_arrowKeys() {
    #expect(Shortcut.specialKeyString(keyCode: UInt16(kVK_UpArrow)) == "↑")
    #expect(Shortcut.specialKeyString(keyCode: UInt16(kVK_DownArrow)) == "↓")
    #expect(Shortcut.specialKeyString(keyCode: UInt16(kVK_LeftArrow)) == "←")
    #expect(Shortcut.specialKeyString(keyCode: UInt16(kVK_RightArrow)) == "→")
}

@Test func specialKeyString_homeEndPageKeys() {
    #expect(Shortcut.specialKeyString(keyCode: UInt16(kVK_Home)) == "↖")
    #expect(Shortcut.specialKeyString(keyCode: UInt16(kVK_End)) == "↘")
    #expect(Shortcut.specialKeyString(keyCode: UInt16(kVK_PageUp)) == "⇞")
    #expect(Shortcut.specialKeyString(keyCode: UInt16(kVK_PageDown)) == "⇟")
}

@Test func specialKeyString_functionKeys() {
    #expect(Shortcut.specialKeyString(keyCode: UInt16(kVK_F1)) == "F1")
    #expect(Shortcut.specialKeyString(keyCode: UInt16(kVK_F12)) == "F12")
}

@Test func specialKeyString_unknownKey_returnsNil() {
    #expect(Shortcut.specialKeyString(keyCode: 0) == nil) // 'A' key
}

// MARK: - Modifier Symbolic Representation

@Test func symbolicRepresentation_command() {
    let flags: NSEvent.ModifierFlags = .command
    #expect(flags.symbolicRepresentation == "⌘")
}

@Test func symbolicRepresentation_allModifiers() {
    let flags: NSEvent.ModifierFlags = [.control, .option, .shift, .command]
    #expect(flags.symbolicRepresentation == "⌃⌥⇧⌘")
}

@Test func symbolicRepresentation_empty() {
    let flags: NSEvent.ModifierFlags = []
    #expect(flags.symbolicRepresentation == "")
}

// MARK: - Display String

@Test func displayString_specialKeyOnly() {
    let shortcut = Shortcut(keyCode: UInt16(kVK_Return), modifiers: [])
    #expect(shortcut.displayString == "↩")
}

@Test func displayString_modifierWithSpecialKey() {
    let shortcut = Shortcut(keyCode: UInt16(kVK_Return), modifiers: .command)
    #expect(shortcut.displayString == "⌘↩")
}

@Test func displayString_letterOnly() {
    let shortcut = Shortcut(keyCode: 1, modifiers: []) // 'S' key
    #expect(shortcut.displayString == "s")
}

@Test func displayString_modifierWithLetter() {
    let shortcut = Shortcut(keyCode: 38, modifiers: [.command, .shift]) // 'J' key
    let display = shortcut.displayString
    #expect(display.contains("⇧"))
    #expect(display.contains("⌘"))
}

// MARK: - keyToCharacter

@Test func keyToCharacter_knownKeys() {
    #expect(Shortcut.keyToCharacter(keyCode: 0)?.lowercased() == "a")
    #expect(Shortcut.keyToCharacter(keyCode: 1)?.lowercased() == "s")
}
```

**Step 2: Run tests to verify they fail**

Run: `just test`
Expected: FAIL — `specialKeyString`, `symbolicRepresentation`, `displayString`, `keyToCharacter` not found

**Step 3: Write the key mapping implementation**

Create `Sources/ShortcutField/Shortcut+KeyMapping.swift`:

```swift
import AppKit
import Carbon.HIToolbox

// MARK: - Display String

extension Shortcut {
    /// Human-readable representation, e.g. "⌘⇧K" or "⌃Tab".
    public var displayString: String {
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

    /// Returns a display string for special keys (Tab, Return, arrows, etc.), or nil for regular keys.
    public static func specialKeyString(keyCode: UInt16) -> String? {
        specialKeyNames[Int(keyCode)]
    }
}

// MARK: - UCKeyTranslate

extension Shortcut {
    /// Converts a virtual key code to the character it produces on the current keyboard layout.
    public static func keyToCharacter(keyCode: UInt16) -> String? {
        guard
            let source = TISCopyCurrentASCIICapableKeyboardLayoutInputSource()?.takeRetainedValue(),
            let layoutDataPointer = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData)
        else {
            return nil
        }

        let layoutData = unsafeBitCast(layoutDataPointer, to: CFData.self)
        let keyLayout = unsafeBitCast(CFDataGetBytePtr(layoutData), to: UnsafePointer<UCKeyboardLayout>.self)
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

extension NSEvent.ModifierFlags {
    /// Symbolic representation of modifier flags, e.g. "⌃⌥⇧⌘".
    public var symbolicRepresentation: String {
        var result = ""
        if contains(.control) { result += "⌃" }
        if contains(.option) { result += "⌥" }
        if contains(.shift) { result += "⇧" }
        if contains(.command) { result += "⌘" }
        return result
    }
}
```

Note: Tab display changed from lowercase "tab" to "Tab" for consistency with other special key names.

**Step 4: Run tests to verify they pass**

Run: `just test`
Expected: All tests PASS

**Step 5: Commit**

```bash
git add -A
git commit -m "feat: add key mapping, display strings, and UCKeyTranslate support"
```

---

### Task 4: Shortcut Matching

Extract NSEvent and KeyPress matching logic.

**Files:**
- Create: `Sources/ShortcutField/Shortcut+Matching.swift`
- Create: `Tests/ShortcutFieldTests/ShortcutMatchingTests.swift`

**Step 1: Write the failing tests**

Create `Tests/ShortcutFieldTests/ShortcutMatchingTests.swift`:

```swift
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
```

**Step 2: Run tests to verify they fail**

Run: `just test`
Expected: FAIL — `matches(_:)` not found on `Shortcut`

**Step 3: Write the matching implementation**

Create `Sources/ShortcutField/Shortcut+Matching.swift`:

```swift
import AppKit
import Carbon.HIToolbox
import SwiftUI

// MARK: - NSEvent Matching

extension Shortcut {
    /// Match against an NSEvent.
    ///
    /// Use this for keys like Tab that SwiftUI's focus system intercepts,
    /// requiring an `NSEvent.addLocalMonitorForEvents` to catch.
    public func matches(_ event: NSEvent) -> Bool {
        guard event.keyCode == keyCode else { return false }
        let eventMods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            .intersection([.shift, .control, .option, .command])
        return eventMods == modifiers
    }
}

// MARK: - SwiftUI KeyPress Matching

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
```

**Step 4: Run tests to verify they pass**

Run: `just test`
Expected: All tests PASS

**Step 5: Commit**

```bash
git add -A
git commit -m "feat: add NSEvent and KeyPress shortcut matching"
```

---

### Task 5: ShortcutRecorderField (AppKit)

Extract the NSSearchField-based recorder, removing Juggler-specific code.

**Files:**
- Create: `Sources/ShortcutField/ShortcutRecorderField.swift`
- Create: `Tests/ShortcutFieldTests/ShortcutRecorderFieldTests.swift`

**Step 1: Write the failing tests**

Create `Tests/ShortcutFieldTests/ShortcutRecorderFieldTests.swift`:

```swift
import AppKit
import Carbon.HIToolbox
import ShortcutField
import Testing

@MainActor
@Test func recorderField_defaultState() {
    let field = ShortcutRecorderField()
    #expect(field.shortcut == nil)
    #expect(!field.isRecording)
    #expect(field.frame.width >= 130)
}

@MainActor
@Test func recorderField_setShortcut_updatesDisplay() {
    let field = ShortcutRecorderField()
    let shortcut = Shortcut(keyCode: UInt16(kVK_Tab), modifiers: .command)
    field.shortcut = shortcut
    #expect(field.shortcut == shortcut)
    #expect(field.stringValue == shortcut.displayString)
}

@MainActor
@Test func recorderField_clearShortcut_clearsDisplay() {
    let field = ShortcutRecorderField()
    field.shortcut = Shortcut(keyCode: UInt16(kVK_Tab), modifiers: .command)
    field.shortcut = nil
    #expect(field.shortcut == nil)
    #expect(field.stringValue == "")
}

@MainActor
@Test func recorderField_onShortcutChange_callback() {
    let field = ShortcutRecorderField()
    var receivedShortcut: Shortcut?
    var callCount = 0
    field.onShortcutChange = { shortcut in
        receivedShortcut = shortcut
        callCount += 1
    }

    let shortcut = Shortcut(keyCode: 38, modifiers: .command)
    field.shortcut = shortcut
    // Callback is only fired by user interaction (event handling), not programmatic set
    #expect(callCount == 0)
}

@MainActor
@Test func recorderField_intrinsicContentSize_hasMinimumWidth() {
    let field = ShortcutRecorderField()
    #expect(field.intrinsicContentSize.width >= 130)
}
```

**Step 2: Run tests to verify they fail**

Run: `just test`
Expected: FAIL — `ShortcutRecorderField` not found

**Step 3: Write the recorder field**

Create `Sources/ShortcutField/ShortcutRecorderField.swift`:

```swift
import AppKit
import Carbon.HIToolbox

/// An AppKit control that records keyboard shortcuts.
///
/// Subclasses `NSSearchField` to provide a familiar text-field appearance with
/// a clear button. Click to start recording, press a key combination to set the
/// shortcut, press Escape to cancel, or Delete to clear.
///
/// For SwiftUI, use ``ShortcutRecorderView`` instead.
public final class ShortcutRecorderField: NSSearchField, NSSearchFieldDelegate, @preconcurrency NSTextViewDelegate {
    /// Whether any recorder instance is currently in recording mode.
    public static var isAnyRecording = false

    private let minimumWidth: CGFloat = 130
    private var eventMonitor: Any?
    private var cancelButton: NSButtonCell?
    private var canBecomeKey = false

    /// Whether this field is currently recording a shortcut.
    public private(set) var isRecording = false

    override public var canBecomeKeyView: Bool { canBecomeKey }

    /// The currently recorded shortcut, or nil if cleared.
    public var shortcut: Shortcut? {
        didSet {
            updateDisplay()
        }
    }

    /// Called when the user records or clears a shortcut.
    public var onShortcutChange: ((Shortcut?) -> Void)?

    /// The placeholder text shown when not recording and no shortcut is set.
    public var defaultPlaceholder: String = "Record Shortcut" {
        didSet {
            if !isRecording {
                placeholderString = defaultPlaceholder
            }
        }
    }

    /// The placeholder text shown during recording.
    public var recordingPlaceholder: String = "Press shortcut..."

    private var showsCancelButton: Bool {
        get { (cell as? NSSearchFieldCell)?.cancelButtonCell != nil }
        set { (cell as? NSSearchFieldCell)?.cancelButtonCell = newValue ? cancelButton : nil }
    }

    deinit {
        endRecording()
    }

    override public init(frame _: NSRect) {
        super.init(frame: NSRect(x: 0, y: 0, width: minimumWidth, height: 24))
        setup()
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    /// Create a new recorder field.
    public convenience init() {
        self.init(frame: .zero)
    }

    private func setup() {
        delegate = self
        placeholderString = defaultPlaceholder
        alignment = .center
        (cell as? NSSearchFieldCell)?.searchButtonCell = nil
        wantsLayer = true
        setContentHuggingPriority(.defaultHigh, for: .vertical)
        setContentHuggingPriority(.defaultHigh, for: .horizontal)

        cancelButton = (cell as? NSSearchFieldCell)?.cancelButtonCell

        updateDisplay()
    }

    override public var intrinsicContentSize: NSSize {
        var size = super.intrinsicContentSize
        size.width = minimumWidth
        return size
    }

    override public func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard window != nil else { return }

        // Prevent receiving initial focus when the window appears.
        // Enable after a brief delay so clicking still works.
        canBecomeKey = false
        DispatchQueue.main.async { [weak self] in
            self?.canBecomeKey = true
        }
    }

    private func updateDisplay() {
        if let shortcut {
            stringValue = shortcut.displayString
            showsCancelButton = true
        } else {
            stringValue = ""
            showsCancelButton = false
        }
    }

    private func startRecording() {
        isRecording = true
        Self.isAnyRecording = true
        placeholderString = recordingPlaceholder
        showsCancelButton = shortcut != nil

        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [
            .keyDown,
            .leftMouseUp,
            .rightMouseUp
        ]) { [weak self] event in
            guard let self, isRecording else { return event }
            return handleEvent(event)
        }
    }

    /// Clean up recording state without blurring focus.
    /// Callers that want to also lose focus should call blur() separately.
    /// Separating these prevents cascading stopRecording calls via controlTextDidEndEditing.
    private func endRecording() {
        guard isRecording else { return }
        isRecording = false
        Self.isAnyRecording = false
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
            self.eventMonitor = nil
        }
        placeholderString = defaultPlaceholder
        showsCancelButton = shortcut != nil
    }

    private func blur() {
        window?.makeFirstResponder(nil)
    }

    // MARK: - NSSearchFieldDelegate

    public func controlTextDidEndEditing(_: Notification) {
        endRecording()
    }

    public func control(_: NSControl, textView _: NSTextView, shouldChangeTextIn _: NSRange,
                        replacementString _: String?) -> Bool {
        false
    }

    public func searchFieldDidEndSearching(_: NSSearchField) {
        shortcut = nil
        onShortcutChange?(nil)
        updateDisplay()
    }

    override public func becomeFirstResponder() -> Bool {
        guard window != nil else { return false }

        let shouldBecomeFirstResponder = super.becomeFirstResponder()
        guard shouldBecomeFirstResponder else { return false }

        startRecording()

        DispatchQueue.main.async { [weak self] in
            if let textView = self?.currentEditor() as? NSTextView {
                textView.insertionPointColor = .clear
                textView.delegate = self
            }
        }

        return true
    }

    // MARK: - NSTextViewDelegate

    public func textView(_: NSTextView, shouldChangeTextIn _: NSRange, replacementString _: String?) -> Bool {
        false
    }

    // MARK: - Event Handling

    private func handleEvent(_ event: NSEvent) -> NSEvent? {
        if event.type == .leftMouseUp || event.type == .rightMouseUp {
            let clickPoint = convert(event.locationInWindow, from: nil)
            let clickMargin: CGFloat = 3.0
            if !bounds.insetBy(dx: -clickMargin, dy: -clickMargin).contains(clickPoint) {
                endRecording()
                blur()
                return event
            }
            return nil
        }

        guard event.type == .keyDown else { return event }

        let modifiers = event.modifierFlags
            .intersection(.deviceIndependentFlagsMask)
            .subtracting([.capsLock, .numericPad, .function])

        if modifiers.isEmpty, event.keyCode == UInt16(kVK_Escape) {
            endRecording()
            blur()
            return nil
        }

        if modifiers.isEmpty,
           event.keyCode == UInt16(kVK_Delete) || event.keyCode == UInt16(kVK_ForwardDelete) {
            shortcut = nil
            onShortcutChange?(nil)
            updateDisplay()
            endRecording()
            blur()
            return nil
        }

        let newShortcut = Shortcut(keyCode: event.keyCode, modifiers: modifiers)
        shortcut = newShortcut
        onShortcutChange?(newShortcut)
        updateDisplay()
        endRecording()
        blur()
        return nil
    }
}
```

**Step 4: Run tests to verify they pass**

Run: `just test`
Expected: All tests PASS

**Step 5: Commit**

```bash
git add -A
git commit -m "feat: add ShortcutRecorderField (AppKit recorder)"
```

---

### Task 6: ShortcutRecorderStyle

Add the style enum and styling infrastructure.

**Files:**
- Create: `Sources/ShortcutField/ShortcutRecorderStyle.swift`

**Step 1: Write the style enum**

Create `Sources/ShortcutField/ShortcutRecorderStyle.swift`:

```swift
import AppKit

/// Visual style for the shortcut recorder.
public enum ShortcutRecorderStyle: Sendable {
    /// Default rounded appearance matching NSSearchField.
    case rounded
    /// Minimal flat border.
    case plain
    /// No visible border — just text.
    case borderless
}

extension ShortcutRecorderField {
    /// Apply a visual style to the recorder field.
    func applyStyle(_ style: ShortcutRecorderStyle) {
        switch style {
        case .rounded:
            bezelStyle = .roundedBezel
            isBezeled = true
            isBordered = true
        case .plain:
            bezelStyle = .squareBezel
            isBezeled = true
            isBordered = true
        case .borderless:
            isBezeled = false
            isBordered = false
        }
    }
}
```

**Step 2: Verify build**

Run: `just build`
Expected: Build succeeds

**Step 3: Commit**

```bash
git add -A
git commit -m "feat: add ShortcutRecorderStyle enum"
```

---

### Task 7: ShortcutRecorderView (SwiftUI)

Create the SwiftUI wrapper with modifier-based customization.

**Files:**
- Create: `Sources/ShortcutField/ShortcutRecorderView.swift`

**Step 1: Write the SwiftUI view**

Create `Sources/ShortcutField/ShortcutRecorderView.swift`:

```swift
import SwiftUI

/// A SwiftUI view that lets users record a keyboard shortcut.
///
/// ```swift
/// @State private var shortcut: Shortcut?
///
/// ShortcutRecorderView($shortcut)
///     .placeholder("Record Shortcut")
///     .style(.rounded)
/// ```
public struct ShortcutRecorderView: NSViewRepresentable {
    @Binding var shortcut: Shortcut?

    private var placeholderText: String = "Record Shortcut"
    private var recordingPlaceholderText: String = "Press shortcut..."
    private var style: ShortcutRecorderStyle = .rounded

    /// Create a shortcut recorder bound to the given shortcut value.
    public init(_ shortcut: Binding<Shortcut?>) {
        _shortcut = shortcut
    }

    public func makeNSView(context _: Context) -> ShortcutRecorderField {
        let field = ShortcutRecorderField()
        field.shortcut = shortcut
        field.defaultPlaceholder = placeholderText
        field.recordingPlaceholder = recordingPlaceholderText
        field.applyStyle(style)
        field.onShortcutChange = { newShortcut in
            DispatchQueue.main.async {
                shortcut = newShortcut
            }
        }
        return field
    }

    public func updateNSView(_ nsView: ShortcutRecorderField, context _: Context) {
        // Don't update while recording — the async binding update from onShortcutChange
        // can set stringValue on the field editor, triggering controlTextDidEndEditing
        // and prematurely stopping the recording session.
        guard !nsView.isRecording else { return }
        nsView.shortcut = shortcut
    }
}

// MARK: - Modifiers

extension ShortcutRecorderView {
    /// Set the placeholder text shown when no shortcut is recorded.
    public func placeholder(_ text: String) -> ShortcutRecorderView {
        var view = self
        view.placeholderText = text
        return view
    }

    /// Set the placeholder text shown during recording.
    public func recordingPlaceholder(_ text: String) -> ShortcutRecorderView {
        var view = self
        view.recordingPlaceholderText = text
        return view
    }

    /// Set the visual style of the recorder.
    public func style(_ style: ShortcutRecorderStyle) -> ShortcutRecorderView {
        var view = self
        view.style = style
        return view
    }
}
```

**Step 2: Verify build**

Run: `just build`
Expected: Build succeeds

**Step 3: Commit**

```bash
git add -A
git commit -m "feat: add ShortcutRecorderView (SwiftUI wrapper)"
```

---

### Task 8: OnShortcut View Modifier

Create the `.onShortcut()` modifier that handles both NSEvent and KeyPress matching.

**Files:**
- Create: `Sources/ShortcutField/OnShortcutModifier.swift`

**Step 1: Write the modifier**

Create `Sources/ShortcutField/OnShortcutModifier.swift`:

```swift
import AppKit
import Carbon.HIToolbox
import SwiftUI

/// View modifier that fires an action when a shortcut is pressed.
///
/// Internally uses both an NSEvent local monitor (for special keys like Tab
/// that SwiftUI's focus system intercepts) and a SwiftUI `onKeyPress` handler.
struct OnShortcutModifier: ViewModifier {
    let shortcut: Shortcut?
    let action: () -> Void

    @State private var eventMonitor: Any?

    func body(content: Content) -> some View {
        content
            .onKeyPress(phases: .down) { press in
                guard let shortcut, shortcut.matches(press) else {
                    return .ignored
                }
                action()
                return .handled
            }
            .onAppear {
                installMonitor()
            }
            .onDisappear {
                removeMonitor()
            }
            .onChange(of: shortcut) { _, _ in
                removeMonitor()
                installMonitor()
            }
    }

    private func installMonitor() {
        guard let shortcut, eventMonitor == nil else { return }

        // Only install for special keys that SwiftUI might not deliver via onKeyPress
        guard Self.needsEventMonitor(keyCode: shortcut.keyCode) else { return }

        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if shortcut.matches(event) {
                action()
                return nil
            }
            return event
        }
    }

    private func removeMonitor() {
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
            self.eventMonitor = nil
        }
    }

    /// Keys that SwiftUI's focus system may intercept before onKeyPress fires.
    private static func needsEventMonitor(keyCode: UInt16) -> Bool {
        switch Int(keyCode) {
        case kVK_Tab, kVK_Escape:
            true
        default:
            false
        }
    }
}

// MARK: - View Extension

extension View {
    /// Perform an action when the given shortcut is pressed.
    ///
    /// Handles both regular keys (via SwiftUI's `onKeyPress`) and special keys
    /// like Tab (via an NSEvent local monitor).
    ///
    /// ```swift
    /// MyView()
    ///     .onShortcut(shortcut) {
    ///         print("Shortcut fired!")
    ///     }
    /// ```
    public func onShortcut(_ shortcut: Shortcut?, perform action: @escaping () -> Void) -> some View {
        modifier(OnShortcutModifier(shortcut: shortcut, action: action))
    }
}
```

**Step 2: Verify build**

Run: `just build`
Expected: Build succeeds

**Step 3: Commit**

```bash
git add -A
git commit -m "feat: add .onShortcut() view modifier"
```

---

### Task 9: README

Write the README with usage examples and installation instructions.

**Files:**
- Create: `README.md`

**Step 1: Write the README**

Create `README.md` with:
- One-line description
- Requirements (macOS 13+, Swift 6.2)
- Installation (Swift Package Manager with GitHub URL)
- Usage sections: Recording (SwiftUI + AppKit), Matching (modifier + manual), Styles, Display Strings
- API overview (link to DocC on Swift Package Index)
- License (MIT)

Keep it concise — model after sindresorhus/KeyboardShortcuts README structure.

**Step 2: Commit**

```bash
git add README.md
git commit -m "docs: add README"
```

---

### Task 10: Example App

The user creates the Xcode project shell manually. Then populate it with demo content.

**Files:**
- User creates: `Example/ShortcutFieldExample/ShortcutFieldExample.xcodeproj` (in Xcode)
- Modify: `Example/ShortcutFieldExample/ShortcutFieldExample/ContentView.swift`
- Modify: `Example/ShortcutFieldExample/ShortcutFieldExample/ShortcutFieldExampleApp.swift` (if needed)

**Step 1: Ask user to create the Xcode project**

Prompt user:
> Please create the Example app in Xcode:
> 1. File > New > Project > macOS > App (SwiftUI, Swift)
> 2. Name: `ShortcutFieldExample`
> 3. Save into `Example/ShortcutFieldExample/`
> 4. Add local package dependency: Project > Package Dependencies > Add Local > select the ShortcutField root (`../../`)
> 5. Confirm it builds

**Step 2: Write ContentView with four demo sections**

Replace `ContentView.swift` with a view containing:

1. **Basic Recorder** — single `ShortcutRecorderView` bound to `@State var shortcut: Shortcut?`, showing the display string below
2. **Multiple Recorders** — "Next" and "Previous" recorders side by side
3. **Live Matching** — a focused text area with `.onShortcut()` modifiers that highlight labels when fired
4. **Style Variations** — three recorders showing `.rounded`, `.plain`, `.borderless`

Each section in a `GroupBox` with a title.

**Step 3: Verify the example app builds and runs**

User runs in Xcode: `Cmd+R`

**Step 4: Commit**

```bash
git add -A
git commit -m "feat: add example app with demo sections"
```

---

### Task 11: Final Polish and Lint

Run linting, formatting, and verify everything is clean.

**Files:**
- Potentially modify: any source files with lint/format issues

**Step 1: Format all code**

Run: `just format`

**Step 2: Lint all code**

Run: `just lint`
Expected: No warnings or errors

**Step 3: Run all tests**

Run: `just test`
Expected: All tests PASS

**Step 4: Commit any formatting changes**

```bash
git add -A
git commit -m "chore: format and lint cleanup"
```

---

### Task 12: Publish

Tag, release, and submit to Swift Package Index.

**Step 1: Tag the release**

Run: `just tag-release-major` (this creates v1.0.0)

**Step 2: Create GitHub Release**

```bash
gh release create v1.0.0 --title "v1.0.0" --notes "Initial release of ShortcutField.

A SwiftUI/AppKit keyboard shortcut recorder for macOS. Records, displays, and matches in-app keyboard shortcuts — including special keys like Tab.

## Features
- ShortcutRecorderView (SwiftUI) and ShortcutRecorderField (AppKit)
- .onShortcut() view modifier for easy matching
- UCKeyTranslate keyboard layout support
- Customizable styles: .rounded, .plain, .borderless
- Full special key support (Tab, arrows, function keys, etc.)"
```

**Step 3: Submit to Swift Package Index**

Fork `SwiftPackageIndex/PackageList`, add the repo URL to `packages.json`, and open a PR.

**Step 4: Verify the package resolves**

In a fresh Xcode project, add the package by GitHub URL and confirm it resolves and builds.
