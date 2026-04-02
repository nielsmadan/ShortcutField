import AppKit

/// A sequential keyboard shortcut composed of multiple steps.
///
/// Each step is a ``Shortcut`` (key code + modifiers). The sequence
/// matches when all steps are pressed in order.
public struct ShortcutSequence: Sendable, Equatable, Codable {
    private enum CodingKeys: String, CodingKey {
        case steps
    }

    /// The ordered steps that make up this sequence.
    public let steps: [Shortcut]

    /// Create a shortcut sequence from an array of steps.
    ///
    /// - Precondition: `steps` must not be empty.
    public init(steps: [Shortcut]) {
        precondition(!steps.isEmpty, "ShortcutSequence requires at least 1 step")
        self.steps = steps
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let steps = try container.decode([Shortcut].self, forKey: .steps)

        guard !steps.isEmpty else {
            throw DecodingError.dataCorruptedError(
                forKey: .steps,
                in: container,
                debugDescription: "ShortcutSequence requires at least 1 step"
            )
        }

        self.steps = steps
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(steps, forKey: .steps)
    }

    /// Human-readable display string, e.g. "⌘K ⌘C".
    public var displayString: String {
        steps.map(\.displayString).joined(separator: " ")
    }
}
