import AppKit
import Carbon.HIToolbox

/// Error thrown by `init(ascii:)` when a text shortcut string is malformed.
public enum ShortcutParsingError: Error, Equatable {
    case empty
    case unknownModifier(String)
    case unknownKey(String)
    case unknownGesture(String)
    case malformedSensitivity(String)
    case sensitivityOnDiscrete
    case emptyStep
}

// MARK: - Token tables

private enum ASCIIToken {
    /// Modifier name → flag. Canonical emit order is ctrl, opt, shift, cmd.
    static let modifiers: [(name: String, flag: NSEvent.ModifierFlags)] = [
        ("ctrl", .control),
        ("opt", .option),
        ("shift", .shift),
        ("cmd", .command),
    ]

    static let specialKeys: [(name: String, keyCode: Int)] = [
        ("tab", kVK_Tab),
        ("return", kVK_Return),
        ("escape", kVK_Escape),
        ("space", kVK_Space),
        ("delete", kVK_Delete),
        ("forward-delete", kVK_ForwardDelete),
        ("home", kVK_Home),
        ("end", kVK_End),
        ("pageup", kVK_PageUp),
        ("pagedown", kVK_PageDown),
        ("up", kVK_UpArrow),
        ("down", kVK_DownArrow),
        ("left", kVK_LeftArrow),
        ("right", kVK_RightArrow),
        ("f1", kVK_F1), ("f2", kVK_F2), ("f3", kVK_F3), ("f4", kVK_F4),
        ("f5", kVK_F5), ("f6", kVK_F6), ("f7", kVK_F7), ("f8", kVK_F8),
        ("f9", kVK_F9), ("f10", kVK_F10), ("f11", kVK_F11), ("f12", kVK_F12),
    ]

    static let ansiKeys: [(name: String, keyCode: Int)] = [
        ("a", kVK_ANSI_A), ("b", kVK_ANSI_B), ("c", kVK_ANSI_C), ("d", kVK_ANSI_D),
        ("e", kVK_ANSI_E), ("f", kVK_ANSI_F), ("g", kVK_ANSI_G), ("h", kVK_ANSI_H),
        ("i", kVK_ANSI_I), ("j", kVK_ANSI_J), ("k", kVK_ANSI_K), ("l", kVK_ANSI_L),
        ("m", kVK_ANSI_M), ("n", kVK_ANSI_N), ("o", kVK_ANSI_O), ("p", kVK_ANSI_P),
        ("q", kVK_ANSI_Q), ("r", kVK_ANSI_R), ("s", kVK_ANSI_S), ("t", kVK_ANSI_T),
        ("u", kVK_ANSI_U), ("v", kVK_ANSI_V), ("w", kVK_ANSI_W), ("x", kVK_ANSI_X),
        ("y", kVK_ANSI_Y), ("z", kVK_ANSI_Z),
        ("0", kVK_ANSI_0), ("1", kVK_ANSI_1), ("2", kVK_ANSI_2), ("3", kVK_ANSI_3),
        ("4", kVK_ANSI_4), ("5", kVK_ANSI_5), ("6", kVK_ANSI_6), ("7", kVK_ANSI_7),
        ("8", kVK_ANSI_8), ("9", kVK_ANSI_9),
    ]

    static let punctuationKeys: [(name: String, keyCode: Int)] = [
        ("minus", kVK_ANSI_Minus),
        ("equal", kVK_ANSI_Equal),
        ("left-bracket", kVK_ANSI_LeftBracket),
        ("right-bracket", kVK_ANSI_RightBracket),
        ("semicolon", kVK_ANSI_Semicolon),
        ("quote", kVK_ANSI_Quote),
        ("comma", kVK_ANSI_Comma),
        ("period", kVK_ANSI_Period),
        ("slash", kVK_ANSI_Slash),
        ("backslash", kVK_ANSI_Backslash),
        ("grave", kVK_ANSI_Grave),
    ]

    static let mouseButtons: [(name: String, number: Int)] = [
        ("left-click", 0),
        ("right-click", 1),
        ("middle-click", 2),
        ("button4", 3),
        ("button5", 4),
    ]

    static let scrollDirections: [(name: String, direction: DiscreteShortcut.ScrollDirection)] = [
        ("scroll-up", .up),
        ("scroll-down", .down),
        ("scroll-left", .left),
        ("scroll-right", .right),
    ]
}

