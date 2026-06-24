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

- **`DiscreteShortcut`** — fire-once binding: one or more `DiscreteShortcut.Step`s. Single keystrokes, mouse clicks, gestures, and multi-step sequences all collapse into this type. The matcher fires once per full match. The `Shortcut` umbrella enum (`.discrete` / `.continuous`) wraps it alongside `ContinuousShortcut` for code that handles either flavor.
- **`ContinuousShortcut`** — sensitivity-bearing single-step type for throttled continuous fire (scroll-to-zoom etc.). The `kind: ContinuousShortcut.Kind` nested enum restricts it to continuous gestures (scroll / pinch / rotate) at the type level — discrete kinds are unrepresentable.

**Source structure:**
- `Shortcut.swift` — `Shortcut` umbrella enum: `.discrete(DiscreteShortcut)` / `.continuous(ContinuousShortcut)`, with a `kind` discriminator and forwarded `displayString`. Codable, Hashable, Sendable.
- `DiscreteShortcut.swift` — Fire-once type: one or more `DiscreteShortcut.Step`s (kind + modifiers). Kind covers `.key`, `.mouseButton`, `.scroll`, `.pinchIn/Out`, `.rotateClockwise/CounterClockwise`, `.smartMagnify`. Codable, Equatable, Hashable, Sendable.
- `DiscreteShortcut+Matching.swift` — `DiscreteShortcut.Step.matches(NSEvent)`, `matches(KeyPress)`, `GestureEventShape` test seam.
- `DiscreteShortcut+DisplayString.swift` — Human-readable display strings (`⌘K`, `Tab`, `Left Click`, `Scroll Up`, `⌘Pinch In`, …); `displayString` joins steps.
- `DiscreteShortcut+KeyMapping.swift` — UCKeyTranslate, special-key names, `NSEvent.ModifierFlags.symbolicRepresentation`.
- `ContinuousShortcut.swift` — Sensitivity-bearing single-step type. Nested `ContinuousShortcut.Kind` exposes only continuous cases (scroll / pinch / rotate). Codable, Equatable, Hashable, Sendable.
- `Syntax/ShortcutASCII.swift` — ASCII text syntax: `Shortcut(ascii:)` parser and `.ascii` serialization; `ExpressibleByStringLiteral`.
- `Matching/ShortcutMatcher.swift` — Public matcher facade; dispatches to `SequenceMatcher` (discrete) or `ContinuousMatcher` (continuous).
- `Matching/SequenceMatcher.swift` — Multi-step discrete sequence matcher with per-step idle timeout.
- `Matching/ContinuousMatcher.swift` — Single continuous-shortcut matcher applying the sensitivity throttle.
- `Matching/ShortcutEventDispatcher.swift` — Shared `NSEvent` local-monitor fan-out used by `.onShortcut`.
- `Matching/ShortcutMatchResult.swift` — Matcher result enum (`.fired`, `.continuousFired`, `.advanced`, `.ignored`).
- `Matching/ShortcutTracking.swift` — Public `ShortcutTracking.isActive` flag for in-progress multi-step matches; bumped automatically by `SequenceMatcher`.
- `BaseShortcutRecorderField.swift` — Shared `NSSearchField` base for the two recorder fields (cell class, sizing, key-view eligibility, event-monitor storage, click hit-test).
- `ShortcutRecorderView.swift` — SwiftUI recorder (NSViewRepresentable) for `DiscreteShortcut`.
- `ShortcutRecorderField.swift` — AppKit `NSSearchField` subclass for `DiscreteShortcut`. Multi-step capture with 1-second idle timeout; bare left-click anywhere (no modifiers) finalizes. Also hosts the public `ShortcutRecording` namespace (`isActive` flag) plus the internal `ActiveShortcutRecorder` protocol and `ShortcutRecordingState`.
- `ContinuousShortcutRecorderView.swift` — SwiftUI recorder with sensitivity slider for `ContinuousShortcut`.
- `ContinuousShortcutRecorderField.swift` — AppKit recorder for `ContinuousShortcut`.
- `ContinuousShortcutRecorderField+Menu.swift` — chevron menu picker for continuous kinds (scroll / pinch / rotate).
- `OnShortcutModifier.swift` — `.onShortcut()` dispatcher; fires once for discrete shortcuts, throttled-continuous for continuous.
- `SuppressShortcutBeep.swift` — `.suppressShortcutBeep()` view modifier; installs a `noResponder(for:)` override gated on `ShortcutTracking.isActive`.
- `ThrottleState.swift` — Internal: shared throttle state for continuous-shortcut firing.
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
