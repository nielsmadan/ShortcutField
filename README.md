# ShortcutField

[![Swift 6.2](https://img.shields.io/badge/Swift-6.2-orange.svg)](https://swift.org)
[![Platform](https://img.shields.io/badge/platform-macOS%2013%2B-blue.svg)](https://developer.apple.com/macos/)
[![License](https://img.shields.io/badge/license-MIT-lightgrey.svg)](LICENSE)

A unified in-app shortcut recorder for macOS apps. Two types cover the design space:

- **`Shortcut`** — fire-once shortcuts. One step (e.g. `⌘K`, `Right Click`, `Pinch In`) or multi-step (e.g. `⌘K ⌘C`, `A → Right Click`, `⌘K → Pinch In`). The matcher fires the bound action exactly once when the user completes the full sequence.
- **`ContinuousShortcut`** — sensitivity-bearing throttled continuous fire. A single scroll / pinch / rotate gesture with a user-tunable `sensitivity` controlling the throttle rate (e.g. scroll-to-zoom).

Special keys like Tab that SwiftUI's focus system normally intercepts work in both.

![Screenshot](screenshot.png)

### Features

- Record any in-app input: key, mouse button, scroll direction, trackpad gesture (pinch / rotate / smart magnify)
- Multi-step shortcuts (e.g. `⌘K ⌘C`, `A → Right Click`, `⌘K → Pinch In`)
- Sensitivity-throttled continuous gestures via `ContinuousShortcut`
- Match against `NSEvent` and SwiftUI `KeyPress`, including special keys like Tab and Escape
- SwiftUI views and AppKit controls
- `Codable`, `Equatable`, `Hashable`, `Sendable` model
- Customizable placeholder text, text color, and minimum width

## Requirements

- macOS 13+
- Swift 6.2+

## Installation

Add ShortcutField to your project via Swift Package Manager:

```swift
dependencies: [
    .package(url: "https://github.com/nielsmadan/ShortcutField", from: "2.0.0")
]
```

## Usage

See the [Example app](Example/) for a workbench and gallery of all recorder styles.

### Recording fire-once shortcuts (SwiftUI)

```swift
import ShortcutField

struct SettingsView: View {
    @State private var shortcut: Shortcut?

    var body: some View {
        ShortcutRecorderView($shortcut)
            .placeholder("Record Shortcut")
    }
}
```

The recorder accepts whatever the user performs — a single keystroke, a (modified) mouse click, a scroll, a trackpad gesture, or a multi-step sequence. Recording finalizes after a 1-second idle pause OR on a bare left-click anywhere (no modifiers) — the unambiguous "I'm done" gesture.

### Recording continuous (sensitivity-bearing) shortcuts

```swift
import ShortcutField

struct ZoomSettingsView: View {
    @State private var zoomShortcut: ContinuousShortcut?

    var body: some View {
        ContinuousShortcutRecorderView($zoomShortcut)
            .placeholder("Record Zoom")
    }
}
```

A chevron menu next to the field provides a click-only path for picking continuous kinds (scroll / pinch / rotate) without performing them.

### Recording shortcuts (AppKit)

```swift
import ShortcutField

let field = ShortcutRecorderField()
field.onShortcutChange = { shortcut in
    print("Recorded: \(shortcut?.displayString ?? "none")")
}

let continuousField = ContinuousShortcutRecorderField()
continuousField.onShortcutChange = { shortcut in
    print("Recorded: \(shortcut?.displayString ?? "none")")
}
```

### Matching shortcuts

Fire-once with `.onShortcut()`:

```swift
MyView()
    .onShortcut(shortcut) {
        print("Shortcut fired!")
    }
```

For 1-step shortcuts the action fires once on the matching event. For multi-step shortcuts the action fires once when the full sequence completes within the per-step timeout (1 second).

Throttled continuous fire with `.onContinuousShortcut()`:

```swift
MyView()
    .onContinuousShortcut(zoomShortcut) {
        zoomLevel += 0.05
    }
```

For manual matching, use the `matches()` methods directly:

```swift
// Match a single Step against an NSEvent
shortcut.steps[0].matches(event)

// Match a single Step against a SwiftUI KeyPress (only valid for `.key` kinds)
shortcut.steps[0].matches(press)

// Match a ContinuousShortcut against an NSEvent
continuousShortcut.matches(event)
```

### Display strings

```swift
let key = Shortcut(keyCode: UInt16(kVK_Tab), modifiers: [.command, .shift])
print(key.displayString) // "⇧⌘Tab"

let click = Shortcut(kind: .mouseButton(number: 1), modifiers: .control)
print(click.displayString) // "⌃Right Click"

let sequence = Shortcut(steps: [
    .init(keyCode: 40, modifiers: .command),  // ⌘K
    .init(keyCode: 8, modifiers: .command),   // ⌘C
])
print(sequence.displayString) // "⌘K ⌘C"

let zoom = ContinuousShortcut(kind: .pinchIn, modifiers: .command, sensitivity: 0.5)
print(zoom.displayString) // "⌘Pinch In"
```

### Customization

```swift
ShortcutRecorderView($shortcut)
    .textColor(.systemTeal)
    .minimumWidth(180)
```

The same modifiers apply to `ContinuousShortcutRecorderView`.

### Sensitivity (ContinuousShortcut only)

The sensitivity slider controls how often `.onContinuousShortcut()` fires during a single physical gesture: `0.0` fires once per gesture, `1.0` fires on every matching event, intermediate values map to a per-fire cooldown.

```swift
ContinuousShortcutRecorderView($zoomShortcut)
    .sensitivityMode(.discrete)        // .discrete (5 ticks) or .continuous
    .sensitivityPosition(.below)        // .below, .left, or .right
```

Discrete mode snaps to five tick marks (0, 0.25, 0.5, 0.75, 1.0). Continuous is a free 0.0-1.0 slider.

> **Why no swipe gestures?** macOS only delivers `NSEvent.swipe` events to apps when the user has enabled "Swipe between pages: Swipe with three fingers" in System Settings → Trackpad → More Gestures, and 4-finger swipes have no equivalent setting (they're reserved by macOS for Mission Control / App Exposé / switch-between-full-screen-apps). Reliable cross-app multi-finger gesture detection on macOS requires the private `MultitouchSupport` framework (used by apps like BetterTouchTool), which would prevent App Store distribution and risk notarization. ShortcutField stays within public APIs, so swipes are out of scope.

## API

### `Shortcut`

The fire-once umbrella. `Codable`, `Equatable`, `Hashable`, `Sendable`.

| Property/Method | Description |
|---|---|
| `steps: [Step]` | One or more ordered steps (non-empty) |
| `displayString: String` | Steps joined by space, e.g. `⌘K ⌘C` |
| `init(steps:)` | Build from an explicit step list |
| `init(kind:modifiers:)` | Convenience for a 1-step shortcut |
| `init(keyCode:modifiers:)` | Convenience for a 1-step keyboard shortcut |
| `Shortcut.isContinuous(_ kind:) -> Bool` | Whether the kind is a continuous gesture |

#### `Shortcut.Step`

A single recordable input within a shortcut.

| Property/Method | Description |
|---|---|
| `kind: Shortcut.Kind` | `.key(keyCode:)`, `.mouseButton(number:)`, `.scroll(direction:)`, `.pinchIn`, `.pinchOut`, `.rotateClockwise`, `.rotateCounterClockwise`, `.smartMagnify` |
| `modifiers: NSEvent.ModifierFlags` | Modifier flags (Command, Shift, Option, Control) |
| `displayString: String` | Human-readable, e.g. `⌘K`, `⌃Right Click`, `⇧Scroll Up`, `⌘Pinch In` |
| `init(kind:modifiers:)` | Build any kind |
| `init(keyCode:modifiers:)` | Convenience for keyboard steps |
| `matches(_ event: NSEvent) -> Bool` | Match against an NSEvent (any kind) |
| `matches(_ press: KeyPress) -> Bool` | Match against a SwiftUI KeyPress (key kinds only; macOS 14+) |

### `ContinuousShortcut`

Sensitivity-bearing single-step shortcut for throttled continuous fire. `Codable`, `Equatable`, `Hashable`, `Sendable`.

| Property/Method | Description |
|---|---|
| `kind: ContinuousShortcut.Kind` | Continuous kind only — `.scroll`, `.pinchIn/Out`, `.rotateClockwise/CounterClockwise`. Discrete kinds are unrepresentable at the type level. |
| `modifiers: NSEvent.ModifierFlags` | Modifier flags (Command, Shift, Option, Control) |
| `sensitivity: Double` | 0.0 (fire once per gesture) to 1.0 (every matching event), clamped in init |
| `displayString: String` | Human-readable, same format as a single `Shortcut.Step` |
| `init(kind:modifiers:sensitivity:)` | Build with sensitivity (default 0.0) |
| `matches(_ event: NSEvent) -> Bool` | Match against an NSEvent |

#### `ContinuousShortcut.Kind`

The continuous-only subset of `Shortcut.Kind`. Lift to / project from the umbrella type via `asShortcutKind` and `init(_ shortcutKind:)` (the latter returns nil for discrete kinds).

```swift
public enum Kind: Sendable, Equatable, Hashable {
    case scroll(direction: Shortcut.ScrollDirection)
    case pinchIn, pinchOut
    case rotateClockwise, rotateCounterClockwise
}
```

### `ShortcutRecorderView`

SwiftUI recorder for fire-once shortcuts.

| Modifier | Description |
|---|---|
| `.placeholder(_:)` | Text when empty (default: "Record Shortcut") |
| `.recordingPlaceholder(_:)` | Text during recording (default: "Record shortcut…") |
| `.textColor(_:)` | Text color (`NSColor`) |
| `.minimumWidth(_:)` | Minimum intrinsic width in points (default 130). SwiftUI's `.frame(width:)` still wins. |

### `ContinuousShortcutRecorderView`

SwiftUI recorder for sensitivity-bearing continuous shortcuts.

| Modifier | Description |
|---|---|
| `.placeholder(_:)` | Text when empty (default: "Record Continuous") |
| `.recordingPlaceholder(_:)` | Text during recording (default: "Scroll / pinch / rotate…") |
| `.textColor(_:)` | Text color (`NSColor`) |
| `.minimumWidth(_:)` | Minimum intrinsic width in points. SwiftUI's `.frame(width:)` still wins. |
| `.sensitivityMode(_:)` | `.discrete` (default) or `.continuous` |
| `.sensitivityPosition(_:)` | `.below` (default), `.left`, or `.right` — placement of the sensitivity slider |

### AppKit recorder fields

`ShortcutRecorderField` and `ContinuousShortcutRecorderField` are the underlying `NSSearchField` subclasses. Public for direct use.

### `.onShortcut(_:perform:)`

View modifier that fires an action when a fire-once shortcut is performed. Requires macOS 14+.

For 1-step shortcuts the action fires immediately on the matching event. For multi-step shortcuts intermediate events propagate normally; only the final step is consumed. Multiple shortcuts that share a common prefix (e.g. `A B` and `A T`) work correctly — each modifier tracks independently and a shared dispatcher delivers every event to all active matchers.

When an intermediate step uses Tab or Escape, the event is consumed to prevent focus changes. Matching is automatically disabled while any recorder field is active.

### `.onContinuousShortcut(_:perform:)`

View modifier that fires an action repeatedly during a continuous gesture, throttled by the bound shortcut's `sensitivity`. Requires macOS 14+.

Uses an `NSEvent` local monitor to match scroll, magnify, and rotate events globally within the app. The view does not need focus. Matching is automatically disabled while any recorder field is active.

### `ShortcutTracking`

`@MainActor` namespace exposing one read-only flag.

| Property | Description |
|---|---|
| `ShortcutTracking.isActive: Bool` | `true` when at least one `.onShortcut()` modifier is partway through matching a multi-step shortcut. Used to suppress the macOS system alert beep on intermediate keys (see [Suppressing the system alert sound](#suppressing-the-system-alert-sound)). |

## Notes

### Recorder behavior

Both `ShortcutRecorderField` and `ContinuousShortcutRecorderField` share these behaviors:

- **Click** the field to start recording
- **Escape** cancels recording without saving
- **Delete** clears the current shortcut (multi-step recorder: only when no steps have been recorded yet)
- Only one recorder can be active at a time. Focusing a new recorder ends the previous one.

`ShortcutRecorderField` finalizes after a 1-second pause between captured steps OR on a bare left-click anywhere (no modifiers). Each captured step resets the idle timer. **Bare left-click can't be a step** — it's reserved for UI interaction (focusing controls, dismissing the recorder) and serves as the "finalize" gesture. Modified left clicks (e.g. `⌃Left Click`) are capturable. All other inputs — including right click and other mouse buttons — can be captured anywhere with no modifiers required.

`ContinuousShortcutRecorderField` finalizes on the first matching gesture event (after threshold accumulation for pinch / rotate). It only accepts continuous kinds; keys, mouse buttons, and smart-magnify are ignored during recording. A chevron menu provides click-only entry for picking gesture kinds without performing them.

### Suppressing the system alert sound

When using `.onShortcut()` with multi-step shortcuts, intermediate key events propagate through the responder chain. If nothing else handles them, macOS plays the system alert sound.

To suppress the beep only during active sequence input (while still allowing it for random unhandled keys), check `ShortcutTracking.isActive` in a `noResponder(for:)` override on your window:

```swift
import ShortcutField

class MainWindow: NSWindow {
    override func noResponder(for eventSelector: Selector) {
        if eventSelector == #selector(keyDown(with:)),
           ShortcutTracking.isActive {
            return // suppress beep only during in-progress multi-step matches
        }
        super.noResponder(for: eventSelector)
    }
}
```

`ShortcutTracking.isActive` is `true` whenever at least one `.onShortcut()` modifier has matched one or more intermediate steps and is waiting for the next event. It resets automatically on completion, timeout, or mismatch.

### How does this differ from KeyboardShortcuts?

[KeyboardShortcuts](https://github.com/sindresorhus/KeyboardShortcuts) registers **global** (system-wide) hotkeys. ShortcutField records **in-app** shortcuts that you match yourself via `.onShortcut()` or `.onContinuousShortcut()` view modifiers. ShortcutField also supports multi-step shortcuts (chord sequences like `⌘K ⌘C`) and non-keyboard inputs (mouse buttons, scroll directions, trackpad gestures), neither of which KeyboardShortcuts covers.

## Contributing

Issues and pull requests are welcome.

## Acknowledgments

ShortcutField's key mapping and display logic is adapted from [KeyboardShortcuts](https://github.com/sindresorhus/KeyboardShortcuts) by Sindre Sorhus (MIT license).

## License

MIT
