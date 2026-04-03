import AppKit

/// A mouse input defined by a button press or scroll direction and modifier flags.
public struct MouseInput: Sendable, Equatable {
    /// The kind of mouse input.
    public enum InputKind: Sendable, Equatable {
        /// A mouse button press. The associated value is the `NSEvent.buttonNumber`
        /// (0 = left, 1 = right, 2 = middle, 3+ = additional buttons).
        case button(Int)
        /// A scroll wheel direction.
        case scroll(ScrollDirection)
    }

    /// A discrete scroll direction.
    public enum ScrollDirection: String, Sendable, Equatable, Codable {
        case up, down, left, right
    }

    /// The kind of mouse input (button or scroll).
    public let kind: InputKind

    /// The modifier flags (Command, Shift, Option, Control).
    public let modifiers: NSEvent.ModifierFlags

    /// Scroll sensitivity from 0.0 (fire once per gesture) to 1.0 (every event).
    /// Only meaningful for `.scroll` inputs; ignored for `.button` inputs.
    public let scrollSensitivity: Double

    public init(kind: InputKind, modifiers: NSEvent.ModifierFlags, scrollSensitivity: Double = 0.0) {
        self.kind = kind
        self.modifiers = modifiers.intersection([.shift, .control, .option, .command])
        if case .button = kind {
            self.scrollSensitivity = 0.0
        } else {
            self.scrollSensitivity = min(1.0, max(0.0, scrollSensitivity))
        }
    }
}

// MARK: - Codable

extension MouseInput: Codable {
    enum CodingKeys: String, CodingKey {
        case type
        case buttonNumber
        case direction
        case modifiers
        case scrollSensitivity
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)

        switch type {
        case "button":
            let buttonNumber = try container.decode(Int.self, forKey: .buttonNumber)
            kind = .button(buttonNumber)
        case "scroll":
            let direction = try container.decode(ScrollDirection.self, forKey: .direction)
            kind = .scroll(direction)
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .type,
                in: container,
                debugDescription: "Unknown mouse input type: \(type)"
            )
        }

        let rawModifiers = try container.decode(UInt.self, forKey: .modifiers)
        modifiers = NSEvent.ModifierFlags(rawValue: rawModifiers)
            .intersection([.shift, .control, .option, .command])

        if case .button = kind {
            scrollSensitivity = 0.0
        } else {
            scrollSensitivity = try min(
                1.0,
                max(0.0,
                    container.decodeIfPresent(Double.self, forKey: .scrollSensitivity) ?? 0.0)
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(modifiers.rawValue, forKey: .modifiers)
        try container.encode(scrollSensitivity, forKey: .scrollSensitivity)

        switch kind {
        case let .button(number):
            try container.encode("button", forKey: .type)
            try container.encode(number, forKey: .buttonNumber)
        case let .scroll(direction):
            try container.encode("scroll", forKey: .type)
            try container.encode(direction, forKey: .direction)
        }
    }
}

// MARK: - Codable for InputKind

extension MouseInput.InputKind: Codable {
    enum CodingKeys: String, CodingKey {
        case type
        case buttonNumber
        case direction
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)

        switch type {
        case "button":
            let buttonNumber = try container.decode(Int.self, forKey: .buttonNumber)
            self = .button(buttonNumber)
        case "scroll":
            let direction = try container.decode(MouseInput.ScrollDirection.self, forKey: .direction)
            self = .scroll(direction)
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .type,
                in: container,
                debugDescription: "Unknown input kind type: \(type)"
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .button(number):
            try container.encode("button", forKey: .type)
            try container.encode(number, forKey: .buttonNumber)
        case let .scroll(direction):
            try container.encode("scroll", forKey: .type)
            try container.encode(direction, forKey: .direction)
        }
    }
}
