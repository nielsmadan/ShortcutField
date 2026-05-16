# ShortcutField 2.1.0 — Design Spec

| | |
|---|---|
| **Date** | 2026-05-14 |
| **Status** | Approved (brainstorm complete, awaiting plan) |
| **Type** | Breaking redesign. Labeled `2.1.0` (not `3.0.0`) deliberately — ShortcutField has no external adopters yet, so a major bump would be semver theater. |
| **Driver** | Prerequisite for ShortcutKit Phase 1. See `ShortcutKit/docs/superpowers/specs/2026-05-14-shortcutkit-phase1-core.md` §2 and §7. |

## 1. Purpose & scope

ShortcutKit (a separate package) builds a higher-level shortcut-management layer on top of ShortcutField. It needs:

1. ShortcutField's matching API on **macOS 13** (the package floor), not just 14.
2. A **unified "any shortcut" type** and a **reusable matcher** it can drive directly.
3. A **text syntax** for shortcuts (`"cmd+s"`-style strings) for human-editable persistence.

Designing for (2) surfaced a naming problem worth fixing at the root: the type a consumer most wants to name `Shortcut` is the *umbrella* (fire-once **or** continuous), but `Shortcut` is currently the fire-once-only struct. With no external adopters, now is the one cheap moment to fix it.

So this release is a **breaking redesign**: `Shortcut` becomes the umbrella; the fire-once struct is renamed `DiscreteShortcut`.

