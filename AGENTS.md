# Repository Guidelines

This is the single source of truth for agent instructions in this repository. `CLAUDE.md` imports this file.

## Project Structure & Module Organization

`ShortcutField` is a Swift Package for macOS providing in-app shortcut recording. Library sources live in `Sources/ShortcutField/`; keep public API types small and focused, with related behavior split into extension files such as `DiscreteShortcut+Matching.swift` and `DiscreteShortcut+KeyMapping.swift`. Tests live in `Tests/ShortcutFieldTests/` and mirror the library surface with focused suites like `ShortcutTests.swift` and `ContinuousShortcutTests.swift`. The manual demo app is in `Example/ShortcutFieldExample/`. Architecture and current API are documented in `README.md` and this file.

## Build, Test, and Development Commands

Use `just` for the common workflow:

```bash
just build    # Build the package (swift build, warnings as errors)
just test     # Run tests (swift test)
just lint     # Run SwiftLint (--strict)
just format   # Run SwiftFormat
just docs     # Build DocC docs, fail on any diagnostic (unresolved links, etc.)
just lint-fix  # Auto-fix SwiftLint violations
just example   # Build & run the example app from Example/
just clean     # Remove build directory
just tag-release-patch ["Tag message"]  # Tag and push a patch release
just tag-release-minor ["Tag message"]  # Tag and push a minor release
just tag-release-major ["Tag message"]  # Tag and push a major release
```

Run `just lint-fix` before submitting when SwiftLint can auto-correct issues.

## Architecture

ShortcutField splits two concerns into distinct types:

- **`DiscreteShortcut`** — fire-once binding: one or more `DiscreteShortcut.Step`s. Single keystrokes, mouse clicks, gestures, and multi-step sequences all collapse into this type. The matcher fires once per full match. The `Shortcut` umbrella enum (`.discrete` / `.continuous`) wraps it alongside `ContinuousShortcut` for code that handles either flavor.
- **`ContinuousShortcut`** — sensitivity-bearing single-step type for throttled continuous fire (scroll-to-zoom etc.). The `kind: ContinuousShortcut.Kind` nested enum restricts it to continuous gestures (scroll / pinch / rotate) at the type level — discrete kinds are unrepresentable.

**Source structure:**
- `Shortcut.swift` — `Shortcut` umbrella enum: `.discrete(DiscreteShortcut)` / `.continuous(ContinuousShortcut)`, with a `kind` discriminator and forwarded `displayString`. Codable, Hashable, Sendable.
- `DiscreteShortcut.swift` — Fire-once type: one or more `DiscreteShortcut.Step`s (kind + modifiers). Kind covers `.key`, `.mouseButton`, `.scroll`, `.pinchIn/Out`, `.rotateClockwise/CounterClockwise`, `.smartMagnify`. Codable, Equatable, Hashable, Sendable.
- `DiscreteShortcut+Matching.swift` — `DiscreteShortcut.Step.matches(NSEvent)`, `matches(KeyPress)`, `GestureEventShape` test seam.
- `DiscreteShortcut+DisplayString.swift` — Human-readable display strings (`⌘K`, `Tab`, `Left Click`, `Scroll Up`, `⌘Pinch In`, …); `displayString` joins steps.
- `DiscreteShortcut+KeyMapping.swift` — UCKeyTranslate, special-key names, `NSEvent.ModifierFlags.symbolicRepresentation`.
- `DiscreteShortcut+Symbol.swift` — SF Symbol name mapping for `DiscreteShortcut.Kind` (gesture/scroll icons; `nil` for keys and mouse buttons).
- `ContinuousShortcut.swift` — Sensitivity-bearing single-step type. Nested `ContinuousShortcut.Kind` exposes only continuous cases (scroll / pinch / rotate). Codable, Equatable, Hashable, Sendable.
- `Syntax/ShortcutASCII.swift` — ASCII text syntax: `Shortcut(ascii:)` parser and `.ascii` serialization; `ExpressibleByStringLiteral`.
- `Matching/ShortcutMatcher.swift` — Public matcher facade; dispatches to `SequenceMatcher` (discrete) or `ContinuousMatcher` (continuous).
- `Matching/SequenceMatcher.swift` — Multi-step discrete sequence matcher with per-step idle timeout.
- `Matching/ContinuousMatcher.swift` — Single continuous-shortcut matcher applying the sensitivity throttle.
- `Matching/ShortcutEventDispatcher.swift` — Shared `NSEvent` local-monitor fan-out used by `.onShortcut`.
- `Matching/ShortcutMatchResult.swift` — Matcher result enum (`.fired`, `.continuousFired`, `.advanced`, `.ignored`).
- `Matching/TextInputFocus.swift` — Internal: focused-responder check behind the text-input gate; `responderOverride` test seam.
- `Matching/ShortcutTracking.swift` — Public `ShortcutTracking.isActive` flag for in-progress multi-step matches; bumped automatically by `SequenceMatcher`.
- `BaseShortcutRecorderField.swift` — Shared `NSSearchField` base for the two recorder fields (cell class, sizing, key-view eligibility, event-monitor storage, click hit-test).
- `ShortcutRecorderView.swift` — SwiftUI recorder (NSViewRepresentable) for `DiscreteShortcut`.
- `ShortcutRecorderField.swift` — AppKit `NSSearchField` subclass for `DiscreteShortcut`. Multi-step capture with 1-second idle timeout; bare left-click anywhere (no modifiers) finalizes. Also hosts the public `ShortcutRecording` namespace (`isActive` flag) plus the internal `ActiveShortcutRecorder` protocol and `ShortcutRecordingState`.
- `ContinuousShortcutRecorderView.swift` — SwiftUI recorder with sensitivity slider for `ContinuousShortcut`.
- `ContinuousShortcutRecorderField.swift` — AppKit recorder for `ContinuousShortcut`.
- `ContinuousShortcutRecorderField+Menu.swift` — chevron menu picker for continuous kinds (scroll / pinch / rotate).
- `ShortcutLabel.swift` — Compact, read-only SwiftUI label for a shortcut (icons + hover tooltips, or verbose text); ideal for a shortcut legend.
- `ShortcutLabelStyle.swift` — `.text` / `.compact` render style enum for display labels.
- `OnShortcutModifier.swift` — `.onShortcut()` dispatcher; fires once for discrete shortcuts, throttled-continuous for continuous.
- `SuppressShortcutBeep.swift` — `.suppressShortcutBeep()` view modifier and `ShortcutTracking.installBeepSuppression()` (view-free equivalent); installs a `noResponder(for:)` override gated on `ShortcutTracking.isActive`.
- `ThrottleState.swift` — Internal: shared throttle state for continuous-shortcut firing.
- `GestureAccumulator.swift` — Internal: per-burst threshold detection for pinch / rotate / scroll, shared between both recorder fields.
- `SensitivitySliderRepresentable.swift` — internal slider helper used by `ContinuousShortcutRecorderView`.
- `SensitivityMode.swift` — sensitivity mode + position enums.
- `ShortcutField.docc/` — DocC catalog (`just docs`).
- `Example/` — Standalone Xcode project with workbench and gallery tabs for manual testing.

