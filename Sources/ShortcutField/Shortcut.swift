import AppKit

/// A keyboard shortcut defined by a key code and modifier flags.
public struct Shortcut: Sendable, Equatable {
    /// The virtual key code (e.g., `kVK_Tab` from Carbon.HIToolbox).
    public let keyCode: UInt16

    /// The modifier flags (Command, Shift, Option, Control).
    public let modifiers: NSEvent.ModifierFlags

    public init(keyCode: UInt16, modifiers: NSEvent.ModifierFlags) {
        self.keyCode = keyCode
        self.modifiers = modifiers.intersection([.shift, .control, .option, .command])
    }
}

// MARK: - Codable

extension Shortcut: Codable {
    enum CodingKeys: String, CodingKey {
        case keyCode
        case modifiers
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        keyCode = try container.decode(UInt16.self, forKey: .keyCode)
        let rawModifiers = try container.decode(UInt.self, forKey: .modifiers)
        modifiers = NSEvent.ModifierFlags(rawValue: rawModifiers)
            .intersection([.shift, .control, .option, .command])
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(keyCode, forKey: .keyCode)
        try container.encode(modifiers.rawValue, forKey: .modifiers)
    }
}
