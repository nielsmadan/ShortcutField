import AppKit
import Carbon.HIToolbox
import ShortcutField
import Testing

// MARK: - Init / clamping

@Test func continuous_storesKindAndModifiers() {
    let cs = ContinuousShortcut(kind: .pinchIn, modifiers: [.command, .shift])
    #expect(cs.kind == .pinchIn)
    #expect(cs.modifiers == [.command, .shift])
}

@Test func continuous_init_masksUnsupportedModifiers() {
    let cs = ContinuousShortcut(kind: .pinchIn, modifiers: [.command, .capsLock, .function])
    #expect(cs.modifiers == .command)
}

// MARK: - Sensitivity clamping

@Test func continuous_sensitivity_defaultsToZero() {
    let cs = ContinuousShortcut(kind: .pinchIn, modifiers: [])
    #expect(cs.sensitivity == 0.0)
}

@Test func continuous_sensitivity_clampsAboveOne() {
    let cs = ContinuousShortcut(kind: .pinchIn, modifiers: [], sensitivity: 1.5)
    #expect(cs.sensitivity == 1.0)
}

@Test func continuous_sensitivity_clampsBelowZero() {
    let cs = ContinuousShortcut(kind: .pinchIn, modifiers: [], sensitivity: -0.5)
    #expect(cs.sensitivity == 0.0)
}

@Test func continuous_sensitivity_preservesValidValue() {
    let kinds: [ContinuousShortcut.Kind] = [
        .scroll(direction: .up),
        .pinchIn, .pinchOut,
        .rotateClockwise, .rotateCounterClockwise,
    ]
    for kind in kinds {
        let cs = ContinuousShortcut(kind: kind, modifiers: [], sensitivity: 0.5)
        #expect(cs.sensitivity == 0.5)
    }
}

// MARK: - Equatable

@Test func continuous_equatable_sameValues_areEqual() {
    let a = ContinuousShortcut(kind: .pinchIn, modifiers: .command, sensitivity: 0.5)
    let b = ContinuousShortcut(kind: .pinchIn, modifiers: .command, sensitivity: 0.5)
    #expect(a == b)
}

@Test func continuous_equatable_differentSensitivity_areNotEqual() {
    let a = ContinuousShortcut(kind: .pinchIn, modifiers: [], sensitivity: 0.0)
    let b = ContinuousShortcut(kind: .pinchIn, modifiers: [], sensitivity: 0.5)
    #expect(a != b)
}

@Test func continuous_equatable_differentKind_areNotEqual() {
    let a = ContinuousShortcut(kind: .pinchIn, modifiers: [])
    let b = ContinuousShortcut(kind: .pinchOut, modifiers: [])
    #expect(a != b)
}

@Test func continuous_equatable_differentModifiers_areNotEqual() {
    let a = ContinuousShortcut(kind: .pinchIn, modifiers: .command)
    let b = ContinuousShortcut(kind: .pinchIn, modifiers: .shift)
    #expect(a != b)
}

// MARK: - Hashable

@Test func continuous_hashable_sameValuesProduceEqualHash() {
    let a = ContinuousShortcut(kind: .pinchIn, modifiers: .command, sensitivity: 0.5)
    let b = ContinuousShortcut(kind: .pinchIn, modifiers: .command, sensitivity: 0.5)
    var set: Set<ContinuousShortcut> = [a]
    set.insert(b)
    #expect(set.count == 1)
}

@Test func continuous_hashable_differentValuesProduceDifferentHash() {
    let a = ContinuousShortcut(kind: .pinchIn, modifiers: [])
    let b = ContinuousShortcut(kind: .pinchOut, modifiers: [])
    let c = ContinuousShortcut(kind: .pinchIn, modifiers: .command)
    let d = ContinuousShortcut(kind: .pinchIn, modifiers: [], sensitivity: 0.5)
    let set: Set<ContinuousShortcut> = [a, b, c, d]
    #expect(set.count == 4)
}

// MARK: - Codable

@Test func continuous_codableRoundtrip_pinch() throws {
    let original = ContinuousShortcut(kind: .pinchIn, modifiers: .command, sensitivity: 0.5)
    let data = try JSONEncoder().encode(original)
    let decoded = try JSONDecoder().decode(ContinuousShortcut.self, from: data)
    #expect(decoded == original)
}

@Test func continuous_codableRoundtrip_scroll() throws {
    let original = ContinuousShortcut(
        kind: .scroll(direction: .down),
        modifiers: .shift,
        sensitivity: 0.6
    )
    let data = try JSONEncoder().encode(original)
    let decoded = try JSONDecoder().decode(ContinuousShortcut.self, from: data)
    #expect(decoded == original)
}