**In scope:**
- Rename: the fire-once struct `Shortcut` → `DiscreteShortcut` (with all nested types).
- New umbrella `Shortcut` enum: `.discrete(DiscreteShortcut)` / `.continuous(ContinuousShortcut)`.
- macOS 13 backport of the matching layer.
- `ShortcutMatcher` (public, unified) + `ShortcutMatchResult` (public).
- `SequenceMatcher` + `ContinuousMatcher` (internal — `ShortcutMatcher`'s delegates).
- `ShortcutEventDispatcher` made public.
- `.onShortcut` unified to take the umbrella `Shortcut`; `.onContinuousShortcut` removed (subsumed).
- Text syntax: `ascii` / `init(ascii:)` on `Shortcut` and `DiscreteShortcut`; `Shortcut: ExpressibleByStringLiteral`.
- Recorder views + tests updated for the rename.
- Tests for all new surface.

**Out of scope:**
- Tagging the release — the maintainer runs the tag step manually after this ships.
- A unified recorder view (records-discrete-or-continuous in one control) — recorders stay typed to the concrete kind they record. Possible future work.
- Any change to `ContinuousShortcut`'s data model or the recorder *behavior*.

## 2. The naming redesign

| Today | After | Notes |
|---|---|---|
| `Shortcut` (struct, fire-once) | **`DiscreteShortcut`** (struct) | "Discrete" is the literal opposite of "continuous"; ShortcutField's matcher code already uses the term. |
| `Shortcut.Kind` (`.key`/`.mouseButton`/`.scroll`/`.pinchIn`/…) | `DiscreteShortcut.Kind` | |
| `Shortcut.Step` | `DiscreteShortcut.Step` | |
| `Shortcut.ScrollDirection` | `DiscreteShortcut.ScrollDirection` | |
| `Shortcut`'s static helpers (`canonicalModifiers`, thresholds, `isContinuous`, …) | move to `DiscreteShortcut` | |
| `ContinuousShortcut` (struct) | `ContinuousShortcut` — **unchanged** | |
| *(new)* | **`Shortcut`** (enum) | The umbrella. `.discrete(DiscreteShortcut)` / `.continuous(ContinuousShortcut)`. |
| *(new)* | `Shortcut.Kind` (enum) | `.discrete` / `.continuous` — the umbrella's discriminator. |

```swift
public enum Shortcut: Sendable, Hashable, Codable {
    case discrete(DiscreteShortcut)
    case continuous(ContinuousShortcut)

    public enum Kind: Sendable, Hashable {
        case discrete
        case continuous
    }
    public var kind: Kind {
        switch self {
        case .discrete: .discrete
        case .continuous: .continuous
        }
    }
}
```

This is internally consistent: `Shortcut.Kind` means "which kind of shortcut" (discrete vs continuous); `DiscreteShortcut.Kind` means "which kind of discrete input" (key vs mouse vs scroll vs …). Both names read correctly.

**Codable:** `Shortcut` is a discriminated wrapper — a `kind` field plus the inner value, reusing `DiscreteShortcut`'s and `ContinuousShortcut`'s existing wire formats unchanged. `DiscreteShortcut`'s wire format is byte-identical to today's `Shortcut` wire format (only the Swift type name changes), so no data-format migration is needed for anything already persisted as the old `Shortcut`.

## 3. macOS 13 backport

ShortcutField's `Package.swift` already declares `.macOS(.v13)`, but the matching layer is gated `@available(macOS 14.0, *)`. The audit found the **only** genuine macOS-14 dependency is the two-parameter `onChange(of:) { old, new in }` closure form:

- `OnShortcutModifier.swift:280` — `.onChange(of: shortcut) { _, _ in ... }` — doesn't read the values → single-parameter form `{ _ in ... }`.
- `OnContinuousShortcutModifier.swift:28` — `.onChange(of: shortcut) { old, new in ... }` — reads `old` → track the previous value in a new `@State private var previousShortcut`, use the single-parameter form.

Everything else is already macOS 13+: `@State`, `.onAppear`/`.onDisappear`, `NSEvent.addLocalMonitorForEvents`, `Task.sleep(for:)`, the `matches(NSEvent)` primitives.

**Change:** drop `@available(macOS 14.0, *)` from the matching layer and the new types in this spec. **Exception:** the `matches(KeyPress)` extension stays `@available(macOS 14.0, *)` — `KeyPress` is itself a 14+ type. After the rename it lives on `DiscreteShortcut.Step`.

## 4. `ShortcutMatcher` — the unified matcher

```swift
@MainActor
public final class ShortcutMatcher {
    public init(_ shortcut: Shortcut)

    /// Feed an NSEvent. Returns whether it advanced/completed a match.
    public func handle(_ event: NSEvent) -> ShortcutMatchResult

    /// Discard in-progress sequence / throttle state.
    public func reset()
}

public enum ShortcutMatchResult: Sendable, Equatable {
    /// Event did not match.
    case ignored
    /// The event matched but did not complete a fire; consume it per `consumeEvent`.
    /// Two cases produce this:
    /// - Discrete multi-step: an intermediate step matched; the matcher advanced.
    ///   `consumeEvent` is true for focus-intercepted keys (Tab, Escape) so the
    ///   event doesn't also drive focus.
    /// - Continuous: the event matched the gesture but the sensitivity throttle
    ///   suppressed this fire. `consumeEvent` is true so the gesture doesn't also
    ///   reach the view beneath — preserving `.onContinuousShortcut`'s behavior.
    case advanced(consumeEvent: Bool)
    /// Discrete: the full shortcut completed on this event.
    case fired
    /// Continuous: a throttled fire occurred. `magnitude` is this event's signed
    /// delta — scroll `scrollingDeltaY`/`X`, magnify `magnification`, rotate
    /// `rotation` (degrees). Consumers can do magnitude-aware dispatch.
    case continuousFired(magnitude: Double)
}
```

`ShortcutMatcher` is the **public face** of matching. It takes the umbrella `Shortcut` and internally delegates by kind:

- **`.discrete(discreteShortcut)`** → an internal **`SequenceMatcher`** — the existing multi-step state machine (currently the internal type named `ShortcutMatcher`, renamed; see § 8). Handles single and multi-step shortcuts, per-step timeout, Tab/Escape consumption.
- **`.continuous(continuousShortcut)`** → an internal **`ContinuousMatcher`** — the continuous-gesture matching logic currently inline in `OnContinuousShortcutModifier.installMonitor()`, extracted into a standalone unit. It owns a `ThrottleState` seeded with the shortcut's `sensitivity`, applies the existing momentum-skip / phase-end / gesture-burst-suppression rules, and emits `.continuousFired(magnitude:)` per throttled fire.

The throttle lives **inside** the matcher: a `ShortcutMatcher` for a `.continuous` shortcut fully encapsulates that `ContinuousShortcut`'s `sensitivity` semantics. Consumers wanting extra rate control (e.g. ShortcutKit's per-run-loop coalescing) layer it on top of `.continuousFired`.

`SequenceMatcher`, `ContinuousMatcher`, and `ThrottleState` stay **internal** — `ShortcutMatcher` is their public face. The existing internal `ShortcutEventResult` enum is **removed**; `ShortcutMatchResult` is the single result type, returned by `ShortcutMatcher.handle(_:)`, by `ShortcutEventDispatcher`'s handler (§ 5.1), and by the internal matchers (a `SequenceMatcher` never produces `.continuousFired`; a `ContinuousMatcher` produces `.ignored`, `.advanced(consumeEvent: true)` for a matched-but-throttle-suppressed event, or `.continuousFired`).

