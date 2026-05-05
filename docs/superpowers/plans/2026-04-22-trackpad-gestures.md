# Trackpad Gestures Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a `TrackpadGesture` peer type to `Shortcut` and `MouseInput` so users can record and bind macOS-recognized trackpad gestures (pinch, rotate, 3/4-finger swipe, smart magnify) as in-app shortcuts.

**Architecture:** New peer model with parallel recorder field, SwiftUI view, and view modifier — mirroring the existing `MouseInput` family. Continuous gestures (pinch, rotate) reuse the existing throttle/sensitivity machinery (renamed from scroll-specific to general-purpose). Discrete gestures (swipe, smart magnify) fire once per `NSEvent`. The recorder field offers two paths to the same value: live recording (default) or a chevron-button menu picker listing all 13 gestures.

**Tech Stack:** Swift 6.2, AppKit, SwiftUI, Carbon.HIToolbox (for key codes), Swift Testing framework.

**Spec:** `docs/superpowers/specs/2026-04-22-trackpad-gestures-design.md`

---

## File Structure

New files (`Sources/ShortcutField/`):
- `TrackpadGesture.swift` — model + Codable
- `TrackpadGesture+Matching.swift` — `matches(NSEvent)`, sign/threshold helpers
- `TrackpadGesture+DisplayString.swift` — display strings
- `TrackpadGestureRecorderField.swift` — AppKit recorder (NSSearchField subclass)
- `TrackpadGestureRecorderView.swift` — SwiftUI NSViewRepresentable wrapper
- `OnTrackpadGestureModifier.swift` — `.onTrackpadGesture()` view modifier

