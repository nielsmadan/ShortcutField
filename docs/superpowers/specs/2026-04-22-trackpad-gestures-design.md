# Trackpad Gestures

Add support for recording and recognizing system-recognized trackpad gestures (pinch, rotate, 3/4-finger swipe, smart magnify) as in-app shortcut bindings, peer to `Shortcut` and `MouseInput`.

## Scope

v1 supports only **system-recognized gestures** — the ones macOS pre-recognizes and delivers as discrete `NSEvent` types. Custom multi-touch recognizers (via `NSTouch`) and private-framework gestures are explicitly out of scope.

Supported gestures (13 total, ignoring modifiers):

| Kind | NSEvent type |
|---|---|
| Pinch In | `.magnify` (magnification > 0) |
| Pinch Out | `.magnify` (magnification < 0) |
| Rotate Clockwise | `.rotate` (rotation < 0) |
| Rotate Counter-Clockwise | `.rotate` (rotation > 0) |
| 3-Finger Swipe ↑/↓/←/→ | `.swipe` (deltaX/deltaY sign, finger count from `allTouches().count`) |
| 4-Finger Swipe ↑/↓/←/→ | `.swipe` (same) |
| Smart Magnify | `.smartMagnify` |

If `NSEvent.swipe` does not reliably expose finger count at recognition time, v1 ships 3-finger swipes only (4-finger cases become future work via a file-level TODO). This will be verified during implementation.

Modifier keys (⌘, ⇧, ⌥, ⌃) are supported alongside gestures — e.g. `⌘Pinch In`, `⇧3-Finger Swipe ←` — matching the existing `MouseInput` convention.

## Model

### `TrackpadGesture`

New type in `TrackpadGesture.swift`. New peer to `Shortcut` and `MouseInput`, not a case on either.

```swift
public struct TrackpadGesture: Sendable, Equatable {
    public enum Kind: Sendable, Equatable {
        case pinchIn
        case pinchOut
        case rotateClockwise
        case rotateCounterClockwise
        case swipe(fingers: Int, direction: SwipeDirection)  // fingers: 3 or 4
        case smartMagnify
    }

    public enum SwipeDirection: String, Sendable, Equatable, Codable {
        case up, down, left, right
    }

    public let kind: Kind
    public let modifiers: NSEvent.ModifierFlags
    public let sensitivity: Double   // 0.0–1.0, clamped on init

    public init(kind: Kind, modifiers: NSEvent.ModifierFlags, sensitivity: Double = 0.0)
}
```

- `modifiers` is masked to `[.shift, .control, .option, .command]` in init (same as `Shortcut` / `MouseInput`).
- `sensitivity` is clamped to `0.0...1.0` in init. Only meaningful for `.pinchIn`, `.pinchOut`, `.rotateClockwise`, `.rotateCounterClockwise`. For `.swipe` and `.smartMagnify`, init forces it to `0.0`.
- `swipe(fingers:direction:)` requires `fingers` ∈ `{3, 4}`; init clamps to 3 if out-of-range.
- Codable: same pattern as `MouseInput`. Forward-compatible via `decodeIfPresent` for `sensitivity` key (defaults to 0.0 if missing).

### Sensitivity semantics

`sensitivity` mirrors `MouseInput.scrollSensitivity` exactly:

- `0.0` — fire once per gesture. Suppressed until the gesture reaches `.ended` phase. Next gesture re-arms.
- `1.0` — no throttling. Fire on every `.changed` event.
- In between — cooldown-throttled via the existing formula `cooldownMs = max(0, 1000 * (1 - s) / 0.75)`.

For continuous gestures within a single physical gesture, **instantaneous direction wins** (Q6). If the user pinches in then reverses to pinch out without lifting, "Pinch Out" starts firing based on the current delta sign.

## Matching

### `TrackpadGesture+Matching.swift`

```swift
public extension TrackpadGesture {
    func matches(_ event: NSEvent) -> Bool
}
```

Matching rules by kind:

- **`.pinchIn` / `.pinchOut`**: `event.type == .magnify`, modifiers match, and `event.magnification` sign matches the bound direction. Sub-threshold deltas (|magnification| < 0.1 per `.changed` step OR cumulative per-gesture threshold 0.05) do not match — prevents jitter. Threshold tuning may change during implementation.
- **`.rotateClockwise` / `.rotateCounterClockwise`**: `event.type == .rotate`, modifiers match, `event.rotation` sign matches (positive rotation = counter-clockwise per AppKit convention). Threshold ~3° per `.changed` step.
- **`.swipe(fingers:direction:)`**: `event.type == .swipe`, modifiers match, `deltaX`/`deltaY` sign matches direction (larger-magnitude axis wins), and `event.allTouches().count` matches `fingers`. If finger-count detection is unreliable, v1 matches only 3-finger swipes and ignores the `fingers` value.
- **`.smartMagnify`**: `event.type == .smartMagnify`, modifiers match.

Modifier comparison masks to `[.shift, .control, .option, .command]` before comparing, same as `MouseInput+Matching`.

