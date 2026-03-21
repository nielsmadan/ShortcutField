# ShortcutField Library Design

A SwiftUI/AppKit keyboard shortcut recorder component for macOS. Records in-app (local) keyboard shortcuts, displays them, and matches them against key events — including special keys like Tab that SwiftUI's focus system normally intercepts.

## Background

Extracted from [Juggler](https://github.com/nielsmadan/juggler), where the component handles configurable in-app hotkeys. The recorder, matching logic, and special-key handling are non-trivial (~440 lines) and reusable across any macOS app with configurable keyboard shortcuts.

**Key differentiator:** KeyboardShortcuts (sindresorhus) handles *global* system hotkeys and explicitly refuses to record Tab. ShortcutField handles *local/in-app* shortcuts where Tab and other special keys are valid, with matching support for both NSEvent and SwiftUI KeyPress.

## Scope

**In scope:**
- Shortcut model (keyCode + modifiers, Codable, display strings)
- Recorder UI component (SwiftUI primary, AppKit also public)
- Shortcut matching (NSEvent and SwiftUI KeyPress)
- `.onShortcut()` view modifier
- Customizable appearance (styles, control sizes)
- UCKeyTranslate keyboard layout support
- Example app
- Documentation, tests, CI, Justfile

**Out of scope:**
- Persistence (no UserDefaults, no @AppStorage — consumers handle storage)
- Global/system-wide hotkeys (that's KeyboardShortcuts' domain)
- Notifications or app-specific callbacks
- Juggler migration (separate follow-up effort)

## Public API

### Model

```swift
public struct Shortcut: Codable, Equatable, Sendable {
    public let keyCode: UInt16
    public let modifiers: NSEvent.ModifierFlags

    public init(keyCode: UInt16, modifiers: NSEvent.ModifierFlags)

    /// e.g. "⌘⇧K", "⌃Tab"
    public var displayString: String

    /// Match against a raw NSEvent (for keys like Tab that SwiftUI intercepts)
    public func matches(_ event: NSEvent) -> Bool

    /// Match against a SwiftUI KeyPress
    public func matches(_ press: KeyPress) -> Bool
}
```

### Recorder View (SwiftUI)

```swift
ShortcutRecorderView($shortcut)
    .placeholder("Record Shortcut")
    .style(.rounded)          // .rounded (default), .plain, .borderless
    .controlSize(.regular)    // also respects SwiftUI .controlSize environment
```

### Recorder Field (AppKit)

```swift
let field = ShortcutRecorderField()  // NSSearchField subclass, also public
field.shortcut = someShortcut
field.onShortcutChange = { shortcut in ... }
```

### Matching Modifier

```swift
MyView()
    .onShortcut(shortcut) {
        print("Shortcut fired!")
    }
```

Internally installs both an NSEvent local monitor (for special keys like Tab) and a SwiftUI KeyPress handler. Consumer never deals with the dual-path complexity.

### Styles

```swift
public enum ShortcutRecorderStyle {
    case rounded     // Default, matches NSSearchField appearance
    case plain       // Minimal border
    case borderless  // No border, just text
}
```

## File Structure

```
ShortcutField/
├── Package.swift                          # macOS 13+, swift-tools-version 6.2
├── README.md
├── LICENSE                                # MIT
├── CLAUDE.md
├── Justfile
├── .spi.yml
├── .swiftlint.yml
├── .swiftformat
├── .gitignore
├── .github/workflows/
│   └── ci.yml
│
├── Sources/ShortcutField/
│   ├── Shortcut.swift                     # Model: keyCode, modifiers, init, Codable
│   ├── Shortcut+Matching.swift            # matches(NSEvent), matches(KeyPress)
│   ├── Shortcut+KeyMapping.swift          # UCKeyTranslate, special keys, displayString
│   ├── ShortcutRecorderView.swift         # SwiftUI view (NSViewRepresentable)
│   ├── ShortcutRecorderField.swift        # NSSearchField subclass
│   ├── ShortcutRecorderStyle.swift        # Style enum and application
│   └── OnShortcutModifier.swift           # .onShortcut() view modifier
│
├── Tests/ShortcutFieldTests/
│   ├── ShortcutTests.swift                # Model: init, equality, codable, sendable
│   ├── ShortcutMatchingTests.swift        # Matching logic, special keys, modifiers
│   ├── ShortcutKeyMappingTests.swift      # UCKeyTranslate, display strings
│   └── ShortcutRecorderFieldTests.swift   # NSView headless: set/clear, frame size
│
└── Example/
    └── ShortcutFieldExample/              # Standalone Xcode project (created in Xcode)
        ├── ShortcutFieldExample.xcodeproj
        └── ShortcutFieldExample/
            ├── ShortcutFieldExampleApp.swift
            └── ContentView.swift
```

## Example App

Single-window app with four sections:

1. **Basic recorder** — record, display, clear a shortcut
2. **Multiple recorders** — two side-by-side ("Next" / "Previous") to show no conflicts
3. **Live matching** — text area where pressing shortcuts highlights/fires them (demonstrates `.onShortcut`)
4. **Style variations** — same recorder in `.rounded`, `.plain`, `.borderless` at different control sizes

## Package.swift

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

## Tooling

### Justfile

| Command | Action |
|---------|--------|
| `just build` | `swift build` |
| `just test` | `swift test` |
| `just lint` | `swiftlint` |
| `just format` | `swiftformat .` |
| `just clean` | `rm -rf .build` |
| `just tag-release-patch` | Bump patch, tag, push |
| `just tag-release-minor` | Bump minor, tag, push |
| `just tag-release-major` | Bump major, tag, push |

### CI (`.github/workflows/ci.yml`)

Two jobs on `macos-26`:
- **build-and-test**: `swift build` + `swift test`
- **lint**: SwiftLint

### SwiftLint / SwiftFormat

Same configs as Juggler, carried over directly.

### Swift Package Index

`.spi.yml`:
```yaml
version: 1
builder:
  configs:
    - documentation_targets: ['ShortcutField']
```

## Extraction Notes

Code extracted from Juggler's `LocalShortcut.swift` and `LocalShortcutRecorderView.swift` with these changes:

- `LocalShortcut` renamed to `Shortcut`
- Remove `save(to:)`, `load(from:)`, `remove(from:)` (persistence is consumer's concern)
- Remove `Notification.Name.localShortcutsDidChange`
- Remove `storageKey` from the recorder view
- Add `ShortcutRecorderStyle` enum and modifier-based customization
- Add `.onShortcut()` view modifier (new code)
- `NSEvent.ModifierFlags.symbolicRepresentation` stays (useful utility, make public)
- `Shortcut.specialKeyString(keyCode:)` and `Shortcut.keyToCharacter(keyCode:)` stay as public static methods

## Publishing Checklist

1. All tests pass (`just test`)
2. Lint clean (`just lint`)
3. README complete with usage examples
4. DocC comments on all public API
5. Example app builds and demonstrates all features
6. `git tag 1.0.0 && git push origin main 1.0.0`
7. Create GitHub Release with changelog
8. Submit PR to [SwiftPackageIndex/PackageList](https://github.com/SwiftPackageIndex/PackageList)
