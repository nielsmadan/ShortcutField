import AppKit
import Carbon.HIToolbox
import ShortcutField
import Testing

@Test func sequence_storesSteps() {
    let steps = [
        Shortcut(keyCode: 40, modifiers: .command),
        Shortcut(keyCode: 8, modifiers: .command),
    ]
    let seq = ShortcutSequence(steps: steps)
    #expect(seq.steps.count == 2)
    #expect(seq.steps[0] == steps[0])
    #expect(seq.steps[1] == steps[1])
}

@Test func sequence_equatable_sameSteps_areEqual() {
    let a = ShortcutSequence(steps: [
        Shortcut(keyCode: 40, modifiers: .command),
        Shortcut(keyCode: 8, modifiers: .command),
    ])
    let b = ShortcutSequence(steps: [
        Shortcut(keyCode: 40, modifiers: .command),
        Shortcut(keyCode: 8, modifiers: .command),
    ])
    #expect(a == b)
}

@Test func sequence_equatable_differentSteps_areNotEqual() {
    let a = ShortcutSequence(steps: [
        Shortcut(keyCode: 40, modifiers: .command),
        Shortcut(keyCode: 8, modifiers: .command),
    ])
    let b = ShortcutSequence(steps: [
        Shortcut(keyCode: 40, modifiers: .command),
        Shortcut(keyCode: 12, modifiers: .command),
    ])
    #expect(a != b)
}

@Test func sequence_codableRoundtrip() throws {
    let original = ShortcutSequence(steps: [
        Shortcut(keyCode: 40, modifiers: .command),
        Shortcut(keyCode: 8, modifiers: .command),
    ])
    let data = try JSONEncoder().encode(original)
    let decoded = try JSONDecoder().decode(ShortcutSequence.self, from: data)
    #expect(decoded == original)
}

@Test func sequence_decodeEmptySteps_throwsDecodingError() {
    let data = Data(#"{"steps":[]}"#.utf8)
    #expect(throws: DecodingError.self) {
        try JSONDecoder().decode(ShortcutSequence.self, from: data)
    }
}

@Test func sequence_init_mixedKinds_succeeds() {
    let steps: [Shortcut] = [
        Shortcut(keyCode: UInt16(kVK_ANSI_K), modifiers: .command),
        Shortcut(kind: .mouseButton(number: 1), modifiers: []),
        Shortcut(kind: .pinchIn, modifiers: []),
        Shortcut(kind: .rotateClockwise, modifiers: .command),
        Shortcut(kind: .smartMagnify, modifiers: []),
    ]
    let seq = ShortcutSequence(steps: steps)
    #expect(seq.steps == steps)
}

@Test func sequence_codableRoundtrip_mixedKinds() throws {
    let original = ShortcutSequence(steps: [
        Shortcut(keyCode: UInt16(kVK_ANSI_K), modifiers: .command),
        Shortcut(kind: .mouseButton(number: 1), modifiers: []),
        Shortcut(kind: .pinchIn, modifiers: []),
        Shortcut(kind: .rotateClockwise, modifiers: .command),
        Shortcut(kind: .smartMagnify, modifiers: []),
        Shortcut(kind: .scroll(direction: .up), modifiers: []),
    ])
    let data = try JSONEncoder().encode(original)
    let decoded = try JSONDecoder().decode(ShortcutSequence.self, from: data)
    #expect(decoded == original)
}

@Test func sequence_decodeMalformed_throwsDecodingError() {
    // Unknown step type — the per-step `Shortcut.init(from:)` should reject it.
    let unknownTypeJSON = Data(#"""
    {"steps":[{"type":"bogus","modifiers":0}]}
    """#.utf8)
    #expect(throws: DecodingError.self) {
        try JSONDecoder().decode(ShortcutSequence.self, from: unknownTypeJSON)
    }

    // Swipe step missing the required `direction` field.
    let missingFieldJSON = Data(#"""
    {"steps":[{"type":"scroll","modifiers":0}]}
    """#.utf8)
    #expect(throws: DecodingError.self) {
        try JSONDecoder().decode(ShortcutSequence.self, from: missingFieldJSON)
    }
}

@Test func sequence_displayString_joinedWithSpace() {
    let seq = ShortcutSequence(steps: [
        Shortcut(keyCode: 40, modifiers: .command),
        Shortcut(keyCode: 8, modifiers: .command),
    ])
    let expected = seq.steps.map(\.displayString).joined(separator: " ")
    #expect(seq.displayString == expected)
}

@Test func sequence_threeSteps() {
    let seq = ShortcutSequence(steps: [
        Shortcut(keyCode: 5, modifiers: []),
        Shortcut(keyCode: 5, modifiers: []),
        Shortcut(keyCode: 5, modifiers: []),
    ])
    #expect(seq.steps.count == 3)
}
