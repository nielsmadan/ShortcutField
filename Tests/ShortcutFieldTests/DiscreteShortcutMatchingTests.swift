import AppKit
import Carbon.HIToolbox
@testable import ShortcutField
import SwiftUI
import Testing

/// CGEvent is not thread-safe — run these serially to avoid crashes in CI.
/// `@MainActor` at struct level also serializes against other @MainActor suites
/// that touch CGEvent / NSSearchField / global ShortcutRecordingState.
@MainActor
@Suite(.serialized) struct DiscreteShortcutMatchingTests {
    // MARK: - Keyboard

    @Test func key_matchesEvent_sameKeyAndModifiers_returnsTrue() {
        let step = DiscreteShortcut.Step(keyCode: UInt16(kVK_Tab), modifiers: [.command, .shift])
        let event = keyDown(kVK_Tab, [.command, .shift])
        #expect(step.matches(event))
    }

    @Test func key_matchesEvent_wrongModifiers_returnsFalse() {
        let step = DiscreteShortcut.Step(keyCode: UInt16(kVK_Tab), modifiers: [.command])
        let event = keyDown(kVK_Tab, [.command, .shift])
        #expect(!step.matches(event))
    }

    @Test func key_matchesEvent_wrongKey_returnsFalse() {
        let step = DiscreteShortcut.Step(keyCode: UInt16(kVK_Tab), modifiers: [.command])
        let event = keyDown(kVK_Return, [.command])
        #expect(!step.matches(event))
    }

    @Test func key_matchesEvent_ignoresNonShortcutFlags() {
        let step = DiscreteShortcut.Step(keyCode: UInt16(kVK_Tab), modifiers: [.command])
        let event = keyDown(kVK_Tab, [.command, .capsLock, .numericPad])
        #expect(step.matches(event))
    }

    @Test func key_matchesEvent_noModifiers() {
        let step = DiscreteShortcut.Step(keyCode: UInt16(kVK_Tab), modifiers: [])
        let event = keyDown(kVK_Tab, [])
        #expect(step.matches(event))
    }

    // MARK: - Pinch (via gesture event shape)

    @Test func pinchIn_matchesNegativeMagnification() {
        let step = DiscreteShortcut.Step(kind: .pinchIn, modifiers: [])
        let event = ShortcutEventShape(type: .magnify, magnification: -0.05)
        #expect(step.matches(event))
    }

    @Test func pinchIn_doesNotMatchPositiveMagnification() {
        let step = DiscreteShortcut.Step(kind: .pinchIn, modifiers: [])
        let event = ShortcutEventShape(type: .magnify, magnification: 0.05)
        #expect(!step.matches(event))
    }

    @Test func pinchOut_matchesPositiveMagnification() {
        let step = DiscreteShortcut.Step(kind: .pinchOut, modifiers: [])
        let event = ShortcutEventShape(type: .magnify, magnification: 0.05)
        #expect(step.matches(event))
    }

    @Test func pinch_subThresholdDoesNotMatch() {
        let step = DiscreteShortcut.Step(kind: .pinchIn, modifiers: [])
        let event = ShortcutEventShape(type: .magnify, magnification: -0.001)
        #expect(!step.matches(event))
    }

    @Test func pinch_modifierMismatchDoesNotMatch() {
        let step = DiscreteShortcut.Step(kind: .pinchIn, modifiers: .command)
        let event = ShortcutEventShape(type: .magnify, modifierFlags: [], magnification: -0.05)
        #expect(!step.matches(event))
    }

    @Test func pinch_modifierMatchMatches() {
        let step = DiscreteShortcut.Step(kind: .pinchIn, modifiers: .command)
        let event = ShortcutEventShape(type: .magnify, modifierFlags: .command, magnification: -0.05)
        #expect(step.matches(event))
    }

    @Test func pinch_doesNotMatchOtherEventType() {
        let step = DiscreteShortcut.Step(kind: .pinchIn, modifiers: [])
        let event = ShortcutEventShape(type: .rotate, rotation: 5)
        #expect(!step.matches(event))
    }

    // MARK: - Rotate

    @Test func rotateCCW_matchesPositiveRotation() {
        let step = DiscreteShortcut.Step(kind: .rotateCounterClockwise, modifiers: [])
        let event = ShortcutEventShape(type: .rotate, rotation: 5)
        #expect(step.matches(event))
    }

    @Test func rotateCW_matchesNegativeRotation() {
        let step = DiscreteShortcut.Step(kind: .rotateClockwise, modifiers: [])
        let event = ShortcutEventShape(type: .rotate, rotation: -5)
        #expect(step.matches(event))
    }

    @Test func rotate_subThresholdDoesNotMatch() {
        let step = DiscreteShortcut.Step(kind: .rotateClockwise, modifiers: [])
        let event = ShortcutEventShape(type: .rotate, rotation: -0.1)
        #expect(!step.matches(event))
    }

    @Test func rotate_modifierMismatchDoesNotMatch() {
        let step = DiscreteShortcut.Step(kind: .rotateClockwise, modifiers: .command)
        let event = ShortcutEventShape(type: .rotate, modifierFlags: [], rotation: -5)
        #expect(!step.matches(event))
    }

