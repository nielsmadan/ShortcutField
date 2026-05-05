import AppKit
import Carbon.HIToolbox
import ShortcutField
import Testing

// MARK: - Init / clamping

@Test func shortcut_storesKindAndModifiers() {
    let s = Shortcut(kind: .key(keyCode: 38), modifiers: [.command, .shift])
    #expect(s.kind == .key(keyCode: 38))
    #expect(s.modifiers.contains(.command))
    #expect(s.modifiers.contains(.shift))
}

@Test func shortcut_keyCodeConvenienceInit_buildsKeyKind() {
    let s = Shortcut(keyCode: 38, modifiers: [.command, .shift])
    #expect(s.kind == .key(keyCode: 38))
    #expect(s.modifiers.contains(.command))
    #expect(s.modifiers.contains(.shift))
}

@Test func shortcut_init_masksUnsupportedModifiers() {
    let s = Shortcut(kind: .pinchIn, modifiers: [.command, .capsLock, .function])
    #expect(s.modifiers == .command)
}

// MARK: - Sensitivity clamping

@Test func sensitivity_defaultsToZero() {
    let s = Shortcut(kind: .pinchIn, modifiers: [])
    #expect(s.sensitivity == 0.0)
}

@Test func sensitivity_clampsAboveOne() {
    let s = Shortcut(kind: .pinchIn, modifiers: [], sensitivity: 1.5)
    #expect(s.sensitivity == 1.0)
}

@Test func sensitivity_clampsBelowZero() {
    let s = Shortcut(kind: .pinchIn, modifiers: [], sensitivity: -0.5)
    #expect(s.sensitivity == 0.0)
}

@Test func sensitivity_preservesValidValueForContinuousKinds() {
    let kinds: [Shortcut.Kind] = [
        .scroll(direction: .up),
        .pinchIn, .pinchOut,
        .rotateClockwise, .rotateCounterClockwise,
    ]
    for kind in kinds {
        let s = Shortcut(kind: kind, modifiers: [], sensitivity: 0.5)
        #expect(s.sensitivity == 0.5)
    }
}

@Test func sensitivity_forcedZeroForDiscreteKinds() {
    let kinds: [Shortcut.Kind] = [
        .key(keyCode: 38),
        .mouseButton(number: 0),
        .smartMagnify,
    ]
    for kind in kinds {
        let s = Shortcut(kind: kind, modifiers: [], sensitivity: 0.7)
        #expect(s.sensitivity == 0.0)
    }
}

// MARK: - Equatable

@Test func equatable_sameValues_areEqual() {
    let a = Shortcut(keyCode: 38, modifiers: [.command])
    let b = Shortcut(keyCode: 38, modifiers: [.command])
    #expect(a == b)
}

@Test func equatable_differentKey_areNotEqual() {
    let a = Shortcut(keyCode: 38, modifiers: [.command])
    let b = Shortcut(keyCode: 1, modifiers: [.command])
    #expect(a != b)
}

@Test func equatable_differentModifiers_areNotEqual() {
    let a = Shortcut(keyCode: 38, modifiers: [.command])
    let b = Shortcut(keyCode: 38, modifiers: [.shift])
    #expect(a != b)
}

@Test func equatable_differentKind_areNotEqual() {
    let a = Shortcut(kind: .pinchIn, modifiers: [])
    let b = Shortcut(kind: .pinchOut, modifiers: [])
    #expect(a != b)
}

@Test func equatable_differentSensitivity_areNotEqual() {
    let a = Shortcut(kind: .pinchIn, modifiers: [], sensitivity: 0.0)
    let b = Shortcut(kind: .pinchIn, modifiers: [], sensitivity: 0.5)
    #expect(a != b)
}

@Test func equatable_buttonsWithDifferentSensitivityArguments_areEqual() {
    let a = Shortcut(kind: .mouseButton(number: 1), modifiers: [], sensitivity: 0.5)
    let b = Shortcut(kind: .mouseButton(number: 1), modifiers: [], sensitivity: 1.0)
    #expect(a == b) // sensitivity forced to 0 for discrete kinds
}

@Test func equatable_sameScrollSensitivity_areEqual() {
    let a = Shortcut(kind: .scroll(direction: .up), modifiers: [], sensitivity: 0.75)
    let b = Shortcut(kind: .scroll(direction: .up), modifiers: [], sensitivity: 0.75)
    #expect(a == b)
}

