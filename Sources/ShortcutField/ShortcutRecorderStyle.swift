import AppKit

/// Visual style for the shortcut recorder.
public enum ShortcutRecorderStyle: Sendable, Hashable {
    /// Default rounded appearance matching NSSearchField.
    case rounded
    /// Minimal flat border.
    case plain
    /// No visible border — just text.
    case borderless
}

extension NSSearchField {
    func applyRecorderStyle(_ style: ShortcutRecorderStyle) {
        switch style {
        case .rounded:
            isBezeled = true
            isBordered = true
            bezelStyle = .roundedBezel
        case .plain:
            isBezeled = true
            isBordered = true
            bezelStyle = .squareBezel
        case .borderless:
            isBezeled = false
            isBordered = false
        }
    }
}
