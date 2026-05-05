import AppKit
import Carbon.HIToolbox

// MARK: - Display String

public extension Shortcut {
    /// Human-readable representation, combining the modifier prefix with the kind label.
    ///
    /// Examples: `⌘K`, `Tab`, `↑`, `⌃Right Click`, `⇧Scroll Up`, `⌘Pinch In`,
    /// `⌃⌥Smart Magnify`.
    var displayString: String {
        modifiers.symbolicRepresentation + kindDisplayString
    }

    private var kindDisplayString: String {
        switch kind {
        case let .key(keyCode):
            keyDisplayString(keyCode: keyCode)
        case let .mouseButton(number):
            mouseButtonDisplayString(number: number)
        case let .scroll(direction):
            scrollDisplayString(direction: direction)
        case .pinchIn: "Pinch In"
        case .pinchOut: "Pinch Out"
        case .rotateClockwise: "Rotate CW"
        case .rotateCounterClockwise: "Rotate CCW"
        case .smartMagnify: "Smart Magnify"
        }
    }

    private func keyDisplayString(keyCode: UInt16) -> String {
        if let specialKeyString = Self.specialKeyString(keyCode: keyCode) {
            return specialKeyString
        }
        if let char = Self.keyToCharacter(keyCode: keyCode) {
            return char
        }
        return "?"
    }

    private func mouseButtonDisplayString(number: Int) -> String {
        switch number {
        case 0: "Left Click"
        case 1: "Right Click"
        case 2: "Middle Click"
        default: "Mouse\(number + 1)"
        }
    }

    private func scrollDisplayString(direction: ScrollDirection) -> String {
        switch direction {
        case .up: "Scroll Up"
        case .down: "Scroll Down"
        case .left: "Scroll Left"
        case .right: "Scroll Right"
        }
    }
}
