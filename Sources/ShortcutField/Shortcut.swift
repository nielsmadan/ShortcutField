import AppKit

/// A unified in-app input shortcut: keyboard, mouse button, scroll, or trackpad gesture.
///
/// `Shortcut` covers every recordable single-event input that ShortcutField supports.
/// Use the convenience init for keyboard shortcuts (the most common case), or the
/// general init for any kind.
public struct Shortcut: Sendable, Equatable {
    /// The kind of input this shortcut represents.
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

    /// A discrete scroll direction.
    public enum ScrollDirection: String, Sendable, Equatable, Hashable, Codable {
        case up, down, left, right
    }

    /// The kind of input.
    public let kind: Kind

    /// The modifier flags (Command, Shift, Option, Control). Other flags are masked off in `init`.
    public let modifiers: NSEvent.ModifierFlags

    /// Sensitivity from 0.0 (fire once per gesture) to 1.0 (fire on every event).
    /// Only meaningful for continuous kinds (scroll, pinch, rotate); forced to 0.0
    /// for discrete kinds (key, mouseButton, smartMagnify).
    public let sensitivity: Double

    public init(kind: Kind, modifiers: NSEvent.ModifierFlags, sensitivity: Double = 0.0) {
        self.kind = Self.normalizeKind(kind)
        self.modifiers = modifiers.intersection([.shift, .control, .option, .command])
        if Self.isContinuous(self.kind) {
            self.sensitivity = min(1.0, max(0.0, sensitivity))
        } else {
            self.sensitivity = 0.0
        }
    }

    /// Convenience init for keyboard shortcuts.
    public init(keyCode: UInt16, modifiers: NSEvent.ModifierFlags) {
        self.init(kind: .key(keyCode: keyCode), modifiers: modifiers)
    }

    // MARK: - Helpers

    /// Whether this kind can fire repeatedly during a single gesture and benefits
    /// from sensitivity throttling. True for `.scroll`, `.pinchIn/Out`, and
    /// `.rotateClockwise/CounterClockwise`; false for discrete kinds.
    public static func isContinuous(_ kind: Kind) -> Bool {
        switch kind {
        case .scroll, .pinchIn, .pinchOut, .rotateClockwise, .rotateCounterClockwise:
            true
        case .key, .mouseButton, .smartMagnify:
            false
        }
    }

    /// Reserved hook for future kind clamping. Currently a no-op.
    static func normalizeKind(_ kind: Kind) -> Kind {
        kind
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

extension Shortcut: Codable {
    enum CodingKeys: String, CodingKey {
        case type
        case keyCode
        case buttonNumber
        case direction
        case modifiers
        case sensitivity
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)

        let decodedKind: Kind
        switch type {
        case "key":
            let keyCode = try container.decode(UInt16.self, forKey: .keyCode)
            decodedKind = .key(keyCode: keyCode)
        case "mouseButton":
            let number = try container.decode(Int.self, forKey: .buttonNumber)
            decodedKind = .mouseButton(number: number)
        case "scroll":
            let direction = try container.decode(ScrollDirection.self, forKey: .direction)
            decodedKind = .scroll(direction: direction)
        case "pinchIn": decodedKind = .pinchIn
        case "pinchOut": decodedKind = .pinchOut
        case "rotateClockwise": decodedKind = .rotateClockwise
        case "rotateCounterClockwise": decodedKind = .rotateCounterClockwise
        case "smartMagnify": decodedKind = .smartMagnify
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .type,
                in: container,
                debugDescription: "Unknown shortcut kind: \(type)"
            )
        }
        kind = Self.normalizeKind(decodedKind)

        let rawModifiers = try container.decode(UInt.self, forKey: .modifiers)
        modifiers = NSEvent.ModifierFlags(rawValue: rawModifiers)
            .intersection([.shift, .control, .option, .command])

        if Self.isContinuous(kind) {
            sensitivity = try min(
                1.0,
                max(0.0,
                    container.decodeIfPresent(Double.self, forKey: .sensitivity) ?? 0.0)
            )
        } else {
            sensitivity = 0.0
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(modifiers.rawValue, forKey: .modifiers)
        if Self.isContinuous(kind) {
            try container.encode(sensitivity, forKey: .sensitivity)
        }

        switch kind {
        case let .key(keyCode):
            try container.encode("key", forKey: .type)
            try container.encode(keyCode, forKey: .keyCode)
        case let .mouseButton(number):
            try container.encode("mouseButton", forKey: .type)
            try container.encode(number, forKey: .buttonNumber)
        case let .scroll(direction):
            try container.encode("scroll", forKey: .type)
            try container.encode(direction, forKey: .direction)
        case .pinchIn:
            try container.encode("pinchIn", forKey: .type)
        case .pinchOut:
            try container.encode("pinchOut", forKey: .type)
        case .rotateClockwise:
            try container.encode("rotateClockwise", forKey: .type)
        case .rotateCounterClockwise:
            try container.encode("rotateCounterClockwise", forKey: .type)
        case .smartMagnify:
            try container.encode("smartMagnify", forKey: .type)
        }
    }
}

// MARK: - Hashable

// `NSEvent.ModifierFlags` is an `OptionSet` but does not conform to `Hashable`,
// so we hash its raw value alongside the kind and sensitivity.
extension Shortcut: Hashable {
    public func hash(into hasher: inout Hasher) {
        hasher.combine(kind)
        hasher.combine(modifiers.rawValue)
        hasher.combine(sensitivity)
    }
}
