/// How a shortcut's kind is rendered in a display label.
///
/// - ``text``: verbose words, e.g. `Rotate CW`, `Scroll Up`, `Left Click`. Matches
///   ``DiscreteShortcut/displayString``; the default for the recorder views/fields.
/// - ``compact``: compact SF Symbols for gestures and scroll, and short abbreviations
///   for mouse clicks (`LMB`/`RMB`/`MMB`). Modifier prefixes and key names
///   stay as-is. Each icon/abbreviation still exposes its full text meaning via
///   ``DiscreteShortcut/Step/displayElements(style:)`` (for tooltips/accessibility).
public enum ShortcutLabelStyle: Sendable, Equatable, Hashable {
    case text
    case compact
}