// MARK: - Step parsing / emitting

extension DiscreteShortcut.Step {
    /// Parse one step token (e.g. "cmd+s", "ctrl+right-click", "scroll-up").
    /// The `@N` sensitivity suffix must already be stripped by the caller.
    static func parse(ascii token: String) throws -> DiscreteShortcut.Step {
        let parts = token.split(separator: "+", omittingEmptySubsequences: false).map(String.init)
        guard !parts.isEmpty, !parts.contains(where: \.isEmpty) else {
            throw ShortcutParsingError.emptyStep
        }
        var modifiers: NSEvent.ModifierFlags = []
        for modPart in parts.dropLast() {
            guard let entry = ASCIIToken.modifiers.first(where: { $0.name == modPart }) else {
                throw ShortcutParsingError.unknownModifier(modPart)
            }
            modifiers.insert(entry.flag)
        }
        let final = parts[parts.count - 1]
        let kind = try Self.parseKind(final)
        return DiscreteShortcut.Step(kind: kind, modifiers: modifiers)
    }

    private static func parseKind(_ token: String) throws -> DiscreteShortcut.Kind {
        if let special = ASCIIToken.specialKeys.first(where: { $0.name == token }) {
            return .key(keyCode: UInt16(special.keyCode))
        }
        if let ansi = ASCIIToken.ansiKeys.first(where: { $0.name == token }) {
            return .key(keyCode: UInt16(ansi.keyCode))
        }
        if let punct = ASCIIToken.punctuationKeys.first(where: { $0.name == token }) {
            return .key(keyCode: UInt16(punct.keyCode))
        }
        if token.hasPrefix("key"), let digits = UInt16(token.dropFirst(3)) {
            return .key(keyCode: digits)
        }
        if token.hasPrefix("key"), token.dropFirst(3).allSatisfy(\.isNumber) {
            // digits present but overflow UInt16
            throw ShortcutParsingError.unknownKey(token)
        }
        if let mouse = ASCIIToken.mouseButtons.first(where: { $0.name == token }) {
            return .mouseButton(number: mouse.number)
        }
        if token.hasPrefix("button"), let n = Int(token.dropFirst(6)), n >= 1 {
            return .mouseButton(number: n - 1)
        }
        if let scroll = ASCIIToken.scrollDirections.first(where: { $0.name == token }) {
            return .scroll(direction: scroll.direction)
        }
        switch token {
        case "pinch-in": return .pinchIn
        case "pinch-out": return .pinchOut
        case "rotate-clockwise": return .rotateClockwise
        case "rotate-counterclockwise": return .rotateCounterClockwise
        case "smart-magnify": return .smartMagnify
        default:
            // Gesture-shaped tokens get .unknownGesture, not the misleading .unknownKey.
            if ["pinch-", "rotate-", "scroll-", "smart-"].contains(where: token.hasPrefix) {
                throw ShortcutParsingError.unknownGesture(token)
            }
            throw ShortcutParsingError.unknownKey(token)
        }
    }

    /// Emit this step as an ascii token.
    var ascii: String {
        let modPrefix = ASCIIToken.modifiers
            .filter { modifiers.contains($0.flag) }
            .map { $0.name + "+" }
            .joined()
        return modPrefix + kindASCII
    }

    private var kindASCII: String {
        switch kind {
        case let .key(keyCode):
            if let special = ASCIIToken.specialKeys.first(where: { $0.keyCode == Int(keyCode) }) {
                return special.name
            }
            if let ansi = ASCIIToken.ansiKeys.first(where: { $0.keyCode == Int(keyCode) }) {
                return ansi.name
            }
            if let punct = ASCIIToken.punctuationKeys.first(where: { $0.keyCode == Int(keyCode) }) {
                return punct.name
            }
            return "key\(keyCode)"
        case let .mouseButton(number):
            return ASCIIToken.mouseButtons.first(where: { $0.number == number })?.name
                ?? "button\(number + 1)"
        case let .scroll(direction):
            return ASCIIToken.scrollDirections.first(where: { $0.direction == direction })!.name
        case .pinchIn: return "pinch-in"
        case .pinchOut: return "pinch-out"
        case .rotateClockwise: return "rotate-clockwise"
        case .rotateCounterClockwise: return "rotate-counterclockwise"
        case .smartMagnify: return "smart-magnify"
        }
    }
}

