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

// Construction with a non-`.key` step (e.g. `.mouseButton`) traps via `precondition`;
// Swift Testing has no clean way to assert preconditions, so the construction-time
// constraint is documented rather than tested. The Codable-side rejection is
// covered below.
@Test func sequence_decodeNonKeyStep_throwsDecodingError() {
    let data = Data(#"{"steps":[{"type":"mouseButton","buttonNumber":0,"modifiers":0,"sensitivity":0}]}"#.utf8)
    #expect(throws: DecodingError.self) {
        try JSONDecoder().decode(ShortcutSequence.self, from: data)
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