Renamed (`Sources/ShortcutField/`):
- `ScrollSensitivityMode.swift` → `SensitivityMode.swift` (also renames the two enums and updates the `discreteIndex` static method's containing type).

Modified (`Sources/ShortcutField/`):
- `OnMouseInputModifier.swift` — rename `ScrollThrottleState` → `ThrottleState`.
- `MouseInputRecorderField.swift` — update enum references (`SensitivityMode`, `SensitivityPosition`).
- `MouseInputRecorderView.swift` — update enum references and modifier signatures.

Modified (`Tests/ShortcutFieldTests/`):
- `MouseInputTests.swift` — update enum references (`ScrollSensitivityMode` → `SensitivityMode`, `ScrollThrottleState` → `ThrottleState`).
- New: `TrackpadGestureTests.swift` — model/Codable/Equatable tests.
- New: `TrackpadGestureMatchingTests.swift` — matching tests.
- New: `TrackpadGestureDisplayStringTests.swift` — display string tests.
- New: `TrackpadGestureRecorderFieldTests.swift` — recorder behavior tests.

Modified (`Example/ShortcutFieldExample/`):
- `ContentView.swift` — add Trackpad Gesture section to Workbench and Gallery tabs.

Modified (root):
- `README.md` — document `TrackpadGesture`, recorder, modifier, sensitivity rename, finger-count caveat.
- `CLAUDE.md` — add new files to source structure list.

---

## Constants Used Throughout

These thresholds will be defined as `static let` on `TrackpadGesture` and shared between matcher and recorder. Defined once here for reference:

```swift
extension TrackpadGesture {
    /// Per-event minimum |magnification| to count a `.magnify` event as directional.
    static let magnifyEventThreshold: Double = 0.005
    /// Per-event minimum |rotation| (degrees) to count a `.rotate` event as directional.
    static let rotateEventThreshold: Double = 0.5
    /// Cumulative |magnification| during a single gesture before the recorder finalizes.
    static let magnifyRecordingThreshold: Double = 0.05
    /// Cumulative |rotation| (degrees) during a single gesture before the recorder finalizes.
    static let rotateRecordingThreshold: Double = 3.0
}
```

These get exercised in tests; specific numeric values may be tuned during manual testing in the Example app.

---

## Task 0: Rename `ScrollSensitivityMode` → `SensitivityMode` and `ScrollThrottleState` → `ThrottleState`

**Why first:** Mechanical rename touching public API and the throttle class. Doing it before adding new code means subsequent tasks reference the final names.

**Files:**
- Modify: `Sources/ShortcutField/ScrollSensitivityMode.swift` → rename file to `SensitivityMode.swift`
- Modify: `Sources/ShortcutField/MouseInputRecorderField.swift`
- Modify: `Sources/ShortcutField/MouseInputRecorderView.swift`
- Modify: `Sources/ShortcutField/OnMouseInputModifier.swift`
- Modify: `Tests/ShortcutFieldTests/MouseInputTests.swift`
- Modify: `Example/ShortcutFieldExample/ContentView.swift`

- [ ] **Step 1: Rename the file and types in `SensitivityMode.swift`**

Rename `Sources/ShortcutField/ScrollSensitivityMode.swift` to `Sources/ShortcutField/SensitivityMode.swift` and update its contents:

```swift
import Foundation

/// Controls how the sensitivity slider/stepper is presented in a recorder UI
/// (used by both `MouseInputRecorderView` for scroll inputs and
/// `TrackpadGestureRecorderView` for continuous gestures).
public enum SensitivityMode: Sendable, Hashable {
    /// User adjusts sensitivity via a slider that snaps to 5 discrete tick marks (default).
    /// Maps to values: 0.0, 0.25, 0.5, 0.75, 1.0.
    case discrete
    /// User adjusts sensitivity via a continuous 0.0-1.0 slider.
    case continuous
    /// Sensitivity UI is hidden. The developer sets sensitivity programmatically
    /// via the binding's value.
    case hidden

    /// The five discrete tick-mark values.
    static let discreteValues: [Double] = [0.0, 0.25, 0.5, 0.75, 1.0]

    /// Returns the discrete tick-mark index (0-4) closest to the given sensitivity value.
    static func discreteIndex(for sensitivity: Double) -> Int {
        let clamped = min(1.0, max(0.0, sensitivity))
        var bestIndex = 0
        var bestDist = Double.greatestFiniteMagnitude
        for (i, val) in discreteValues.enumerated() {
            let dist = abs(val - clamped)
            if dist < bestDist {
                bestDist = dist
                bestIndex = i
            }
        }
        return bestIndex
    }
}

/// Where the sensitivity control appears relative to the recorder field.
public enum SensitivityPosition: Sendable, Hashable {
    /// Control appears below the field (default).
    case below
    /// Control appears to the left of the field.
    case left
    /// Control appears to the right of the field.
    case right
}
```

Per project memory, the user handles git themselves — do NOT run `git mv` or any other `git` command. Instead, use the `Write` tool to create `Sources/ShortcutField/SensitivityMode.swift` with the new contents, then delete the old `Sources/ShortcutField/ScrollSensitivityMode.swift` via `rm` (file-system only). The user will sort out the git history during commit.

- [ ] **Step 2: Rename `ScrollThrottleState` → `ThrottleState` in `OnMouseInputModifier.swift`**

In `Sources/ShortcutField/OnMouseInputModifier.swift`, replace `ScrollThrottleState` with `ThrottleState` everywhere (the class definition, the `@State private var throttleState` usage, the `Self.handleScroll(throttle:)` call site). Also rename the helper function to a more general name:

```swift
struct ThrottleDecision: Equatable {
    var shouldFire: Bool
    var rearmAfter: Duration?
}

@MainActor
final class ThrottleState {
    var sensitivity: Double = 0.0
    var lastFireInstant: ContinuousClock.Instant?
    var suppressed = false
    var rearmWorkItem: DispatchWorkItem?

    func reset() {
        lastFireInstant = nil
        suppressed = false
        rearmWorkItem?.cancel()
        rearmWorkItem = nil
    }

    nonisolated static func cooldownSeconds(for sensitivity: Double) -> Double {
        max(0, (1.0 - sensitivity) / 0.75)
    }

    static func evaluate(
        state: ThrottleState,
        now: ContinuousClock.Instant
    ) -> ThrottleDecision {
        // ... existing body, with ScrollThrottleDecision -> ThrottleDecision
    }
}
```

Inside `OnMouseInputModifier`, rename `Self.handleScroll(throttle:action:)` to `Self.handleThrottled(throttle:action:)` (still scroll-specific in usage but generically named). Update all call sites in the file.

- [ ] **Step 3: Update enum references in `MouseInputRecorderField.swift` and `MouseInputRecorderView.swift`**

Replace every occurrence of `ScrollSensitivityMode` with `SensitivityMode` and `ScrollSensitivityPosition` with `SensitivityPosition`.

- [ ] **Step 4: Update `MouseInputTests.swift`**

Replace `ScrollSensitivityMode` with `SensitivityMode` and `ScrollThrottleState` with `ThrottleState` in the test file.

- [ ] **Step 5: Update `Example/ShortcutFieldExample/ContentView.swift`**

Replace `ScrollSensitivityMode` with `SensitivityMode` and `ScrollSensitivityPosition` with `SensitivityPosition` (state variable types, picker bindings, etc.).

- [ ] **Step 6: Build and run tests**

```bash
just build
just test
just lint
```

Expected: All build, lint, and tests pass with renames in place.

- [ ] **Step 7: Commit**

User handles commits — pause and report:

> Renames complete. `ScrollSensitivityMode` → `SensitivityMode`, `ScrollSensitivityPosition` → `SensitivityPosition`, `ScrollThrottleState` → `ThrottleState`. Tests pass.

---

## Task 1: `TrackpadGesture` model

**Files:**
- Create: `Sources/ShortcutField/TrackpadGesture.swift`
- Create: `Tests/ShortcutFieldTests/TrackpadGestureTests.swift`

- [ ] **Step 1: Write failing tests for the model**

Create `Tests/ShortcutFieldTests/TrackpadGestureTests.swift`:

```swift
import AppKit
import Foundation
@testable import ShortcutField
import Testing

struct TrackpadGestureTests {
    // MARK: - Init / clamping

    @Test func init_storesKindAndModifiers() {
        let g = TrackpadGesture(kind: .pinchIn, modifiers: [.command, .shift])
        #expect(g.kind == .pinchIn)
        #expect(g.modifiers.contains(.command))
        #expect(g.modifiers.contains(.shift))
    }

    @Test func init_masksUnsupportedModifiers() {
        let g = TrackpadGesture(kind: .pinchIn, modifiers: [.command, .capsLock, .function])
        #expect(g.modifiers == .command)
    }

    @Test func sensitivity_defaultsToZero() {
        let g = TrackpadGesture(kind: .pinchIn, modifiers: [])
        #expect(g.sensitivity == 0.0)
    }

    @Test func sensitivity_clampsAboveOne() {
        let g = TrackpadGesture(kind: .pinchIn, modifiers: [], sensitivity: 1.5)
        #expect(g.sensitivity == 1.0)
    }

    @Test func sensitivity_clampsBelowZero() {
        let g = TrackpadGesture(kind: .pinchIn, modifiers: [], sensitivity: -0.5)
        #expect(g.sensitivity == 0.0)
    }

    @Test func sensitivity_preservesValidValueForContinuousKinds() {
        let kinds: [TrackpadGesture.Kind] = [
            .pinchIn, .pinchOut, .rotateClockwise, .rotateCounterClockwise,
        ]
        for kind in kinds {
            let g = TrackpadGesture(kind: kind, modifiers: [], sensitivity: 0.5)
            #expect(g.sensitivity == 0.5)
        }
    }

    @Test func sensitivity_forcedZeroForDiscreteKinds() {
        let kinds: [TrackpadGesture.Kind] = [
            .swipe(fingers: 3, direction: .up),
            .swipe(fingers: 4, direction: .left),
            .smartMagnify,
        ]
        for kind in kinds {
            let g = TrackpadGesture(kind: kind, modifiers: [], sensitivity: 0.7)
            #expect(g.sensitivity == 0.0)
        }
    }

    @Test func swipe_fingersClampedToValidRange() {
        let two = TrackpadGesture(kind: .swipe(fingers: 2, direction: .up), modifiers: [])
        let five = TrackpadGesture(kind: .swipe(fingers: 5, direction: .up), modifiers: [])
        if case let .swipe(fingers, _) = two.kind { #expect(fingers == 3) }
        if case let .swipe(fingers, _) = five.kind { #expect(fingers == 3) }
    }

    @Test func swipe_fingersThreeOrFourPreserved() {
        let three = TrackpadGesture(kind: .swipe(fingers: 3, direction: .right), modifiers: [])
        let four = TrackpadGesture(kind: .swipe(fingers: 4, direction: .down), modifiers: [])
        if case let .swipe(fingers, _) = three.kind { #expect(fingers == 3) }
        if case let .swipe(fingers, _) = four.kind { #expect(fingers == 4) }
    }

    // MARK: - Equatable

    @Test func equatable_sameKindAndModifiers_equal() {
        let a = TrackpadGesture(kind: .pinchIn, modifiers: .command)
        let b = TrackpadGesture(kind: .pinchIn, modifiers: .command)
        #expect(a == b)
    }

    @Test func equatable_differentKind_notEqual() {
        let a = TrackpadGesture(kind: .pinchIn, modifiers: [])
        let b = TrackpadGesture(kind: .pinchOut, modifiers: [])
        #expect(a != b)
    }

    @Test func equatable_differentModifiers_notEqual() {
        let a = TrackpadGesture(kind: .pinchIn, modifiers: .command)
        let b = TrackpadGesture(kind: .pinchIn, modifiers: .shift)
        #expect(a != b)
    }

    @Test func equatable_differentSensitivity_notEqual() {
        let a = TrackpadGesture(kind: .pinchIn, modifiers: [], sensitivity: 0.0)
        let b = TrackpadGesture(kind: .pinchIn, modifiers: [], sensitivity: 0.5)
        #expect(a != b)
    }

    @Test func equatable_differentSwipeFingers_notEqual() {
        let a = TrackpadGesture(kind: .swipe(fingers: 3, direction: .up), modifiers: [])
        let b = TrackpadGesture(kind: .swipe(fingers: 4, direction: .up), modifiers: [])
        #expect(a != b)
    }

    @Test func equatable_differentSwipeDirection_notEqual() {
        let a = TrackpadGesture(kind: .swipe(fingers: 3, direction: .up), modifiers: [])
        let b = TrackpadGesture(kind: .swipe(fingers: 3, direction: .down), modifiers: [])
        #expect(a != b)
    }

    // MARK: - Codable round-trip

    @Test func codable_roundtripPinch() throws {
        let g = TrackpadGesture(kind: .pinchIn, modifiers: .command, sensitivity: 0.5)
        let data = try JSONEncoder().encode(g)
        let decoded = try JSONDecoder().decode(TrackpadGesture.self, from: data)
        #expect(decoded == g)
    }

    @Test func codable_roundtripRotate() throws {
        let g = TrackpadGesture(kind: .rotateCounterClockwise, modifiers: .shift, sensitivity: 0.75)
        let data = try JSONEncoder().encode(g)
        let decoded = try JSONDecoder().decode(TrackpadGesture.self, from: data)
        #expect(decoded == g)
    }

    @Test func codable_roundtripSwipe3Finger() throws {
        let g = TrackpadGesture(kind: .swipe(fingers: 3, direction: .left), modifiers: .option)
        let data = try JSONEncoder().encode(g)
        let decoded = try JSONDecoder().decode(TrackpadGesture.self, from: data)
        #expect(decoded == g)
    }

    @Test func codable_roundtripSwipe4Finger() throws {
        let g = TrackpadGesture(kind: .swipe(fingers: 4, direction: .right), modifiers: [])
        let data = try JSONEncoder().encode(g)
        let decoded = try JSONDecoder().decode(TrackpadGesture.self, from: data)
        #expect(decoded == g)
    }

    @Test func codable_roundtripSmartMagnify() throws {
        let g = TrackpadGesture(kind: .smartMagnify, modifiers: .control)
        let data = try JSONEncoder().encode(g)
        let decoded = try JSONDecoder().decode(TrackpadGesture.self, from: data)
        #expect(decoded == g)
    }

    @Test func codable_backwardCompat_missingSensitivity() throws {
        let json = """
        {"type":"pinchIn","modifiers":1048576}
        """
        let data = Data(json.utf8)
        let decoded = try JSONDecoder().decode(TrackpadGesture.self, from: data)
        #expect(decoded.kind == .pinchIn)
        #expect(decoded.sensitivity == 0.0)
    }

    @Test func codable_clampsSensitivityOnDecode() throws {
        let json = """
        {"type":"pinchIn","modifiers":0,"sensitivity":5.0}
        """
        let data = Data(json.utf8)
        let decoded = try JSONDecoder().decode(TrackpadGesture.self, from: data)
        #expect(decoded.sensitivity == 1.0)
    }

    @Test func codable_swipeRequiresFingersAndDirection() throws {
        let json = """
        {"type":"swipe","fingers":3,"direction":"up","modifiers":0}
        """
        let data = Data(json.utf8)
        let decoded = try JSONDecoder().decode(TrackpadGesture.self, from: data)
        #expect(decoded.kind == .swipe(fingers: 3, direction: .up))
    }

    @Test func codable_unknownTypeThrows() {
        let json = """
        {"type":"something_else","modifiers":0}
        """
        let data = Data(json.utf8)
        #expect(throws: DecodingError.self) {
            _ = try JSONDecoder().decode(TrackpadGesture.self, from: data)
        }
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
just test 2>&1 | tail -40
```

Expected: build error — `TrackpadGesture` not defined.

- [ ] **Step 3: Implement `TrackpadGesture.swift`**

Create `Sources/ShortcutField/TrackpadGesture.swift`:

```swift
import AppKit

/// A trackpad gesture defined by a gesture kind and modifier flags.
///
/// Supported kinds are the system-recognized gestures macOS delivers as discrete
/// `NSEvent` types: pinch (in / out), rotate (clockwise / counter-clockwise),
/// 3- or 4-finger swipe (up / down / left / right), and smart magnify.
public struct TrackpadGesture: Sendable, Equatable {
    /// The kind of trackpad gesture.
    public enum Kind: Sendable, Equatable {
        case pinchIn
        case pinchOut
        case rotateClockwise
        case rotateCounterClockwise
        /// A swipe with `fingers` fingers (3 or 4) in `direction`.
        case swipe(fingers: Int, direction: SwipeDirection)
        case smartMagnify
    }

    /// A discrete swipe direction.
    public enum SwipeDirection: String, Sendable, Equatable, Codable {
        case up, down, left, right
    }

    /// The kind of gesture.
    public let kind: Kind

    /// The modifier flags (Command, Shift, Option, Control). Other flags are masked off in `init`.
    public let modifiers: NSEvent.ModifierFlags

    /// Sensitivity from 0.0 (fire once per gesture) to 1.0 (fire on every event).
    /// Only meaningful for continuous gestures (pinch, rotate); forced to 0.0 for
    /// discrete gestures (swipe, smart magnify).
    public let sensitivity: Double

    public init(kind: Kind, modifiers: NSEvent.ModifierFlags, sensitivity: Double = 0.0) {
        self.kind = Self.normalizeKind(kind)
        self.modifiers = modifiers.intersection([.shift, .control, .option, .command])
        if Self.isContinuous(self.kind) {
            self.sensitivity = min(1.0, max(0.0, sensitivity))
        } else {
            self.sensitivity = 0.0
        }
    }

    static func normalizeKind(_ kind: Kind) -> Kind {
        if case let .swipe(fingers, direction) = kind {
            let clamped = (fingers == 3 || fingers == 4) ? fingers : 3
            return .swipe(fingers: clamped, direction: direction)
        }
        return kind
    }

    static func isContinuous(_ kind: Kind) -> Bool {
        switch kind {
        case .pinchIn, .pinchOut, .rotateClockwise, .rotateCounterClockwise:
            return true
        case .swipe, .smartMagnify:
            return false
        }
    }

    // MARK: - Thresholds (shared between matcher and recorder)

    /// Per-event minimum |magnification| to count a `.magnify` event as directional.
    static let magnifyEventThreshold: Double = 0.005
    /// Per-event minimum |rotation| (degrees) to count a `.rotate` event as directional.
    static let rotateEventThreshold: Double = 0.5
    /// Cumulative |magnification| during a single gesture before the recorder finalizes.
    static let magnifyRecordingThreshold: Double = 0.05
    /// Cumulative |rotation| (degrees) during a single gesture before the recorder finalizes.
    static let rotateRecordingThreshold: Double = 3.0
}

// MARK: - Codable

extension TrackpadGesture: Codable {
    enum CodingKeys: String, CodingKey {
        case type
        case fingers
        case direction
        case modifiers
        case sensitivity
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)

        let decodedKind: Kind
        switch type {
        case "pinchIn": decodedKind = .pinchIn
        case "pinchOut": decodedKind = .pinchOut
        case "rotateClockwise": decodedKind = .rotateClockwise
        case "rotateCounterClockwise": decodedKind = .rotateCounterClockwise
        case "smartMagnify": decodedKind = .smartMagnify
        case "swipe":
            let fingers = try container.decode(Int.self, forKey: .fingers)
            let direction = try container.decode(SwipeDirection.self, forKey: .direction)
            decodedKind = .swipe(fingers: fingers, direction: direction)
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .type,
                in: container,
                debugDescription: "Unknown trackpad gesture type: \(type)"
            )
        }
        kind = Self.normalizeKind(decodedKind)

        let rawModifiers = try container.decode(UInt.self, forKey: .modifiers)
        modifiers = NSEvent.ModifierFlags(rawValue: rawModifiers)
            .intersection([.shift, .control, .option, .command])

        if Self.isContinuous(kind) {
            sensitivity = try min(
                1.0,
                max(0.0,
                    container.decodeIfPresent(Double.self, forKey: .sensitivity) ?? 0.0)
            )
        } else {
            sensitivity = 0.0
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(modifiers.rawValue, forKey: .modifiers)
        if Self.isContinuous(kind) {
            try container.encode(sensitivity, forKey: .sensitivity)
        }

        switch kind {
        case .pinchIn:
            try container.encode("pinchIn", forKey: .type)
        case .pinchOut:
            try container.encode("pinchOut", forKey: .type)
        case .rotateClockwise:
            try container.encode("rotateClockwise", forKey: .type)
        case .rotateCounterClockwise:
            try container.encode("rotateCounterClockwise", forKey: .type)
        case .smartMagnify:
            try container.encode("smartMagnify", forKey: .type)
        case let .swipe(fingers, direction):
            try container.encode("swipe", forKey: .type)
            try container.encode(fingers, forKey: .fingers)
            try container.encode(direction, forKey: .direction)
        }
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
just test 2>&1 | tail -20
```

Expected: all `TrackpadGestureTests` pass.

- [ ] **Step 5: Lint**

```bash
just lint
```

Expected: no violations. If any, run `just lint-fix` and re-run.

- [ ] **Step 6: Commit**

User handles commits — pause and report:

> `TrackpadGesture` model added with init clamping, Codable, Equatable. Tests pass.

---

## Task 2: `TrackpadGesture+DisplayString`

**Files:**
- Create: `Sources/ShortcutField/TrackpadGesture+DisplayString.swift`
- Create: `Tests/ShortcutFieldTests/TrackpadGestureDisplayStringTests.swift`

- [ ] **Step 1: Write failing tests**

Create `Tests/ShortcutFieldTests/TrackpadGestureDisplayStringTests.swift`:

```swift
import AppKit
@testable import ShortcutField
import Testing

struct TrackpadGestureDisplayStringTests {
    @Test func pinchIn_noModifiers() {
        let g = TrackpadGesture(kind: .pinchIn, modifiers: [])
        #expect(g.displayString == "Pinch In")
    }

    @Test func pinchOut_noModifiers() {
        let g = TrackpadGesture(kind: .pinchOut, modifiers: [])
        #expect(g.displayString == "Pinch Out")
    }

    @Test func rotateClockwise_noModifiers() {
        let g = TrackpadGesture(kind: .rotateClockwise, modifiers: [])
        #expect(g.displayString == "Rotate CW")
    }

    @Test func rotateCounterClockwise_noModifiers() {
        let g = TrackpadGesture(kind: .rotateCounterClockwise, modifiers: [])
        #expect(g.displayString == "Rotate CCW")
    }

    @Test func swipe3FingerUp() {
        let g = TrackpadGesture(kind: .swipe(fingers: 3, direction: .up), modifiers: [])
        #expect(g.displayString == "3-Finger Swipe ↑")
    }

    @Test func swipe3FingerDown() {
        let g = TrackpadGesture(kind: .swipe(fingers: 3, direction: .down), modifiers: [])
        #expect(g.displayString == "3-Finger Swipe ↓")
    }

    @Test func swipe3FingerLeft() {
        let g = TrackpadGesture(kind: .swipe(fingers: 3, direction: .left), modifiers: [])
        #expect(g.displayString == "3-Finger Swipe ←")
    }

    @Test func swipe3FingerRight() {
        let g = TrackpadGesture(kind: .swipe(fingers: 3, direction: .right), modifiers: [])
        #expect(g.displayString == "3-Finger Swipe →")
    }

    @Test func swipe4FingerUp() {
        let g = TrackpadGesture(kind: .swipe(fingers: 4, direction: .up), modifiers: [])
        #expect(g.displayString == "4-Finger Swipe ↑")
    }

    @Test func smartMagnify_noModifiers() {
        let g = TrackpadGesture(kind: .smartMagnify, modifiers: [])
        #expect(g.displayString == "Smart Magnify")
    }

    @Test func pinchIn_withCommand() {
        let g = TrackpadGesture(kind: .pinchIn, modifiers: .command)
        #expect(g.displayString == "⌘Pinch In")
    }

    @Test func swipe3Up_withShift() {
        let g = TrackpadGesture(kind: .swipe(fingers: 3, direction: .up), modifiers: .shift)
        #expect(g.displayString == "⇧3-Finger Swipe ↑")
    }

    @Test func smartMagnify_withControlOption() {
        let g = TrackpadGesture(kind: .smartMagnify, modifiers: [.control, .option])
        // Order in `symbolicRepresentation` follows Apple convention: ⌃ ⌥ ⇧ ⌘
        #expect(g.displayString == "⌃⌥Smart Magnify")
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
just test 2>&1 | tail -20
```

Expected: build error — `displayString` not defined on `TrackpadGesture`.

- [ ] **Step 3: Implement display strings**

Create `Sources/ShortcutField/TrackpadGesture+DisplayString.swift`:

```swift
import AppKit

public extension TrackpadGesture {
    /// Human-readable representation, e.g. "⌃Pinch In", "⇧3-Finger Swipe ↑".
    var displayString: String {
        modifiers.symbolicRepresentation + kindDisplayString
    }

    private var kindDisplayString: String {
        switch kind {
        case .pinchIn: "Pinch In"
        case .pinchOut: "Pinch Out"
        case .rotateClockwise: "Rotate CW"
        case .rotateCounterClockwise: "Rotate CCW"
        case .smartMagnify: "Smart Magnify"
        case let .swipe(fingers, direction):
            "\(fingers)-Finger Swipe \(directionArrow(direction))"
        }
    }

    private func directionArrow(_ direction: SwipeDirection) -> String {
        switch direction {
        case .up: "↑"
        case .down: "↓"
        case .left: "←"
        case .right: "→"
        }
    }
}
```

The `modifiers.symbolicRepresentation` extension already exists on `NSEvent.ModifierFlags` (used by `MouseInput+DisplayString` and `Shortcut+KeyMapping`). If it doesn't compile, check `Sources/ShortcutField/Shortcut+KeyMapping.swift` for the helper definition and re-use it as-is.

- [ ] **Step 4: Run tests to verify they pass**

```bash
just test 2>&1 | tail -20
```

Expected: all display string tests pass.

- [ ] **Step 5: Lint and commit checkpoint**

```bash
just lint
```

User handles commits — pause and report:

> Display strings added. Tests pass.

---

## Task 3: `TrackpadGesture+Matching`

**Files:**
- Create: `Sources/ShortcutField/TrackpadGesture+Matching.swift`
- Create: `Tests/ShortcutFieldTests/TrackpadGestureMatchingTests.swift`

The matcher needs synthesized `NSEvent`s for testing. Real `NSEvent` initializers for gesture types are private/limited; the test approach uses dependency injection via a small internal helper struct that the matcher calls into.

- [ ] **Step 1: Define a testable event-shape helper**

Add to the top of `Sources/ShortcutField/TrackpadGesture+Matching.swift`:

```swift
import AppKit

/// Internal shape used by the matcher so unit tests can synthesize gesture events
/// without needing to construct real `NSEvent` gesture instances.
struct GestureEventShape: Equatable {
    var type: NSEvent.EventType
    var modifierFlags: NSEvent.ModifierFlags
    var magnification: Double
    var rotation: Double          // degrees
    var deltaX: Double
    var deltaY: Double
    var fingerCount: Int          // from event.allTouches().count for swipes; 0 if N/A

    init(
        type: NSEvent.EventType,
        modifierFlags: NSEvent.ModifierFlags = [],
        magnification: Double = 0,
        rotation: Double = 0,
        deltaX: Double = 0,
        deltaY: Double = 0,
        fingerCount: Int = 0
    ) {
        self.type = type
        self.modifierFlags = modifierFlags
        self.magnification = magnification
        self.rotation = rotation
        self.deltaX = deltaX
        self.deltaY = deltaY
        self.fingerCount = fingerCount
    }

    init(_ event: NSEvent) {
        type = event.type
        modifierFlags = event.modifierFlags
        magnification = (event.type == .magnify) ? Double(event.magnification) : 0
        rotation = (event.type == .rotate) ? Double(event.rotation) : 0
        deltaX = Double(event.deltaX)
        deltaY = Double(event.deltaY)
        if event.type == .swipe {
            fingerCount = event.allTouches().count
        } else {
            fingerCount = 0
        }
    }
}
```

- [ ] **Step 2: Write failing tests**

Create `Tests/ShortcutFieldTests/TrackpadGestureMatchingTests.swift`:

```swift
import AppKit
@testable import ShortcutField
import Testing

struct TrackpadGestureMatchingTests {
    // MARK: - Pinch

    @Test func pinchIn_matchesPositiveMagnification() {
        let g = TrackpadGesture(kind: .pinchIn, modifiers: [])
        let event = GestureEventShape(type: .magnify, magnification: 0.05)
        #expect(g.matches(event))
    }

    @Test func pinchIn_doesNotMatchNegativeMagnification() {
        let g = TrackpadGesture(kind: .pinchIn, modifiers: [])
        let event = GestureEventShape(type: .magnify, magnification: -0.05)
        #expect(!g.matches(event))
    }

    @Test func pinchOut_matchesNegativeMagnification() {
        let g = TrackpadGesture(kind: .pinchOut, modifiers: [])
        let event = GestureEventShape(type: .magnify, magnification: -0.05)
        #expect(g.matches(event))
    }

    @Test func pinch_subThresholdDoesNotMatch() {
        let g = TrackpadGesture(kind: .pinchIn, modifiers: [])
        let event = GestureEventShape(type: .magnify, magnification: 0.001)
        #expect(!g.matches(event))
    }

    @Test func pinch_modifierMismatchDoesNotMatch() {
        let g = TrackpadGesture(kind: .pinchIn, modifiers: .command)
        let event = GestureEventShape(type: .magnify, modifierFlags: [], magnification: 0.05)
        #expect(!g.matches(event))
    }

    @Test func pinch_modifierMatchMatches() {
        let g = TrackpadGesture(kind: .pinchIn, modifiers: .command)
        let event = GestureEventShape(type: .magnify, modifierFlags: .command, magnification: 0.05)
        #expect(g.matches(event))
    }

    @Test func pinch_doesNotMatchOtherEventType() {
        let g = TrackpadGesture(kind: .pinchIn, modifiers: [])
        let event = GestureEventShape(type: .rotate, rotation: 5)
        #expect(!g.matches(event))
    }

    // MARK: - Rotate (positive rotation = counter-clockwise per AppKit)

    @Test func rotateCCW_matchesPositiveRotation() {
        let g = TrackpadGesture(kind: .rotateCounterClockwise, modifiers: [])
        let event = GestureEventShape(type: .rotate, rotation: 5)
        #expect(g.matches(event))
    }

    @Test func rotateCW_matchesNegativeRotation() {
        let g = TrackpadGesture(kind: .rotateClockwise, modifiers: [])
        let event = GestureEventShape(type: .rotate, rotation: -5)
        #expect(g.matches(event))
    }

    @Test func rotate_subThresholdDoesNotMatch() {
        let g = TrackpadGesture(kind: .rotateClockwise, modifiers: [])
        let event = GestureEventShape(type: .rotate, rotation: -0.1)
        #expect(!g.matches(event))
    }

    // MARK: - Swipe

    @Test func swipe3FingerUp_matchesPositiveDeltaY() {
        let g = TrackpadGesture(kind: .swipe(fingers: 3, direction: .up), modifiers: [])
        let event = GestureEventShape(type: .swipe, deltaY: 1, fingerCount: 3)
        #expect(g.matches(event))
    }

    @Test func swipe3FingerDown_matchesNegativeDeltaY() {
        let g = TrackpadGesture(kind: .swipe(fingers: 3, direction: .down), modifiers: [])
        let event = GestureEventShape(type: .swipe, deltaY: -1, fingerCount: 3)
        #expect(g.matches(event))
    }

    @Test func swipe3FingerLeft_matchesNegativeDeltaX() {
        let g = TrackpadGesture(kind: .swipe(fingers: 3, direction: .left), modifiers: [])
        let event = GestureEventShape(type: .swipe, deltaX: -1, fingerCount: 3)
        #expect(g.matches(event))
    }

    @Test func swipe3FingerRight_matchesPositiveDeltaX() {
        let g = TrackpadGesture(kind: .swipe(fingers: 3, direction: .right), modifiers: [])
        let event = GestureEventShape(type: .swipe, deltaX: 1, fingerCount: 3)
        #expect(g.matches(event))
    }

    @Test func swipe3Finger_doesNotMatch4FingerEvent() {
        let g = TrackpadGesture(kind: .swipe(fingers: 3, direction: .up), modifiers: [])
        let event = GestureEventShape(type: .swipe, deltaY: 1, fingerCount: 4)
        #expect(!g.matches(event))
    }

    @Test func swipe4Finger_matches4FingerEvent() {
        let g = TrackpadGesture(kind: .swipe(fingers: 4, direction: .up), modifiers: [])
        let event = GestureEventShape(type: .swipe, deltaY: 1, fingerCount: 4)
        #expect(g.matches(event))
    }

    @Test func swipe_zeroFingerCount_matchesAnyFingers_fallback() {
        // When fingerCount is 0 (AppKit didn't expose it), match any fingers count.
        let g3 = TrackpadGesture(kind: .swipe(fingers: 3, direction: .up), modifiers: [])
        let g4 = TrackpadGesture(kind: .swipe(fingers: 4, direction: .up), modifiers: [])
        let event = GestureEventShape(type: .swipe, deltaY: 1, fingerCount: 0)
        #expect(g3.matches(event))
        #expect(g4.matches(event))
    }

    @Test func swipe_largerAxisWins() {
        // deltaX larger than deltaY → horizontal swipe
        let g = TrackpadGesture(kind: .swipe(fingers: 3, direction: .right), modifiers: [])
        let event = GestureEventShape(type: .swipe, deltaX: 1, deltaY: 0.3, fingerCount: 3)
        #expect(g.matches(event))
        let gWrong = TrackpadGesture(kind: .swipe(fingers: 3, direction: .up), modifiers: [])
        #expect(!gWrong.matches(event))
    }

    // MARK: - Smart magnify

    @Test func smartMagnify_matchesEvent() {
        let g = TrackpadGesture(kind: .smartMagnify, modifiers: [])
        let event = GestureEventShape(type: .smartMagnify)
        #expect(g.matches(event))
    }

    @Test func smartMagnify_doesNotMatchPinch() {
        let g = TrackpadGesture(kind: .smartMagnify, modifiers: [])
        let event = GestureEventShape(type: .magnify, magnification: 0.05)
        #expect(!g.matches(event))
    }
}
```

- [ ] **Step 3: Run tests to verify they fail**

```bash
just test 2>&1 | tail -20
```

Expected: build error — `matches(_ event: GestureEventShape)` not defined.

- [ ] **Step 4: Implement the matcher**

Add to `Sources/ShortcutField/TrackpadGesture+Matching.swift` (below the `GestureEventShape` definition):

```swift
public extension TrackpadGesture {
    /// Match against an `NSEvent` (gesture event types: `.magnify`, `.rotate`, `.swipe`, `.smartMagnify`).
    func matches(_ event: NSEvent) -> Bool {
        matches(GestureEventShape(event))
    }
}

extension TrackpadGesture {
    /// Match against a synthesized event shape — used by tests and by `matches(_ event: NSEvent)`.
    func matches(_ event: GestureEventShape) -> Bool {
        let eventMods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            .intersection([.shift, .control, .option, .command])
        guard eventMods == modifiers else { return false }

        switch kind {
        case .pinchIn:
            guard event.type == .magnify else { return false }
            return event.magnification > Self.magnifyEventThreshold
        case .pinchOut:
            guard event.type == .magnify else { return false }
            return event.magnification < -Self.magnifyEventThreshold
        case .rotateCounterClockwise:
            guard event.type == .rotate else { return false }
            return event.rotation > Self.rotateEventThreshold
        case .rotateClockwise:
            guard event.type == .rotate else { return false }
            return event.rotation < -Self.rotateEventThreshold
        case let .swipe(fingers, direction):
            guard event.type == .swipe else { return false }
            // Fall back to "match any fingers" when AppKit didn't expose finger count (0).
            if event.fingerCount != 0, event.fingerCount != fingers { return false }
            return swipeMatches(direction: direction, deltaX: event.deltaX, deltaY: event.deltaY)
        case .smartMagnify:
            return event.type == .smartMagnify
        }
    }

    private func swipeMatches(direction: SwipeDirection, deltaX: Double, deltaY: Double) -> Bool {
        // Larger-magnitude axis wins.
        if abs(deltaX) >= abs(deltaY) {
            switch direction {
            case .right: return deltaX > 0
            case .left: return deltaX < 0
            default: return false
            }
        } else {
            switch direction {
            case .up: return deltaY > 0
            case .down: return deltaY < 0
            default: return false
            }
        }
    }
}
```

- [ ] **Step 5: Run tests to verify they pass**

```bash
just test 2>&1 | tail -20
```

Expected: all matching tests pass.

- [ ] **Step 6: Lint**

```bash
just lint
```

- [ ] **Step 7: Commit checkpoint**

User handles commits — pause and report:

> Matching logic added. Pinch direction by sign, rotate direction (CCW = positive per AppKit), swipe direction by larger-magnitude axis, swipe finger count with zero-fallback. Tests pass.

---

## Task 4: `OnTrackpadGestureModifier`

**Files:**
- Create: `Sources/ShortcutField/OnTrackpadGestureModifier.swift`

The throttle behavior is fully covered by the existing `ThrottleState` tests. This task adds the SwiftUI modifier wrapper. No new unit tests are practical for the NSEvent-monitor closure (same situation as `OnMouseInputModifier` — manual testing in the Example app covers it).

- [ ] **Step 1: Create the modifier file**

Create `Sources/ShortcutField/OnTrackpadGestureModifier.swift`:

```swift
import AppKit
import SwiftUI

/// View modifier that fires an action when a trackpad gesture is detected.
///
/// Uses an NSEvent local monitor to match `.magnify`, `.rotate`, `.swipe`, and
/// `.smartMagnify` events globally within the app, so the view does not need
/// focus. Matching is disabled while any recorder field is active. Continuous
/// gestures (pinch, rotate) are throttled according to the gesture's `sensitivity`.
@available(macOS 14.0, *)
struct OnTrackpadGestureModifier: ViewModifier {
    let gesture: TrackpadGesture?
    let action: () -> Void

    @State private var eventMonitor: Any?
    @State private var throttleState = ThrottleState()

    func body(content: Content) -> some View {
        content
            .onAppear {
                throttleState.sensitivity = gesture?.sensitivity ?? 0.0
                installMonitor()
            }
            .onDisappear {
                removeMonitor()
                throttleState.reset()
            }
            .onChange(of: gesture) { old, new in
                throttleState.sensitivity = new?.sensitivity ?? 0.0
                throttleState.reset()
                if old?.kind != new?.kind || old?.modifiers != new?.modifiers {
                    removeMonitor()
                    installMonitor()
                }
            }
    }

    private func installMonitor() {
        guard let gesture, eventMonitor == nil else { return }
        let throttle = throttleState

        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [
            .magnify,
            .rotate,
            .swipe,
            .smartMagnify,
        ]) { event in
            if ShortcutRecordingState.isAnyRecording {
                return event
            }

            // Reset throttle on gesture end so the next physical gesture starts fresh.
            // `phase` is only meaningful for .magnify and .rotate; .swipe and .smartMagnify
            // are discrete and we don't see end-phase events for them.
            if (event.type == .magnify || event.type == .rotate),
               event.phase == .ended || event.phase == .cancelled
            {
                throttle.reset()
                return event
            }

            guard gesture.matches(event) else {
                return event
            }

            if TrackpadGesture.isContinuous(gesture.kind) {
                Self.handleThrottled(throttle: throttle, action: action)
            } else {
                action()
            }
            return nil
        }
    }

    private static func handleThrottled(throttle: ThrottleState, action: () -> Void) {
        let decision = ThrottleState.evaluate(state: throttle, now: .now)
        if decision.shouldFire {
            action()
        }
        if let delay = decision.rearmAfter {
            throttle.rearmWorkItem?.cancel()
            let workItem = DispatchWorkItem {
                MainActor.assumeIsolated {
                    throttle.suppressed = false
                }
            }
            throttle.rearmWorkItem = workItem
            let milliseconds = Int(delay.components.seconds * 1000
                + delay.components.attoseconds / 1_000_000_000_000_000)
            DispatchQueue.main.asyncAfter(
                deadline: .now() + .milliseconds(milliseconds),
                execute: workItem
            )
        }
    }

    private func removeMonitor() {
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
            self.eventMonitor = nil
        }
    }
}

public extension View {
    /// Perform an action when the given trackpad gesture is detected.
    ///
    /// Uses an `NSEvent` local monitor to match gesture events globally within
    /// the app. The view does not need focus. Matching is automatically disabled
    /// while any recorder field is active. Continuous gestures (pinch, rotate)
    /// are throttled per the gesture's `sensitivity`.
    ///
    /// ```swift
    /// MyView()
    ///     .onTrackpadGesture(gesture) {
    ///         print("Gesture fired!")
    ///     }
    /// ```
    @available(macOS 14.0, *)
    func onTrackpadGesture(
        _ gesture: TrackpadGesture?,
        perform action: @escaping () -> Void
    ) -> some View {
        modifier(OnTrackpadGestureModifier(gesture: gesture, action: action))
    }
}

