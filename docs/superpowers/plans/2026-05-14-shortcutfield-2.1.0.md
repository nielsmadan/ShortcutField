# ShortcutField 2.1.0 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement the ShortcutField 2.1.0 breaking redesign — rename the fire-once `Shortcut` struct to `DiscreteShortcut`, introduce a unified umbrella `Shortcut` enum, add a public `ShortcutMatcher` + `ShortcutEventDispatcher`, unify `.onShortcut`, backport to macOS 13, and add a VS Code-style text syntax.

**Architecture:** The fire-once struct becomes `DiscreteShortcut`; a new `Shortcut` enum (`.discrete(DiscreteShortcut)` / `.continuous(ContinuousShortcut)`) is the umbrella. Matching is consolidated behind a public `ShortcutMatcher` that delegates to internal `SequenceMatcher` (discrete) and `ContinuousMatcher` (continuous). `.onShortcut` takes the umbrella; `.onContinuousShortcut` is removed. New code is written macOS 13+ (no `@available(macOS 14)`).

**Tech Stack:** Swift 6.2, macOS 13+, SwiftPM, Swift Testing (`@Test`/`#expect`), AppKit, Carbon.HIToolbox. Build/test via `just build` / `just test` / `just lint`.

**Spec:** `docs/superpowers/specs/2026-05-14-shortcutfield-2.1.0-design.md`. Section references below (e.g. "spec §4") point there.

**Working directory:** all paths are relative to the ShortcutField repo root: `/Users/nielsmadan/wrksp/juggler/ShortcutField/`.

**Note on commit style:** the existing repo uses Conventional Commits (`feat:`, `chore:`, `fix:`). lefthook pre-commit runs swiftformat + swiftlint --strict on staged Swift files; pre-push runs build + test. Each task ends in a commit that must pass those hooks.

---

## File Structure (end state)

```
Sources/ShortcutField/
  DiscreteShortcut.swift               ← renamed from Shortcut.swift (Task 1)
  DiscreteShortcut+Matching.swift      ← renamed from Shortcut+Matching.swift (Task 1)
  DiscreteShortcut+DisplayString.swift ← renamed from Shortcut+DisplayString.swift (Task 1)
  DiscreteShortcut+KeyMapping.swift    ← renamed from Shortcut+KeyMapping.swift (Task 1)
  ContinuousShortcut.swift             ← references updated (Task 1)
  Shortcut.swift                       ← NEW: umbrella enum (Task 2)
  Matching/
    SequenceMatcher.swift              ← extracted + renamed from internal ShortcutMatcher (Task 3)
    ContinuousMatcher.swift            ← NEW: extracted from OnContinuousShortcutModifier (Task 4)
    ShortcutMatcher.swift              ← NEW: public unified matcher + ShortcutMatchResult (Task 5)
    ShortcutEventDispatcher.swift      ← extracted + made public (Task 6)
  ThrottleState.swift                  ← unchanged
  GestureAccumulator.swift             ← references updated (Task 1)
  OnShortcutModifier.swift             ← reimplemented, unified .onShortcut, macOS 13 (Task 7)
  Syntax/
    ShortcutASCII.swift                ← NEW: ascii / init(ascii:) / ExpressibleByStringLiteral / ShortcutParsingError (Task 8)
  ShortcutRecorderView.swift           ← references updated (Task 1)
  ShortcutRecorderField.swift          ← references updated (Task 1)
  ContinuousShortcutRecorderView.swift ← unchanged
  ContinuousShortcutRecorderField.swift          ← references updated (Task 1)
  ContinuousShortcutRecorderField+Menu.swift     ← references updated (Task 1)
  SensitivityMode.swift                ← unchanged
  SensitivitySliderRepresentable.swift ← unchanged
  (OnContinuousShortcutModifier.swift  ← DELETED in Task 7)

Tests/ShortcutFieldTests/
  DiscreteShortcutTests.swift          ← renamed from ShortcutTests.swift (Task 1)
  DiscreteShortcutMatchingTests.swift  ← renamed from ShortcutMatchingTests.swift (Task 1)
  DiscreteShortcutDisplayStringTests.swift ← renamed from ShortcutDisplayStringTests.swift (Task 1)
  DiscreteShortcutKeyMappingTests.swift    ← renamed from ShortcutKeyMappingTests.swift (Task 1)
  ContinuousShortcutTests.swift        ← references updated (Task 1)
  GestureAccumulatorTests.swift        ← references updated (Task 1)
  ShortcutRecorderFieldTests.swift     ← references updated (Task 1)
  ContinuousShortcutRecorderFieldTests.swift ← unchanged
  ShortcutTests.swift                  ← NEW: umbrella enum tests (Task 2)
  Matching/
    SequenceMatcherTests.swift         ← NEW (Task 3) — only if internal matcher wasn't directly tested before
    ContinuousMatcherTests.swift       ← NEW (Task 4)
    ShortcutMatcherTests.swift         ← NEW (Task 5)
  ShortcutASCIITests.swift             ← NEW (Task 8)
```

---

## Task 1: Rename `Shortcut` struct → `DiscreteShortcut`

**Goal:** Pure mechanical rename. The fire-once struct `Shortcut` (and all its nested types and static members) becomes `DiscreteShortcut`. After this task the package builds and every existing test passes — **zero behavior change**. The name `Shortcut` is left unused (Task 2 reclaims it).

This task is not TDD-shaped — it's a rename. Its "test" is: the existing suite stays green.

**Files:**
- Rename: `Sources/ShortcutField/Shortcut.swift` → `DiscreteShortcut.swift`
- Rename: `Sources/ShortcutField/Shortcut+Matching.swift` → `DiscreteShortcut+Matching.swift`
- Rename: `Sources/ShortcutField/Shortcut+DisplayString.swift` → `DiscreteShortcut+DisplayString.swift`
- Rename: `Sources/ShortcutField/Shortcut+KeyMapping.swift` → `DiscreteShortcut+KeyMapping.swift`
- Rename: `Tests/ShortcutFieldTests/ShortcutTests.swift` → `DiscreteShortcutTests.swift`
- Rename: `Tests/ShortcutFieldTests/ShortcutMatchingTests.swift` → `DiscreteShortcutMatchingTests.swift`
- Rename: `Tests/ShortcutFieldTests/ShortcutDisplayStringTests.swift` → `DiscreteShortcutDisplayStringTests.swift`
- Rename: `Tests/ShortcutFieldTests/ShortcutKeyMappingTests.swift` → `DiscreteShortcutKeyMappingTests.swift`
- Modify (references only): `ContinuousShortcut.swift`, `OnShortcutModifier.swift`, `OnContinuousShortcutModifier.swift`, `GestureAccumulator.swift`, `ShortcutRecorderView.swift`, `ShortcutRecorderField.swift`, `ContinuousShortcutRecorderField.swift`, `ContinuousShortcutRecorderField+Menu.swift`, `Tests/ShortcutFieldTests/ContinuousShortcutTests.swift`, `Tests/ShortcutFieldTests/GestureAccumulatorTests.swift`, `Tests/ShortcutFieldTests/ShortcutRecorderFieldTests.swift`

- [ ] **Step 1: `git mv` the source and test files**

```bash
cd /Users/nielsmadan/wrksp/juggler/ShortcutField
git mv Sources/ShortcutField/Shortcut.swift Sources/ShortcutField/DiscreteShortcut.swift
git mv Sources/ShortcutField/Shortcut+Matching.swift Sources/ShortcutField/DiscreteShortcut+Matching.swift
git mv Sources/ShortcutField/Shortcut+DisplayString.swift Sources/ShortcutField/DiscreteShortcut+DisplayString.swift
git mv Sources/ShortcutField/Shortcut+KeyMapping.swift Sources/ShortcutField/DiscreteShortcut+KeyMapping.swift
git mv Tests/ShortcutFieldTests/ShortcutTests.swift Tests/ShortcutFieldTests/DiscreteShortcutTests.swift
git mv Tests/ShortcutFieldTests/ShortcutMatchingTests.swift Tests/ShortcutFieldTests/DiscreteShortcutMatchingTests.swift
git mv Tests/ShortcutFieldTests/ShortcutDisplayStringTests.swift Tests/ShortcutFieldTests/DiscreteShortcutDisplayStringTests.swift
git mv Tests/ShortcutFieldTests/ShortcutKeyMappingTests.swift Tests/ShortcutFieldTests/DiscreteShortcutKeyMappingTests.swift
```

- [ ] **Step 2: Replace the `Shortcut` identifier with `DiscreteShortcut` across all source and test files**

The rename target is the **standalone capitalized word `Shortcut`** only. Use a word-boundary, case-sensitive replacement so compound identifiers are NOT touched: `ShortcutField`, `ShortcutRecorderView`, `ShortcutRecorderField`, `ShortcutRecording`, `ShortcutRecordingState`, `ShortcutEventDispatcher`, `ShortcutEventResult`, `ShortcutMatcher`, `ShortcutTracking`, `OnShortcutModifier`, `OnContinuousShortcutModifier`, `ContinuousShortcut` (and its nested types), `onShortcut`, `onShortcutChange` — these must all remain unchanged. The regex `\bShortcut\b` already excludes every one of them (no word boundary exists between `Shortcut` and an adjacent word character, and `ContinuousShortcut` has no boundary before `Shortcut`).

Run, from the repo root:
```bash
for f in Sources/ShortcutField/*.swift Tests/ShortcutFieldTests/*.swift; do
  perl -i -pe 's/\bShortcut\b/DiscreteShortcut/g' "$f"
done
```