## Coding Style & Naming Conventions

This package targets Swift 6.2 (strict concurrency — all new types must be `Sendable`-safe) and macOS 13+. Follow the existing style: 4-space indentation and 120-character line width, enforced by SwiftLint and SwiftFormat. Use UpperCamelCase for types (`ShortcutRecorderView`), lowerCamelCase for properties and methods (`displayString`), and keep file names aligned with the primary type or extension they contain.

## Comments & Documentation

Write a comment only when a reader of the code cannot recover the information from it. Names and signatures are the documentation; a comment that restates them is noise.

**`///` vs `//`.** Use `///` when the information belongs to callers, `//` when it belongs to whoever edits the body. `///` feeds Xcode Quick Help and autocomplete at *every* access level, so an internal helper with a real precondition, a nil-return rule, or a unit still deserves one — the payoff is the editor, not the docs site. DocC publishes only `public`/`open` symbols, so an internal `///` never renders anywhere.

**The test is the caller, not the access level.** Ask whether someone calling this needs the information at the call site. If yes, `///` it regardless of access level. If no, delete it regardless of how public the symbol is. Things that pass: units and ranges (`|magnification|` vs. degrees vs. scroll units, per-event vs. cumulative), preconditions ("the ` @N` suffix must already be stripped"), nil semantics, framework traps (attributed strings ignore the control's `alignment`), and hazards (`event.phase` throws on key events). Things that fail: any sentence recoverable from the signature.

**Access level is easy to misjudge.** Members of a `public extension` are public by default; members of a `public class` or `struct` are *internal* by default. When it matters, check the built symbol graph under `.build/docc` rather than reading the modifier.

**Duplication.** One authoritative explanation per constraint, nearest the code that depends on it. Repeat it only where each site is independently hazardous. The exception is published DocC pages: those are read in isolation, so a public symbol should carry its own explanation even if a sibling page states the same thing.

**Never comment on what is not there** — no notes about removed code, rejected alternatives, or deliberate absences; that belongs in the commit message. Never invent a rationale you cannot verify: if a constant's origin is unknown, document its observable effect and leave the origin alone. Keep `TODO`/`FIXME` tied to a concrete action plus a blocker or issue reference, and preserve functional directives (`swiftlint:disable`) and legal headers.

When a symbol seems to need a comment to be understandable, first check whether it should exist. An identity function or a misleading name is better deleted or renamed than explained.

## Testing Guidelines

Tests use the Swift Testing framework, not XCTest. Prefer `@Test` and `#expect` and keep one responsibility per test file or suite. Name tests after observable behavior, for example `DiscreteShortcutMatchingTests.swift` or `ShortcutRecorderFieldTests.swift`. Run `just test` locally before opening a PR; add or update tests for every public API or matching/recording behavior change.

## Commit & Pull Request Guidelines

Recent history uses short conventional prefixes — only `feat:`, `fix:`, and `chore:`. Keep commit subjects imperative and scoped, for example `fix: handle tab matching in recorder`. Pull requests should include a clear summary, linked issue or plan when relevant, and screenshots or screen recordings for UI changes in `Example/`. Mention any lint, format, or test commands you ran.

## Agent Notes

Do not overwrite unrelated user changes in the working tree. Prefer minimal, targeted edits and update docs or the example app when public behavior changes.