```

**Note:** `isContinuous(_:)` is already defined in `TrackpadGesture.swift` (Task 1). Do NOT redefine it here.

- [ ] **Step 2: Build to verify it compiles**

```bash
just build 2>&1 | tail -20
```

Expected: build succeeds.

- [ ] **Step 3: Lint**

```bash
just lint
```

- [ ] **Step 4: Commit checkpoint**

User handles commits — pause and report:

> `.onTrackpadGesture()` modifier added with throttling, recorder-active gating, and end-phase reset. Build clean.

---

## Task 5: `TrackpadGestureRecorderField` (live recording only — no menu yet)

**Files:**
- Create: `Sources/ShortcutField/TrackpadGestureRecorderField.swift`
- Create: `Tests/ShortcutFieldTests/TrackpadGestureRecorderFieldTests.swift`

This task adds the AppKit recorder with live recording. The chevron menu picker is a follow-up task (Task 6) to keep this PR-scope reasonable.

- [ ] **Step 1: Write failing tests**

Create `Tests/ShortcutFieldTests/TrackpadGestureRecorderFieldTests.swift`:

```swift
import AppKit
@testable import ShortcutField
import Testing

@MainActor
struct TrackpadGestureRecorderFieldTests {
    @Test func defaultState_noGestureNoRecording() {
        let field = TrackpadGestureRecorderField()
        #expect(field.trackpadGesture == nil)
        #expect(field.isRecording == false)
    }