This renames the struct `Shortcut` → `DiscreteShortcut` and, because every nested reference is written `Shortcut.Step` / `Shortcut.Kind` / `Shortcut.ScrollDirection` / `Shortcut.canonicalModifiers` / `Shortcut.magnifyEventThreshold` / etc., those all become `DiscreteShortcut.*` automatically. Doc comments mentioning the capitalized type name are renamed too, which is correct.

- [ ] **Step 3: Rename the one compound identifier the regex misses**

`ContinuousShortcut.Kind` has a property `asShortcutKind` (it lifts a continuous kind to the umbrella kind type) and a failable initializer `init?(_ shortcutKind: Shortcut.Kind)`. The `\bShortcut\b` regex did NOT rename `asShortcutKind` (no word boundary inside the identifier), but it *did* rename the return type and the `Shortcut.Kind` parameter type to `DiscreteShortcut.Kind`. So after Step 2, `asShortcutKind` returns `DiscreteShortcut.Kind` — a now-misleading name.

In `Sources/ShortcutField/ContinuousShortcut.swift`, rename:
- the property `asShortcutKind` → `asDiscreteKind`
- the initializer parameter label `shortcutKind` → `discreteKind` (in `init?(_ discreteKind: DiscreteShortcut.Kind)`)

Then update the one call site of `asShortcutKind` — `ContinuousShortcut.matches(_:)` in the same file uses `kind.asShortcutKind` — and `ContinuousShortcut.displayString` likewise. Grep to be sure:
```bash
grep -rn "asShortcutKind|shortcutKind" Sources/ Tests/
```
Update every hit. (As of the pre-2.1.0 source the only references are inside `ContinuousShortcut.swift`.)

- [ ] **Step 4: Review the diff for false positives**

Run:
```bash
git diff
```
Expected: every change is `Shortcut` → `DiscreteShortcut` on the standalone word, plus the `asShortcutKind` → `asDiscreteKind` rename from Step 3. Confirm none of the protected compound identifiers (listed in Step 2) were altered. If a doc comment used "Shortcut" to mean the general *concept* rather than the type, renaming it to "DiscreteShortcut" is acceptable and not worth reverting — the file is now about `DiscreteShortcut`.

- [ ] **Step 5: Verify the build succeeds**

Run:
```bash
just build
```
Expected: `Build complete!` with no errors. If there are errors, they will be unresolved references — most likely a spot where `Shortcut` was used without the word boundary the regex expects (e.g. inside a string literal). Fix each by hand.

- [ ] **Step 6: Verify all existing tests pass**

Run:
```bash
just test
```
Expected: the full pre-existing suite passes — same test count as before this task, all green. This is the proof the rename was behavior-preserving.

- [ ] **Step 7: Verify lint is clean**

Run:
```bash
just lint
```
Expected: `Done linting! Found 0 violations`.

- [ ] **Step 8: Commit**

```bash
git add -A
git commit -m "refactor: rename Shortcut struct to DiscreteShortcut"
```

---

## Task 2: The umbrella `Shortcut` enum

**Goal:** Introduce the new `Shortcut` enum — the unified "any shortcut" type, `.discrete(DiscreteShortcut)` / `.continuous(ContinuousShortcut)` — with a nested `Kind`, `Codable`, `Hashable`, `Sendable`, and a `displayString` that forwards to the inner value. (Spec §2.)

**Files:**
- Create: `Sources/ShortcutField/Shortcut.swift`
- Create: `Tests/ShortcutFieldTests/ShortcutTests.swift`

- [ ] **Step 1: Write the failing test**

Create `Tests/ShortcutFieldTests/ShortcutTests.swift`:
```swift
import AppKit
import Carbon.HIToolbox
import Testing
@testable import ShortcutField

@Suite("Shortcut umbrella enum")
struct ShortcutTests {
    private var sampleDiscrete: DiscreteShortcut {
        DiscreteShortcut(keyCode: UInt16(kVK_ANSI_S), modifiers: .command)
    }
    private var sampleContinuous: ContinuousShortcut {
        ContinuousShortcut(kind: .pinchOut, modifiers: .command, sensitivity: 0.5)
    }

    @Test("kind reflects the case")
    func kind() {
        #expect(Shortcut.discrete(sampleDiscrete).kind == .discrete)
        #expect(Shortcut.continuous(sampleContinuous).kind == .continuous)
    }

    @Test("displayString forwards to the inner value")
    func displayString() {
        #expect(Shortcut.discrete(sampleDiscrete).displayString == sampleDiscrete.displayString)
        #expect(Shortcut.continuous(sampleContinuous).displayString == sampleContinuous.displayString)
    }

    @Test("Codable round-trips both cases")
    func codableRoundTrip() throws {
        for shortcut in [Shortcut.discrete(sampleDiscrete), .continuous(sampleContinuous)] {
            let data = try JSONEncoder().encode(shortcut)
            let decoded = try JSONDecoder().decode(Shortcut.self, from: data)
            #expect(decoded == shortcut)
        }
    }

    @Test("Hashable distinguishes the cases")
    func hashable() {
        let a = Shortcut.discrete(sampleDiscrete)
        let b = Shortcut.continuous(sampleContinuous)
        #expect(a != b)
        #expect(Set([a, b, a]).count == 2)
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run:
```bash
just test 2>&1 | tail -20
```
Expected: compilation failure — `cannot find 'Shortcut' in scope` (the enum doesn't exist yet).

- [ ] **Step 3: Implement the `Shortcut` enum**

Create `Sources/ShortcutField/Shortcut.swift`:
```swift
import Foundation

/// Any shortcut binding — fire-once (`DiscreteShortcut`) or sensitivity-bearing
/// continuous (`ContinuousShortcut`).
///
/// `Shortcut` is the umbrella type for code that handles both flavors. The two
/// concrete types remain available directly: use `DiscreteShortcut` /
/// `ContinuousShortcut` when the kind is fixed, `Shortcut` when it varies.
public enum Shortcut: Sendable, Hashable {
    case discrete(DiscreteShortcut)
    case continuous(ContinuousShortcut)

    /// Discriminator for the two cases.
    public enum Kind: Sendable, Hashable {
        case discrete
        case continuous
    }

    /// Which case this value is.
    public var kind: Kind {
        switch self {
        case .discrete: .discrete
        case .continuous: .continuous
        }
    }

    /// Human-readable representation, forwarded to the inner value.
    public var displayString: String {
        switch self {
        case let .discrete(shortcut): shortcut.displayString
        case let .continuous(shortcut): shortcut.displayString
        }
    }
}

// MARK: - Codable

extension Shortcut: Codable {
    private enum CodingKeys: String, CodingKey {
        case kind
        case discrete
        case continuous
    }

    private enum KindTag: String, Codable {
        case discrete
        case continuous
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let tag = try container.decode(KindTag.self, forKey: .kind)
        switch tag {
        case .discrete:
            self = try .discrete(container.decode(DiscreteShortcut.self, forKey: .discrete))
        case .continuous:
            self = try .continuous(container.decode(ContinuousShortcut.self, forKey: .continuous))
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .discrete(shortcut):
            try container.encode(KindTag.discrete, forKey: .kind)
            try container.encode(shortcut, forKey: .discrete)
        case let .continuous(shortcut):
            try container.encode(KindTag.continuous, forKey: .kind)
            try container.encode(shortcut, forKey: .continuous)
        }
    }
}
```

Note: the `Codable` format is a discriminated wrapper — `{ "kind": "discrete", "discrete": { ...DiscreteShortcut... } }`. It reuses `DiscreteShortcut`'s and `ContinuousShortcut`'s existing `Codable` conformances unchanged.

- [ ] **Step 4: Run the test to verify it passes**

Run:
```bash
just test 2>&1 | tail -20
```
Expected: the four `ShortcutTests` tests pass; the rest of the suite still passes.

- [ ] **Step 5: Verify build + lint**

Run:
```bash
just build && just lint
```
Expected: `Build complete!` and `0 violations`.

- [ ] **Step 6: Commit**

```bash
git add Sources/ShortcutField/Shortcut.swift Tests/ShortcutFieldTests/ShortcutTests.swift
git commit -m "feat: add umbrella Shortcut enum"
```

---

## Task 3: Extract and rename the internal matcher → `SequenceMatcher`

**Goal:** The internal `ShortcutMatcher` class (the multi-step state machine) currently lives inside `OnShortcutModifier.swift` and is gated `@available(macOS 14.0, *)`. Move it to its own file `Matching/SequenceMatcher.swift`, rename it `SequenceMatcher`, drop the macOS-14 gate, and change its result type from the internal `ShortcutEventResult` to the new public `ShortcutMatchResult` (defined in Task 5 — but its case names are introduced here so Task 3 can compile standalone).

To keep Task 3 self-contained, `ShortcutMatchResult` is defined in this task (in `SequenceMatcher.swift` temporarily is wrong — instead define it in its own small file now, and Task 5 adds `ShortcutMatcher` alongside it). **Define `ShortcutMatchResult` in `Matching/ShortcutMatchResult.swift` as the first step of this task.**

**Files:**
- Create: `Sources/ShortcutField/Matching/ShortcutMatchResult.swift`
- Create: `Sources/ShortcutField/Matching/SequenceMatcher.swift` (moved from `OnShortcutModifier.swift`)
- Modify: `Sources/ShortcutField/OnShortcutModifier.swift` (remove the `ShortcutMatcher` class + `ShortcutEventResult` enum; they move out)
- Create: `Tests/ShortcutFieldTests/Matching/SequenceMatcherTests.swift`

- [ ] **Step 1: Create `ShortcutMatchResult`**

Create `Sources/ShortcutField/Matching/ShortcutMatchResult.swift`:
```swift
import Foundation

