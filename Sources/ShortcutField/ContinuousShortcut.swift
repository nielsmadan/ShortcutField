import AppKit

/// A sensitivity-bearing shortcut for throttled continuous fire.
///
/// Use `ContinuousShortcut` when the dev wants the bound action to fire repeatedly
/// during a single physical gesture (e.g. scroll-to-zoom), with the user-tunable
/// `sensitivity` controlling the throttle rate.
///
/// The kind is restricted at the type level to continuous gestures (`scroll`,
/// `pinchIn/Out`, `rotateClockwise/CounterClockwise`).
///
/// For fire-once shortcuts (matching keystrokes, mouse clicks, single gestures, or
/// multi-step sequences), use ``Shortcut`` and `.onShortcut`.
public struct ContinuousShortcut: Sendable, Equatable, Hashable {
    /// The continuous-only subset of `Shortcut.Kind`. Discrete kinds (`key`,
    /// `mouseButton`, `smartMagnify`) are unrepresentable.
    public enum Kind: Sendable, Equatable, Hashable {
        case scroll(direction: Shortcut.ScrollDirection)
        case pinchIn
        case pinchOut
        case rotateClockwise
        case rotateCounterClockwise

        /// Lift to the umbrella `Shortcut.Kind` for matching/display reuse.
        public var asShortcutKind: Shortcut.Kind {
            switch self {
            case let .scroll(direction): .scroll(direction: direction)
            case .pinchIn: .pinchIn
            case .pinchOut: .pinchOut
            case .rotateClockwise: .rotateClockwise
            case .rotateCounterClockwise: .rotateCounterClockwise
            }
        }

        /// Project from an umbrella kind, returning nil for discrete kinds.
        public init?(_ shortcutKind: Shortcut.Kind) {
            switch shortcutKind {
            case let .scroll(direction): self = .scroll(direction: direction)
            case .pinchIn: self = .pinchIn
            case .pinchOut: self = .pinchOut
            case .rotateClockwise: self = .rotateClockwise
            case .rotateCounterClockwise: self = .rotateCounterClockwise
            case .key, .mouseButton, .smartMagnify: return nil
            }
        }
    }

    /// The continuous-gesture kind this shortcut binds to.
    public let kind: Kind

    /// Modifier flags (Command, Shift, Option, Control). Other flags are masked off in `init`.
    public let modifiers: NSEvent.ModifierFlags

    /// Throttle sensitivity from 0.0 (fire once per gesture) to 1.0 (fire on every event).
    public let sensitivity: Double

    /// Build a continuous shortcut. `sensitivity` is silently clamped to `0.0...1.0`.
    public init(kind: Kind, modifiers: NSEvent.ModifierFlags, sensitivity: Double = 0.0) {
        self.kind = kind
        self.modifiers = Shortcut.canonicalModifiers(modifiers)
        self.sensitivity = min(1.0, max(0.0, sensitivity))
    }
}

// MARK: - Codable

extension ContinuousShortcut: Codable {
    enum CodingKeys: String, CodingKey {
        case modifiers
        case sensitivity
    }

    public init(from decoder: any Decoder) throws {
        let kindContainer = try decoder.container(keyedBy: Shortcut.Kind.CodingKeys.self)
        let decodedShortcutKind = try Shortcut.Kind(from: kindContainer)
        guard let decodedKind = Kind(decodedShortcutKind) else {
            throw DecodingError.dataCorruptedError(
                forKey: Shortcut.Kind.CodingKeys.type, in: kindContainer,
                debugDescription: "ContinuousShortcut requires a continuous kind, got \(decodedShortcutKind.tag)"
            )
        }
        kind = decodedKind

        let container = try decoder.container(keyedBy: CodingKeys.self)
        let rawModifiers = try container.decode(UInt.self, forKey: .modifiers)
        modifiers = Shortcut.canonicalModifiers(NSEvent.ModifierFlags(rawValue: rawModifiers))

        let rawSensitivity = try container.decodeIfPresent(Double.self, forKey: .sensitivity) ?? 0.0
        sensitivity = min(1.0, max(0.0, rawSensitivity))
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(modifiers.rawValue, forKey: .modifiers)
        try container.encode(sensitivity, forKey: .sensitivity)

        var kindContainer = encoder.container(keyedBy: Shortcut.Kind.CodingKeys.self)
        try kind.asShortcutKind.encode(into: &kindContainer)
    }
}

// MARK: - Hashable

// `NSEvent.ModifierFlags` is an `OptionSet` but does not conform to `Hashable`,
// so we hash its raw value alongside the kind and sensitivity.
public extension ContinuousShortcut {
    func hash(into hasher: inout Hasher) {
        hasher.combine(kind)
        hasher.combine(modifiers.rawValue)
        hasher.combine(sensitivity)
    }
}

// MARK: - Matching

public extension ContinuousShortcut {
    /// Match against an NSEvent.
    func matches(_ event: NSEvent) -> Bool {
        Shortcut.Step(kind: kind.asShortcutKind, modifiers: modifiers).matches(event)
    }
}

// MARK: - Display string

public extension ContinuousShortcut {
    /// Human-readable representation. Same format as a single-step `Shortcut`.
    var displayString: String {
        Shortcut.Step(kind: kind.asShortcutKind, modifiers: modifiers).displayString
    }
}
