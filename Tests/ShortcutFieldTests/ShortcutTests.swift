import AppKit
import Carbon.HIToolbox
@testable import ShortcutField
import Testing

@Suite struct ShortcutTests {
    // MARK: - Step init

    @Test func step_storesKindAndModifiers() {
        let step = Shortcut.Step(kind: .key(keyCode: UInt16(kVK_ANSI_J)), modifiers: [.command, .shift])
        #expect(step.kind == .key(keyCode: UInt16(kVK_ANSI_J)))
        #expect(step.modifiers == [.command, .shift])
    }

    @Test func step_keyCodeConvenienceInit_buildsKeyKind() {
        let step = Shortcut.Step(keyCode: UInt16(kVK_ANSI_J), modifiers: [.command, .shift])
        #expect(step.kind == .key(keyCode: UInt16(kVK_ANSI_J)))
        #expect(step.modifiers == [.command, .shift])
    }

    @Test func step_init_masksUnsupportedModifiers() {
        let step = Shortcut.Step(kind: .pinchIn, modifiers: [.command, .capsLock, .function])
        #expect(step.modifiers == .command)
    }

    // MARK: - Shortcut init

    @Test func shortcut_init_keyCode_buildsSingleStep() {
        let s = Shortcut(keyCode: UInt16(kVK_ANSI_J), modifiers: [.command])
        #expect(s.steps.count == 1)
        #expect(s.steps[0].kind == .key(keyCode: UInt16(kVK_ANSI_J)))
        #expect(s.steps[0].modifiers == .command)
    }

    @Test func shortcut_init_kind_buildsSingleStep() {
        let s = Shortcut(kind: .pinchIn, modifiers: [.command])
        #expect(s.steps.count == 1)
        #expect(s.steps[0].kind == .pinchIn)
        #expect(s.steps[0].modifiers == .command)
    }

    @Test func shortcut_init_steps_preservesOrder() {
        let steps: [Shortcut.Step] = [
            .init(keyCode: UInt16(kVK_ANSI_J), modifiers: [.command]),
            .init(keyCode: UInt16(kVK_ANSI_S), modifiers: [.command]),
        ]
        let s = Shortcut(steps: steps)
        #expect(s.steps == steps)
    }

    @Test func shortcut_init_mixedKinds_succeeds() {
        let steps: [Shortcut.Step] = [
            .init(kind: .key(keyCode: UInt16(kVK_ANSI_K)), modifiers: .command),
            .init(kind: .mouseButton(number: 1), modifiers: []),
            .init(kind: .pinchIn, modifiers: []),
            .init(kind: .rotateClockwise, modifiers: .command),
            .init(kind: .smartMagnify, modifiers: []),
        ]
        let s = Shortcut(steps: steps)
        #expect(s.steps == steps)
    }

    // MARK: - Equatable

    @Test func shortcut_equatable_sameSteps_areEqual() {
        let a = Shortcut(keyCode: UInt16(kVK_ANSI_J), modifiers: [.command])
        let b = Shortcut(keyCode: UInt16(kVK_ANSI_J), modifiers: [.command])
        #expect(a == b)
    }

    @Test func shortcut_equatable_differentSteps_areNotEqual() {
        let a = Shortcut(keyCode: UInt16(kVK_ANSI_J), modifiers: [.command])
        let b = Shortcut(keyCode: UInt16(kVK_ANSI_S), modifiers: [.command])
        #expect(a != b)
    }

    @Test func shortcut_equatable_differentLength_areNotEqual() {
        let a = Shortcut(steps: [.init(keyCode: UInt16(kVK_ANSI_J), modifiers: .command)])
        let b = Shortcut(steps: [
            .init(keyCode: UInt16(kVK_ANSI_J), modifiers: .command),
            .init(keyCode: UInt16(kVK_ANSI_S), modifiers: .command),
        ])
        #expect(a != b)
    }

    // MARK: - Hashable

    @Test func shortcut_hashable_sameValuesProduceEqualHash() {
        let a = Shortcut(keyCode: UInt16(kVK_ANSI_J), modifiers: [.command])
        let b = Shortcut(keyCode: UInt16(kVK_ANSI_J), modifiers: [.command])
        var set: Set<Shortcut> = [a]
        set.insert(b)
        #expect(set.count == 1)
    }

    @Test func shortcut_hashable_differentStepsProduceDifferentHash() {
        let a = Shortcut(kind: .pinchIn, modifiers: [])
        let b = Shortcut(kind: .pinchOut, modifiers: [])
        let set: Set<Shortcut> = [a, b]
        #expect(set.count == 2)
    }

    // MARK: - Codable

    @Test func shortcut_codableRoundtrip_singleStep() throws {
        let original = Shortcut(keyCode: UInt16(kVK_ANSI_J), modifiers: [.command, .shift])
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(Shortcut.self, from: data)
        #expect(decoded == original)
    }