/// The outcome of feeding one `NSEvent` to a `ShortcutMatcher`.
public enum ShortcutMatchResult: Sendable, Equatable {
    /// The event did not match.
    case ignored
    /// A discrete multi-step shortcut advanced past an intermediate step.
    /// `consumeEvent` is `true` for focus-intercepted keys (Tab, Escape) so the
    /// event does not also drive focus.
    case advanced(consumeEvent: Bool)
    /// A discrete shortcut completed on this event.
    case fired
    /// A continuous shortcut produced a throttled fire. `magnitude` is this
    /// event's signed delta (scroll `scrollingDeltaY`/`X`, magnify
    /// `magnification`, rotate `rotation` in degrees).
    case continuousFired(magnitude: Double)
}
```

- [ ] **Step 2: Move and rename the matcher into `SequenceMatcher.swift`**

Open the current `Sources/ShortcutField/OnShortcutModifier.swift`. It contains, in order:
1. `enum ShortcutEventResult` (`@available(macOS 14.0, *)`)
2. `final class ShortcutMatcher` (`@available(macOS 14.0, *)`, `@MainActor`)
3. `final class ShortcutEventDispatcher` (`@available(macOS 14.0, *)`, `@MainActor`)
4. `enum ShortcutTracking` (`@available(macOS 14.0, *)`)
5. `struct OnShortcutModifier` (`@available(macOS 14.0, *)`)
6. `extension View { func onShortcut(...) }`

Cut items (1) and (2) — `ShortcutEventResult` and `ShortcutMatcher` — out of `OnShortcutModifier.swift` and into a new file `Sources/ShortcutField/Matching/SequenceMatcher.swift`. In the moved code:
- Delete `enum ShortcutEventResult` entirely — it is replaced by `ShortcutMatchResult` (Step 1).
- Rename `class ShortcutMatcher` → `class SequenceMatcher`.
- Remove the `@available(macOS 14.0, *)` annotation from `SequenceMatcher`.
- Change `SequenceMatcher.handle(_:)`'s return type from `ShortcutEventResult` to `ShortcutMatchResult`, and within its body rename the result cases: `.ignored` stays `.ignored`, `.advanced(consumeEvent:)` stays `.advanced(consumeEvent:)`, and `.matched` becomes `.fired`.
- The `trackingStateDidChange` callback, `stepTimeout`, `currentStep`, `isTracking`, the continuous-suppression set, `preempt`, `reset`, `restartTimeout`, `isInterceptedByFocusSystem` — all move unchanged (they reference only `DiscreteShortcut` and Foundation/AppKit types, all macOS 13+).
- `SequenceMatcher` is initialized with a `DiscreteShortcut` (it currently takes `Shortcut?` which is now `DiscreteShortcut?` after Task 1 — keep it `DiscreteShortcut?`).

`SequenceMatcher.swift` starts with `import AppKit` and `import Carbon.HIToolbox` (the moved code uses `kVK_Tab` / `kVK_Escape`).

- [ ] **Step 3: Leave `OnShortcutModifier.swift` referencing the moved types**

After the cut, `OnShortcutModifier.swift` still contains `ShortcutEventDispatcher`, `ShortcutTracking`, `OnShortcutModifier`, and the `onShortcut` extension — all still `@available(macOS 14.0, *)` for now (Task 6 and Task 7 update them). They reference `SequenceMatcher` (was `ShortcutMatcher`) and `ShortcutMatchResult` (was `ShortcutEventResult`):
- In `ShortcutEventDispatcher`: change `typealias Handler = (NSEvent) -> ShortcutEventResult` → `(NSEvent) -> ShortcutMatchResult`, and in `handleEvent` update the `switch` arms — `.matched` becomes `.fired`; add a `.continuousFired` arm that also sets `shouldConsume = true`.
- In `OnShortcutModifier`: the `@State private var matcher = ShortcutMatcher()` becomes `SequenceMatcher()`. (Task 7 rewrites this file fully — this is just the minimal change to keep the package compiling now.)

- [ ] **Step 4: Write the failing test**

Create `Tests/ShortcutFieldTests/Matching/SequenceMatcherTests.swift`. `SequenceMatcher` is `@MainActor`. Use `CGEvent`-constructed key events (the existing `DiscreteShortcutMatchingTests.swift` shows the pattern for synthesizing key `NSEvent`s — mirror it):
```swift
import AppKit
import Carbon.HIToolbox
import Testing
@testable import ShortcutField

@MainActor
@Suite("SequenceMatcher")
struct SequenceMatcherTests {
    /// Build a key-down NSEvent for the given keycode + modifiers.
    private func keyDown(_ keyCode: Int, _ modifiers: NSEvent.ModifierFlags = []) -> NSEvent {
        let cg = CGEvent(
            keyboardEventSource: nil,
            virtualKey: CGKeyCode(keyCode),
            keyDown: true
        )!
        cg.flags = CGEventFlags(rawValue: UInt64(modifiers.rawValue))
        return NSEvent(cgEvent: cg)!
    }

    @Test("single-step discrete shortcut fires on its event")
    func singleStepFires() {
        let matcher = SequenceMatcher()
        matcher.configure(
            shortcut: DiscreteShortcut(keyCode: UInt16(kVK_ANSI_S), modifiers: .command),
            action: {}
        )
        let result = matcher.handle(keyDown(kVK_ANSI_S, .command))
        #expect(result == .fired)
    }

    @Test("non-matching event is ignored")
    func nonMatchingIgnored() {
        let matcher = SequenceMatcher()
        matcher.configure(
            shortcut: DiscreteShortcut(keyCode: UInt16(kVK_ANSI_S), modifiers: .command),
            action: {}
        )
        let result = matcher.handle(keyDown(kVK_ANSI_A, .command))
        #expect(result == .ignored)
    }

    @Test("multi-step shortcut advances then fires")
    func multiStepAdvancesThenFires() {
        let matcher = SequenceMatcher()
        matcher.configure(
            shortcut: DiscreteShortcut(steps: [
                .init(keyCode: UInt16(kVK_ANSI_K), modifiers: .command),
                .init(keyCode: UInt16(kVK_ANSI_C), modifiers: .command),
            ]),
            action: {}
        )
        #expect(matcher.handle(keyDown(kVK_ANSI_K, .command)) == .advanced(consumeEvent: false))
        #expect(matcher.handle(keyDown(kVK_ANSI_C, .command)) == .fired)
    }
}
```
Note: `configure(shortcut:action:)` is the existing method on the matcher (verified in the pre-rename `ShortcutMatcher`). If its signature differs after the move, adjust the test to match the actual API — do not change the matcher's API to fit the test.

- [ ] **Step 5: Run the test to verify it passes**

Run:
```bash
just test 2>&1 | tail -25
```
Expected: `SequenceMatcherTests` pass; the full suite still passes (the move is behavior-preserving — `.matched` → `.fired` is a pure rename of the result case).

- [ ] **Step 6: Verify build + lint**

```bash
just build && just lint
```
Expected: `Build complete!`, `0 violations`.

- [ ] **Step 7: Commit**

```bash
git add Sources/ShortcutField/Matching/ShortcutMatchResult.swift Sources/ShortcutField/Matching/SequenceMatcher.swift Sources/ShortcutField/OnShortcutModifier.swift Tests/ShortcutFieldTests/Matching/SequenceMatcherTests.swift
git commit -m "refactor: extract SequenceMatcher and ShortcutMatchResult from OnShortcutModifier"
```

---

## Task 4: Extract `ContinuousMatcher`

**Goal:** The continuous-gesture matching logic currently lives inline in `OnContinuousShortcutModifier.installMonitor()`'s event-monitor closure. Extract it into a standalone, testable `@MainActor` class `ContinuousMatcher` that takes a `ContinuousShortcut`, owns a `ThrottleState`, and returns `ShortcutMatchResult` (`.ignored` or `.continuousFired(magnitude:)`). Written macOS 13+ (no `@available` gate). `OnContinuousShortcutModifier.swift` is left untouched in this task — it is deleted in Task 7.

**Files:**
- Create: `Sources/ShortcutField/Matching/ContinuousMatcher.swift`
- Create: `Tests/ShortcutFieldTests/Matching/ContinuousMatcherTests.swift`

Reference: read the current `Sources/ShortcutField/OnContinuousShortcutModifier.swift` `installMonitor()` closure for the exact rules to preserve — recording-state skip is the *dispatcher's* job (not the matcher's), momentum-scroll pass-through, phase-end throttle reset for the matching continuous kind, `shortcut.matches(event)` guard, and `ThrottleState.handleEvent`. Read `ThrottleState.swift` for `ThrottleState` (it has `sensitivity`, `reset()`, `handleEvent(action:)`, and the static `evaluate(state:now:) -> ThrottleDecision`).

- [ ] **Step 1: Write the failing test**

Create `Tests/ShortcutFieldTests/Matching/ContinuousMatcherTests.swift`. The existing `ContinuousShortcutRecorderFieldTests.swift` / `GestureAccumulatorTests.swift` show how the suite synthesizes gesture events; gesture `NSEvent`s cannot be constructed directly, so `ContinuousMatcher` must expose a test seam. Mirror the `GestureEventShape` seam pattern already used by `DiscreteShortcut+Matching.swift` and the matcher — `ContinuousMatcher` exposes an internal `handle(shape:)` taking a `GestureEventShape`-like value, and the public `handle(_ event: NSEvent)` builds the shape from the event. For scroll, the shape also needs the signed delta. Define a small internal `ContinuousEventShape` in `ContinuousMatcher.swift` if `GestureEventShape` does not already carry scroll deltas; the test drives `handle(shape:)` directly.

```swift
import AppKit
import Testing
@testable import ShortcutField

