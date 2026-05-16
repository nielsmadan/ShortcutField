/// Any shortcut binding — fire-once (`DiscreteShortcut`) or sensitivity-bearing
/// continuous (`ContinuousShortcut`).
///
/// `Shortcut` is the umbrella type for code that handles both flavors. The two
/// concrete types remain available directly: use `DiscreteShortcut` /
/// `ContinuousShortcut` when the kind is fixed, `Shortcut` when it varies.
public enum Shortcut: Sendable, Hashable, Codable {
    case discrete(DiscreteShortcut)
    case continuous(ContinuousShortcut)

    /// Discriminator for the two cases.
    public enum Kind: Sendable, Hashable {
        case discrete
        case continuous
    }

    /// Which case this value is.
    public var kind: Kind {
        switch self {
        case .discrete: .discrete
        case .continuous: .continuous
        }
    }

    /// Human-readable representation, forwarded to the inner value.
    public var displayString: String {
        switch self {
        case let .discrete(shortcut): shortcut.displayString
        case let .continuous(shortcut): shortcut.displayString
        }
    }
}

// MARK: - Codable

extension Shortcut {
    private enum CodingKeys: String, CodingKey {
        case kind
        case discrete
        case continuous
    }

    private enum KindTag: String, Codable {
        case discrete
        case continuous
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let tag = try container.decode(KindTag.self, forKey: .kind)
        switch tag {
        case .discrete:
            self = try .discrete(container.decode(DiscreteShortcut.self, forKey: .discrete))
        case .continuous:
            self = try .continuous(container.decode(ContinuousShortcut.self, forKey: .continuous))
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .discrete(shortcut):
            try container.encode(KindTag.discrete, forKey: .kind)
            try container.encode(shortcut, forKey: .discrete)
        case let .continuous(shortcut):
            try container.encode(KindTag.continuous, forKey: .kind)
            try container.encode(shortcut, forKey: .continuous)
        }
    }
}