    @Test func rotate_modifierMatchMatches() {
        let step = DiscreteShortcut.Step(kind: .rotateClockwise, modifiers: .command)
        let event = ShortcutEventShape(type: .rotate, modifierFlags: .command, rotation: -5)
        #expect(step.matches(event))
    }

    @Test func rotate_doesNotMatchOtherEventType() {
        let step = DiscreteShortcut.Step(kind: .rotateClockwise, modifiers: [])
        let event = ShortcutEventShape(type: .magnify, magnification: -0.05)
        #expect(!step.matches(event))
    }

    // MARK: - Smart magnify

    @Test func smartMagnify_matchesEvent() {
        let step = DiscreteShortcut.Step(kind: .smartMagnify, modifiers: [])
        let event = ShortcutEventShape(type: .smartMagnify)
        #expect(step.matches(event))
    }

    @Test func smartMagnify_doesNotMatchPinch() {
        let step = DiscreteShortcut.Step(kind: .smartMagnify, modifiers: [])
        let event = ShortcutEventShape(type: .magnify, magnification: 0.05)
        #expect(!step.matches(event))
    }

    @Test func smartMagnify_modifierMismatchDoesNotMatch() {
        let step = DiscreteShortcut.Step(kind: .smartMagnify, modifiers: .command)
        let event = ShortcutEventShape(type: .smartMagnify, modifierFlags: [])
        #expect(!step.matches(event))
    }

    @Test func smartMagnify_modifierMatchMatches() {
        let step = DiscreteShortcut.Step(kind: .smartMagnify, modifiers: .command)
        let event = ShortcutEventShape(type: .smartMagnify, modifierFlags: .command)
        #expect(step.matches(event))
    }

    // MARK: - Cross-kind: gesture step should not match key event

    @Test func gestureStep_doesNotMatchKeyEvent() {
        let step = DiscreteShortcut.Step(kind: .pinchIn, modifiers: [])
        let event = keyDown(kVK_Tab)
        #expect(!step.matches(event))
    }

    @Test func keyStep_doesNotMatchGestureEvent() {
        let step = DiscreteShortcut.Step(keyCode: UInt16(kVK_Tab), modifiers: [])
        let event = ShortcutEventShape(type: .magnify, magnification: -0.05)
        #expect(!step.matches(event))
    }

    // MARK: - ContinuousShortcut.matches reuses step matching

    @Test func continuousShortcut_matches_scrollUp_returnsTrue() {
        let cs = ContinuousShortcut(kind: .scroll(direction: .up), modifiers: [])
        #expect(cs.matches(scrollEvent(deltaY: 10)))
    }

    @Test func continuousShortcut_matches_scrollDown_doesNotMatchUp() {
        let cs = ContinuousShortcut(kind: .scroll(direction: .up), modifiers: [])
        #expect(!cs.matches(scrollEvent(deltaY: -10)))
    }

    @Test func continuousShortcut_matches_modifierMismatch_returnsFalse() {
        let cs = ContinuousShortcut(kind: .scroll(direction: .up), modifiers: .command)
        #expect(!cs.matches(scrollEvent(deltaY: 10)))
    }
}

// MARK: - KeyPress

private struct LayoutFixture {
    var unshifted: [Int: String]
    var shifted: [Int: String]

    func character(_ keyCode: UInt16, _ isShifted: Bool) -> String? {
        (isShifted ? shifted : unshifted)[Int(keyCode)]
    }
}

private let usLayout = LayoutFixture(
    unshifted: [kVK_ANSI_K: "k", kVK_ANSI_E: "e", kVK_ANSI_1: "1", kVK_ANSI_Keypad1: "1"],
    shifted: [kVK_ANSI_K: "K", kVK_ANSI_E: "E", kVK_ANSI_1: "!", kVK_ANSI_Keypad1: "1"]
)

private let azertyLayout = LayoutFixture(
    unshifted: [kVK_ANSI_K: "k", kVK_ANSI_1: "&"],
    shifted: [kVK_ANSI_K: "K", kVK_ANSI_1: "1"]
)

@available(macOS 14.0, *)
private func functionKey(_ unicode: Int) -> KeyEquivalent {
    KeyEquivalent(Character(UnicodeScalar(UInt32(unicode))!))
}

@available(macOS 14.0, *)
private func step(_ keyCode: Int, _ modifiers: NSEvent.ModifierFlags = []) -> DiscreteShortcut.Step {
    DiscreteShortcut.Step(keyCode: UInt16(keyCode), modifiers: modifiers)
}

@Suite("KeyPress matching") struct KeyPressMatchingTests {
    @available(macOS 14.0, *)
    private func press(
        _ step: DiscreteShortcut.Step, key: KeyEquivalent, characters: String? = nil,
        modifiers: SwiftUI.EventModifiers = [], phase: KeyPress.Phases = .down, layout: LayoutFixture = usLayout
    ) -> Bool {
        step.matches(
            key: key, characters: characters ?? String(key.character), modifiers: modifiers, phase: phase,
            layoutCharacter: layout.character
        )
    }