@MainActor
@Suite("ContinuousMatcher")
struct ContinuousMatcherTests {
    @Test("matching pinch event at full sensitivity fires with magnitude")
    func firesWithMagnitude() {
        let matcher = ContinuousMatcher(
            ContinuousShortcut(kind: .pinchOut, modifiers: [], sensitivity: 1.0)
        )
        let shape = ContinuousEventShape(type: .magnify, modifierFlags: [], magnification: 0.3, rotation: 0, scrollDeltaX: 0, scrollDeltaY: 0, phase: [])
        let result = matcher.handle(shape: shape)
        #expect(result == .continuousFired(magnitude: 0.3))
    }

    @Test("non-matching event is ignored")
    func nonMatchingIgnored() {
        let matcher = ContinuousMatcher(
            ContinuousShortcut(kind: .pinchOut, modifiers: [], sensitivity: 1.0)
        )
        // pinchIn-direction magnification (negative) does not match pinchOut
        let shape = ContinuousEventShape(type: .magnify, modifierFlags: [], magnification: -0.3, rotation: 0, scrollDeltaX: 0, scrollDeltaY: 0, phase: [])
        #expect(matcher.handle(shape: shape) == .ignored)
    }

    @Test("sensitivity 0 fires once then suppresses within the gesture")
    func sensitivityZeroFiresOnce() {
        let matcher = ContinuousMatcher(
            ContinuousShortcut(kind: .pinchOut, modifiers: [], sensitivity: 0.0)
        )
        let shape = ContinuousEventShape(type: .magnify, modifierFlags: [], magnification: 0.1, rotation: 0, scrollDeltaX: 0, scrollDeltaY: 0, phase: [])
        if case .continuousFired = matcher.handle(shape: shape) {} else {
            Issue.record("expected first event to fire")
        }
        #expect(matcher.handle(shape: shape) == .ignored)
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run:
```bash
just test 2>&1 | tail -20
```
Expected: compilation failure — `cannot find 'ContinuousMatcher'` / `cannot find 'ContinuousEventShape'`.

- [ ] **Step 3: Implement `ContinuousMatcher`**

Create `Sources/ShortcutField/Matching/ContinuousMatcher.swift`:
```swift
import AppKit

/// Test seam: a value-typed snapshot of the fields of a continuous `NSEvent`
/// (`.scrollWheel`, `.magnify`, `.rotate`) that `ContinuousMatcher` reads.
/// Gesture `NSEvent`s cannot be synthesized in tests, so the matcher's core
/// runs on this shape.
struct ContinuousEventShape: Equatable {
    var type: NSEvent.EventType
    var modifierFlags: NSEvent.ModifierFlags
    var magnification: Double
    var rotation: Double           // degrees
    var scrollDeltaX: Double
    var scrollDeltaY: Double
    var phase: NSEvent.Phase

    init(
        type: NSEvent.EventType,
        modifierFlags: NSEvent.ModifierFlags,
        magnification: Double,
        rotation: Double,
        scrollDeltaX: Double,
        scrollDeltaY: Double,
        phase: NSEvent.Phase
    ) {
        self.type = type
        self.modifierFlags = modifierFlags
        self.magnification = magnification
        self.rotation = rotation
        self.scrollDeltaX = scrollDeltaX
        self.scrollDeltaY = scrollDeltaY
        self.phase = phase
    }

    init(_ event: NSEvent) {
        type = event.type
        modifierFlags = event.modifierFlags
        magnification = (event.type == .magnify) ? Double(event.magnification) : 0
        rotation = (event.type == .rotate) ? Double(event.rotation) : 0
        scrollDeltaX = (event.type == .scrollWheel) ? Double(event.scrollingDeltaX) : 0
        scrollDeltaY = (event.type == .scrollWheel) ? Double(event.scrollingDeltaY) : 0
        phase = (event.type == .magnify || event.type == .rotate || event.type == .scrollWheel)
            ? event.phase : []
    }
}

/// Matches a single `ContinuousShortcut` against a stream of continuous gesture
/// events, applying the shortcut's `sensitivity` throttle. Internal — wrapped by
/// the public `ShortcutMatcher`.
@MainActor
final class ContinuousMatcher {
    private let shortcut: ContinuousShortcut
    private let throttle = ThrottleState()

    init(_ shortcut: ContinuousShortcut) {
        self.shortcut = shortcut
        throttle.sensitivity = shortcut.sensitivity
    }

    func reset() {
        throttle.reset()
    }

    func handle(_ event: NSEvent) -> ShortcutMatchResult {
        handle(shape: ContinuousEventShape(event))
    }

    func handle(shape: ContinuousEventShape) -> ShortcutMatchResult {
        // Momentum scroll: system-driven inertial events — never match.
        if shape.type == .scrollWheel, shape.phase == [] {
            // Mouse-wheel notches also have empty phase; fall through to matching.
            // Trackpad momentum is distinguished by `momentumPhase`, which the
            // public `handle(_ event:)` path checks before calling this. The
            // shape-based path is test-only and does not model momentum.
        }

        // Phase-end: reset throttle so the next physical gesture starts fresh.
        let isContinuousType = shape.type == .magnify || shape.type == .rotate
        if isContinuousType, shape.phase == .ended || shape.phase == .cancelled {
            if Self.eventTypeMatchesKind(shape.type, shortcut.kind) {
                throttle.reset()
            }
            return .ignored
        }

        guard matches(shape) else { return .ignored }

        var fired = false
        throttle.handleEvent { fired = true }
        guard fired else { return .ignored }
        return .continuousFired(magnitude: magnitude(of: shape))
    }

    /// Whether the shape matches this shortcut's kind + modifiers.
    private func matches(_ shape: ContinuousEventShape) -> Bool {
        let mods = DiscreteShortcut.canonicalModifiers(shape.modifierFlags)
        guard mods == shortcut.modifiers else { return false }
        switch shortcut.kind {
        case let .scroll(direction):
            guard shape.type == .scrollWheel else { return false }
            return scrollDirection(of: shape) == direction
        case .pinchIn:
            return shape.type == .magnify && shape.magnification < -DiscreteShortcut.magnifyEventThreshold
        case .pinchOut:
            return shape.type == .magnify && shape.magnification > DiscreteShortcut.magnifyEventThreshold
        case .rotateClockwise:
            return shape.type == .rotate && shape.rotation < -DiscreteShortcut.rotateEventThreshold
        case .rotateCounterClockwise:
            return shape.type == .rotate && shape.rotation > DiscreteShortcut.rotateEventThreshold
        }
    }

    /// Signed per-event magnitude for the shortcut's kind.
    private func magnitude(of shape: ContinuousEventShape) -> Double {
        switch shortcut.kind {
        case let .scroll(direction):
            switch direction {
            case .up, .down: shape.scrollDeltaY
            case .left, .right: shape.scrollDeltaX
            }
        case .pinchIn, .pinchOut:
            shape.magnification
        case .rotateClockwise, .rotateCounterClockwise:
            shape.rotation
        }
    }

    private func scrollDirection(of shape: ContinuousEventShape) -> DiscreteShortcut.ScrollDirection? {
        let dx = shape.scrollDeltaX
        let dy = shape.scrollDeltaY
        let threshold = 0.5
        if abs(dy) >= abs(dx) {
            guard abs(dy) >= threshold else { return nil }
            return dy > 0 ? .up : .down
        } else {
            guard abs(dx) >= threshold else { return nil }
            return dx > 0 ? .left : .right
        }
    }

    private static func eventTypeMatchesKind(
        _ eventType: NSEvent.EventType,
        _ kind: ContinuousShortcut.Kind
    ) -> Bool {
        switch (eventType, kind) {
        case (.magnify, .pinchIn), (.magnify, .pinchOut): true
        case (.rotate, .rotateClockwise), (.rotate, .rotateCounterClockwise): true
        default: false
        }
    }
}
```
Note: `DiscreteShortcut.canonicalModifiers`, `DiscreteShortcut.magnifyEventThreshold`, `DiscreteShortcut.rotateEventThreshold` are the static members that lived on the old `Shortcut` and are now on `DiscreteShortcut` (after Task 1). If any are currently `internal` they are reachable from this file (same module); if any are `private`, promote to `static` `internal` as part of this step. The scroll-direction and threshold logic mirrors the existing `DiscreteShortcut.scrollDirection(from:)` and `DiscreteShortcut.Step.matchesGesture` — keep the numbers identical.

The public `handle(_ event: NSEvent)` path additionally short-circuits trackpad momentum: before building the shape, `if event.type == .scrollWheel, event.momentumPhase != [] { return .ignored }`. Add that guard at the top of `handle(_ event:)`:
```swift
    func handle(_ event: NSEvent) -> ShortcutMatchResult {
        if event.type == .scrollWheel, event.momentumPhase != [] {
            return .ignored
        }
        return handle(shape: ContinuousEventShape(event))
    }
```

- [ ] **Step 4: Run the test to verify it passes**

Run:
```bash
just test 2>&1 | tail -20
```
Expected: `ContinuousMatcherTests` pass; full suite still passes.

- [ ] **Step 5: Verify build + lint**

```bash
just build && just lint
```
Expected: `Build complete!`, `0 violations`.

- [ ] **Step 6: Commit**

```bash
git add Sources/ShortcutField/Matching/ContinuousMatcher.swift Tests/ShortcutFieldTests/Matching/ContinuousMatcherTests.swift
git commit -m "feat: add ContinuousMatcher extracted from OnContinuousShortcutModifier"
```

---

## Task 5: `ShortcutMatcher` — the public unified matcher

**Goal:** Add the public `@MainActor` `ShortcutMatcher`, initialized with an umbrella `Shortcut`, delegating to `SequenceMatcher` (`.discrete`) or `ContinuousMatcher` (`.continuous`). It is the public face of matching. (Spec §4.)

**Files:**
- Create: `Sources/ShortcutField/Matching/ShortcutMatcher.swift`
- Create: `Tests/ShortcutFieldTests/Matching/ShortcutMatcherTests.swift`

- [ ] **Step 1: Write the failing test**

Create `Tests/ShortcutFieldTests/Matching/ShortcutMatcherTests.swift`:
```swift
import AppKit
import Carbon.HIToolbox
import Testing
@testable import ShortcutField

@MainActor
@Suite("ShortcutMatcher")
struct ShortcutMatcherTests {
    private func keyDown(_ keyCode: Int, _ modifiers: NSEvent.ModifierFlags = []) -> NSEvent {
        let cg = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(keyCode), keyDown: true)!
        cg.flags = CGEventFlags(rawValue: UInt64(modifiers.rawValue))
        return NSEvent(cgEvent: cg)!
    }

    @Test("discrete shortcut fires through the unified matcher")
    func discreteFires() {
        let matcher = ShortcutMatcher(
            .discrete(DiscreteShortcut(keyCode: UInt16(kVK_ANSI_S), modifiers: .command))
        )
        #expect(matcher.handle(keyDown(kVK_ANSI_S, .command)) == .fired)
    }

    @Test("discrete shortcut ignores a non-matching event")
    func discreteIgnores() {
        let matcher = ShortcutMatcher(
            .discrete(DiscreteShortcut(keyCode: UInt16(kVK_ANSI_S), modifiers: .command))
        )
        #expect(matcher.handle(keyDown(kVK_ANSI_A, .command)) == .ignored)
    }

    @Test("reset clears in-progress sequence state")
    func resetClears() {
        let matcher = ShortcutMatcher(.discrete(DiscreteShortcut(steps: [
            .init(keyCode: UInt16(kVK_ANSI_K), modifiers: .command),
            .init(keyCode: UInt16(kVK_ANSI_C), modifiers: .command),
        ])))
        _ = matcher.handle(keyDown(kVK_ANSI_K, .command))   // advance
        matcher.reset()
        // After reset, the second step alone should not fire.
        #expect(matcher.handle(keyDown(kVK_ANSI_C, .command)) == .ignored)
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run:
```bash
just test 2>&1 | tail -20
```
Expected: compilation failure — `cannot find 'ShortcutMatcher'`.

- [ ] **Step 3: Implement `ShortcutMatcher`**

Create `Sources/ShortcutField/Matching/ShortcutMatcher.swift`:
```swift
import AppKit

/// Matches a `Shortcut` against a stream of `NSEvent`s.
///
/// The public face of matching: construct one with any `Shortcut` (discrete or
/// continuous) and feed it events. Internally delegates to a `SequenceMatcher`
/// for `.discrete` shortcuts and a `ContinuousMatcher` for `.continuous` ones,
/// so callers never branch on kind.
@MainActor
public final class ShortcutMatcher {
    private enum Backing {
        case discrete(SequenceMatcher)
        case continuous(ContinuousMatcher)
    }

    private let backing: Backing

    public init(_ shortcut: Shortcut) {
        switch shortcut {
        case let .discrete(discrete):
            let sequence = SequenceMatcher()
            sequence.configure(shortcut: discrete, action: {})
            backing = .discrete(sequence)
        case let .continuous(continuous):
            backing = .continuous(ContinuousMatcher(continuous))
        }
    }

    /// Feed an `NSEvent`. Returns whether it advanced or completed a match.
    public func handle(_ event: NSEvent) -> ShortcutMatchResult {
        switch backing {
        case let .discrete(sequence): sequence.handle(event)
        case let .continuous(continuous): continuous.handle(event)
        }
    }

    /// Discard in-progress sequence / throttle state.
    public func reset() {
        switch backing {
        case let .discrete(sequence): sequence.reset()
        case let .continuous(continuous): continuous.reset()
        }
    }
}
```
Note: `SequenceMatcher` currently fires its `action` closure on a completed match (a holdover from when it drove `.onShortcut` directly). `ShortcutMatcher` passes an empty `action: {}` because the *result* (`.fired`) is the signal callers use — the action closure is vestigial for the matcher-as-value use. Task 7 (the `.onShortcut` reimplementation) confirms whether `SequenceMatcher` should drop the `action` closure entirely; if so, that cleanup happens there. For Task 5, passing `{}` is correct and keeps `SequenceMatcher`'s existing API untouched.

- [ ] **Step 4: Run the test to verify it passes**

Run:
```bash
just test 2>&1 | tail -20
```
Expected: `ShortcutMatcherTests` pass; full suite still passes.

- [ ] **Step 5: Verify build + lint**

```bash
just build && just lint
```
Expected: `Build complete!`, `0 violations`.

- [ ] **Step 6: Commit**

```bash
git add Sources/ShortcutField/Matching/ShortcutMatcher.swift Tests/ShortcutFieldTests/Matching/ShortcutMatcherTests.swift
git commit -m "feat: add public unified ShortcutMatcher"
```

---

## Task 6: Make `ShortcutEventDispatcher` public

**Goal:** Move `ShortcutEventDispatcher` out of `OnShortcutModifier.swift` into its own file, make it `public`, drop the `@available(macOS 14.0, *)` gate, and expose `register(id:handler:)` / `unregister(id:)` with the `Handler` typealias `(NSEvent) -> ShortcutMatchResult`. Behavior — lazy monitor install, recording-suppression, newest-first consumption — is unchanged. (Spec §5.1.)

**Files:**
- Create: `Sources/ShortcutField/Matching/ShortcutEventDispatcher.swift` (moved from `OnShortcutModifier.swift`)
- Modify: `Sources/ShortcutField/OnShortcutModifier.swift` (remove the dispatcher class)
- Create: `Tests/ShortcutFieldTests/Matching/ShortcutEventDispatcherTests.swift`

- [ ] **Step 1: Move the dispatcher into its own file and make it public**

Cut `final class ShortcutEventDispatcher` out of `OnShortcutModifier.swift` into a new `Sources/ShortcutField/Matching/ShortcutEventDispatcher.swift`. In the moved code:
- Remove the `@available(macOS 14.0, *)` annotation.
- Add `public` to the class, to `static let shared`, to `typealias Handler`, to `register(id:handler:)`, and to `unregister(id:)`.
- Keep `@MainActor`.
- The `Handler` typealias is already `(NSEvent) -> ShortcutMatchResult` after Task 3 Step 3. Confirm it reads `public typealias Handler = (NSEvent) -> ShortcutMatchResult`.
- `handleEvent`, `installMonitorIfNeeded`, `removeMonitor`, `handlers`, `handlerSnapshot`, `eventMonitor` stay `private` / internal — only `shared`, `register`, `unregister`, `Handler` are public.
- The `handleEvent` consumption logic stays: iterate `handlerSnapshot`, `.ignored` → continue, `.advanced(consumeEvent:)` → `shouldConsume ||= consumeEvent`, `.fired` → `shouldConsume = true`, `.continuousFired` → `shouldConsume = true`. Return `nil` (consume) if `shouldConsume`, else the event.
- `ShortcutRecordingState.isAnyRecording` early-return stays unchanged.

The file starts with `import AppKit`.

- [ ] **Step 2: Write the failing test**

Create `Tests/ShortcutFieldTests/Matching/ShortcutEventDispatcherTests.swift`:
```swift
import AppKit
import Carbon.HIToolbox
import Testing
@testable import ShortcutField

@MainActor
@Suite("ShortcutEventDispatcher")
struct ShortcutEventDispatcherTests {
    private func keyDown(_ keyCode: Int, _ modifiers: NSEvent.ModifierFlags = []) -> NSEvent {
        let cg = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(keyCode), keyDown: true)!
        cg.flags = CGEventFlags(rawValue: UInt64(modifiers.rawValue))
        return NSEvent(cgEvent: cg)!
    }

    @Test("a registered handler receives events; unregister stops delivery")
    func registerUnregister() {
        let dispatcher = ShortcutEventDispatcher.shared
        let id = UUID()
        var received = 0
        dispatcher.register(id: id) { _ in
            received += 1
            return .ignored
        }
        _ = dispatcher.handleEvent(keyDown(kVK_ANSI_S, .command))
        #expect(received == 1)

        dispatcher.unregister(id: id)
        _ = dispatcher.handleEvent(keyDown(kVK_ANSI_S, .command))
        #expect(received == 1)   // no further delivery
    }

    @Test("a .fired result consumes the event")
    func firedConsumes() {
        let dispatcher = ShortcutEventDispatcher.shared
        let id = UUID()
        dispatcher.register(id: id) { _ in .fired }
        defer { dispatcher.unregister(id: id) }
        #expect(dispatcher.handleEvent(keyDown(kVK_ANSI_S, .command)) == nil)
    }
}
```
Note: `handleEvent` must be at least `internal` (it is — it's the monitor callback). If it is `private`, change it to `internal` so the test can drive it directly without installing a real monitor.

- [ ] **Step 3: Run the test to verify it passes**

Run:
```bash
just test 2>&1 | tail -20
```
Expected: `ShortcutEventDispatcherTests` pass; full suite still passes (the move + visibility change is behavior-preserving).

- [ ] **Step 4: Verify build + lint**

```bash
just build && just lint
```
Expected: `Build complete!`, `0 violations`.

- [ ] **Step 5: Commit**

```bash
git add Sources/ShortcutField/Matching/ShortcutEventDispatcher.swift Sources/ShortcutField/OnShortcutModifier.swift Tests/ShortcutFieldTests/Matching/ShortcutEventDispatcherTests.swift
git commit -m "feat: make ShortcutEventDispatcher public"
```

---

## Task 7: Unified `.onShortcut`; remove `.onContinuousShortcut`

**Goal:** Reimplement `.onShortcut` to take the umbrella `Shortcut?` and fire `action` appropriately for either case (once on `.fired` for discrete; on each `.continuousFired` for continuous). Built on `ShortcutMatcher` + `ShortcutEventDispatcher`. Drop the `@available(macOS 14.0, *)` gate. Delete `OnContinuousShortcutModifier.swift` entirely — it is subsumed. Preserve `ShortcutTracking.isActive`. (Spec §5.2.)

**Files:**
- Modify: `Sources/ShortcutField/OnShortcutModifier.swift` (rewrite the modifier + extension)
- Delete: `Sources/ShortcutField/OnContinuousShortcutModifier.swift`
- Modify: `Tests/ShortcutFieldTests/` — any test referencing `.onContinuousShortcut` or the old `.onShortcut(DiscreteShortcut?)` signature

- [ ] **Step 1: Rewrite `OnShortcutModifier.swift`**

After Tasks 3 and 6, `OnShortcutModifier.swift` contains only `ShortcutTracking` and `OnShortcutModifier` + the `View.onShortcut` extension (the matcher, result enum, and dispatcher have moved out). Rewrite the file so:
- `ShortcutTracking` stays as-is but drop its `@available(macOS 14.0, *)` annotation.
- `OnShortcutModifier` becomes a `ViewModifier` taking `let shortcut: Shortcut?` (umbrella) and `let action: () -> Void`. Drop `@available(macOS 14.0, *)`.
- It holds `@State private var matcher: ShortcutMatcher?` and `@State private var listenerID = UUID()`.
- On `.onAppear` (and on `.onChange(of: shortcut)` using the **single-parameter** macOS-13 form `{ newValue in ... }`): rebuild the `ShortcutMatcher` from the current `shortcut` (nil → no matcher, unregister), register a handler with `ShortcutEventDispatcher.shared` that calls `matcher.handle(event)` and:
  - on `.fired` → call `action()`, return `.fired`.
  - on `.continuousFired(let m)` → call `action()`, return `.continuousFired(magnitude: m)`.
  - on `.advanced(let consume)` → return `.advanced(consumeEvent: consume)` (drives `ShortcutTracking` — see below).
  - on `.ignored` → return `.ignored`.
- On `.onDisappear`: `ShortcutEventDispatcher.shared.unregister(id: listenerID)` and `matcher?.reset()`.
- `ShortcutTracking.isActive` integration: the old code wired `matcher.trackingStateDidChange` to bump `ShortcutTracking.activeCount`. `SequenceMatcher` still exposes `trackingStateDidChange` (it moved unchanged in Task 3). But `ShortcutMatcher` wraps `SequenceMatcher` privately. Add a `public var trackingStateDidChange: ((Bool) -> Void)?` passthrough on `ShortcutMatcher` that forwards to the backing `SequenceMatcher` (no-op for `.continuous`). Wire it in `OnShortcutModifier` exactly as the old code did: `+1` when tracking starts, `-1` when it ends.

```swift
import AppKit
import SwiftUI

/// Whether any `.onShortcut()` modifier with a multi-step discrete shortcut is
/// partway through matching (past step 0).
///
/// Use this in a `noResponder(for:)` override to suppress the system alert sound
/// only for key events that are part of an in-progress sequence match.
public enum ShortcutTracking {
    /// `true` when at least one `.onShortcut()` modifier has matched one or more
    /// intermediate steps and is waiting for the next event.
    @MainActor public private(set) static var isActive = false