## 5. `ShortcutEventDispatcher` public; `.onShortcut` unified

### 5.1 `ShortcutEventDispatcher` becomes public

The existing internal `ShortcutEventDispatcher` — the shared, app-wide single `NSEvent` local monitor with handler fan-out — becomes public:

```swift
@MainActor
public final class ShortcutEventDispatcher {
    public static let shared: ShortcutEventDispatcher

    public typealias Handler = (NSEvent) -> ShortcutMatchResult

    /// Register a handler. Handlers are consulted newest-first; the first
    /// result requiring consumption consumes the event.
    public func register(id: UUID, handler: @escaping Handler)
    public func unregister(id: UUID)
}
```

- Monitor installs lazily on first `register`, removes on last `unregister` — unchanged.
- Recording-suppression (events pass through untouched while a recorder field is active) — unchanged.
- **Newest-first consumption**: handlers consulted in reverse registration order; the first returning `.fired`, `.continuousFired`, or `.advanced(consumeEvent: true)` consumes the event. ShortcutKit relies on this ordering for "innermost active context wins."

### 5.2 `.onShortcut` unified; `.onContinuousShortcut` removed

With `Shortcut` as the umbrella, there is **one** modifier:

```swift
public extension View {
    /// Fires `action` when `shortcut` is performed. For `.discrete` shortcuts the
    /// action fires once on completion; for `.continuous` shortcuts it fires
    /// repeatedly, throttled by the shortcut's `sensitivity`.
    func onShortcut(_ shortcut: Shortcut?, perform action: @escaping () -> Void) -> some View
}
```

