import AppKit

/// A fire-once in-app shortcut composed of one or more steps.
///
/// Each step is a single recordable input — a keyboard key, mouse button, scroll
/// direction, smart-magnify, or trackpad gesture. A single keystroke is a 1-step
/// shortcut; a multi-step sequence (e.g. `⌘K ⌘C`) is an N-step shortcut. The
/// matcher fires the bound action exactly once when the user completes the full
/// sequence.
///
/// For sensitivity-bearing throttled continuous fire (e.g. scroll-to-zoom with a
/// user-tunable rate), use ``ContinuousShortcut`` and `.onShortcut`.
public struct DiscreteShortcut: Sendable, Equatable, Hashable {
    /// One step in a shortcut. Each step is a single recordable input event.
    public struct Step: Sendable, Equatable, Hashable {
        /// The input this step represents (key, mouse button, scroll, gesture, …).
        public let kind: Kind

        /// Modifier flags (Command, Shift, Option, Control). Other flags are masked off in `init`.
        public let modifiers: NSEvent.ModifierFlags

        /// Build a step of any kind.
        public init(kind: Kind, modifiers: NSEvent.ModifierFlags) {
            self.kind = Self.normalizeKind(kind)
            self.modifiers = DiscreteShortcut.canonicalModifiers(modifiers)
        }

        /// Convenience for keyboard steps; equivalent to `init(kind: .key(keyCode:), modifiers:)`.
        public init(keyCode: UInt16, modifiers: NSEvent.ModifierFlags) {
            self.init(kind: .key(keyCode: keyCode), modifiers: modifiers)
        }

        static func normalizeKind(_ kind: Kind) -> Kind { kind }
    }

    /// The kind of input a step represents.
    public enum Kind: Sendable, Equatable, Hashable {
        /// A keyboard key. Associated value is the virtual key code (e.g.,
        /// `kVK_Tab` from Carbon.HIToolbox).
        case key(keyCode: UInt16)
        /// A mouse button press. Associated value is `NSEvent.buttonNumber`
        /// (0 = left, 1 = right, 2 = middle, 3+ = additional buttons).
        case mouseButton(number: Int)
        /// A scroll wheel direction.
        case scroll(direction: ScrollDirection)
        /// Pinch close (fingers coming together). Per Apple's `NSEvent.magnification`,
        /// this corresponds to negative magnification (zoom out / "demagnify").
        case pinchIn
        /// Pinch open / spread (fingers moving apart). Positive magnification.
        case pinchOut
        case rotateClockwise
        case rotateCounterClockwise
        case smartMagnify
    }

    /// A discrete scroll direction. Codable wire format uses the lowercase case
    /// names (`"up"` / `"down"` / `"left"` / `"right"`).
    public enum ScrollDirection: String, Sendable, Equatable, Hashable, Codable {
        case up, down, left, right
    }

    /// The ordered steps that make up this shortcut. Always non-empty.
    public let steps: [Step]

    /// Create a shortcut from an explicit list of steps.
    ///
    /// - Precondition: `steps` must not be empty.
    public init(steps: [Step]) {
        precondition(!steps.isEmpty, "DiscreteShortcut requires at least 1 step")
        self.steps = steps
    }

    /// Convenience init for a 1-step shortcut.
    public init(kind: Kind, modifiers: NSEvent.ModifierFlags) {
        self.init(steps: [Step(kind: kind, modifiers: modifiers)])
    }

    /// Convenience init for a 1-step keyboard shortcut.
    public init(keyCode: UInt16, modifiers: NSEvent.ModifierFlags) {
        self.init(steps: [Step(keyCode: keyCode, modifiers: modifiers)])
    }

    // MARK: - Helpers

    /// Whether this kind can fire repeatedly during a single gesture and benefits
    /// from sensitivity throttling. True for `.scroll`, `.pinchIn/Out`, and
    /// `.rotateClockwise/CounterClockwise`; false for discrete kinds.
    static func isContinuous(_ kind: Kind) -> Bool {
        switch kind {
        case .scroll, .pinchIn, .pinchOut, .rotateClockwise, .rotateCounterClockwise:
            true
        case .key, .mouseButton, .smartMagnify:
            false
        }
    }

    // MARK: - Modifier mask

    /// The four modifier flags that participate in shortcut matching.
    static let canonicalModifierMask: NSEvent.ModifierFlags = [.shift, .control, .option, .command]

    /// Mask raw `NSEvent.modifierFlags` to the canonical set
    /// (`.shift`, `.control`, `.option`, `.command`).
    ///
    /// Strips Caps Lock, numeric pad, function key, and any non-device-independent
    /// flags so recorders, matchers, and UI compare modifiers consistently.
    static func canonicalModifiers(_ flags: NSEvent.ModifierFlags) -> NSEvent.ModifierFlags {
        flags.intersection(.deviceIndependentFlagsMask).intersection(canonicalModifierMask)
    }

    // MARK: - Thresholds (shared between matcher and recorder)

