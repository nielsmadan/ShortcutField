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

ShortcutField is a Swift package providing in-app shortcut recording for macOS apps. The design splits two concerns into distinct types:

- **`Shortcut`** — fire-once umbrella: one or more `Shortcut.Step`s. Single keystrokes, mouse clicks, gestures, and multi-step sequences all collapse into this type. The matcher fires once per full match.
- **`ContinuousShortcut`** — sensitivity-bearing single-step type for throttled continuous fire (scroll-to-zoom etc.). The `kind: ContinuousShortcut.Kind` nested enum restricts it to continuous gestures (scroll / pinch / rotate) at the type level — discrete kinds are unrepresentable.

**Source structure:**
- `Shortcut.swift` — Fire-once umbrella + nested `Shortcut.Step` (kind + modifiers). Kind covers `.key`, `.mouseButton`, `.scroll`, `.pinchIn/Out`, `.rotateClockwise/CounterClockwise`, `.smartMagnify`. Codable, Equatable, Hashable, Sendable.
- `Shortcut+Matching.swift` — `Shortcut.Step.matches(NSEvent)`, `matches(KeyPress)`, `GestureEventShape` test seam.
- `Shortcut+DisplayString.swift` — Human-readable display strings (`⌘K`, `Tab`, `Left Click`, `Scroll Up`, `⌘Pinch In`, …); `Shortcut.displayString` joins steps.
- `Shortcut+KeyMapping.swift` — UCKeyTranslate, special-key names, `NSEvent.ModifierFlags.symbolicRepresentation`.
- `ContinuousShortcut.swift` — Sensitivity-bearing single-step type. Nested `ContinuousShortcut.Kind` exposes only continuous cases (scroll / pinch / rotate). Codable, Equatable, Hashable, Sendable.
- `ShortcutRecorderView.swift` — SwiftUI recorder (NSViewRepresentable) for `Shortcut`.
- `ShortcutRecorderField.swift` — AppKit `NSSearchField` subclass for `Shortcut`. Multi-step capture with 1-second idle timeout; bare left-click anywhere (no modifiers) finalizes.
- `ContinuousShortcutRecorderView.swift` — SwiftUI recorder with sensitivity slider for `ContinuousShortcut`.
- `ContinuousShortcutRecorderField.swift` — AppKit recorder for `ContinuousShortcut`.
- `ContinuousShortcutRecorderField+Menu.swift` — chevron menu picker for continuous kinds (scroll / pinch / rotate).
- `OnShortcutModifier.swift` — `.onShortcut()` fire-once dispatcher; `ShortcutMatcher`, `ShortcutEventDispatcher`, `ShortcutTracking`.
- `OnContinuousShortcutModifier.swift` — `.onContinuousShortcut()` throttled-continuous dispatcher.
- `ThrottleState.swift` — Internal: shared throttle state for `OnContinuousShortcutModifier`.
- `GestureAccumulator.swift` — Internal: per-burst threshold detection for pinch / rotate / scroll, shared between both recorder fields.
- `SensitivitySliderRepresentable.swift` — internal slider helper used by `ContinuousShortcutRecorderView`.
- `SensitivityMode.swift` — sensitivity mode + position enums.
- `Example/` — Standalone Xcode project with workbench and gallery tabs for manual testing.

## Code Style

- SwiftLint and SwiftFormat configured
- 4-space indentation, 120 char max width
- Swift Testing framework (@Test, #expect)
- Swift 6.2 language mode (strict concurrency — all new types must be Sendable-safe)
- macOS 13+ minimum deployment target