- Built on `ShortcutMatcher` — single matching path.
- `.discrete` → `action` on `.fired`. `.continuous` → `action` on each `.continuousFired` (the `magnitude` is ignored; the simple modifier's callback is `() -> Void`). Consumers wanting magnitude use `ShortcutMatcher` directly.
- **`.onContinuousShortcut` is removed** — subsumed by `.onShortcut(.continuous(...))`.
- `ShortcutTracking.isActive` (the in-progress-sequence signal) is preserved.

This is a breaking change to the modifier surface: callers of `.onShortcut(someOldShortcut)` now pass `.discrete(...)`, and `.onContinuousShortcut` callers move to `.onShortcut(.continuous(...))`. Mechanical migration.

## 6. Text syntax

A VS Code-style round-trippable text representation. Lives in ShortcutField because it represents ShortcutField's own types, and `ExpressibleByStringLiteral` conformance must live with the type.

```swift
public extension Shortcut {
    init(ascii: String) throws        // produces the umbrella (.discrete or .continuous per resolution rule)
    var ascii: String { get }
}

public extension DiscreteShortcut {
    init(ascii: String) throws        // always a DiscreteShortcut; a `@N` suffix throws
    var ascii: String { get }
}

extension Shortcut: ExpressibleByStringLiteral {
    // `"cmd+s"` is a Shortcut anywhere one is expected.
}

public enum ShortcutParsingError: Error, Equatable {
    case empty
    case unknownModifier(String)
    case unknownKey(String)
    case unknownGesture(String)
    case malformedSensitivity(String)
    case sensitivityOnDiscrete
    case emptyStep
}
```

### 6.1 Grammar

| Form | Example | Result |
|---|---|---|
| Modifier + key | `cmd+s` | ⌘S |
| Multiple modifiers | `cmd+shift+a` | ⇧⌘A |
| Multi-step (space-separated) | `cmd+k cmd+c` | ⌘K ⌘C |
| Mouse | `ctrl+right-click` | ⌃Right Click |
| Scroll | `shift+scroll-up` | ⇧Scroll Up |
| Gesture | `cmd+pinch-in` | ⌘Pinch In |
| Continuous w/ sensitivity | `cmd+pinch-out @0.5` | ⌘Pinch Out, sensitivity 0.5 |

- **Modifiers**: `cmd`, `ctrl`, `opt`, `shift` — lowercase, order-insensitive, joined with `+`.
- **Keys**: `a`–`z`, `0`–`9`, `tab`, `return`, `escape`, `space`, `delete`, `up`/`down`/`left`/`right`, `home`/`end`/`pageup`/`pagedown`, `f1`–`f12` — the set `DiscreteShortcut.Step`'s key-mapping table supports, plus letter/number keys via layout-aware mapping.
- **Mouse**: `left-click`, `right-click`, `middle-click`, `button4`, `button5`.
- **Scroll**: `scroll-up`, `scroll-down`, `scroll-left`, `scroll-right`.
- **Gestures**: `pinch-in`, `pinch-out`, `rotate-clockwise`, `rotate-counterclockwise`, `smart-magnify`.
- **Steps** are space-separated: `cmd+k cmd+c`.
- **Sensitivity suffix**: ` @N` where `N` parses as a `Double` in `0.0...1.0`. Valid only when the (single, bare) step is a continuous-capable gesture kind. Omitted → default sensitivity (`0.0`).

### 6.2 Discrete vs continuous resolution

`scroll` / `pinch-*` / `rotate-*` kinds exist in both `DiscreteShortcut.Kind` and `ContinuousShortcut.Kind`, so a bare gesture string is ambiguous. Resolution for `Shortcut(ascii:)` and the string literal:

- Multi-step (contains a space), or a key / mouse / `smart-magnify` step → `.discrete`.
- A single bare gesture kind (`scroll-*`, `pinch-*`, `rotate-*`) → `.continuous` with the `@N` sensitivity if given, else default. This is the overwhelmingly common intent.
- The rare discrete gesture binding uses the explicit `.discrete(DiscreteShortcut(...))` API.

`DiscreteShortcut(ascii:)` always produces a `DiscreteShortcut` — a bare gesture string parses as a discrete gesture step, and a ` @N` suffix throws `ShortcutParsingError.sensitivityOnDiscrete`.

### 6.3 Failure handling

- **`ExpressibleByStringLiteral`** cannot throw. A string *literal* is a compile-time constant; a malformed literal triggers `fatalError` with a descriptive message — caught immediately on first run during development, the same risk profile as `URL(string:)!`.
- The throwing **`init(ascii:)`** is for *runtime* strings (config-file parsing, command palettes) where input genuinely might be invalid.
- **Round-trip guarantee**: `try Shortcut(ascii: s.ascii) == s` for any `Shortcut`; `try DiscreteShortcut(ascii: d.ascii) == d` for any `DiscreteShortcut`. Continuous shortcuts round-trip including the `@N` sensitivity.

A compile-time-validating `#shortcut("cmd+s")` macro is a possible future hardening — explicitly **not** in this release.

## 7. Recorder views + other rename ripple

- `ShortcutRecorderView` / `ShortcutRecorderField` record discrete input → stay typed to **`DiscreteShortcut`**. `ShortcutRecorderView($discreteShortcut)` where the binding is `DiscreteShortcut?`. Behavior unchanged; only the type name changes.
- `ContinuousShortcutRecorderView` / `ContinuousShortcutRecorderField` → unchanged (`ContinuousShortcut`).
- `Shortcut.displayString` → `DiscreteShortcut.displayString`. The umbrella `Shortcut` gains a `displayString` that forwards to the inner value's, so consumers with a `Shortcut` can display it directly.
- `OnContinuousShortcutModifier.swift` → folded into the unified `.onShortcut` path; the file may be removed or repurposed for `ContinuousMatcher`.
- All internal references (`Shortcut+Matching.swift`, `Shortcut+DisplayString.swift`, `Shortcut+KeyMapping.swift`, `GestureAccumulator`, the recorder fields) update to `DiscreteShortcut`. Extension filenames rename to `DiscreteShortcut+Matching.swift` etc.

## 8. Internal matcher rename

The existing internal type named `ShortcutMatcher` (the single-shortcut multi-step state machine in `OnShortcutModifier.swift`) is renamed **`SequenceMatcher`** — it matches a `DiscreteShortcut`, which is a sequence of steps. This frees `ShortcutMatcher` for the public unified matcher (§ 4). Internal rename → no external API impact beyond what § 4 already introduces.

## 9. File structure

Indicative — the implementation plan finalizes exact boundaries.

```
Sources/ShortcutField/
  DiscreteShortcut.swift               ← renamed from Shortcut.swift
  DiscreteShortcut+Matching.swift      ← renamed from Shortcut+Matching.swift
  DiscreteShortcut+DisplayString.swift ← renamed from Shortcut+DisplayString.swift
  DiscreteShortcut+KeyMapping.swift    ← renamed from Shortcut+KeyMapping.swift
  ContinuousShortcut.swift             (unchanged)
  Shortcut.swift                       ← new: the umbrella enum + Shortcut.Kind + Codable + displayString
  Matching/
    ShortcutMatcher.swift              ← new: public unified matcher + ShortcutMatchResult
    SequenceMatcher.swift              ← renamed internal matcher (was in OnShortcutModifier.swift)
    ContinuousMatcher.swift            ← new: extracted from OnContinuousShortcutModifier
    ShortcutEventDispatcher.swift      ← made public; moved out of OnShortcutModifier.swift
  ThrottleState.swift                  (unchanged, internal)
  GestureAccumulator.swift             (unchanged, internal)
  OnShortcutModifier.swift             ← unified .onShortcut on ShortcutMatcher; macOS 13
  Syntax/
    ShortcutASCII.swift                ← new: ascii / init(ascii:) / ExpressibleByStringLiteral / ShortcutParsingError
  ShortcutRecorderView.swift           ← DiscreteShortcut-typed
  ShortcutRecorderField.swift          ← DiscreteShortcut-typed
  ContinuousShortcutRecorderView.swift (unchanged)
  ContinuousShortcutRecorderField.swift (unchanged)
  ContinuousShortcutRecorderField+Menu.swift (unchanged)
  SensitivityMode.swift                (unchanged)
  SensitivitySliderRepresentable.swift (unchanged)
```

`OnContinuousShortcutModifier.swift` is removed (its matching logic → `ContinuousMatcher.swift`, its modifier → unified `.onShortcut`).

## 10. Testing

Swift Testing (`@Test`, `#expect`), files mirroring source types.

**Renamed test files** (track the source rename): `ShortcutTests` → `DiscreteShortcutTests`, `ShortcutMatchingTests` → `DiscreteShortcutMatchingTests`, `ShortcutDisplayStringTests` → `DiscreteShortcutDisplayStringTests`, `ShortcutKeyMappingTests` → `DiscreteShortcutKeyMappingTests`. Recorder-field tests update type references.

**New test files:**
- `ShortcutTests` — the umbrella enum: `kind`, `displayString` forwarding, `Codable` round-trip for both cases.
- `ShortcutMatcherTests` — discrete single + multi-step + Tab/Escape consumption; continuous throttled fire + `magnitude` extraction. Uses the existing `GestureEventShape` test seam for gesture events.
- `ContinuousMatcherTests` — the extracted continuous matcher in isolation: momentum-skip, phase-end reset, gesture-burst suppression, sensitivity throttle.
- `ShortcutASCIITests` — grammar round-trip for every form; discrete-vs-continuous resolution; `@N` parsing; every `ShortcutParsingError` case; `ExpressibleByStringLiteral` happy path.

**Regression bar:** the unified `.onShortcut` must preserve the observable behavior of the old `.onShortcut` (for discrete) and `.onContinuousShortcut` (for continuous). The existing matching/recorder suites — renamed and retyped — are the safety net.

**CI:** add a macOS-13 build/test lane if the GitHub runner images support it; otherwise the existing `macos-26` lane still exercises the backported source (the `@available` removal is source-level).

## 11. Release

The implementation plan does **not** tag the release. When the work is complete, tests green, and behavior preserved, the maintainer cuts `v2.1.0` manually. ShortcutKit then sets its dependency to `from: "2.1.0"`.

Note: this is a breaking change shipped under a minor version number — a deliberate choice given zero external adopters (§ Type, top of doc). The maintainer should be aware `from: "2.1.0"` in ShortcutKit's manifest will, by SPM semantics, also accept hypothetical future `2.x` releases as non-breaking; with a single first-party consumer this is acceptable.

## 12. Downstream ripple

This rename ripples into two places outside ShortcutField:

1. **The ShortcutKit Phase 1 spec** (`2026-05-14-shortcutkit-phase1-core.md`) currently uses `ShortcutBinding` / `ShortcutBindingKind` for the umbrella. Those become `Shortcut` / `Shortcut.Kind`; `defaultBinding` → `defaultShortcut`; `RawState.overrides` value type changes; `BindingMatcher` references → `ShortcutMatcher`. That spec must be updated before its plan is written.
2. **The maintainer's existing app(s)** that depend on ShortcutField — mechanical migration (`Shortcut` → `DiscreteShortcut`, `.onContinuousShortcut` → `.onShortcut(.continuous(...))`).

## 13. Approval

| Item | Status |
|---|---|
| Brainstorm | Approved |
| Spec self-review | Pending |
| User review of written spec | Pending |
| Transition to writing-plans | Pending |
