# CLAUDE.md

## Build & Run

```bash
just build    # Build the package
just test     # Run tests
just lint     # Run SwiftLint
just format   # Run SwiftFormat
just lint-fix  # Auto-fix SwiftLint violations
just example   # Build & run the example app
just clean     # Remove build directory
just tag-release-patch  # Tag and push a patch release
just tag-release-minor  # Tag and push a minor release
```

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
- `Example/` — Standalone Xcode project with workbench and gallery tabs for manual testing

## Code Style

- SwiftLint and SwiftFormat configured
- 4-space indentation, 120 char max width
- Swift Testing framework (@Test, #expect)
- Swift 6.2 language mode (strict concurrency — all new types must be Sendable-safe)
- macOS 13+ minimum deployment target
