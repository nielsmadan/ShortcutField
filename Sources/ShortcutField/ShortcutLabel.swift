import SwiftUI

/// A compact, read-only label for a shortcut — ideal for a shortcut legend.
///
/// In ``ShortcutLabelStyle/compact`` style (the default) gestures and scroll render as
/// SF Symbols and mouse clicks as short abbreviations, so the label stays narrow.
/// Each icon or abbreviation carries a hover tooltip (and accessibility label) with
/// its full text meaning, e.g. hovering the rotate icon shows "Rotate CW".
///
/// ```swift
/// ShortcutLabel(shortcut)            // icons with hover tooltips
/// ShortcutLabel(shortcut, style: .text) // verbose words
/// ```
///
/// For an editable recorder, use ``ShortcutRecorderView`` /
/// ``ContinuousShortcutRecorderView`` (which also take `.labelStyle(_:)`).
public struct ShortcutLabel: View {
    private let elements: [ShortcutDisplayElement]

    /// Label for any ``Shortcut``.
    public init(_ shortcut: Shortcut, style: ShortcutLabelStyle = .compact) {
        elements = shortcut.displayElements(style: style)
    }

    /// Label for a ``DiscreteShortcut``.
    public init(_ shortcut: DiscreteShortcut, style: ShortcutLabelStyle = .compact) {
        elements = shortcut.displayElements(style: style)
    }

    /// Label for a ``ContinuousShortcut``.
    public init(_ shortcut: ContinuousShortcut, style: ShortcutLabelStyle = .compact) {
        elements = shortcut.displayElements(style: style)
    }

    public var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(elements.enumerated()), id: \.offset) { _, element in
                view(for: element)
            }
        }
        // Read the whole label as one unit (e.g. "⌘Rotate CW") rather than letting
        // VoiceOver announce the modifier, icon, and abbreviation as separate nodes.
        // Per-element `.help` (pointer hover) is unaffected — it's not in the a11y tree.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: accessibilityText))
    }

    /// The full text meaning of the label, folding icon/abbreviation elements back to
    /// their `label`. Equals the shortcut's `displayString`.
    private var accessibilityText: String {
        elements.map { element in
            switch element {
            case let .text(string): string
            case let .symbol(_, label): label
            case let .abbreviation(_, label): label
            }
        }.joined()
    }

    @ViewBuilder
    private func view(for element: ShortcutDisplayElement) -> some View {
        switch element {
        case let .text(string):
            Text(verbatim: string)
        case let .symbol(name, label):
            Image(systemName: name)
                .help(Text(verbatim: label))
        case let .abbreviation(short, label):
            Text(verbatim: short)
                .help(Text(verbatim: label))
        }
    }
}
