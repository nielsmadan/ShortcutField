import AppKit
import Carbon.HIToolbox
@testable import ShortcutField
import Testing

// NSSearchField instantiation can crash when run in parallel in headless CI
@Suite(.serialized) struct ShortcutSequenceRecorderFieldTests {
    @MainActor
    @Test func sequenceRecorderField_defaultState() {
        let field = ShortcutSequenceRecorderField()
        #expect(field.shortcutSequence == nil)
        #expect(!field.isRecording)
        #expect(field.frame.width >= 130)
    }

    @MainActor
    @Test func sequenceRecorderField_setSequence_updatesDisplay() {
        let field = ShortcutSequenceRecorderField()
        let seq = ShortcutSequence(steps: [
            Shortcut(keyCode: 40, modifiers: .command),
            Shortcut(keyCode: 8, modifiers: .command)
        ])
        field.shortcutSequence = seq
        #expect(field.shortcutSequence == seq)
        #expect(field.stringValue == seq.displayString)
    }

    @MainActor
    @Test func sequenceRecorderField_clearSequence_clearsDisplay() {
        let field = ShortcutSequenceRecorderField()
        field.shortcutSequence = ShortcutSequence(steps: [
            Shortcut(keyCode: 40, modifiers: .command),
            Shortcut(keyCode: 8, modifiers: .command)
        ])
        field.shortcutSequence = nil
        #expect(field.shortcutSequence == nil)
        #expect(field.stringValue == "")
    }

    @MainActor
    @Test func sequenceRecorderField_onSequenceChange_notCalledOnProgrammaticSet() {
        let field = ShortcutSequenceRecorderField()
        var callCount = 0
        field.onShortcutSequenceChange = { _ in
            callCount += 1
        }
        field.shortcutSequence = ShortcutSequence(steps: [
            Shortcut(keyCode: 40, modifiers: .command),
            Shortcut(keyCode: 8, modifiers: .command)
        ])
        #expect(callCount == 0)
    }

    @MainActor
    @Test func sequenceRecorderField_controlTextDidEndEditing_submitsRecordedSteps() {
        let field = ShortcutSequenceRecorderField()
        field._startRecordingForTesting()

        let event = NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: .command,
            timestamp: 0, windowNumber: 0, context: nil,
            characters: "k", charactersIgnoringModifiers: "k",
            isARepeat: false, keyCode: 40 // K
        )!
        _ = field._handleEventForTesting(event)

        var receivedSequence: ShortcutSequence?
        field.onShortcutSequenceChange = { receivedSequence = $0 }

        field._controlTextDidEndEditingForTesting()

        #expect(!field.isRecording)
        #expect(field.shortcutSequence != nil)
        #expect(field.shortcutSequence?.steps.count == 1)
        #expect(receivedSequence != nil)
        #expect(receivedSequence == field.shortcutSequence)
    }

    @MainActor
    @Test func sequenceRecorderField_controlTextDidEndEditing_noSteps_doesNotSetSequence() {
        let field = ShortcutSequenceRecorderField()
        field._startRecordingForTesting()

        var callbackCalled = false
        field.onShortcutSequenceChange = { _ in callbackCalled = true }

        field._controlTextDidEndEditingForTesting()

        #expect(!field.isRecording)
        #expect(field.shortcutSequence == nil)
        #expect(!callbackCalled)
    }

    @MainActor
    @Test func sequenceRecorderField_intrinsicContentSize_hasMinimumWidth() {
        let field = ShortcutSequenceRecorderField()
        #expect(field.intrinsicContentSize.width >= 130)
    }

    @MainActor
    @Test func sequenceRecorderField_setSequence_preservedWhenCleared() {
        let field = ShortcutSequenceRecorderField()
        let seq = ShortcutSequence(steps: [
            Shortcut(keyCode: 40, modifiers: .command),
            Shortcut(keyCode: 8, modifiers: .command)
        ])
        field.shortcutSequence = seq
        field.shortcutSequence = nil
        #expect(field.shortcutSequence == nil)
        // Re-set to verify field still works after clearing
        field.shortcutSequence = seq
        #expect(field.stringValue == seq.displayString)
    }
}