## Recognition

### `.onTrackpadGesture()` view modifier

New file `OnTrackpadGestureModifier.swift`.

```swift
@available(macOS 14.0, *)
public extension View {
    func onTrackpadGesture(_ gesture: TrackpadGesture?, perform action: @escaping () -> Void) -> some View
}
```

**Behavior:**
- Uses `NSEvent.addLocalMonitorForEvents(matching: [.magnify, .rotate, .swipe, .smartMagnify])`.
- Blocked while `ShortcutRecordingState.isAnyRecording` is true (same as `.onMouseInput`).
- For continuous gestures (pinch/rotate), throttled via shared `ThrottleState` (see rename below). On `.ended` or `.cancelled` phase, throttle state resets so the next gesture starts fresh.
- Discrete gestures (swipe, smart magnify) fire once per event, no throttling.
- Sensitivity changes reinstall/reset the monitor via `onChange(of: gesture)`, same pattern as `OnMouseInputModifier`.

### Shared throttle state rename

`ScrollThrottleState` in `OnMouseInputModifier.swift` is renamed to **`ThrottleState`** (generic, reused by `OnTrackpadGestureModifier`). It stays internal. Either stays in `OnMouseInputModifier.swift` or moves to a new `ThrottleState.swift` — implementation discretion.

## Display Strings

### `TrackpadGesture+DisplayString.swift`

```swift
public extension TrackpadGesture {
    var displayString: String   // e.g. "⌃Pinch In", "⇧3-Finger Swipe ↑"
}
```

| Kind | Display |
|---|---|
| `.pinchIn` | `Pinch In` |
| `.pinchOut` | `Pinch Out` |
| `.rotateClockwise` | `Rotate CW` |
| `.rotateCounterClockwise` | `Rotate CCW` |
| `.swipe(3, .up)` | `3-Finger Swipe ↑` |
| `.swipe(3, .down)` | `3-Finger Swipe ↓` |
| `.swipe(3, .left)` | `3-Finger Swipe ←` |
| `.swipe(3, .right)` | `3-Finger Swipe →` |
| `.swipe(4, .up)` | `4-Finger Swipe ↑` |
| `.swipe(4, .down)` | `4-Finger Swipe ↓` |
| `.swipe(4, .left)` | `4-Finger Swipe ←` |
| `.swipe(4, .right)` | `4-Finger Swipe →` |
| `.smartMagnify` | `Smart Magnify` |

Modifier prefix uses the same `modifiers.symbolicRepresentation` helper as `Shortcut` / `MouseInput`.

## Recorder Components

### `TrackpadGestureRecorderField` (AppKit)

New `NSSearchField` subclass. Structure mirrors `MouseInputRecorderField`.

**Behavior on focus:**
- Click field → enters recording mode, installs event monitor for `[.magnify, .rotate, .swipe, .smartMagnify, .keyDown]`.
- Perform gesture → captured, field finalizes, blurs. For continuous gestures (pinch/rotate), finalize on the first `.changed` event that crosses the direction threshold — same threshold constants the matcher uses.
- Escape cancels recording; Delete clears the stored gesture (same as existing recorders).
- Click outside → ends recording (same as existing recorders).
- Blocked by `ShortcutRecordingState` so only one recorder is active at a time.

**List picker (approved in Q4 option A):** small chevron button on the right side of the field, inside the search-field cell next to the clear button. Opens an `NSMenu` listing all 13 gestures, organized into sections:

- Pinch → Pinch In, Pinch Out
- Rotate → Rotate CW, Rotate CCW
- Swipe (3-finger) → ↑, ↓, ←, →
- Swipe (4-finger) → ↑, ↓, ←, →
- Smart Magnify

Menu item selection captures `NSApp.currentEvent?.modifierFlags` at click time so ⌘-clicking a menu item produces a modified gesture (`⌘Pinch In`). If modifier capture proves unreliable with `NSMenu`, fall back to recording modifiers only via live-recording (document the limitation).

**Properties (mirrors `MouseInputRecorderField`):**
- `trackpadGesture: TrackpadGesture?`
- `defaultPlaceholder: String` (default `"Record Gesture"`)
- `recordingPlaceholder: String` (default `"Perform gesture…"`)
- `fieldTextColor: NSColor?`
- `fieldBackgroundColor: NSColor?`
- `onTrackpadGestureChange: ((TrackpadGesture?) -> Void)?`
- `sensitivityMode: SensitivityMode` (default `.discrete`)
- `sensitivityPosition: SensitivityPosition` (default `.below`)

**Sensitivity UI:** reuses the existing sensitivity slider/stepper implementation. Visible only when the recorded gesture's kind is continuous (`.pinchIn`, `.pinchOut`, `.rotateClockwise`, `.rotateCounterClockwise`). Hidden for swipe and smart-magnify.

### `TrackpadGestureRecorderView` (SwiftUI)

`NSViewRepresentable` wrapper. Modifier API mirrors `MouseInputRecorderView`.