    @available(macOS 14.0, *)
    @Test func tab_matchesTabKey() {
        #expect(press(step(kVK_Tab), key: .tab))
    }

    @available(macOS 14.0, *)
    @Test func return_matchesReturnKey() {
        #expect(press(step(kVK_Return, .command), key: .return, modifiers: .command))
    }

    @available(macOS 14.0, *)
    @Test func arrows_matchTheirKeyEquivalents() {
        #expect(press(step(kVK_UpArrow), key: .upArrow))
        #expect(press(step(kVK_DownArrow), key: .downArrow))
        #expect(press(step(kVK_LeftArrow), key: .leftArrow))
        #expect(press(step(kVK_RightArrow), key: .rightArrow))
    }

    @available(macOS 14.0, *)
    @Test func specialKey_wrongKey_doesNotMatch() {
        #expect(!press(step(kVK_Tab), key: .return))
    }

    @available(macOS 14.0, *)
    @Test func letter_matchesItsLayoutCharacter() {
        #expect(press(step(kVK_ANSI_K, .command), key: "k", modifiers: .command))
    }

    @available(macOS 14.0, *)
    @Test func letter_matchesRegardlessOfCase() {
        #expect(press(step(kVK_ANSI_K, .command), key: "K", modifiers: .command))
    }

    @available(macOS 14.0, *)
    @Test func letter_modifierMismatch_doesNotMatch() {
        #expect(!press(step(kVK_ANSI_K, .command), key: "k", modifiers: [.command, .shift]))
    }

    @available(macOS 14.0, *)
    @Test func digitRow_usesTheLayoutCharacter() {
        #expect(press(step(kVK_ANSI_1), key: "&", layout: azertyLayout))
        #expect(!press(step(kVK_ANSI_1), key: "1", layout: azertyLayout))
    }

    @available(macOS 14.0, *)
    @Test func nonKeyStep_doesNotMatch() {
        let click = DiscreteShortcut.Step(kind: .mouseButton(number: 0), modifiers: [])
        #expect(!press(click, key: .return))
    }

    @available(macOS 14.0, *)
    @Test func keyUp_doesNotMatch() {
        #expect(!press(step(kVK_Tab), key: .tab, phase: .up))
        #expect(press(step(kVK_Tab), key: .tab, phase: .repeat))
    }

    @available(macOS 14.0, *)
    @Test func functionKeys_matchTheirFunctionKeyCharacters() {
        #expect(press(step(kVK_F1), key: functionKey(NSF1FunctionKey)))
        #expect(press(step(kVK_F5, .command), key: functionKey(NSF5FunctionKey), modifiers: .command))
        #expect(press(step(kVK_F13), key: functionKey(NSF13FunctionKey)))
        #expect(press(step(kVK_F20), key: functionKey(NSF20FunctionKey)))
        #expect(!press(step(kVK_F5), key: functionKey(NSF6FunctionKey)))
    }

    @available(macOS 14.0, *)
    @Test func forwardDeleteHelpAndClear_match() {
        #expect(press(step(kVK_ForwardDelete), key: .deleteForward))
        #expect(press(step(kVK_Help), key: functionKey(NSHelpFunctionKey)))
        #expect(press(step(kVK_ANSI_KeypadClear), key: .clear, modifiers: .numericPad))
        #expect(press(step(kVK_ANSI_KeypadEnter), key: KeyEquivalent("\u{03}"), modifiers: .numericPad))
    }

    @available(macOS 14.0, *)
    @Test func keypadDigit_matchesItsCharacter() {
        #expect(press(step(kVK_ANSI_Keypad1), key: "1", modifiers: .numericPad))
        #expect(!press(step(kVK_ANSI_Keypad1), key: "2", modifiers: .numericPad))
    }

    @available(macOS 14.0, *)
    @Test func shiftedSymbol_matchesShiftedOrUnshiftedCharacters() {
        #expect(press(step(kVK_ANSI_1, .shift), key: "!", modifiers: .shift))
        #expect(press(step(kVK_ANSI_1, .shift), key: "1", modifiers: .shift))
        #expect(press(step(kVK_ANSI_1, .shift), key: "1", modifiers: .shift, layout: azertyLayout))
        #expect(press(step(kVK_ANSI_1, .shift), key: "&", modifiers: .shift, layout: azertyLayout))
    }

    @available(macOS 14.0, *)
    @Test func optionStep_matchesBaseCharacter() {
        #expect(press(step(kVK_ANSI_E, .option), key: "e", modifiers: .option))
    }
}

@available(macOS 14.0, *)
@MainActor
@Test func keyPressSeam_defaultsToTheCurrentLayout() throws {
    let k = try #require(DiscreteShortcut.keyToCharacter(keyCode: UInt16(kVK_ANSI_K)))
    let step = DiscreteShortcut.Step(keyCode: UInt16(kVK_ANSI_K), modifiers: .command)
    #expect(step.matches(key: KeyEquivalent(Character(k)), characters: k, modifiers: .command, phase: .down))
}
