# Sequential Shortcuts

Add support for recording and recognizing multi-step keyboard shortcuts (e.g. `⌘K ⌘C`, `,K`, `G G`).

## Model

### `ShortcutSequence`

New type in `ShortcutSequence.swift`.

```swift
public struct ShortcutSequence: Sendable, Equatable, Codable {
    public let steps: [Shortcut]  // minimum 2

    public init(steps: [Shortcut])  // precondition: steps.count >= 2

    public var displayString: String  // joins step display strings with " ", e.g. "⌘K ⌘C"
}
```

- Each step is a `Shortcut` (keyCode + optional modifiers) — supports both chord sequences (`⌘K ⌘C`) and plain key sequences (`G G`)
- Arbitrary length (2+)
- Codable, Equatable, Sendable — same patterns as `Shortcut`

### Prefix conflicts

If `,K` and `,KC` are both registered, `,K` always wins because it completes first. No detection, no warnings — each sequence matcher is independent with no global state.

## Recording

### `ShortcutSequenceRecorderField`

New AppKit control in `ShortcutSequenceRecorderField.swift`. Subclasses `NSSearchField`, same approach as `ShortcutRecorderField`.

**Behavior:**
- Click to start recording
- Each key press appends a step to the sequence and updates the display (e.g. `"⌘K ..."`)
- 1 second timeout after the last key press finalizes the recording
- If the timeout fires with fewer than 2 steps, the recording is discarded (existing sequence preserved, no callback)
- Escape cancels recording, Delete clears the recorded sequence
- Calls `onShortcutSequenceChange: ((ShortcutSequence?) -> Void)?` on completion

**Properties (same as ShortcutRecorderField):**
- `shortcutSequence: ShortcutSequence?`
- `defaultPlaceholder: String`
- `recordingPlaceholder: String`
- `fieldTextColor: NSColor?`
- `fieldBackgroundColor: NSColor?`
- `onShortcutSequenceChange: ((ShortcutSequence?) -> Void)?`

**Shared styling:** Both fields subclass `NSSearchField`, so add a constrained protocol extension (e.g. `RecorderFieldStyling where Self: NSSearchField`) with default implementations for `applyStyle(_:)` and `applyBackgroundColor()`. Both fields use the same `ShortcutRecorderStyle` enum.

### `ShortcutSequenceRecorderView`

New SwiftUI view in `ShortcutSequenceRecorderView.swift`. `NSViewRepresentable` wrapper around `ShortcutSequenceRecorderField`.

```swift
ShortcutSequenceRecorderView($sequence)
    .placeholder("Record Sequence")
    .recordingPlaceholder("Press keys...")
    .style(.rounded)
    .textColor(.white)
    .fieldBackgroundColor(.systemBlue.withAlphaComponent(0.1))
```

Same modifier API as `ShortcutRecorderView`.

## Recognition

### `.onShortcutSequence()` view modifier

New modifier in `OnShortcutSequenceModifier.swift`.

```swift
MyView()
    .onShortcutSequence(sequence) {
        print("Sequence matched!")
    }
```

**Behavior:**
- Each modifier instance independently tracks its position in its sequence (no global state)
- On each key press: if it matches the expected next step, advance the position
- If the sequence is fully matched, consume the final key event and fire the action immediately
- If a key doesn't match the expected next step, reset position to 0
- 1 second timeout between steps resets the tracker to prevent stale partial matches
- Intermediate key events propagate normally (not consumed) — only the final matching step is consumed

**Dual-path recognition** (same pattern as `OnShortcutModifier`):
- `onKeyPress` for regular keys
- `NSEvent.addLocalMonitorForEvents` for special keys (Tab, Escape) that SwiftUI intercepts
- Single shared sequence tracker state (`@State`) consumed by both paths — each key event only fires through one path (special keys via monitor, regular keys via `onKeyPress`), same as existing `OnShortcutModifier`
- Only key-down events advance the tracker; modifier key-up between steps is ignored

**macOS 14+ requirement** (same as `OnShortcutModifier`).

**Conflict with single shortcuts:** If a view has both `.onShortcut(⌘K)` and `.onShortcutSequence(⌘K ⌘C)`, the single shortcut fires first and prevents the sequence from completing. This is the developer's responsibility to avoid — do not register a single shortcut that conflicts with the first step of a sequence.

## Files

| File | Type | Description |
|---|---|---|
| `ShortcutSequence.swift` | New | Model: `[Shortcut]` wrapper |
| `ShortcutSequenceRecorderField.swift` | New | AppKit recorder for sequences |
| `ShortcutSequenceRecorderView.swift` | New | SwiftUI wrapper |
| `OnShortcutSequenceModifier.swift` | New | `.onShortcutSequence()` recognition |
| `ShortcutRecorderStyle.swift` | Modified | May need to extract shared styling if not already reusable |
| `ShortcutRecorderField.swift` | Modified | Extract shared setup code if significant overlap |

## Testing

- `ShortcutSequence` model: init, displayString, Codable roundtrip, Equatable
- `ShortcutSequenceRecorderField`: default state, set/clear sequence, display updates
- Recognition logic: full match fires, partial match tracks, wrong key resets, timeout resets

## Example App

Add a sequence recorder to the example app's workbench and gallery tabs alongside the existing single shortcut recorder, demonstrating recording and recognition of sequential shortcuts.