```swift
@State private var gesture: TrackpadGesture?

TrackpadGestureRecorderView($gesture)
    .placeholder("Record Gesture")
    .recordingPlaceholder("Perform gesture…")
    .style(.rounded)
    .textColor(.systemTeal)
    .fieldBackgroundColor(NSColor.systemBlue.withAlphaComponent(0.1))
    .sensitivityMode(.discrete)
    .sensitivityPosition(.below)
```

## Public API rename: `SensitivityMode` / `SensitivityPosition`

`ScrollSensitivityMode` → **`SensitivityMode`**. `ScrollSensitivityPosition` → **`SensitivityPosition`**. The enum cases stay the same (`.discrete`, `.continuous`, `.hidden` for mode; `.below`, `.left`, `.right` for position). The file `ScrollSensitivityMode.swift` renames to `SensitivityMode.swift`.

Call-site impact:
- `MouseInputRecorderField.sensitivityMode: ScrollSensitivityMode` → `SensitivityMode`
- `MouseInputRecorderView.sensitivityMode(_:)` takes `SensitivityMode`
- Same for `.sensitivityPosition`

This is a breaking public API change. Because the project is pre-1.0 in gesture support terms and the rename is mechanical, callers only need to rename the enum type. Ship under a minor version bump with a one-line migration note in the README.

## Edge Cases

- **Sub-threshold pinch/rotate:** gestures whose cumulative motion never crosses the direction threshold do not fire and do not capture during recording. User retries.
- **Concurrent recorders:** blocked by existing `ShortcutRecordingState.isAnyRecording`.
- **Modifier flags on swipe:** captured from the swipe event directly, not from a lagging modifier-up event.
- **Finger count on swipe:** see Scope section — if `allTouches().count` is unreliable at recognition time, v1 ships 3-finger only.
- **Gesture cancelled by OS:** `.cancelled` phase arrives; throttle state resets same as `.ended`.
- **Smart magnify during recording:** fires on `.began` phase only (it is a discrete event by construction).
- **No gesture event sources available:** local monitor returns nothing; no crash, no false fires.

## Files

**New:**
- `Sources/ShortcutField/TrackpadGesture.swift`
- `Sources/ShortcutField/TrackpadGesture+Matching.swift`
- `Sources/ShortcutField/TrackpadGesture+DisplayString.swift`
- `Sources/ShortcutField/TrackpadGestureRecorderField.swift`
- `Sources/ShortcutField/TrackpadGestureRecorderView.swift`
- `Sources/ShortcutField/OnTrackpadGestureModifier.swift`

**Renamed:**
- `Sources/ShortcutField/ScrollSensitivityMode.swift` → `SensitivityMode.swift`; types inside renamed accordingly.

**Modified:**
- `Sources/ShortcutField/MouseInputRecorderField.swift` — update enum references.
- `Sources/ShortcutField/MouseInputRecorderView.swift` — update enum references in `.sensitivityMode(_:)` / `.sensitivityPosition(_:)` signatures.
- `Sources/ShortcutField/OnMouseInputModifier.swift` — rename `ScrollThrottleState` → `ThrottleState`; updated to be reused by the gesture modifier.
- `Example/` — add "Trackpad Gesture" section to workbench and gallery tabs.
- `README.md` — document `TrackpadGesture`, `TrackpadGestureRecorderView`, `TrackpadGestureRecorderField`, `.onTrackpadGesture()`, the `SensitivityMode` / `SensitivityPosition` rename, and the finger-count caveat if it ships with that limitation.

**No changes to:**
- `Shortcut.swift`, `Shortcut+*.swift`, `ShortcutRecorderField.swift`, `ShortcutRecorderView.swift`, `OnShortcutModifier.swift`
- `ShortcutSequence.swift`, `ShortcutSequenceRecorderField.swift`, `ShortcutSequenceRecorderView.swift`, `OnShortcutSequenceModifier.swift`
- `MouseInput.swift`, `MouseInput+Matching.swift`, `MouseInput+DisplayString.swift`

## Testing

**Unit:**
- `TrackpadGesture` init: modifier masking, sensitivity clamping, sensitivity forced to 0 for discrete kinds, `swipe` finger clamping.
- `Codable` round-trip for every kind; `decodeIfPresent` defaults `sensitivity` to 0 when missing (backward compat).
- `Equatable`: same kind/modifiers but different sensitivity are not equal; different swipe finger counts not equal.
- `displayString` for every kind, with and without modifiers.
- `matches(_:)` using synthesized `NSEvent`s: correct kind + sign + modifiers returns true; mismatches return false; sub-threshold deltas return false.
- Throttle behavior: existing `ScrollThrottleState` tests cover the formula; a new gesture-specific test verifies reset on `.ended` phase.

**Manual (Example app):**
- "Trackpad Gesture" section in workbench and gallery tabs.
- Record each gesture kind via live recording.
- Record each gesture kind via chevron menu picker, including with modifier keys held.
- Bind `.onTrackpadGesture` to an action and verify firing during the gesture (sensitivity 0.0 = once, 1.0 = continuous).
- Verify matching is blocked while a recorder field is active.