    @Test func shortcut_codableRoundtrip_multiStep() throws {
        let original = Shortcut(steps: [
            .init(keyCode: UInt16(kVK_ANSI_K), modifiers: .command),
            .init(keyCode: UInt16(kVK_ANSI_C), modifiers: .command),
        ])
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(Shortcut.self, from: data)
        #expect(decoded == original)
    }

    @Test func shortcut_codableRoundtrip_mixedKinds() throws {
        let original = Shortcut(steps: [
            .init(kind: .key(keyCode: UInt16(kVK_ANSI_K)), modifiers: .command),
            .init(kind: .mouseButton(number: 1), modifiers: []),
            .init(kind: .pinchIn, modifiers: []),
            .init(kind: .rotateCounterClockwise, modifiers: .shift),
            .init(kind: .smartMagnify, modifiers: []),
            .init(kind: .scroll(direction: .down), modifiers: []),
        ])
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(Shortcut.self, from: data)
        #expect(decoded == original)
    }

    @Test func shortcut_decodeEmptySteps_throwsDecodingError() {
        let data = Data(#"{"steps":[]}"#.utf8)
        #expect(throws: DecodingError.self) {
            _ = try JSONDecoder().decode(Shortcut.self, from: data)
        }
    }

    @Test func shortcut_decodeUnknownStepType_throwsDecodingError() {
        let data = Data(#"""
        {"steps":[{"type":"bogus","modifiers":0}]}
        """#.utf8)
        #expect(throws: DecodingError.self) {
            _ = try JSONDecoder().decode(Shortcut.self, from: data)
        }
    }

    @Test func shortcut_decodeMissingStepField_throwsDecodingError() {
        // scroll step missing the required `direction` field
        let data = Data(#"""
        {"steps":[{"type":"scroll","modifiers":0}]}
        """#.utf8)
        #expect(throws: DecodingError.self) {
            _ = try JSONDecoder().decode(Shortcut.self, from: data)
        }
    }

    @Test func shortcut_decodeOldFlatShape_throwsDecodingError() {
        // Pre-refactor v1 shape: bare `{type, keyCode, modifiers}` without `steps`.
        // The new decoder requires the `steps` envelope and must cleanly reject the old shape.
        let cmd = NSEvent.ModifierFlags.command.rawValue
        let json = #"{"type":"key","keyCode":38,"modifiers":\#(cmd)}"#
        #expect(throws: DecodingError.self) {
            _ = try JSONDecoder().decode(Shortcut.self, from: Data(json.utf8))
        }
    }

    // MARK: - Convenience-init equivalence

    @Test func shortcut_keyCodeConvenienceInit_equivalentToStepsInit() {
        let a = Shortcut(keyCode: UInt16(kVK_ANSI_J), modifiers: [.command])
        let b = Shortcut(steps: [Shortcut.Step(keyCode: UInt16(kVK_ANSI_J), modifiers: [.command])])
        #expect(a == b)
    }

    @Test func shortcut_kindConvenienceInit_equivalentToStepsInit() {
        let a = Shortcut(kind: .pinchIn, modifiers: [.command])
        let b = Shortcut(steps: [Shortcut.Step(kind: .pinchIn, modifiers: [.command])])
        #expect(a == b)
    }

    // MARK: - Kind.tag (wire-format discriminator)

    @Test func kind_tag_pinsCanonicalStrings() {
        #expect(Shortcut.Kind.key(keyCode: 0).tag == "key")
        #expect(Shortcut.Kind.mouseButton(number: 0).tag == "mouseButton")
        #expect(Shortcut.Kind.scroll(direction: .up).tag == "scroll")
        #expect(Shortcut.Kind.pinchIn.tag == "pinchIn")
        #expect(Shortcut.Kind.pinchOut.tag == "pinchOut")
        #expect(Shortcut.Kind.rotateClockwise.tag == "rotateClockwise")
        #expect(Shortcut.Kind.rotateCounterClockwise.tag == "rotateCounterClockwise")
        #expect(Shortcut.Kind.smartMagnify.tag == "smartMagnify")
    }
}

// MARK: - Display string

// UCKeyTranslate is not thread-safe — keep these in the serialized display-string
// suite (see ShortcutDisplayStringTests.swift) rather than free top-level tests.

@MainActor
@Suite(.serialized) struct ShortcutDisplayStringStructuralTests {
    @Test func shortcut_displayString_singleStep_pinsLiteral() {
        let s = Shortcut(keyCode: UInt16(kVK_Tab), modifiers: .command)
        #expect(s.displayString == "⌘Tab")
    }

    @Test func shortcut_displayString_joinedWithSpace_pinsLiteral() {
        let s = Shortcut(steps: [
            .init(keyCode: UInt16(kVK_Tab), modifiers: .command),
            .init(keyCode: UInt16(kVK_Return), modifiers: .command),
        ])
        #expect(s.displayString == "⌘Tab ⌘↩")
    }
}