    @MainActor fileprivate static var activeCount = 0 {
        didSet { isActive = activeCount > 0 }
    }
}

/// View modifier backing `.onShortcut`.
struct OnShortcutModifier: ViewModifier {
    let shortcut: Shortcut?
    let action: () -> Void

    @State private var matcher: ShortcutMatcher?
    @State private var listenerID = UUID()

    func body(content: Content) -> some View {
        content
            .onAppear { install() }
            .onDisappear { teardown() }
            .onChange(of: shortcut) { _ in
                teardown()
                install()
            }
    }

    private func install() {
        guard let shortcut else { return }
        let matcher = ShortcutMatcher(shortcut)
        matcher.trackingStateDidChange = { isTracking in
            ShortcutTracking.activeCount += isTracking ? 1 : -1
        }
        self.matcher = matcher
        ShortcutEventDispatcher.shared.register(id: listenerID) { event in
            let result = matcher.handle(event)
            switch result {
            case .fired, .continuousFired:
                action()
            case .advanced, .ignored:
                break
            }
            return result
        }
    }

    private func teardown() {
        ShortcutEventDispatcher.shared.unregister(id: listenerID)
        matcher?.reset()
        matcher = nil
    }
}

// MARK: - View Extension

public extension View {
    /// Perform an action when `shortcut` is performed.
    ///
    /// For `.discrete` shortcuts the action fires once on completion. For
    /// `.continuous` shortcuts it fires repeatedly, throttled by the shortcut's
    /// `sensitivity`. Multi-step discrete shortcuts fire once when the full
    /// sequence completes within the per-step timeout.
    ///
    /// - Note: Intermediate key events of a multi-step match propagate through
    ///   the responder chain and may trigger the macOS system alert sound. Check
    ///   ``ShortcutTracking/isActive`` in a `noResponder(for:)` override to
    ///   suppress the beep selectively.
    func onShortcut(_ shortcut: Shortcut?, perform action: @escaping () -> Void) -> some View {
        modifier(OnShortcutModifier(shortcut: shortcut, action: action))
    }
}
```

- [ ] **Step 2: Add the `trackingStateDidChange` passthrough to `ShortcutMatcher`**

Modify `Sources/ShortcutField/Matching/ShortcutMatcher.swift` — add to the class:
```swift
    /// Forwards the in-progress-sequence signal from the backing discrete
    /// matcher. No-op for continuous shortcuts.
    public var trackingStateDidChange: ((Bool) -> Void)? {
        didSet {
            if case let .discrete(sequence) = backing {
                sequence.trackingStateDidChange = trackingStateDidChange
            }
        }
    }
```

- [ ] **Step 3: Delete `OnContinuousShortcutModifier.swift`**

```bash
cd /Users/nielsmadan/wrksp/juggler/ShortcutField
git rm Sources/ShortcutField/OnContinuousShortcutModifier.swift
```

- [ ] **Step 4: Update tests that used the old modifier signatures**

Search for usages:
```bash
grep -rn "onContinuousShortcut\|onShortcut" Tests/ShortcutFieldTests/
```
For each hit:
- `.onContinuousShortcut(cs) { ... }` → `.onShortcut(.continuous(cs)) { ... }`.
- `.onShortcut(discreteShortcut) { ... }` → `.onShortcut(.discrete(discreteShortcut)) { ... }`.
If a test only existed to exercise `OnContinuousShortcutModifier`'s internals (now covered by `ContinuousMatcherTests`), and it cannot be expressed against the public API, delete it and note the coverage moved to `ContinuousMatcherTests`.

- [ ] **Step 5: Run the full suite**

Run:
```bash
just test 2>&1 | tail -25
```
Expected: all tests pass. The `.onShortcut` / (former) `.onContinuousShortcut` observable behavior is preserved — discrete shortcuts fire once, continuous shortcuts fire throttled.

- [ ] **Step 6: Verify build + lint**

```bash
just build && just lint
```
Expected: `Build complete!`, `0 violations`. The package now builds with **no `@available(macOS 14.0, *)`** on the matching/modifier layer (only `DiscreteShortcut.Step.matches(KeyPress)` retains it — `KeyPress` is a 14+ type).

- [ ] **Step 7: Commit**

```bash
git add -A
git commit -m "feat: unify onShortcut on the umbrella Shortcut; remove onContinuousShortcut"
```

---

## Task 8: Text syntax — `ascii` / `init(ascii:)` / `ExpressibleByStringLiteral`

**Goal:** Add the VS Code-style text syntax: `ShortcutParsingError`, `DiscreteShortcut.ascii` + `init(ascii:)`, `Shortcut.ascii` + `init(ascii:)`, and `Shortcut: ExpressibleByStringLiteral`. (Spec §6.)

**Files:**
- Create: `Sources/ShortcutField/Syntax/ShortcutASCII.swift`
- Create: `Tests/ShortcutFieldTests/ShortcutASCIITests.swift`

- [ ] **Step 1: Write the failing tests**

Create `Tests/ShortcutFieldTests/ShortcutASCIITests.swift`:
```swift
import AppKit
import Carbon.HIToolbox
import Testing
@testable import ShortcutField

@Suite("Shortcut text syntax")
struct ShortcutASCIITests {
    @Test("discrete round-trips: key + modifiers")
    func discreteKeyRoundTrip() throws {
        let s = try DiscreteShortcut(ascii: "cmd+s")
        #expect(s == DiscreteShortcut(keyCode: UInt16(kVK_ANSI_S), modifiers: .command))
        #expect(s.ascii == "cmd+s")
    }

