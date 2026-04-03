# Scroll Sensitivity for Mouse Input Shortcuts

## Problem

When a user binds an action to a scroll direction (e.g., "Scroll Up"), the `.onMouseInput()` modifier fires on every matching scroll event. Continuous scrolling produces many events rapidly, which may not be desirable — some actions should fire once per scroll gesture, others should fire repeatedly.

## Design

### Model: `scrollSensitivity` on `MouseInput`

Add a `scrollSensitivity: Double` property to `MouseInput`, clamped to 0.0-1.0, defaulting to 0.0. Only meaningful for `.scroll` inputs; ignored for `.button` inputs. Persisted via Codable.

The property is `let` (immutable, like `kind` and `modifiers`). To change sensitivity, create a new `MouseInput` with the desired value. The `init` clamps the value to `0.0...1.0`.

```swift
public struct MouseInput: Sendable, Equatable, Codable {
    public let kind: InputKind
    public let modifiers: NSEvent.ModifierFlags
    public let scrollSensitivity: Double  // 0.0-1.0, clamped in init. Default: 0.0

    public init(kind: InputKind, modifiers: NSEvent.ModifierFlags, scrollSensitivity: Double = 0.0) {
        self.kind = kind
        self.modifiers = modifiers.intersection([.shift, .control, .option, .command])
        self.scrollSensitivity = min(1.0, max(0.0, scrollSensitivity))
    }
}
```

### Sensitivity → Cooldown Mapping

**Special case: 0.0** = fire once per scroll gesture. Suppress all further events until scrolling stops (350ms idle window). Then re-arm.

**Special case: 1.0** = no throttling. Every matched scroll event fires.

**Values in between (0.0 < s < 1.0):** Map to a cooldown via interpolation. The five stepper presets serve as reference points:

| Stepper position | Value | Cooldown |
|-----------------|-------|----------|
| 1 | 0.0 | fire once (special) |
| 2 | 0.25 | 1000ms |
| 3 | 0.5 | 500ms |
| 4 | 0.75 | 250ms |
| 5 | 1.0 | 0ms (special) |

For continuous values between the reference points, linearly interpolate the cooldown. For example, 0.375 (halfway between 0.25 and 0.5) → 750ms. Values just above 0.0 (e.g., 0.01) use a very long cooldown (~1900ms) via extrapolation from the 0.25→1000ms and 0.0 boundary.

**Cooldown formula** for 0.0 < s < 1.0:

The reference points (excluding the 0.0 special case) form a curve from s=0.25→1000ms down to s=1.0→0ms. Linearly interpolate: `cooldown = 1000.0 * (1.0 - s) / 0.75` for s in the 0.25-1.0 range. For s < 0.25 (but > 0.0), extrapolate: values near 0.0 get very long cooldowns approaching ~1333ms, providing a near-fire-once experience without the special idle-detection logic.

Simplified: `cooldownMs = max(0, 1000.0 * (1.0 - s) / 0.75)` for any s > 0.0.

- s = 0.01 → ~1320ms
- s = 0.25 → 1000ms
- s = 0.5 → 667ms
- s = 0.75 → 333ms
- s = 0.99 → ~13ms
- s = 1.0 → 0ms

**Fire-once mechanism (s = 0.0):** After the action fires, set a `suppressed` flag. On each subsequent scroll event, schedule (or reschedule) a `DispatchWorkItem` via `DispatchQueue.main.asyncAfter` with a 350ms delay to clear the `suppressed` flag. When the block fires (no scroll events for 350ms), the flag clears and the next scroll gesture can fire again. The 350ms window is generous enough to avoid re-arming mid-gesture on trackpads.

### Modifier Changes (`OnMouseInputModifier`)

**State management:** Since the NSEvent monitor closure runs outside SwiftUI's update cycle, throttle state is held in a reference-type `ScrollThrottleState` class that the closure captures:

```swift
@MainActor
final class ScrollThrottleState {
    var lastFireDate: Date?
    var suppressed = false
    var rearmWorkItem: DispatchWorkItem?

    func reset() {
        lastFireDate = nil
        suppressed = false
        rearmWorkItem?.cancel()
        rearmWorkItem = nil
    }
}
```