    @Test func setGesture_updatesStringValue() {
        let field = TrackpadGestureRecorderField()
        field.trackpadGesture = TrackpadGesture(kind: .pinchIn, modifiers: .command)
        #expect(field.stringValue == "⌘Pinch In")
    }

    @Test func clearGesture_resetsStringValue() {
        let field = TrackpadGestureRecorderField()
        field.trackpadGesture = TrackpadGesture(kind: .pinchIn, modifiers: [])
        field.trackpadGesture = nil
        #expect(field.stringValue == "")
    }

    @Test func defaultPlaceholder() {
        let field = TrackpadGestureRecorderField()
        #expect(field.defaultPlaceholder == "Record Gesture")
    }

    @Test func recordingPlaceholder() {
        let field = TrackpadGestureRecorderField()
        #expect(field.recordingPlaceholder == "Perform gesture\u{2026}")
    }

    @Test func sensitivityMode_defaultsToDiscrete() {
        let field = TrackpadGestureRecorderField()
        #expect(field.sensitivityMode == .discrete)
    }

    @Test func sensitivityPosition_defaultsToBelow() {
        let field = TrackpadGestureRecorderField()
        #expect(field.sensitivityPosition == .below)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
just test 2>&1 | tail -20
```

Expected: build error — `TrackpadGestureRecorderField` not defined.

- [ ] **Step 3: Implement the recorder field**

Create `Sources/ShortcutField/TrackpadGestureRecorderField.swift`. Pattern is parallel to `MouseInputRecorderField.swift` — use it as a reference. Read it before implementing.

```swift
import AppKit
import Carbon.HIToolbox

/// An AppKit control that records macOS-recognized trackpad gestures.
///
/// Subclasses `NSSearchField`. Click to start recording, then perform a gesture
/// (pinch, rotate, 3/4-finger swipe, smart magnify). Press Escape to cancel,
/// or Delete to clear.
///
/// For SwiftUI, use ``TrackpadGestureRecorderView`` instead.
public final class TrackpadGestureRecorderField: NSSearchField, NSSearchFieldDelegate, NSTextViewDelegate,
    ActiveShortcutRecorder
{
    override public class var cellClass: AnyClass? {
        get { CenteredSearchFieldCell.self }
        set { super.cellClass = newValue }
    }

    public static var isAnyRecording: Bool { ShortcutRecordingState.isAnyRecording }

    private let minimumWidth: CGFloat = 160
    private var bezeledHeight: CGFloat = 0
    private nonisolated(unsafe) var eventMonitor: Any?
    private var cancelButton: NSButtonCell?
    private var canBecomeKey = false
    private var isStartingRecording = false

    /// Cumulative magnification accumulated within the current pinch gesture.
    private var pinchAccumulator: Double = 0
    /// Cumulative rotation (degrees) accumulated within the current rotate gesture.
    private var rotateAccumulator: Double = 0

    public private(set) var isRecording = false

    override public var canBecomeKeyView: Bool { canBecomeKey }

    public var trackpadGesture: TrackpadGesture? {
        didSet { updateDisplay() }
    }

    public var onTrackpadGestureChange: ((TrackpadGesture?) -> Void)?

    public var defaultPlaceholder: String = "Record Gesture" {
        didSet {
            if !isRecording { placeholderString = defaultPlaceholder }
        }
    }

    public var recordingPlaceholder: String = "Perform gesture\u{2026}"

    public var fieldTextColor: NSColor? {
        didSet { textColor = fieldTextColor }
    }

    public var fieldBackgroundColor: NSColor? {
        didSet { applyBackgroundColor() }
    }

    public var sensitivityMode: SensitivityMode = .discrete
    public var sensitivityPosition: SensitivityPosition = .below

    private func applyBackgroundColor() {
        if let color = fieldBackgroundColor {
            isBezeled = false
            layer?.backgroundColor = color.cgColor
            layer?.cornerRadius = 6
            layer?.borderWidth = 0.5
            layer?.borderColor = NSColor.separatorColor.cgColor
        } else {
            isBezeled = true
            layer?.backgroundColor = nil
            layer?.cornerRadius = 0
            layer?.borderWidth = 0
            layer?.borderColor = nil
        }
    }

    private var showsCancelButton: Bool {
        get { (cell as? NSSearchFieldCell)?.cancelButtonCell != nil }
        set { (cell as? NSSearchFieldCell)?.cancelButtonCell = newValue ? cancelButton : nil }
    }

    deinit {
        ShortcutRecordingState.endOnDeinit(for: self)
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
        }
    }

    override public init(frame _: NSRect) {
        super.init(frame: NSRect(x: 0, y: 0, width: minimumWidth, height: 24))
        setup()
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

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
        bezeledHeight = super.intrinsicContentSize.height
        updateDisplay()
    }

    override public var intrinsicContentSize: NSSize {
        NSSize(width: minimumWidth, height: bezeledHeight)
    }

    override public func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow == nil { endRecording() }
        super.viewWillMove(toWindow: newWindow)
    }