    @Test("discrete round-trips: multiple modifiers, order-insensitive parse")
    func multiModifier() throws {
        let s = try DiscreteShortcut(ascii: "shift+cmd+a")
        #expect(s == DiscreteShortcut(keyCode: UInt16(kVK_ANSI_A), modifiers: [.command, .shift]))
        // emitter uses canonical order ctrl, opt, shift, cmd
        #expect(s.ascii == "shift+cmd+a")
    }

    @Test("discrete round-trips: multi-step")
    func multiStep() throws {
        let s = try DiscreteShortcut(ascii: "cmd+k cmd+c")
        #expect(s.steps.count == 2)
        #expect(s.ascii == "cmd+k cmd+c")
    }

    @Test("discrete round-trips: mouse, scroll, gesture, special keys")
    func nonKeyForms() throws {
        #expect(try DiscreteShortcut(ascii: "ctrl+right-click").ascii == "ctrl+right-click")
        #expect(try DiscreteShortcut(ascii: "shift+scroll-up").ascii == "shift+scroll-up")
        #expect(try DiscreteShortcut(ascii: "cmd+pinch-in").ascii == "cmd+pinch-in")
        #expect(try DiscreteShortcut(ascii: "tab").ascii == "tab")
        #expect(try DiscreteShortcut(ascii: "escape").ascii == "escape")
    }