The modifier holds this as `@State private var throttleState = ScrollThrottleState()`.

On a matching scroll event:
1. If `mouseInput.kind` is `.button`, fire immediately (sensitivity doesn't apply).
2. Read `mouseInput.scrollSensitivity`.
3. If 0.0: use fire-once logic (check `suppressed` flag, schedule re-arm).
4. If 1.0: fire immediately.
5. Otherwise: compute cooldown, check elapsed time since `lastFireDate`.

When `mouseInput` changes (including sensitivity-only changes), the existing `onChange(of: mouseInput)` handler reinstalls the monitor and calls `throttleState.reset()`. Since `scrollSensitivity` participates in `Equatable`, a sensitivity change produces a new `MouseInput` value and triggers `onChange`.

On `onDisappear`, cancel any pending rearm work item.

### Codable

The `scrollSensitivity` field encodes as a `Double` under the key `"scrollSensitivity"`. On decode, use `decodeIfPresent` to default to 0.0 if the key is missing (backward compatibility):

```swift
scrollSensitivity = min(1.0, max(0.0,
    try container.decodeIfPresent(Double.self, forKey: .scrollSensitivity) ?? 0.0
))
```

### Recorder UI

The `MouseInputRecorderView` (and `MouseInputRecorderField`) gain a `sensitivityMode` configuration:

```swift
public enum ScrollSensitivityMode: Sendable {
    /// User adjusts sensitivity via a discrete 1-5 stepper (default).
    /// Maps to values: 0.0, 0.25, 0.5, 0.75, 1.0.
    case stepper
    /// User adjusts sensitivity via a continuous 0.0-1.0 slider.
    case continuous
    /// Sensitivity UI is hidden. The developer sets sensitivity programmatically
    /// via the MouseInput value in the binding.
    case hidden
}
```

**SwiftUI API:**
```swift
MouseInputRecorderView($mouseInput)
    .sensitivityMode(.continuous)

MouseInputRecorderView($mouseInput)
    .sensitivityMode(.hidden)
```

**AppKit API:**
```swift
field.sensitivityMode = .hidden
```

**Behavior by mode:**

**`.stepper` (default):** When a `.scroll` input is recorded, a small `NSStepper` (5 positions) appears inline next to the display string. Each position maps to 0.0, 0.25, 0.5, 0.75, 1.0. Adjusting the stepper creates a new `MouseInput` with the corresponding sensitivity value.

**`.continuous`:** Same position, uses an `NSSlider` with 0.0-1.0 range. The slider value is used directly as the `scrollSensitivity`. Allows fine-grained tuning between the preset points.

**`.hidden`:** No sensitivity control is shown. The developer sets `scrollSensitivity` when constructing the `MouseInput` programmatically.

In all modes, the sensitivity control is only visible when `mouseInput?.kind` is `.scroll`. The display string does NOT include the sensitivity value.

### What Changes

**Modified files:**
- `MouseInput.swift` — add `scrollSensitivity` property, update init/Codable
- `OnMouseInputModifier.swift` — add `ScrollThrottleState` class, throttling logic, cooldown formula
- `MouseInputRecorderField.swift` — add stepper/slider UI for scroll inputs, `sensitivityMode` property
- `MouseInputRecorderView.swift` — add `.sensitivityMode()` modifier, pass through to field

**No changes to:**
- `MouseInput+Matching.swift` — matching logic stays the same
- `MouseInput+DisplayString.swift` — display string does not change

### Testing

- Unit tests for cooldown computation at various sensitivity values
- Unit test for fire-once (0.0) and no-throttle (1.0) special cases
- Unit test for Codable backward compatibility (missing key defaults to 0.0)
- Unit test for clamping (values outside 0.0-1.0 clamped in init and decode)
- Unit test for Equatable: same kind/modifiers but different sensitivity are not equal
- Manual testing in Example app: record scroll input, test all three sensitivity modes, verify fire rate changes