// MARK: - Hashable

@Test func hashable_sameValuesProduceEqualHash() {
    let a = Shortcut(keyCode: 38, modifiers: [.command])
    let b = Shortcut(keyCode: 38, modifiers: [.command])
    var setA: Set<Shortcut> = [a]
    setA.insert(b)
    #expect(setA.count == 1)
}

@Test func hashable_differentKindsProduceDifferentHash() {
    let a = Shortcut(kind: .pinchIn, modifiers: [])
    let b = Shortcut(kind: .pinchOut, modifiers: [])
    let set: Set<Shortcut> = [a, b]
    #expect(set.count == 2)
}

// MARK: - Codable round-trip

@Test func codable_keyRoundtrip() throws {
    let original = Shortcut(keyCode: 38, modifiers: [.command, .shift])
    let data = try JSONEncoder().encode(original)
    let decoded = try JSONDecoder().decode(Shortcut.self, from: data)
    #expect(decoded == original)
}

@Test func codable_keyRoundtrip_noModifiers() throws {
    let original = Shortcut(keyCode: 36, modifiers: [])
    let data = try JSONEncoder().encode(original)
    let decoded = try JSONDecoder().decode(Shortcut.self, from: data)
    #expect(decoded == original)
}

@Test func codable_mouseButtonRoundtrip() throws {
    let original = Shortcut(kind: .mouseButton(number: 2), modifiers: .control)
    let data = try JSONEncoder().encode(original)
    let decoded = try JSONDecoder().decode(Shortcut.self, from: data)
    #expect(decoded == original)
}

@Test func codable_scrollRoundtrip_withSensitivity() throws {
    let original = Shortcut(
        kind: .scroll(direction: .down),
        modifiers: .shift,
        sensitivity: 0.6
    )
    let data = try JSONEncoder().encode(original)
    let decoded = try JSONDecoder().decode(Shortcut.self, from: data)
    #expect(decoded == original)
    #expect(decoded.sensitivity == 0.6)
}

@Test func codable_pinchRoundtrip() throws {
    let original = Shortcut(kind: .pinchIn, modifiers: .command, sensitivity: 0.5)
    let data = try JSONEncoder().encode(original)
    let decoded = try JSONDecoder().decode(Shortcut.self, from: data)
    #expect(decoded == original)
}

@Test func codable_rotateRoundtrip() throws {
    let original = Shortcut(
        kind: .rotateCounterClockwise,
        modifiers: .shift,
        sensitivity: 0.75
    )
    let data = try JSONEncoder().encode(original)
    let decoded = try JSONDecoder().decode(Shortcut.self, from: data)
    #expect(decoded == original)
}

@Test func codable_smartMagnifyRoundtrip() throws {
    let original = Shortcut(kind: .smartMagnify, modifiers: .control)
    let data = try JSONEncoder().encode(original)
    let decoded = try JSONDecoder().decode(Shortcut.self, from: data)
    #expect(decoded == original)
}

@Test func codable_clampsSensitivityOnDecode() throws {
    let json = """
    {"type":"pinchIn","modifiers":0,"sensitivity":5.0}
    """
    let data = Data(json.utf8)
    let decoded = try JSONDecoder().decode(Shortcut.self, from: data)
    #expect(decoded.sensitivity == 1.0)
}

@Test func codable_backwardCompat_pinchMissingSensitivity() throws {
    let json = """
    {"type":"pinchIn","modifiers":1048576}
    """
    let data = Data(json.utf8)
    let decoded = try JSONDecoder().decode(Shortcut.self, from: data)
    #expect(decoded.kind == .pinchIn)
    #expect(decoded.sensitivity == 0.0)
}

@Test func codable_buttonDecodesWithZeroSensitivity() throws {
    let json = """
    {"type":"mouseButton","buttonNumber":1,"modifiers":0,"sensitivity":0.5}
    """
    let data = Data(json.utf8)
    let decoded = try JSONDecoder().decode(Shortcut.self, from: data)
    #expect(decoded.sensitivity == 0.0)
}

@Test func codable_unknownTypeThrows() {
    let json = """
    {"type":"something_else","modifiers":0}
    """
    let data = Data(json.utf8)
    #expect(throws: DecodingError.self) {
        _ = try JSONDecoder().decode(Shortcut.self, from: data)
    }
}