    override public func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard window != nil else { return }
        canBecomeKey = false
        DispatchQueue.main.async { [weak self] in
            self?.canBecomeKey = true
        }
    }

    private func updateDisplay() {
        if let trackpadGesture {
            stringValue = trackpadGesture.displayString
            showsCancelButton = true
        } else {
            stringValue = ""
            showsCancelButton = false
        }
    }

    func startRecording() {
        guard !isRecording else { return }
        isStartingRecording = true
        isRecording = true
        pinchAccumulator = 0
        rotateAccumulator = 0
        ShortcutRecordingState.begin(for: self)
        placeholderString = recordingPlaceholder
        showsCancelButton = trackpadGesture != nil

        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [
            .leftMouseDown,
            .magnify,
            .rotate,
            .swipe,
            .smartMagnify,
            .keyDown,
        ]) { [weak self] event in
            guard let self, isRecording else { return event }
            return handleEvent(event)
        }
        isStartingRecording = false
    }

    func endRecording() {
        guard isRecording else { return }
        isRecording = false
        pinchAccumulator = 0
        rotateAccumulator = 0
        ShortcutRecordingState.end(for: self)
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
            self.eventMonitor = nil
        }
        placeholderString = defaultPlaceholder
        showsCancelButton = trackpadGesture != nil
    }

    private func blur() {
        window?.makeFirstResponder(nil)
    }

    func forceEndRecordingSession() {
        endRecording()
    }

    // MARK: - NSSearchFieldDelegate

    public func controlTextDidEndEditing(_: Notification) {
        guard !isStartingRecording else { return }
        endRecording()
    }

    public func control(_: NSControl, textView _: NSTextView, shouldChangeTextIn _: NSRange,
                        replacementString _: String?) -> Bool
    {
        false
    }

    public func searchFieldDidEndSearching(_: NSSearchField) {
        trackpadGesture = nil
        onTrackpadGestureChange?(nil)
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

    override public func resignFirstResponder() -> Bool {
        let shouldResignFirstResponder = super.resignFirstResponder()
        guard shouldResignFirstResponder else { return false }
        guard !isStartingRecording else { return true }
        endRecording()
        return true
    }

    // MARK: - NSTextViewDelegate

    public func textView(_: NSTextView, shouldChangeTextIn _: NSRange, replacementString _: String?) -> Bool {
        false
    }

    // MARK: - Event handling

    private func handleEvent(_ event: NSEvent) -> NSEvent? {
        if event.type == .keyDown {
            return handleKeyEvent(event)
        }
        if event.type == .leftMouseDown {
            return handleClickEvent(event)
        }
        return handleGestureEvent(event)
    }

    private func handleKeyEvent(_ event: NSEvent) -> NSEvent? {
        let modifiers = event.modifierFlags
            .intersection(.deviceIndependentFlagsMask)
            .subtracting([.capsLock, .numericPad, .function])

        if modifiers.isEmpty, event.keyCode == UInt16(kVK_Escape) {
            endRecording()
            blur()
            return nil
        }

        if modifiers.isEmpty,
           event.keyCode == UInt16(kVK_Delete) || event.keyCode == UInt16(kVK_ForwardDelete)
        {
            trackpadGesture = nil
            onTrackpadGestureChange?(nil)
            endRecording()
            blur()
            return nil
        }

        return event
    }

    private func handleClickEvent(_ event: NSEvent) -> NSEvent? {
        let clickPoint = convert(event.locationInWindow, from: nil)
        let clickMargin: CGFloat = 3.0
        let isInsideField = bounds.insetBy(dx: -clickMargin, dy: -clickMargin).contains(clickPoint)
        if !isInsideField {
            endRecording()
            blur()
            return event
        }
        return event
    }

    private func handleGestureEvent(_ event: NSEvent) -> NSEvent? {
        let modifiers = event.modifierFlags
            .intersection(.deviceIndependentFlagsMask)
            .intersection([.shift, .control, .option, .command])

        switch event.type {
        case .magnify:
            pinchAccumulator += Double(event.magnification)
            if abs(pinchAccumulator) >= TrackpadGesture.magnifyRecordingThreshold {
                let kind: TrackpadGesture.Kind = pinchAccumulator > 0 ? .pinchIn : .pinchOut
                finalize(kind: kind, modifiers: modifiers)
                return nil
            }
            return nil
        case .rotate:
            rotateAccumulator += Double(event.rotation)
            if abs(rotateAccumulator) >= TrackpadGesture.rotateRecordingThreshold {
                let kind: TrackpadGesture.Kind = rotateAccumulator > 0
                    ? .rotateCounterClockwise
                    : .rotateClockwise
                finalize(kind: kind, modifiers: modifiers)
                return nil
            }
            return nil
        case .swipe:
            let dx = Double(event.deltaX)
            let dy = Double(event.deltaY)
            let direction: TrackpadGesture.SwipeDirection = {
                if abs(dx) >= abs(dy) {
                    return dx > 0 ? .right : .left
                } else {
                    return dy > 0 ? .up : .down
                }
            }()
            let touchCount = event.allTouches().count
            let fingers = (touchCount == 4) ? 4 : 3
            finalize(kind: .swipe(fingers: fingers, direction: direction), modifiers: modifiers)
            return nil
        case .smartMagnify:
            finalize(kind: .smartMagnify, modifiers: modifiers)
            return nil
        default:
            return event
        }
    }

    private func finalize(kind: TrackpadGesture.Kind, modifiers: NSEvent.ModifierFlags) {
        let existingSensitivity = trackpadGesture?.sensitivity ?? 0.0
        let newGesture = TrackpadGesture(kind: kind, modifiers: modifiers, sensitivity: existingSensitivity)
        trackpadGesture = newGesture
        onTrackpadGestureChange?(newGesture)
        endRecording()
        blur()
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
just test 2>&1 | tail -20
```

Expected: all `TrackpadGestureRecorderFieldTests` pass.

- [ ] **Step 5: Lint**

```bash
just lint
```

- [ ] **Step 6: Commit checkpoint**

User handles commits — pause and report:

> Recorder field added. Live recording with cumulative-threshold finalization for pinch/rotate, immediate finalization for swipe/smart-magnify. Tests pass.

---

## Task 6: Chevron-button menu picker on `TrackpadGestureRecorderField`

**Files:**
- Modify: `Sources/ShortcutField/TrackpadGestureRecorderField.swift`
- Modify: `Tests/ShortcutFieldTests/TrackpadGestureRecorderFieldTests.swift`

- [ ] **Step 1: Write failing tests**

Append to `Tests/ShortcutFieldTests/TrackpadGestureRecorderFieldTests.swift`:

```swift
@MainActor
struct TrackpadGestureRecorderFieldMenuTests {
    @Test func gestureMenu_listsAllThirteenGestures() {
        let menu = TrackpadGestureRecorderField.makeGestureMenu(target: nil)
        // Flatten: top-level items are sections (titles), nested items are the gestures.
        var leafCount = 0
        for item in menu.items {
            if let submenu = item.submenu {
                leafCount += submenu.items.filter { !$0.isSeparatorItem && $0.title.isEmpty == false }.count
            } else if !item.isSeparatorItem, !item.title.isEmpty {
                leafCount += 1
            }
        }
        #expect(leafCount == 13)
    }

    @Test func gestureMenu_includesPinchInOut() {
        let menu = TrackpadGestureRecorderField.makeGestureMenu(target: nil)
        let allTitles = collectMenuTitles(menu)
        #expect(allTitles.contains("Pinch In"))
        #expect(allTitles.contains("Pinch Out"))
    }

    @Test func gestureMenu_includesAllSwipeDirections() {
        let menu = TrackpadGestureRecorderField.makeGestureMenu(target: nil)
        let allTitles = collectMenuTitles(menu)
        for label in ["3-Finger Swipe ↑", "3-Finger Swipe ↓", "3-Finger Swipe ←", "3-Finger Swipe →",
                      "4-Finger Swipe ↑", "4-Finger Swipe ↓", "4-Finger Swipe ←", "4-Finger Swipe →"]
        {
            #expect(allTitles.contains(label))
        }
    }

    private func collectMenuTitles(_ menu: NSMenu) -> [String] {
        var titles: [String] = []
        for item in menu.items {
            if let submenu = item.submenu {
                titles.append(contentsOf: collectMenuTitles(submenu))
            } else if !item.isSeparatorItem, !item.title.isEmpty {
                titles.append(item.title)
            }
        }
        return titles
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
just test 2>&1 | tail -20
```

Expected: build error — `makeGestureMenu` not defined.

- [ ] **Step 3: Add the menu builder and chevron button**

Add to `TrackpadGestureRecorderField.swift`:

```swift
extension TrackpadGestureRecorderField {
    /// Builds the gesture-picker menu used by the chevron button.
    /// Public-internal: also called by tests to verify menu contents.
    static func makeGestureMenu(target: AnyObject?) -> NSMenu {
        let root = NSMenu()

        // Section: Pinch
        let pinch = NSMenu()
        pinch.addItem(menuItem(for: .pinchIn, target: target))
        pinch.addItem(menuItem(for: .pinchOut, target: target))
        let pinchHeader = NSMenuItem(title: "Pinch", action: nil, keyEquivalent: "")
        pinchHeader.submenu = pinch
        root.addItem(pinchHeader)

        // Section: Rotate
        let rotate = NSMenu()
        rotate.addItem(menuItem(for: .rotateClockwise, target: target))
        rotate.addItem(menuItem(for: .rotateCounterClockwise, target: target))
        let rotateHeader = NSMenuItem(title: "Rotate", action: nil, keyEquivalent: "")
        rotateHeader.submenu = rotate
        root.addItem(rotateHeader)

        // Section: Swipe (3-finger)
        let three = NSMenu()
        for dir in [TrackpadGesture.SwipeDirection.up, .down, .left, .right] {
            three.addItem(menuItem(for: .swipe(fingers: 3, direction: dir), target: target))
        }
        let threeHeader = NSMenuItem(title: "Swipe (3-finger)", action: nil, keyEquivalent: "")
        threeHeader.submenu = three
        root.addItem(threeHeader)

        // Section: Swipe (4-finger)
        let four = NSMenu()
        for dir in [TrackpadGesture.SwipeDirection.up, .down, .left, .right] {
            four.addItem(menuItem(for: .swipe(fingers: 4, direction: dir), target: target))
        }
        let fourHeader = NSMenuItem(title: "Swipe (4-finger)", action: nil, keyEquivalent: "")
        fourHeader.submenu = four
        root.addItem(fourHeader)

        // Smart Magnify
        root.addItem(menuItem(for: .smartMagnify, target: target))

        return root
    }

    private static func menuItem(
        for kind: TrackpadGesture.Kind, target: AnyObject?
    ) -> NSMenuItem {
        // Construct a temporary gesture purely to reuse displayString — modifiers
        // are captured at click time from NSApp.currentEvent.
        let displayLabel = TrackpadGesture(kind: kind, modifiers: []).displayString
        let item = NSMenuItem(
            title: displayLabel,
            action: #selector(TrackpadGestureRecorderField.menuPicked(_:)),
            keyEquivalent: ""
        )
        item.target = target
        item.representedObject = KindBox(kind: kind)
        return item
    }

    private final class KindBox: NSObject {
        let kind: TrackpadGesture.Kind
        init(kind: TrackpadGesture.Kind) { self.kind = kind }
    }

    @objc func menuPicked(_ sender: NSMenuItem) {
        guard let box = sender.representedObject as? KindBox else { return }
        let modifiers = NSApp.currentEvent?.modifierFlags
            .intersection(.deviceIndependentFlagsMask)
            .intersection([.shift, .control, .option, .command]) ?? []
        let existingSensitivity = trackpadGesture?.sensitivity ?? 0.0
        let new = TrackpadGesture(kind: box.kind, modifiers: modifiers, sensitivity: existingSensitivity)
        trackpadGesture = new
        onTrackpadGestureChange?(new)
    }
}
```

Then add a chevron button positioned inside the search-field cell on the right side. Wire it to show `makeGestureMenu(target: self)` as a popup at the chevron's location.

In `setup()` (after the existing `cancelButton = ...` line), add:

```swift
configureChevronButton()
```

Add the button configuration method:

```swift
private var chevronButton: NSButton?

private func configureChevronButton() {
    let button = NSButton(frame: .zero)
    button.bezelStyle = .accessoryBarAction
    button.isBordered = false
    button.image = NSImage(systemSymbolName: "chevron.down", accessibilityDescription: "Pick gesture")
    button.imagePosition = .imageOnly
    button.target = self
    button.action = #selector(showGesturePickerMenu(_:))
    button.translatesAutoresizingMaskIntoConstraints = false
    button.setContentHuggingPriority(.required, for: .horizontal)
    button.setContentCompressionResistancePriority(.required, for: .horizontal)
    addSubview(button)
    NSLayoutConstraint.activate([
        button.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -22), // leave room for clear button
        button.centerYAnchor.constraint(equalTo: centerYAnchor),
        button.widthAnchor.constraint(equalToConstant: 16),
        button.heightAnchor.constraint(equalToConstant: 16),
    ])
    chevronButton = button
}

@objc private func showGesturePickerMenu(_ sender: NSButton) {
    let menu = Self.makeGestureMenu(target: self)
    let location = NSPoint(x: 0, y: sender.bounds.height + 2)
    menu.popUp(positioning: nil, at: location, in: sender)
}
```

**Note:** The `MainActor` isolation on `NSEvent.addLocalMonitorForEvents` callback closures captures `self` weakly — same pattern as elsewhere. The chevron button itself is `@MainActor` by virtue of being an `NSView`.

- [ ] **Step 4: Run tests to verify they pass**

```bash
just test 2>&1 | tail -20
```

Expected: all menu tests pass.

- [ ] **Step 5: Lint**

```bash
just lint
```

- [ ] **Step 6: Commit checkpoint**

User handles commits — pause and report:

> Chevron-button menu picker added. 13 gestures organized into Pinch / Rotate / Swipe (3-finger) / Swipe (4-finger) / Smart Magnify, modifiers captured at click time. Tests pass.

---

## Task 7: `TrackpadGestureRecorderView` (SwiftUI wrapper)

**Files:**
- Create: `Sources/ShortcutField/TrackpadGestureRecorderView.swift`

This task mirrors `MouseInputRecorderView.swift` very closely. Read it before implementing.

- [ ] **Step 1: Implement the SwiftUI wrapper**

Create `Sources/ShortcutField/TrackpadGestureRecorderView.swift`:

```swift
import SwiftUI

/// A SwiftUI view that lets users record a macOS-recognized trackpad gesture.
///
/// ```swift
/// @State private var gesture: TrackpadGesture?
///
/// TrackpadGestureRecorderView($gesture)
///     .placeholder("Record Gesture")
///     .style(.rounded)
/// ```
public struct TrackpadGestureRecorderView: View {
    @Binding var gesture: TrackpadGesture?

    private var placeholderText: String = "Record Gesture"
    private var recordingPlaceholderText: String = "Perform gesture\u{2026}"
    private var style: ShortcutRecorderStyle = .rounded
    private var textColorValue: NSColor?
    private var backgroundColorValue: NSColor?
    private var sensitivityModeValue: SensitivityMode = .discrete
    private var sensitivityPositionValue: SensitivityPosition = .below

    public init(_ gesture: Binding<TrackpadGesture?>) {
        _gesture = gesture
    }

    public var body: some View {
        if showSensitivity {
            sensitivityLayout
        } else {
            fieldView
        }
    }

    @ViewBuilder
    private var sensitivityLayout: some View {
        switch sensitivityPositionValue {
        case .below:
            VStack(spacing: 6) {
                fieldView
                sensitivityControl
            }
        case .left:
            HStack(alignment: .center, spacing: 10) {
                sensitivityControl
                fieldView
            }
        case .right:
            HStack(alignment: .center, spacing: 10) {
                fieldView
                sensitivityControl
            }
        }
    }

    private var fieldView: some View {
        FieldRepresentable(
            gesture: $gesture,
            placeholderText: placeholderText,
            recordingPlaceholderText: recordingPlaceholderText,
            style: style,
            textColorValue: textColorValue,
            backgroundColorValue: backgroundColorValue
        )
    }

    private var showSensitivity: Bool {
        guard sensitivityModeValue != .hidden else { return false }
        guard let kind = gesture?.kind else { return false }
        return TrackpadGesture.isContinuous(kind)
    }

    private var sensitivityControl: some View {
        VStack(spacing: 2) {
            SensitivitySliderRepresentable(
                value: sensitivityBinding,
                snapToTicks: sensitivityModeValue == .discrete
            )
            .frame(width: 130, height: 18)
            Text("Sensitivity")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    private var sensitivityBinding: Binding<Double> {
        Binding(
            get: { gesture?.sensitivity ?? 0.0 },
            set: { newValue in
                guard let g = gesture, TrackpadGesture.isContinuous(g.kind) else { return }
                gesture = TrackpadGesture(
                    kind: g.kind, modifiers: g.modifiers, sensitivity: newValue
                )
            }
        )
    }
}

private struct FieldRepresentable: NSViewRepresentable {
    @Binding var gesture: TrackpadGesture?
    var placeholderText: String
    var recordingPlaceholderText: String
    var style: ShortcutRecorderStyle
    var textColorValue: NSColor?
    var backgroundColorValue: NSColor?

    func makeNSView(context _: Context) -> TrackpadGestureRecorderField {
        let field = TrackpadGestureRecorderField()
        field.trackpadGesture = gesture
        field.defaultPlaceholder = placeholderText
        field.recordingPlaceholder = recordingPlaceholderText
        field.applyRecorderStyle(style)
        field.fieldTextColor = textColorValue
        field.fieldBackgroundColor = backgroundColorValue
        field.onTrackpadGestureChange = { newGesture in
            DispatchQueue.main.async {
                gesture = newGesture
            }
        }
        return field
    }

    func updateNSView(_ nsView: TrackpadGestureRecorderField, context _: Context) {
        guard !nsView.isRecording else { return }
        nsView.trackpadGesture = gesture
        nsView.defaultPlaceholder = placeholderText
        nsView.recordingPlaceholder = recordingPlaceholderText
        nsView.applyRecorderStyle(style)
        nsView.fieldTextColor = textColorValue
        nsView.fieldBackgroundColor = backgroundColorValue
    }
}

// `SensitivitySliderRepresentable` already exists in MouseInputRecorderView.swift.
// If it is fileprivate there, factor it out into an internal helper file shared by both views.

// MARK: - Modifiers

public extension TrackpadGestureRecorderView {
    func placeholder(_ text: String) -> TrackpadGestureRecorderView {
        var view = self
        view.placeholderText = text
        return view
    }

    func recordingPlaceholder(_ text: String) -> TrackpadGestureRecorderView {
        var view = self
        view.recordingPlaceholderText = text
        return view
    }

    func style(_ style: ShortcutRecorderStyle) -> TrackpadGestureRecorderView {
        var view = self
        view.style = style
        return view
    }

    func textColor(_ color: NSColor) -> TrackpadGestureRecorderView {
        var view = self
        view.textColorValue = color
        return view
    }

    func fieldBackgroundColor(_ color: NSColor) -> TrackpadGestureRecorderView {
        var view = self
        view.backgroundColorValue = color
        return view
    }

    func sensitivityMode(_ mode: SensitivityMode) -> TrackpadGestureRecorderView {
        var view = self
        view.sensitivityModeValue = mode
        return view
    }

    func sensitivityPosition(_ position: SensitivityPosition) -> TrackpadGestureRecorderView {
        var view = self
        view.sensitivityPositionValue = position
        return view
    }
}
```

- [ ] **Step 2: Resolve `SensitivitySliderRepresentable` reuse**

Check `MouseInputRecorderView.swift`:
- If `SensitivitySliderRepresentable` is `private` or `fileprivate`, extract it to a new internal file `Sources/ShortcutField/SensitivitySliderRepresentable.swift` so both views can use it. Otherwise leave it where it is and import as needed.

- [ ] **Step 3: Build to verify it compiles**

```bash
just build 2>&1 | tail -20
```

Expected: build succeeds.

- [ ] **Step 4: Lint**

```bash
just lint
```

- [ ] **Step 5: Commit checkpoint**

User handles commits — pause and report:

> SwiftUI `TrackpadGestureRecorderView` added with full modifier API parity. Build clean.

---

## Task 8: Verify `applyRecorderStyle` works for the new field

**Files:**
- Modify (if needed): `Sources/ShortcutField/ShortcutRecorderStyle.swift`

The `applyRecorderStyle(_:)` extension lives on a protocol or directly on `NSSearchField`. Verify it's reachable from `TrackpadGestureRecorderField`.

- [ ] **Step 1: Inspect `ShortcutRecorderStyle.swift`**

```bash
just build 2>&1 | grep -i "applyRecorderStyle" || true
```

If the build already passed in Task 7, no work is needed here.

- [ ] **Step 2: If `applyRecorderStyle` was constrained to specific types, broaden to include `TrackpadGestureRecorderField`**

Most likely the protocol-based extension already covers any `NSSearchField` subclass. If not, extend the protocol's `Self` constraint or add a conformance.

- [ ] **Step 3: Build**

```bash
just build
```

- [ ] **Step 4: No commit needed if no changes were required.** Otherwise pause and report.

---

## Task 9: Example app — Workbench tab

**Files:**
- Modify: `Example/ShortcutFieldExample/ContentView.swift`

This is manual UI work. Add a "Trackpad Gesture" recorder block to the existing `WorkbenchTab` panel, parallel to the "Mouse Input" block (around line 96–115 in the current file).

- [ ] **Step 1: Add state for gesture and match counter**

Add to the `@State` declarations at the top of `WorkbenchTab`:

```swift
@State private var trackpadGesture: TrackpadGesture?
@State private var gestureMatchCount = 0
@State private var gestureLastMatched = false
```

- [ ] **Step 2: Add the recorder block to the left panel**

After the existing "Mouse Input" block in `WorkbenchTab`'s left column, add:

```swift
Divider().padding(.horizontal, 20)

Text("Trackpad Gesture")
    .font(.caption)
    .foregroundStyle(.tertiary)
TrackpadGestureRecorderView($trackpadGesture)
    .placeholder("Record Gesture")
    .style(selectedStyle)
    .controlSize(selectedSize)
    .ifLet(selectedTextColor.nsColor) { view, color in view.textColor(color) }
    .ifLet(selectedBgColor.nsColor) { view, color in view.fieldBackgroundColor(color) }
    .sensitivityMode(selectedSensitivityMode)
    .sensitivityPosition(selectedSensitivityPosition)
    .frame(width: 220)

if let trackpadGesture {
    Text(trackpadGesture.displayString)
        .font(.title.monospaced())
        .foregroundStyle(.secondary)
} else {
    Text("No gesture")
        .foregroundStyle(.tertiary)
}
```

If `.ifLet` doesn't already exist as a helper in the example, use a simpler conditional `.modifier(...)` pattern; check existing usages in the file for the established pattern (the mouse-input block is the reference).

- [ ] **Step 3: Add a match feedback section in the right panel**

In the right panel of `WorkbenchTab`, after the mouse-input feedback, add a parallel block showing `gestureMatchCount` and `gestureLastMatched`. Use `.onTrackpadGesture(trackpadGesture) { gestureMatchCount += 1; gestureLastMatched = true }`.

Follow the same pattern as the existing mouse-input feedback for consistency.

- [ ] **Step 4: Manual verification**

The user runs the example app per project memory:

> Please run `just example` to verify the gesture recorder appears in the Workbench tab and that recording works. Test at least: pinch in, pinch out, rotate, 3-finger swipe in each direction, 4-finger swipe (if your trackpad delivers them), smart magnify (two-finger double-tap).

Wait for user confirmation before proceeding.

- [ ] **Step 5: Commit checkpoint**

User handles commits — pause and report:

> Workbench tab updated with `TrackpadGestureRecorderView`. Awaiting user manual verification.

---

## Task 10: Example app — Gallery tab

**Files:**
- Modify: `Example/ShortcutFieldExample/ContentView.swift`

- [ ] **Step 1: Add `TrackpadGestureRecorderView` examples to the Gallery tab**

In `GalleryTab`, add a section showing `TrackpadGestureRecorderView` in each of the three styles (`.rounded`, `.plain`, `.borderless`), parallel to the existing mouse-input gallery section.

```swift
@State private var galleryGesture1: TrackpadGesture?
@State private var galleryGesture2: TrackpadGesture?
@State private var galleryGesture3: TrackpadGesture?

// in body:
Section {
    HStack(spacing: 16) {
        TrackpadGestureRecorderView($galleryGesture1).style(.rounded).frame(width: 200)
        TrackpadGestureRecorderView($galleryGesture2).style(.plain).frame(width: 200)
        TrackpadGestureRecorderView($galleryGesture3).style(.borderless).frame(width: 200)
    }
} header: {
    Text("Trackpad Gesture")
}
```

Follow the established gallery section pattern.

- [ ] **Step 2: Manual verification**

> Please run `just example` and switch to the Gallery tab to verify all three style variants render correctly.

- [ ] **Step 3: Commit checkpoint**

User handles commits — pause and report:

> Gallery tab updated. Awaiting user manual verification.

---

## Task 11: Documentation — README

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Add `TrackpadGesture` section after the `MouseInput` section**

Insert a new section in `README.md` documenting:

1. `TrackpadGesture` model with example construction
2. `TrackpadGestureRecorderView` SwiftUI usage example
3. `TrackpadGestureRecorderField` AppKit one-line note (mirrors `MouseInputRecorderField`'s treatment)
4. `.onTrackpadGesture()` view modifier
5. Sensitivity behavior (refers to existing scroll-sensitivity section pattern)
6. The `SensitivityMode` / `SensitivityPosition` rename (with one-line migration note for users coming from the previous version that had `ScrollSensitivityMode` / `ScrollSensitivityPosition`). Note explicitly: `MouseInput.scrollSensitivity` keeps its name; only the public enums were renamed.
7. Caveat about 4-finger swipe finger-count detection if it ships with the fallback (only 3-finger reliable).

Keep the section style consistent with existing sections — terse, code examples, table-of-properties format where appropriate.

- [ ] **Step 2: Update Features list at top of README**

Add a bullet point:

```markdown
- Record trackpad gestures (pinch, rotate, 3/4-finger swipe, smart magnify)
```

- [ ] **Step 3: Update CLAUDE.md source structure**

Add the new files to the source-structure list in `CLAUDE.md`:

```markdown
- `TrackpadGesture.swift` — Model: gesture kind + modifiers + sensitivity, Codable, Sendable
- `TrackpadGesture+Matching.swift` — matches(NSEvent) for gesture event types
- `TrackpadGesture+DisplayString.swift` — display strings (e.g. "⌘Pinch In")
- `TrackpadGestureRecorderView.swift` — SwiftUI recorder
- `TrackpadGestureRecorderField.swift` — AppKit recorder with chevron menu picker
- `OnTrackpadGestureModifier.swift` — .onTrackpadGesture() view modifier
- `SensitivityMode.swift` — sensitivity mode + position enums (renamed from ScrollSensitivityMode.swift)
```

- [ ] **Step 4: Commit checkpoint**

User handles commits — pause and report:

> README and CLAUDE.md updated. All tasks complete.

---

## Task 12: Final verification

- [ ] **Step 1: Full build, test, lint, format pass**

```bash
just build && just test && just lint && just format
```

Expected: all green. If `just format` produced changes, review them.

- [ ] **Step 2: Manual smoke test in the example app**

> Please do a final pass in `just example`:
> - Workbench tab: record each gesture kind (pinch in/out, rotate CW/CCW, 3-finger swipes in 4 directions, 4-finger swipes if available, smart magnify)
> - Workbench tab: pick gestures via the chevron menu, confirm modifier capture works (⌘-click on a menu item)
> - Workbench tab: verify `.onTrackpadGesture` fires for each bound gesture, sensitivity slider behavior matches scroll's (0.0 = once, 1.0 = continuous)
> - Gallery tab: all three styles render correctly with gestures
> - Verify recording is blocked when another recorder field is active (focus a shortcut field, then perform a gesture — gesture-binding actions should not fire)

- [ ] **Step 3: Final report to user**

Summarize the work and pause for user to commit / tag a release.