@Test func continuous_codableRoundtrip_rotate() throws {
    let original = ContinuousShortcut(
        kind: .rotateCounterClockwise,
        modifiers: .shift,
        sensitivity: 0.75
    )
    let data = try JSONEncoder().encode(original)
    let decoded = try JSONDecoder().decode(ContinuousShortcut.self, from: data)
    #expect(decoded == original)
}

@Test func continuous_decode_clampsSensitivity() throws {
    let json = """
    {"type":"pinchIn","modifiers":0,"sensitivity":5.0}
    """
    let data = Data(json.utf8)
    let decoded = try JSONDecoder().decode(ContinuousShortcut.self, from: data)
    #expect(decoded.sensitivity == 1.0)
}

@Test func continuous_decode_missingSensitivity_defaultsToZero() throws {
    let cmd = NSEvent.ModifierFlags.command.rawValue
    let json = #"{"type":"pinchIn","modifiers":\#(cmd)}"#
    let decoded = try JSONDecoder().decode(ContinuousShortcut.self, from: Data(json.utf8))
    #expect(decoded.kind == .pinchIn)
    #expect(decoded.sensitivity == 0.0)
}

@Test func continuous_decode_keyKind_throws() {
    let json = #"{"type":"key","keyCode":38,"modifiers":0}"#
    #expect(throws: DecodingError.self) {
        _ = try JSONDecoder().decode(ContinuousShortcut.self, from: Data(json.utf8))
    }
}

@Test func continuous_decode_mouseButtonKind_throws() {
    let json = #"{"type":"mouseButton","buttonNumber":1,"modifiers":0}"#
    #expect(throws: DecodingError.self) {
        _ = try JSONDecoder().decode(ContinuousShortcut.self, from: Data(json.utf8))
    }
}

@Test func continuous_decode_smartMagnifyKind_throws() {
    let json = #"{"type":"smartMagnify","modifiers":0}"#
    #expect(throws: DecodingError.self) {
        _ = try JSONDecoder().decode(ContinuousShortcut.self, from: Data(json.utf8))
    }
}

@Test func continuous_decode_bogusKind_throws() {
    let json = #"{"type":"bogus","modifiers":0}"#
    #expect(throws: DecodingError.self) {
        _ = try JSONDecoder().decode(ContinuousShortcut.self, from: Data(json.utf8))
    }
}

// MARK: - Display string

@Test func continuous_displayString_pinch_withCommand() {
    let cs = ContinuousShortcut(kind: .pinchIn, modifiers: .command, sensitivity: 0.5)
    #expect(cs.displayString == "⌘Pinch In")
}

@Test func continuous_displayString_scroll_noModifiers() {
    let cs = ContinuousShortcut(kind: .scroll(direction: .up), modifiers: [])
    #expect(cs.displayString == "Scroll Up")
}

// MARK: - Kind projection (ContinuousShortcut.Kind ↔ DiscreteShortcut.Kind)

@Test func continuousKind_init_fromDiscreteKey_returnsNil() {
    #expect(ContinuousShortcut.Kind(.key(keyCode: UInt16(kVK_ANSI_K))) == nil)
}

@Test func continuousKind_init_fromDiscreteMouseButton_returnsNil() {
    #expect(ContinuousShortcut.Kind(.mouseButton(number: 1)) == nil)
}

@Test func continuousKind_init_fromDiscreteSmartMagnify_returnsNil() {
    #expect(ContinuousShortcut.Kind(.smartMagnify) == nil)
}

@Test func continuousKind_init_fromContinuous_returnsMatchingVariant() {
    #expect(ContinuousShortcut.Kind(.scroll(direction: .down)) == .scroll(direction: .down))
    #expect(ContinuousShortcut.Kind(.pinchIn) == .pinchIn)
    #expect(ContinuousShortcut.Kind(.pinchOut) == .pinchOut)
    #expect(ContinuousShortcut.Kind(.rotateClockwise) == .rotateClockwise)
    #expect(ContinuousShortcut.Kind(.rotateCounterClockwise) == .rotateCounterClockwise)
}

@Test func continuousKind_asDiscreteKind_roundtrips() {
    let cases: [ContinuousShortcut.Kind] = [
        .scroll(direction: .right),
        .pinchIn, .pinchOut,
        .rotateClockwise, .rotateCounterClockwise,
    ]
    for kind in cases {
        let lifted = kind.asDiscreteKind
        let projected = ContinuousShortcut.Kind(lifted)
        #expect(projected == kind)
    }
}