// MARK: - DiscreteShortcut ascii

public extension DiscreteShortcut {
    /// Parse a VS Code-style ascii string into a discrete shortcut.
    /// Steps are space-separated; a ` @N` sensitivity suffix is invalid here.
    /// Input is case-sensitive; all tokens are lowercase, matching the output of `.ascii`.
    init(ascii: String) throws {
        let trimmed = ascii.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { throw ShortcutParsingError.empty }
        // ` @N` is the sensitivity delimiter — same rule as `Shortcut(ascii:)`.
        if trimmed.range(of: " @") != nil {
            throw ShortcutParsingError.sensitivityOnDiscrete
        }
        let tokens = trimmed.split(separator: " ").map(String.init)
        guard !tokens.isEmpty else { throw ShortcutParsingError.empty }
        let steps = try tokens.map { try DiscreteShortcut.Step.parse(ascii: $0) }
        self.init(steps: steps)
    }

    /// VS Code-style ascii representation. Round-trips with `init(ascii:)`.
    var ascii: String {
        steps.map(\.ascii).joined(separator: " ")
    }
}

// MARK: - Shortcut ascii (umbrella)

public extension Shortcut {
    /// Parse a VS Code-style ascii string into the umbrella `Shortcut`.
    ///
    /// Resolution: a multi-step string, or a single key / mouse / `smart-magnify`
    /// step → `.discrete`. A single bare gesture kind (`scroll-*`, `pinch-*`,
    /// `rotate-*`) → `.continuous`, with the ` @N` sensitivity suffix if present
    /// (else default sensitivity `0.0`).
    /// Input is case-sensitive; all tokens are lowercase, matching the output of `.ascii`.
    init(ascii: String) throws {
        let trimmed = ascii.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { throw ShortcutParsingError.empty }

        var body = trimmed
        var sensitivitySuffix: String?
        if let atRange = trimmed.range(of: " @") {
            body = String(trimmed[..<atRange.lowerBound])
            sensitivitySuffix = String(trimmed[atRange.upperBound...])
        }

        let tokens = body.split(separator: " ").map(String.init)

        // Reject a sensitivity suffix on a multi-step string *before* parsing the
        // suffix value — otherwise the error reported depends on whether the
        // number happens to parse (`malformedSensitivity` vs `sensitivityOnDiscrete`).
        guard tokens.count == 1 else {
            if sensitivitySuffix != nil { throw ShortcutParsingError.sensitivityOnDiscrete }
            self = try .discrete(DiscreteShortcut(ascii: body))
            return
        }

        let step = try DiscreteShortcut.Step.parse(ascii: tokens[0])
        guard let continuousKind = ContinuousShortcut.Kind(step.kind) else {
            if sensitivitySuffix != nil { throw ShortcutParsingError.sensitivityOnDiscrete }
            self = .discrete(DiscreteShortcut(steps: [step]))
            return
        }

        var sensitivity = 0.0
        if let suffix = sensitivitySuffix {
            guard let value = Double(suffix), (0.0 ... 1.0).contains(value) else {
                throw ShortcutParsingError.malformedSensitivity(suffix)
            }
            sensitivity = value
        }
        self = .continuous(ContinuousShortcut(
            kind: continuousKind,
            modifiers: step.modifiers,
            sensitivity: sensitivity
        ))
    }

    /// VS Code-style ascii representation. Round-trips with `init(ascii:)`.
    var ascii: String {
        switch self {
        case let .discrete(shortcut):
            return shortcut.ascii
        case let .continuous(shortcut):
            let step = DiscreteShortcut.Step(
                kind: shortcut.kind.asDiscreteKind,
                modifiers: shortcut.modifiers
            )
            return step.ascii + " @" + String(shortcut.sensitivity)
        }
    }
}

// MARK: - ExpressibleByStringLiteral

extension Shortcut: ExpressibleByStringLiteral {
    /// `"cmd+s"` is a `Shortcut` anywhere one is expected.
    ///
    /// A string *literal* is a compile-time constant; a malformed literal
    /// triggers `fatalError` — caught immediately during development. For
    /// runtime strings (config files, command palettes) use the throwing
    /// `init(ascii:)` instead.
    public init(stringLiteral value: String) {
        do {
            self = try Shortcut(ascii: value)
        } catch {
            fatalError("Invalid Shortcut string literal \"\(value)\": \(error)")
        }
    }
}