    /// Per-event minimum |magnification| to count a `.magnify` event as directional.
    static let magnifyEventThreshold: Double = 0.005
    /// Per-event minimum |rotation| (degrees) to count a `.rotate` event as directional.
    static let rotateEventThreshold: Double = 0.5
    /// Cumulative |magnification| during a single gesture before the recorder finalizes.
    static let magnifyRecordingThreshold: Double = 0.05
    /// Cumulative |rotation| (degrees) during a single gesture before the recorder finalizes.
    static let rotateRecordingThreshold: Double = 3.0
    /// Per-event minimum |delta| (in scroll units) to count a `.scrollWheel` event
    /// as a recording gesture. Higher than the matching threshold so recording isn't
    /// triggered by stray finger twitches on the trackpad.
    static let scrollRecordingThreshold: Double = 5.0
}

// MARK: - Codable

extension DiscreteShortcut: Codable {
    private enum CodingKeys: String, CodingKey {
        case steps
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let steps = try container.decode([Step].self, forKey: .steps)
        guard !steps.isEmpty else {
            throw DecodingError.dataCorruptedError(
                forKey: .steps,
                in: container,
                debugDescription: "DiscreteShortcut requires at least 1 step"
            )
        }
        self.steps = steps
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(steps, forKey: .steps)
    }
}

// MARK: - Kind Codable

extension DiscreteShortcut.Kind {
    /// Coding keys for the type discriminator and per-kind payload fields. Shared
    /// between `DiscreteShortcut.Step` and `ContinuousShortcut` so the JSON shape stays
    /// flat — `{type, keyCode?, buttonNumber?, direction?, ...parent fields}`.
    enum CodingKeys: String, CodingKey {
        case type
        case keyCode
        case buttonNumber
        case direction
    }

    /// String discriminator for the wire format.
    var tag: String {
        switch self {
        case .key: "key"
        case .mouseButton: "mouseButton"
        case .scroll: "scroll"
        case .pinchIn: "pinchIn"
        case .pinchOut: "pinchOut"
        case .rotateClockwise: "rotateClockwise"
        case .rotateCounterClockwise: "rotateCounterClockwise"
        case .smartMagnify: "smartMagnify"
        }
    }

    /// Decode a `Kind` from a keyed container that holds the `type` discriminator
    /// and any payload fields (`keyCode`, `buttonNumber`, `direction`).
    init(from container: KeyedDecodingContainer<CodingKeys>) throws {
        let tag = try container.decode(String.self, forKey: .type)
        switch tag {
        case "key":
            self = try .key(keyCode: container.decode(UInt16.self, forKey: .keyCode))
        case "mouseButton":
            self = try .mouseButton(number: container.decode(Int.self, forKey: .buttonNumber))
        case "scroll":
            self = try .scroll(direction: container.decode(DiscreteShortcut.ScrollDirection.self, forKey: .direction))
        case "pinchIn": self = .pinchIn
        case "pinchOut": self = .pinchOut
        case "rotateClockwise": self = .rotateClockwise
        case "rotateCounterClockwise": self = .rotateCounterClockwise
        case "smartMagnify": self = .smartMagnify
        default:
            throw DecodingError.dataCorruptedError(
                forKey: CodingKeys.type, in: container,
                debugDescription: "Unknown shortcut kind: \(tag)"
            )
        }
    }

    /// Encode the discriminator and payload into a keyed container alongside the
    /// parent's other fields.
    func encode(into container: inout KeyedEncodingContainer<CodingKeys>) throws {
        try container.encode(tag, forKey: .type)
        switch self {
        case let .key(keyCode):
            try container.encode(keyCode, forKey: .keyCode)
        case let .mouseButton(number):
            try container.encode(number, forKey: .buttonNumber)
        case let .scroll(direction):
            try container.encode(direction, forKey: .direction)
        case .pinchIn, .pinchOut, .rotateClockwise, .rotateCounterClockwise, .smartMagnify:
            break
        }
    }
}

extension DiscreteShortcut.Step: Codable {
    enum CodingKeys: String, CodingKey {
        case modifiers
    }

    public init(from decoder: any Decoder) throws {
        let kindContainer = try decoder.container(keyedBy: DiscreteShortcut.Kind.CodingKeys.self)
        kind = try Self.normalizeKind(DiscreteShortcut.Kind(from: kindContainer))

        let modifiersContainer = try decoder.container(keyedBy: CodingKeys.self)
        let rawModifiers = try modifiersContainer.decode(UInt.self, forKey: .modifiers)
        modifiers = DiscreteShortcut.canonicalModifiers(NSEvent.ModifierFlags(rawValue: rawModifiers))
    }

    public func encode(to encoder: any Encoder) throws {
        var modifiersContainer = encoder.container(keyedBy: CodingKeys.self)
        try modifiersContainer.encode(modifiers.rawValue, forKey: .modifiers)

        var kindContainer = encoder.container(keyedBy: DiscreteShortcut.Kind.CodingKeys.self)
        try kind.encode(into: &kindContainer)
    }
}

// `NSEvent.ModifierFlags` is an `OptionSet` but does not conform to `Hashable`,
// so we hash its raw value alongside the kind.
public extension DiscreteShortcut.Step {
    func hash(into hasher: inout Hasher) {
        hasher.combine(kind)
        hasher.combine(modifiers.rawValue)
    }
}
