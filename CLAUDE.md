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

ShortcutField is a Swift package providing a unified in-app shortcut recorder for macOS apps. A single `Shortcut` type covers keyboard keys, mouse buttons, scroll directions, and trackpad gestures. The package handles recording, displaying, and matching them — including special keys like Tab that SwiftUI's focus system intercepts.

**Source structure:**
- `Shortcut.swift` — Model: kind + modifiers + sensitivity. Kind covers `.key`, `.mouseButton`, `.scroll`, `.pinchIn/Out`, `.rotateClockwise/CounterClockwise`, `.smartMagnify`. Codable, Equatable, Hashable, Sendable.
- `Shortcut+Matching.swift` — matches(NSEvent), matches(KeyPress), GestureEventShape test seam
- `Shortcut+DisplayString.swift` — Human-readable display strings per kind (`⌘K`, `Tab`, `Left Click`, `Scroll Up`, `⌘Pinch In`, …)
- `Shortcut+KeyMapping.swift` — UCKeyTranslate, special-key names, NSEvent.ModifierFlags.symbolicRepresentation extension
- `ShortcutRecorderView.swift` — SwiftUI recorder (NSViewRepresentable)
- `ShortcutRecorderField.swift` — AppKit NSSearchField subclass that records all kinds
- `ShortcutRecorderField+Menu.swift` — chevron menu picker (lists non-keyboard kinds)
- `ShortcutRecorderStyle.swift` — .rounded, .plain, .borderless styles
- `OnShortcutModifier.swift` — .onShortcut() view modifier (covers all kinds, throttles continuous ones)
- `ShortcutSequence.swift` — Sequential shortcut composed of `[Shortcut]` of any kind (keys, mouse, scroll, gestures)
- `ShortcutSequenceRecorderField.swift`, `ShortcutSequenceRecorderView.swift`, `OnShortcutSequenceModifier.swift` — sequence pipeline
- `ThrottleState.swift` — Internal: shared throttle state for OnShortcutModifier
- `SensitivitySliderRepresentable.swift` — internal slider helper used by ShortcutRecorderView for continuous kinds
- `SensitivityMode.swift` — sensitivity mode + position enums
- `Example/` — Standalone Xcode project with workbench and gallery tabs for manual testing

## Code Style

- SwiftLint and SwiftFormat configured
- 4-space indentation, 120 char max width
- Swift Testing framework (@Test, #expect)
- Swift 6.2 language mode (strict concurrency — all new types must be Sendable-safe)
- macOS 13+ minimum deployment target
