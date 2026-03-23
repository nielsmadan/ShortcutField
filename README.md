# ShortcutField

A keyboard shortcut recorder for macOS apps. Record, display, and match **in-app** keyboard shortcuts — including special keys like Tab that SwiftUI's focus system normally intercepts.

![Screenshot](screenshot.png)

## Requirements

- macOS 13+
- Swift 6.2+

## Installation

Add ShortcutField to your project via Swift Package Manager:

```swift
dependencies: [
    .package(url: "https://github.com/nielsmadan/ShortcutField", from: "1.0.0")
]
```

## Usage

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

### Recording Shortcuts (AppKit)

```swift
import ShortcutField

let field = ShortcutRecorderField()
field.onShortcutChange = { shortcut in
    print("Recorded: \(shortcut?.displayString ?? "none")")
}
```

### Matching Shortcuts

The `.onShortcut()` modifier handles both regular keys and special keys like Tab automatically:

```swift
MyView()
    .onShortcut(shortcut) {
        print("Shortcut fired!")
    }
```

For manual matching, use the `matches()` methods directly:

```swift
// Match against NSEvent (for keys like Tab that SwiftUI intercepts)
shortcut.matches(event)

// Match against SwiftUI KeyPress
shortcut.matches(press)
```

### Display Strings

```swift
let shortcut = Shortcut(keyCode: UInt16(kVK_Tab), modifiers: [.command, .shift])
print(shortcut.displayString) // "⇧⌘Tab"
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

## API

### `Shortcut`

The shortcut model. `Codable`, `Equatable`, `Sendable`.

| Property/Method | Description |
|---|---|
| `keyCode: UInt16` | Virtual key code |
| `modifiers: NSEvent.ModifierFlags` | Modifier flags |
| `displayString: String` | Human-readable, e.g. "⌘⇧K" |
| `matches(_ event: NSEvent) -> Bool` | Match against NSEvent |
| `matches(_ press: KeyPress) -> Bool` | Match against SwiftUI KeyPress (macOS 14+) |

### `ShortcutRecorderView`

SwiftUI recorder component.

| Modifier | Description |
|---|---|
| `.placeholder(_:)` | Text when empty (default: "Record Shortcut") |
| `.recordingPlaceholder(_:)` | Text during recording (default: "Press shortcut...") |
| `.style(_:)` | `.rounded`, `.plain`, or `.borderless` |
| `.textColor(_:)` | Text color (`NSColor`) |
| `.fieldBackgroundColor(_:)` | Background color (`NSColor`); uses a layer because `NSSearchFieldCell` ignores `backgroundColor` |

### `ShortcutRecorderField`

AppKit recorder (`NSSearchField` subclass). Also public for direct use.

### `.onShortcut(_:perform:)`

View modifier that fires an action when a shortcut is pressed. Requires macOS 14+.

## Acknowledgments

ShortcutField's key mapping and display logic is adapted from [KeyboardShortcuts](https://github.com/sindresorhus/KeyboardShortcuts) by Sindre Sorhus (MIT license).

## License

MIT
