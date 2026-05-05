# ShortcutField

[![Swift 6.2](https://img.shields.io/badge/Swift-6.2-orange.svg)](https://swift.org)
[![Platform](https://img.shields.io/badge/platform-macOS%2013%2B-blue.svg)](https://developer.apple.com/macos/)
[![License](https://img.shields.io/badge/license-MIT-lightgrey.svg)](LICENSE)

A unified in-app shortcut recorder for macOS apps. Record, display, and match any single-event input — keyboard keys, mouse buttons, scroll directions, and trackpad gestures — through one `Shortcut` type, recorder, view, and view modifier. Special keys like Tab that SwiftUI's focus system normally intercepts work too.

![Screenshot](screenshot.png)

### Features

- Record any in-app input shortcut: key, mouse button, scroll direction, trackpad gesture (pinch / rotate / smart magnify)
- Sequential keyboard shortcuts (e.g. `⌘K ⌘C`)
- Match shortcuts against `NSEvent` and SwiftUI `KeyPress`, including special keys like Tab and Escape
- SwiftUI views and AppKit controls
- `Codable`, `Equatable`, `Hashable`, `Sendable` model
- Three visual styles: rounded, plain, borderless
- Custom text and background colors
- Sensitivity throttling for continuous inputs (scroll, pinch, rotate)

## Requirements

- macOS 13+
- Swift 6.2+

## Installation

Add ShortcutField to your project via Swift Package Manager:

```swift
dependencies: [
    .package(url: "https://github.com/nielsmadan/ShortcutField", from: "1.1.0")
]
```

## Usage

See the [Example app](Example/) for a workbench and gallery of all recorder styles.

### Recording Shortcuts (SwiftUI)

```swift
import ShortcutField

struct SettingsView: View {
    @State private var shortcut: Shortcut?

    var body: some View {
        ShortcutRecorderView($shortcut)
            .placeholder("Record Shortcut")
            .style(.rounded)
    }
}
```

The unified recorder accepts a key press, a (modified) mouse click, a scroll, or a trackpad gesture. A chevron menu next to the field provides a click-only path for non-keyboard kinds (mouse buttons, scroll directions, pinch / rotate / smart magnify).

### Recording Shortcuts (AppKit)

```swift
import ShortcutField

let field = ShortcutRecorderField()
field.onShortcutChange = { shortcut in
    print("Recorded: \(shortcut?.displayString ?? "none")")
}
```

### Matching Shortcuts

The `.onShortcut()` modifier handles every shortcut kind automatically (keys, mouse buttons, scroll, gestures), and throttles continuous kinds per the shortcut's `sensitivity`:

```swift
MyView()
    .onShortcut(shortcut) {
        print("Shortcut fired!")
    }
```

For manual matching, use the `matches()` methods directly:

```swift
// Match against NSEvent (covers all kinds)
shortcut.matches(event)

// Match against SwiftUI KeyPress (only valid for `.key` kinds)
shortcut.matches(press)
```

### Display Strings

```swift
let key = Shortcut(keyCode: UInt16(kVK_Tab), modifiers: [.command, .shift])
print(key.displayString) // "⇧⌘Tab"

let pinch = Shortcut(kind: .pinchIn, modifiers: .command, sensitivity: 0.5)
print(pinch.displayString) // "⌘Pinch In"

let click = Shortcut(kind: .mouseButton(number: 1), modifiers: .control)
print(click.displayString) // "⌃Right Click"
```

### Styles

```swift
ShortcutRecorderView($shortcut).style(.rounded)    // Default
ShortcutRecorderView($shortcut).style(.plain)       // Minimal border
ShortcutRecorderView($shortcut).style(.borderless)  // No border
```

### Colors

```swift
ShortcutRecorderView($shortcut)
    .textColor(.systemTeal)
    .fieldBackgroundColor(NSColor.systemBlue.withAlphaComponent(0.1))
```

Setting a background color uses a layer-backed background because `NSSearchFieldCell` does not render `NSTextField.backgroundColor`.

### Sensitivity

For continuous kinds (scroll, pinch, rotate), the recorder shows a sensitivity slider that controls how often `.onShortcut()` fires during a single physical gesture: `0.0` fires once per gesture, `1.0` fires on every matching event, intermediate values map to a per-fire cooldown.

```swift
ShortcutRecorderView($shortcut)
    .sensitivityMode(.discrete)        // .discrete (5 ticks), .continuous, or .hidden
    .sensitivityPosition(.below)        // .below, .left, or .right
```

Discrete mode snaps to five tick marks (0, 0.25, 0.5, 0.75, 1.0). Continuous is a free 0.0-1.0 slider. Hidden removes the control entirely (set the value programmatically via the binding). The slider is only shown when the current shortcut's kind is continuous; for discrete kinds (key, mouse button, smart magnify) it disappears.

> **Why no swipe gestures?** macOS only delivers `NSEvent.swipe` events to apps when the user has enabled "Swipe between pages: Swipe with three fingers" in System Settings → Trackpad → More Gestures, and 4-finger swipes have no equivalent setting (they're reserved by macOS for Mission Control / App Exposé / switch-between-full-screen-apps). Reliable cross-app multi-finger gesture detection on macOS requires the private `MultitouchSupport` framework (used by apps like BetterTouchTool), which would prevent App Store distribution and risk notarization. ShortcutField stays within public APIs, so swipes are out of scope.

## API

### `Shortcut`

The unified shortcut model. `Codable`, `Equatable`, `Hashable`, `Sendable`.

| Property/Method | Description |
|---|---|
| `kind: Kind` | `.key(keyCode:)`, `.mouseButton(number:)`, `.scroll(direction:)`, `.pinchIn`, `.pinchOut`, `.rotateClockwise`, `.rotateCounterClockwise`, `.smartMagnify` |
| `modifiers: NSEvent.ModifierFlags` | Modifier flags (Command, Shift, Option, Control) |
| `sensitivity: Double` | 0.0 (fire once per gesture) to 1.0 (every event); only meaningful for continuous kinds |
| `displayString: String` | Human-readable, e.g. `⌘K`, `⌃Right Click`, `⇧Scroll Up`, `⌘Pinch In` |
| `init(kind:modifiers:sensitivity:)` | Build any kind |
| `init(keyCode:modifiers:)` | Convenience for keyboard shortcuts |
| `matches(_ event: NSEvent) -> Bool` | Match against an NSEvent (any kind) |
| `matches(_ press: KeyPress) -> Bool` | Match against a SwiftUI KeyPress (key kinds only; macOS 14+) |
| `Shortcut.isContinuous(_ kind:) -> Bool` | Whether the kind benefits from sensitivity throttling |

### `ShortcutRecorderView`

SwiftUI recorder component.

| Modifier | Description |
|---|---|
| `.placeholder(_:)` | Text when empty (default: "Record Shortcut") |
| `.recordingPlaceholder(_:)` | Text during recording (default: "Press / click / scroll / gesture…") |
| `.style(_:)` | `.rounded`, `.plain`, or `.borderless` |
| `.textColor(_:)` | Text color (`NSColor`) |
| `.fieldBackgroundColor(_:)` | Background color (`NSColor`); uses a layer because `NSSearchFieldCell` ignores `backgroundColor` |
| `.sensitivityMode(_:)` | `.discrete` (default), `.continuous`, or `.hidden` — only shown for continuous kinds |
| `.sensitivityPosition(_:)` | `.below` (default), `.left`, or `.right` — placement of the sensitivity slider |

### `ShortcutRecorderField`

AppKit recorder (`NSSearchField` subclass). Also public for direct use.

### `.onShortcut(_:perform:)`

View modifier that fires an action when a shortcut is detected. Requires macOS 14+.

Uses an `NSEvent` local monitor to match key, mouse, scroll, and trackpad gesture events globally within the app, including special keys like Tab. The view does not need focus. Matching is automatically disabled while any recorder field is active. Continuous kinds (scroll, pinch, rotate) are throttled per the shortcut's `sensitivity`.

### `ShortcutSequence`

A sequential keyboard shortcut composed of multiple steps. `Codable`, `Equatable`, `Sendable`.

```swift
let sequence = ShortcutSequence(steps: [
    Shortcut(keyCode: 40, modifiers: .command),  // ⌘K
    Shortcut(keyCode: 8, modifiers: .command),   // ⌘C
])
print(sequence.displayString) // "⌘K ⌘C"
```

The sequence's recorder field currently only accepts keyboard input (each step is a `.key(...)` shortcut). The model itself holds an array of `Shortcut`, so it can be constructed programmatically with any kind, but the live recorder is keyboard-only for now.

| Property | Description |
|---|---|
| `steps: [Shortcut]` | Ordered steps (at least 1 required) |
| `displayString: String` | Human-readable, e.g. "⌘K ⌘C" |

### `ShortcutSequenceRecorderView`

SwiftUI recorder for sequential shortcuts.

```swift
@State private var sequence: ShortcutSequence?

ShortcutSequenceRecorderView($sequence)
    .placeholder("Record Sequence")
    .style(.rounded)
```

Press keys in order. The recording finalizes after a 1-second pause.

| Modifier | Description |
|---|---|
| `.placeholder(_:)` | Text when empty (default: "Record Sequence") |
| `.recordingPlaceholder(_:)` | Text during recording (default: "Press keys...") |
| `.style(_:)` | `.rounded`, `.plain`, or `.borderless` |
| `.textColor(_:)` | Text color (`NSColor`) |
| `.fieldBackgroundColor(_:)` | Background color (`NSColor`); uses a layer because `NSSearchFieldCell` ignores `backgroundColor` |

### `ShortcutSequenceRecorderField`

AppKit sequential recorder (`NSSearchField` subclass). Also public for direct use.

### `.onShortcutSequence(_:perform:)`

View modifier that fires an action when a shortcut sequence is pressed. Requires macOS 14+.

```swift
MyView()
    .onShortcutSequence(sequence) {
        print("Sequence matched!")
    }
```

Each modifier tracks independently, while an internal shared dispatcher delivers each key event to all active sequence matchers. That lets sequences with a common prefix (e.g. `⌘K ⌘C` and `⌘K ⌘T`) work correctly.

When an intermediate step uses Tab or Escape, the event is consumed to prevent focus changes. The final matching step is always consumed. Other intermediate keys propagate normally through the responder chain (see [Suppressing the system alert sound](#suppressing-the-system-alert-sound) below). Matching is automatically disabled while any recorder field is active.

## Notes

### Recorder behavior

Both `ShortcutRecorderField` and `ShortcutSequenceRecorderField` share these behaviors:

- **Click** the field to start recording
- **Escape** cancels recording without saving
- **Delete** clears the current shortcut or sequence (sequence recorder: only when no steps have been recorded yet)
- **Click outside** the field finalizes the recording
- Only one recorder can be active at a time. Focusing a new recorder ends the previous one.

`ShortcutRecorderField` also accepts mouse, scroll, and trackpad gesture input. Bare left clicks (no modifiers) are reserved for UI interaction and not captured; modified left clicks (e.g. `⌃Left Click`) are. A chevron button on the trailing edge opens a menu of pickable non-keyboard kinds for click-only entry. Continuous gestures (pinch, rotate) finalize once a small cumulative threshold is exceeded; discrete gestures (smart magnify) finalize on the first matching event.

The sequence recorder finalizes after a **1-second pause** between key presses. Each key press resets the timer.

### Suppressing the system alert sound

When using `.onShortcutSequence()`, intermediate key events propagate through the responder chain. If nothing else handles them, macOS plays the system alert sound. This does not affect `.onShortcut()`, which consumes its key event immediately.

To suppress the beep only during active sequence input (while still allowing it for random unhandled keys), check `ShortcutSequenceTracking.isActive` in a `noResponder(for:)` override on your window:

```swift
import ShortcutField

class MainWindow: NSWindow {
    override func noResponder(for eventSelector: Selector) {
        if eventSelector == #selector(keyDown(with:)),
           ShortcutSequenceTracking.isActive {
            return // suppress beep only during sequence tracking
        }
        super.noResponder(for: eventSelector)
    }
}
```

`ShortcutSequenceTracking.isActive` is `true` whenever at least one `.onShortcutSequence()` modifier has matched one or more intermediate steps and is waiting for the next key press. It resets automatically on completion, timeout, or mismatch.

### How does this differ from KeyboardShortcuts?

[KeyboardShortcuts](https://github.com/sindresorhus/KeyboardShortcuts) registers **global** (system-wide) hotkeys. ShortcutField records **in-app** shortcuts that you match yourself via `.onShortcut()` or `.onShortcutSequence()` view modifiers. ShortcutField also supports sequential shortcuts (chord sequences like `⌘K ⌘C`) and non-keyboard inputs (mouse buttons, scroll directions, trackpad gestures), neither of which KeyboardShortcuts covers.

## Contributing

Issues and pull requests are welcome.

## Acknowledgments

ShortcutField's key mapping and display logic is adapted from [KeyboardShortcuts](https://github.com/sindresorhus/KeyboardShortcuts) by Sindre Sorhus (MIT license).

## License

MIT
