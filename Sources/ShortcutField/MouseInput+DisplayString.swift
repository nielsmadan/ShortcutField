import AppKit

// MARK: - Display String

public extension MouseInput {
    /// Human-readable representation, e.g. "Mouse4", "⌃Right Click", "⇧Scroll Up".
    var displayString: String {
        let modifierString = modifiers.symbolicRepresentation
        return modifierString + kindDisplayString
    }

    private var kindDisplayString: String {
        switch kind {
        case let .button(number):
            switch number {
            case 0: "Left Click"
            case 1: "Right Click"
            case 2: "Middle Click"
            default: "Mouse\(number + 1)"
            }
        case let .scroll(direction):
            switch direction {
            case .up: "Scroll Up"
            case .down: "Scroll Down"
            case .left: "Scroll Left"
            case .right: "Scroll Right"
            }
        }
    }
}