    @Test("umbrella resolves bare gesture to continuous")
    func umbrellaContinuousResolution() throws {
        let s = try Shortcut(ascii: "cmd+pinch-out @0.5")
        guard case let .continuous(cs) = s else {
            Issue.record("expected .continuous"); return
        }
        #expect(cs.kind == .pinchOut)
        #expect(cs.sensitivity == 0.5)
        #expect(s.ascii == "cmd+pinch-out @0.5")
    }

    @Test("umbrella resolves key/multistep to discrete")
    func umbrellaDiscreteResolution() throws {
        guard case .discrete = try Shortcut(ascii: "cmd+s") else {
            Issue.record("expected .discrete"); return
        }
        guard case .discrete = try Shortcut(ascii: "cmd+k cmd+c") else {
            Issue.record("expected .discrete"); return
        }
    }

    @Test("ExpressibleByStringLiteral produces a Shortcut")
    func stringLiteral() {
        let s: Shortcut = "cmd+s"
        #expect(s == .discrete(DiscreteShortcut(keyCode: UInt16(kVK_ANSI_S), modifiers: .command)))
    }

    @Test("parse errors")
    func parseErrors() {
        #expect(throws: ShortcutParsingError.empty) { try DiscreteShortcut(ascii: "") }
        #expect(throws: ShortcutParsingError.unknownModifier("hyper")) {
            try DiscreteShortcut(ascii: "hyper+s")
        }
        #expect(throws: ShortcutParsingError.unknownKey("notakey")) {
            try DiscreteShortcut(ascii: "cmd+notakey")
        }
        #expect(throws: ShortcutParsingError.sensitivityOnDiscrete) {
            try DiscreteShortcut(ascii: "cmd+s @0.5")
        }
        #expect(throws: ShortcutParsingError.malformedSensitivity("abc")) {
            try Shortcut(ascii: "pinch-in @abc")
        }
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run:
```bash
just test 2>&1 | tail -20
```
Expected: compilation failure — `cannot find 'ShortcutParsingError'`, no `init(ascii:)`.

- [ ] **Step 3: Implement the error type and token tables**

Create `Sources/ShortcutField/Syntax/ShortcutASCII.swift`. Start with the error enum and the static token tables:
```swift
import AppKit
import Carbon.HIToolbox

/// Error thrown by `init(ascii:)` when a text shortcut string is malformed.
public enum ShortcutParsingError: Error, Equatable {
    case empty
    case unknownModifier(String)
    case unknownKey(String)
    case unknownGesture(String)
    case malformedSensitivity(String)
    case sensitivityOnDiscrete
    case emptyStep
}

// MARK: - Token tables

private enum ASCIIToken {
    /// Modifier name → flag. Canonical emit order is ctrl, opt, shift, cmd.
    static let modifiers: [(name: String, flag: NSEvent.ModifierFlags)] = [
        ("ctrl", .control),
        ("opt", .option),
        ("shift", .shift),
        ("cmd", .command),
    ]

    /// Special key name ↔ virtual keycode.
    static let specialKeys: [(name: String, keyCode: Int)] = [
        ("tab", kVK_Tab),
        ("return", kVK_Return),
        ("escape", kVK_Escape),
        ("space", kVK_Space),
        ("delete", kVK_Delete),
        ("forward-delete", kVK_ForwardDelete),
        ("home", kVK_Home),
        ("end", kVK_End),
        ("pageup", kVK_PageUp),
        ("pagedown", kVK_PageDown),
        ("up", kVK_UpArrow),
        ("down", kVK_DownArrow),
        ("left", kVK_LeftArrow),
        ("right", kVK_RightArrow),
        ("f1", kVK_F1), ("f2", kVK_F2), ("f3", kVK_F3), ("f4", kVK_F4),
        ("f5", kVK_F5), ("f6", kVK_F6), ("f7", kVK_F7), ("f8", kVK_F8),
        ("f9", kVK_F9), ("f10", kVK_F10), ("f11", kVK_F11), ("f12", kVK_F12),
    ]

    /// Letter/digit name ↔ ANSI virtual keycode. Layout-independent in the
    /// `kVK_ANSI_*` sense — `"s"` is the physical S key on a QWERTY layout.
    static let ansiKeys: [(name: String, keyCode: Int)] = [
        ("a", kVK_ANSI_A), ("b", kVK_ANSI_B), ("c", kVK_ANSI_C), ("d", kVK_ANSI_D),
        ("e", kVK_ANSI_E), ("f", kVK_ANSI_F), ("g", kVK_ANSI_G), ("h", kVK_ANSI_H),
        ("i", kVK_ANSI_I), ("j", kVK_ANSI_J), ("k", kVK_ANSI_K), ("l", kVK_ANSI_L),
        ("m", kVK_ANSI_M), ("n", kVK_ANSI_N), ("o", kVK_ANSI_O), ("p", kVK_ANSI_P),
        ("q", kVK_ANSI_Q), ("r", kVK_ANSI_R), ("s", kVK_ANSI_S), ("t", kVK_ANSI_T),
        ("u", kVK_ANSI_U), ("v", kVK_ANSI_V), ("w", kVK_ANSI_W), ("x", kVK_ANSI_X),
        ("y", kVK_ANSI_Y), ("z", kVK_ANSI_Z),
        ("0", kVK_ANSI_0), ("1", kVK_ANSI_1), ("2", kVK_ANSI_2), ("3", kVK_ANSI_3),
        ("4", kVK_ANSI_4), ("5", kVK_ANSI_5), ("6", kVK_ANSI_6), ("7", kVK_ANSI_7),
        ("8", kVK_ANSI_8), ("9", kVK_ANSI_9),
    ]

    /// Mouse-button name ↔ button number.
    static let mouseButtons: [(name: String, number: Int)] = [
        ("left-click", 0),
        ("right-click", 1),
        ("middle-click", 2),
        ("button4", 3),
        ("button5", 4),
    ]

    /// Scroll-direction name ↔ direction.
    static let scrollDirections: [(name: String, direction: DiscreteShortcut.ScrollDirection)] = [
        ("scroll-up", .up),
        ("scroll-down", .down),
        ("scroll-left", .left),
        ("scroll-right", .right),
    ]
}
```

- [ ] **Step 4: Implement the `DiscreteShortcut.Step` token parse/emit**

Append to `Sources/ShortcutField/Syntax/ShortcutASCII.swift`:
```swift
// MARK: - Step parsing / emitting

extension DiscreteShortcut.Step {
    /// Parse one step token (e.g. "cmd+s", "ctrl+right-click", "scroll-up").
    /// The `@N` sensitivity suffix must already be stripped by the caller.
    static func parse(ascii token: String) throws -> DiscreteShortcut.Step {
        let parts = token.split(separator: "+", omittingEmptySubsequences: false).map(String.init)
        guard !parts.isEmpty, !parts.contains(where: \.isEmpty) else {
            throw ShortcutParsingError.emptyStep
        }
        var modifiers: NSEvent.ModifierFlags = []
        for modPart in parts.dropLast() {
            guard let entry = ASCIIToken.modifiers.first(where: { $0.name == modPart }) else {
                throw ShortcutParsingError.unknownModifier(modPart)
            }
            modifiers.insert(entry.flag)
        }
        let final = parts[parts.count - 1]
        let kind = try Self.parseKind(final)
        return DiscreteShortcut.Step(kind: kind, modifiers: modifiers)
    }

    private static func parseKind(_ token: String) throws -> DiscreteShortcut.Kind {
        if let special = ASCIIToken.specialKeys.first(where: { $0.name == token }) {
            return .key(keyCode: UInt16(special.keyCode))
        }
        if let ansi = ASCIIToken.ansiKeys.first(where: { $0.name == token }) {
            return .key(keyCode: UInt16(ansi.keyCode))
        }
        if let mouse = ASCIIToken.mouseButtons.first(where: { $0.name == token }) {
            return .mouseButton(number: mouse.number)
        }
        if let scroll = ASCIIToken.scrollDirections.first(where: { $0.name == token }) {
            return .scroll(direction: scroll.direction)
        }
        switch token {
        case "pinch-in": return .pinchIn
        case "pinch-out": return .pinchOut
        case "rotate-clockwise": return .rotateClockwise
        case "rotate-counterclockwise": return .rotateCounterClockwise
        case "smart-magnify": return .smartMagnify
        default: throw ShortcutParsingError.unknownKey(token)
        }
    }

    /// Emit this step as an ascii token.
    var ascii: String {
        let modPrefix = ASCIIToken.modifiers
            .filter { modifiers.contains($0.flag) }
            .map { $0.name + "+" }
            .joined()
        return modPrefix + kindASCII
    }

    private var kindASCII: String {
        switch kind {
        case let .key(keyCode):
            if let special = ASCIIToken.specialKeys.first(where: { $0.keyCode == Int(keyCode) }) {
                return special.name
            }
            if let ansi = ASCIIToken.ansiKeys.first(where: { $0.keyCode == Int(keyCode) }) {
                return ansi.name
            }
            return "?"
        case let .mouseButton(number):
            return ASCIIToken.mouseButtons.first(where: { $0.number == number })?.name
                ?? "button\(number + 1)"
        case let .scroll(direction):
            return ASCIIToken.scrollDirections.first(where: { $0.direction == direction })!.name
        case .pinchIn: return "pinch-in"
        case .pinchOut: return "pinch-out"
        case .rotateClockwise: return "rotate-clockwise"
        case .rotateCounterClockwise: return "rotate-counterclockwise"
        case .smartMagnify: return "smart-magnify"
        }
    }
}
```
Note: `DiscreteShortcut.Step` is initialized `DiscreteShortcut.Step(kind:modifiers:)` and `DiscreteShortcut.Step(keyCode:modifiers:)` — confirm against `DiscreteShortcut.swift` (post-Task-1). `DiscreteShortcut.Kind` cases are `.key(keyCode:)`, `.mouseButton(number:)`, `.scroll(direction:)`, `.pinchIn`, `.pinchOut`, `.rotateClockwise`, `.rotateCounterClockwise`, `.smartMagnify`.

