# ``ShortcutField``

A unified in-app shortcut recorder for macOS apps.

## Overview

ShortcutField records and matches in-app input — keys, mouse buttons, scroll
directions, and trackpad gestures — through one umbrella type, ``Shortcut``,
with two cases:

- ``DiscreteShortcut`` fires once: a single keystroke, a (modified) click, a
  gesture, or a multi-step sequence such as `⌘K ⌘C`.
- ``ContinuousShortcut`` fires repeatedly during a scroll / pinch / rotate
  gesture, throttled by a user-tunable `sensitivity` (e.g. scroll-to-zoom).

Record with the SwiftUI views (``ShortcutRecorderView``,
``ContinuousShortcutRecorderView``) or the AppKit fields, match with
``SwiftUICore/View/onShortcut(_:perform:)`` or a ``ShortcutMatcher`` you drive yourself, and
display with `displayString`. Special keys that SwiftUI's focus system normally
intercepts — Tab, Escape — work throughout.

For full usage guides, the VS Code-style text syntax, and behavior notes, see
the [README](https://github.com/nielsmadan/ShortcutField) and the bundled
`Example/` app.

## Topics

### Shortcut Model

- ``Shortcut``
- ``DiscreteShortcut``
- ``ContinuousShortcut``

### Recording (SwiftUI)

- ``ShortcutRecorderView``
- ``ContinuousShortcutRecorderView``

### Recording (AppKit)

- ``ShortcutRecorderField``
- ``ContinuousShortcutRecorderField``
- ``BaseShortcutRecorderField``

### Matching

- ``SwiftUICore/View/onShortcut(_:perform:)``
- ``ShortcutMatcher``
- ``ShortcutMatchResult``
- ``ShortcutEventDispatcher``
- ``ShortcutTracking``

### Suppressing the system beep

- ``SwiftUICore/View/suppressShortcutBeep()``

### Configuration

- ``SensitivityMode``
- ``SensitivityPosition``

### Text Syntax

- ``ShortcutParsingError``
