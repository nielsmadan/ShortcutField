import AppKit
import Carbon.HIToolbox

// MARK: - Display String

public extension DiscreteShortcut.Step {
    /// Human-readable representation of a single step, combining the modifier
    /// prefix with the kind label.
    ///
    /// Examples: `⌘K`, `Tab`, `↑`, `⌃Right Click`, `⇧Scroll Up`, `⌘Pinch In`,
    /// `⌃⌥Smart Magnify`.
    var displayString: String {
        modifiers.symbolicRepresentation + kind.displayLabel
    }
}

extension DiscreteShortcut.Kind {
    /// Human-readable text label for the kind alone (no modifier prefix).
    ///
    /// Examples: `K`, `Tab`, `Right Click`, `Scroll Up`, `Pinch In`, `Rotate CW`.
    /// This is the canonical text meaning reused by the icon/segment rendering
    /// (as tooltips and accessibility descriptions).
    var displayLabel: String {
        switch self {
        case let .key(keyCode):
            Self.keyDisplayString(keyCode: keyCode)
        case let .mouseButton(number):
            Self.mouseButtonDisplayString(number: number)
        case let .scroll(direction):
            Self.scrollDisplayString(direction: direction)
        case .pinchIn: "Pinch In"
        case .pinchOut: "Pinch Out"
        case .rotateClockwise: "Rotate CW"
        case .rotateCounterClockwise: "Rotate CCW"
        case .smartMagnify: "Smart Magnify"
        }
    }

    private static func keyDisplayString(keyCode: UInt16) -> String {
        if let specialKeyString = DiscreteShortcut.specialKeyString(keyCode: keyCode) {
            return specialKeyString
        }
        if let char = DiscreteShortcut.keyToCharacter(keyCode: keyCode) {
            return char
        }
        return "?"
    }

    private static func mouseButtonDisplayString(number: Int) -> String {
        switch number {
        case 0: "Left Click"
        case 1: "Right Click"
        case 2: "Middle Click"
        default: "Mouse\(number + 1)"
        }
    }

    private static func scrollDisplayString(direction: DiscreteShortcut.ScrollDirection) -> String {
        switch direction {
        case .up: "Scroll Up"
        case .down: "Scroll Down"
        case .left: "Scroll Left"
        case .right: "Scroll Right"
        }
    }
}

public extension DiscreteShortcut {
    /// Human-readable representation of the full shortcut. For multi-step shortcuts
    /// (e.g. `⌘K ⌘C`), step display strings are joined with a space.
    var displayString: String {
        steps.map(\.displayString).joined(separator: " ")
    }
}