- [ ] **Step 5: Implement `DiscreteShortcut` and `Shortcut` ascii**

Append to `Sources/ShortcutField/Syntax/ShortcutASCII.swift`:
```swift
// MARK: - DiscreteShortcut ascii

public extension DiscreteShortcut {
    /// Parse a VS Code-style ascii string into a discrete shortcut.
    /// Steps are space-separated; a ` @N` sensitivity suffix is invalid here.
    init(ascii: String) throws {
        let trimmed = ascii.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { throw ShortcutParsingError.empty }
        if trimmed.contains("@") {
            throw ShortcutParsingError.sensitivityOnDiscrete
        }
        let tokens = trimmed.split(separator: " ").map(String.init)
        guard !tokens.isEmpty else { throw ShortcutParsingError.empty }
        let steps = try tokens.map { try DiscreteShortcut.Step.parse(ascii: $0) }
        self.init(steps: steps)
    }

    /// VS Code-style ascii representation. Round-trips with `init(ascii:)`.
    var ascii: String {
        steps.map(\.ascii).joined(separator: " ")
    }
}

// MARK: - Shortcut ascii (umbrella)

public extension Shortcut {
    /// Parse a VS Code-style ascii string into the umbrella `Shortcut`.
    ///
    /// Resolution: a multi-step string, or a single key / mouse / `smart-magnify`
    /// step → `.discrete`. A single bare gesture kind (`scroll-*`, `pinch-*`,
    /// `rotate-*`) → `.continuous`, with the ` @N` sensitivity suffix if present
    /// (else default sensitivity `0.0`).
    init(ascii: String) throws {
        let trimmed = ascii.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { throw ShortcutParsingError.empty }

        // Split off an optional " @N" sensitivity suffix.
        var body = trimmed
        var sensitivity: Double?
        if let atRange = trimmed.range(of: " @") {
            body = String(trimmed[..<atRange.lowerBound])
            let suffix = String(trimmed[atRange.upperBound...])
            guard let value = Double(suffix), (0.0...1.0).contains(value) else {
                throw ShortcutParsingError.malformedSensitivity(suffix)
            }
            sensitivity = value
        }

        let tokens = body.split(separator: " ").map(String.init)
        guard tokens.count == 1 else {
            // Multi-step → discrete (sensitivity suffix on multi-step is invalid).
            if sensitivity != nil { throw ShortcutParsingError.sensitivityOnDiscrete }
            self = try .discrete(DiscreteShortcut(ascii: body))
            return
        }

        // Single step: parse it, then resolve discrete vs continuous by kind.
        let step = try DiscreteShortcut.Step.parse(ascii: tokens[0])
        if let continuousKind = ContinuousShortcut.Kind(step.kind) {
            self = .continuous(ContinuousShortcut(
                kind: continuousKind,
                modifiers: step.modifiers,
                sensitivity: sensitivity ?? 0.0
            ))
        } else {
            if sensitivity != nil { throw ShortcutParsingError.sensitivityOnDiscrete }
            self = .discrete(DiscreteShortcut(steps: [step]))
        }
    }

    /// VS Code-style ascii representation. Round-trips with `init(ascii:)`.
    var ascii: String {
        switch self {
        case let .discrete(shortcut):
            return shortcut.ascii
        case let .continuous(shortcut):
            let step = DiscreteShortcut.Step(
                kind: shortcut.kind.asDiscreteKind,
                modifiers: shortcut.modifiers
            )
            return step.ascii + " @" + Self.formatSensitivity(shortcut.sensitivity)
        }
    }

    private static func formatSensitivity(_ value: Double) -> String {
        // Compact: drop a trailing ".0" so 0.5 → "0.5", 1 → "1.0" stays "1.0".
        // Round-trip safety: Double("0.5") == 0.5.
        String(value)
    }
}

// MARK: - ExpressibleByStringLiteral

extension Shortcut: ExpressibleByStringLiteral {
    /// `"cmd+s"` is a `Shortcut` anywhere one is expected.
    ///
    /// A string *literal* is a compile-time constant; a malformed literal
    /// triggers `fatalError` — caught immediately during development. For
    /// runtime strings (config files, command palettes) use the throwing
    /// `init(ascii:)` instead.
    public init(stringLiteral value: String) {
        do {
            self = try Shortcut(ascii: value)
        } catch {
            fatalError("Invalid Shortcut string literal \"\(value)\": \(error)")
        }
    }
}
```
Note: `ContinuousShortcut.Kind(step.kind)` is the failable projector that already exists on `ContinuousShortcut.Kind` (`init?(_ discreteKind: DiscreteShortcut.Kind)` after Task 1). `shortcut.kind.asDiscreteKind` is the `asShortcutKind` property renamed `asDiscreteKind` in Task 1 Step 3 — it lifts a `ContinuousShortcut.Kind` to a `DiscreteShortcut.Kind`.

- [ ] **Step 6: Run the tests to verify they pass**

Run:
```bash
just test 2>&1 | tail -25
```
Expected: all `ShortcutASCIITests` pass; full suite still passes. If a round-trip fails on sensitivity formatting (e.g. `"0.5"` vs `"0.50"`), adjust `formatSensitivity` so `Double(formatSensitivity(x)) == x` and the canonical form is stable.

- [ ] **Step 7: Verify build + lint**

```bash
just build && just lint
```
Expected: `Build complete!`, `0 violations`.

- [ ] **Step 8: Commit**

```bash
git add Sources/ShortcutField/Syntax/ShortcutASCII.swift Tests/ShortcutFieldTests/ShortcutASCIITests.swift
git commit -m "feat: add VS Code-style text syntax for Shortcut and DiscreteShortcut"
```

---

## Task 9: Final verification

**Goal:** Confirm 2.1.0 is complete, behavior-preserving, and ready for the maintainer to tag.

- [ ] **Step 1: Full clean build + test + lint**

Run:
```bash
just clean && just build && just test && just lint
```
Expected: `Build complete!`, the full suite passes, `0 violations`.

- [ ] **Step 2: Confirm the macOS-13 backport is complete**

Run:
```bash
grep -rn "@available(macOS 14" Sources/ShortcutField/
```
Expected: the **only** remaining hit is in `DiscreteShortcut+Matching.swift` on the `matches(_ press: KeyPress)` extension — `KeyPress` is a macOS-14 type, so that annotation is correct and stays. If `@available(macOS 14` appears anywhere else (matchers, dispatcher, modifier, `Shortcut`, text syntax), it is a bug — remove it.

- [ ] **Step 3: Confirm `.onContinuousShortcut` is fully gone**

Run:
```bash
grep -rn "onContinuousShortcut\|OnContinuousShortcutModifier" Sources/ Tests/
```
Expected: no output.

- [ ] **Step 4: Confirm the example app still builds** (if `just example` is wired up)

Run:
```bash
just example 2>&1 | tail -5
```
Expected: builds and launches. If the example app uses `.onShortcut(someShortcut)` or `.onContinuousShortcut(...)` or `Shortcut(...)` / `ShortcutRecorderView`, it needs the same mechanical migration as the tests (`Shortcut` → `DiscreteShortcut`, `.onShortcut(.discrete(...))`, `.onContinuousShortcut` → `.onShortcut(.continuous(...))`). If `just example` is not wired up or the example is out of scope for this repo's CI, skip this step and note it.

- [ ] **Step 5: Inspect the commit log**

Run:
```bash
git log --oneline
```
Expected (in addition to prior history):
```
feat: add VS Code-style text syntax for Shortcut and DiscreteShortcut
feat: unify onShortcut on the umbrella Shortcut; remove onContinuousShortcut
feat: make ShortcutEventDispatcher public
feat: add public unified ShortcutMatcher
feat: add ContinuousMatcher extracted from OnContinuousShortcutModifier
refactor: extract SequenceMatcher and ShortcutMatchResult from OnShortcutModifier
feat: add umbrella Shortcut enum
refactor: rename Shortcut struct to DiscreteShortcut
```

- [ ] **Step 6: Stop — do not tag**

The release is **not tagged by this plan** (spec §11). Report to the maintainer that 2.1.0 is implementation-complete, all checks green, and ready for them to run the tag step manually.

---

## Done

After Task 9, ShortcutField has:
- `Shortcut` as the umbrella enum; `DiscreteShortcut` as the fire-once struct; `ContinuousShortcut` unchanged.
- A public `ShortcutMatcher` + `ShortcutMatchResult`, backed by internal `SequenceMatcher` / `ContinuousMatcher`.
- A public `ShortcutEventDispatcher`.
- A unified `.onShortcut` taking the umbrella; `.onContinuousShortcut` removed.
- The matching/modifier layer on macOS 13 (`matches(KeyPress)` aside).
- The VS Code-style text syntax with `ExpressibleByStringLiteral`.

The maintainer tags `v2.1.0`. ShortcutKit then bumps its dependency to `from: "2.1.0"` and Phase 1's plan can be written against the shipped API.
