import AppKit
import Carbon.HIToolbox
@testable import ShortcutField
import Testing

private func makeKeyEvent(keyCode: UInt16, modifiers: NSEvent.ModifierFlags = []) -> NSEvent {
    let event = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: true)!
    event.flags = CGEventFlags(rawValue: UInt64(modifiers.rawValue))
    return NSEvent(cgEvent: event)!
}

// CGEvent-backed key events and NSSearchField instances are not thread-safe in CI.
@Suite(.serialized) struct ShortcutSequenceTabHandlingTests {
    @MainActor
    @Test func dispatcher_sharedTabPrefix_routesToMatchingSequence() {
        let dispatcher = ShortcutSequenceEventDispatcher()
        let matcherT = ShortcutSequenceMatcher()
        let matcherQ = ShortcutSequenceMatcher()

        let sequenceT = ShortcutSequence(steps: [
            Shortcut(keyCode: UInt16(kVK_Tab), modifiers: []),
            Shortcut(keyCode: UInt16(kVK_Tab), modifiers: []),
            Shortcut(keyCode: 17, modifiers: []),
        ])
        let sequenceQ = ShortcutSequence(steps: [
            Shortcut(keyCode: UInt16(kVK_Tab), modifiers: []),
            Shortcut(keyCode: UInt16(kVK_Tab), modifiers: []),
            Shortcut(keyCode: 12, modifiers: []),
        ])

        var tCount = 0
        var qCount = 0

        matcherT.configure(sequence: sequenceT) { tCount += 1 }
        matcherQ.configure(sequence: sequenceQ) { qCount += 1 }

        dispatcher.register(id: UUID()) { matcherT.handle($0) }
        dispatcher.register(id: UUID()) { matcherQ.handle($0) }

        #expect(dispatcher.handleEvent(makeKeyEvent(keyCode: UInt16(kVK_Tab))) == nil)
        #expect(dispatcher.handleEvent(makeKeyEvent(keyCode: UInt16(kVK_Tab))) == nil)
        #expect(dispatcher.handleEvent(makeKeyEvent(keyCode: 17)) == nil)

        #expect(tCount == 1)
        #expect(qCount == 0)
    }

    @MainActor
    @Test func dispatcher_sharedTabPrefix_canMatchSiblingSequenceAfterReset() {
        let dispatcher = ShortcutSequenceEventDispatcher()
        let matcherT = ShortcutSequenceMatcher()
        let matcherQ = ShortcutSequenceMatcher()

        let sequenceT = ShortcutSequence(steps: [
            Shortcut(keyCode: UInt16(kVK_Tab), modifiers: []),
            Shortcut(keyCode: UInt16(kVK_Tab), modifiers: []),
            Shortcut(keyCode: 17, modifiers: []),
        ])
        let sequenceQ = ShortcutSequence(steps: [
            Shortcut(keyCode: UInt16(kVK_Tab), modifiers: []),
            Shortcut(keyCode: UInt16(kVK_Tab), modifiers: []),
            Shortcut(keyCode: 12, modifiers: []),
        ])

        var tCount = 0
        var qCount = 0

        matcherT.configure(sequence: sequenceT) { tCount += 1 }
        matcherQ.configure(sequence: sequenceQ) { qCount += 1 }

        dispatcher.register(id: UUID()) { matcherT.handle($0) }
        dispatcher.register(id: UUID()) { matcherQ.handle($0) }

        #expect(dispatcher.handleEvent(makeKeyEvent(keyCode: UInt16(kVK_Tab))) == nil)
        #expect(dispatcher.handleEvent(makeKeyEvent(keyCode: UInt16(kVK_Tab))) == nil)
        #expect(dispatcher.handleEvent(makeKeyEvent(keyCode: 12)) == nil)

        #expect(tCount == 0)
        #expect(qCount == 1)
    }

    @MainActor
    @Test func dispatcher_doesNotMatchWhileRecorderIsActive() {
        let dispatcher = ShortcutSequenceEventDispatcher()
        let matcher = ShortcutSequenceMatcher()
        let token = NSObject()

        let sequence = ShortcutSequence(steps: [
            Shortcut(keyCode: UInt16(kVK_Tab), modifiers: []),
            Shortcut(keyCode: UInt16(kVK_Tab), modifiers: []),
            Shortcut(keyCode: 17, modifiers: []),
        ])

        var fireCount = 0
        matcher.configure(sequence: sequence) { fireCount += 1 }
        dispatcher.register(id: UUID()) { matcher.handle($0) }

        ShortcutRecordingState.beginTestRecording(for: token)
        defer { ShortcutRecordingState.endTestRecording(for: token) }

        #expect(dispatcher.handleEvent(makeKeyEvent(keyCode: UInt16(kVK_Tab))) != nil)
        #expect(dispatcher.handleEvent(makeKeyEvent(keyCode: UInt16(kVK_Tab))) != nil)
        #expect(dispatcher.handleEvent(makeKeyEvent(keyCode: 17)) != nil)
        #expect(fireCount == 0)
    }

    @MainActor
    @Test func recordingState_staysActiveUntilAllRecorderTypesStop() {
        let single = ShortcutRecorderField()
        let sequence = ShortcutSequenceRecorderField()

        single.startRecording()
        sequence.startRecording()
        #expect(ShortcutRecorderField.isAnyRecording)

        single.endRecording()
        #expect(ShortcutRecorderField.isAnyRecording)

        sequence.endRecording()
        #expect(!ShortcutRecorderField.isAnyRecording)
    }

    @MainActor
    @Test func startingSequenceRecorderForceEndsActiveSingleRecorder() {
        let single = ShortcutRecorderField()
        let sequence = ShortcutSequenceRecorderField()

        single.startRecording()
        #expect(single.isRecording)

        sequence.startRecording()

        #expect(!single.isRecording)
        #expect(sequence.isRecording)
    }

    @MainActor
    @Test func sequenceRecorderField_resigningFirstResponderFinalizesRecordedSteps() {
        let field = ShortcutSequenceRecorderField()
        field.startRecording()
        _ = field.handleEvent(makeKeyEvent(keyCode: UInt16(kVK_Tab)))
        _ = field.handleEvent(makeKeyEvent(keyCode: 17))

        field.finalizeRecording()

        let expected = ShortcutSequence(steps: [
            Shortcut(keyCode: UInt16(kVK_Tab), modifiers: []),
            Shortcut(keyCode: 17, modifiers: []),
        ])
        #expect(field.shortcutSequence == expected)
        #expect(!field.isRecording)
    }

    @MainActor
    @Test func recordingState_clearsWhenRecorderLeavesWindow() {
        let field = ShortcutRecorderField()
        field.startRecording()
        #expect(ShortcutRecorderField.isAnyRecording)

        field.viewWillMove(toWindow: nil)
        #expect(!ShortcutRecorderField.isAnyRecording)
    }

    @MainActor
    @Test func sequenceRecorderField_secondRecorderTakesOwnership() {
        let first = ShortcutSequenceRecorderField()
        let second = ShortcutSequenceRecorderField()

        first.startRecording()
        #expect(first.isRecording)

        second.startRecording()

        #expect(!first.isRecording)
        #expect(second.isRecording)
    }

    @MainActor
    @Test func sequenceRecorderField_inactiveRecorderDoesNotCaptureTabSequence() {
        let first = ShortcutSequenceRecorderField()
        let second = ShortcutSequenceRecorderField()

        first.startRecording()
        second.startRecording()

        #expect(first.handleEvent(makeKeyEvent(keyCode: UInt16(kVK_Tab))) != nil)

        _ = second.handleEvent(makeKeyEvent(keyCode: UInt16(kVK_Tab)))
        _ = second.handleEvent(makeKeyEvent(keyCode: UInt16(kVK_Tab)))
        _ = second.handleEvent(makeKeyEvent(keyCode: 17))
        second.finalizeRecording()

        let expected = ShortcutSequence(steps: [
            Shortcut(keyCode: UInt16(kVK_Tab), modifiers: []),
            Shortcut(keyCode: UInt16(kVK_Tab), modifiers: []),
            Shortcut(keyCode: 17, modifiers: []),
        ])

        #expect(first.shortcutSequence == nil)
        #expect(second.shortcutSequence == expected)
    }

    @MainActor
    @Test func sequenceRecorderField_insertTabCommand_recordsTabSteps() {
        let field = ShortcutSequenceRecorderField()
        field.startRecording()

        #expect(field.handleCommand(#selector(NSResponder.insertTab(_:)),
                                    event: makeKeyEvent(keyCode: UInt16(kVK_Tab))))
        #expect(field.handleCommand(#selector(NSResponder.insertTab(_:)),
                                    event: makeKeyEvent(keyCode: UInt16(kVK_Tab))))
        #expect(field.handleCommand(#selector(NSResponder.insertText(_:)),
                                    event: makeKeyEvent(keyCode: 17)) == false)

        _ = field.handleEvent(makeKeyEvent(keyCode: 17))
        field.finalizeRecording()

        let expected = ShortcutSequence(steps: [
            Shortcut(keyCode: UInt16(kVK_Tab), modifiers: []),
            Shortcut(keyCode: UInt16(kVK_Tab), modifiers: []),
            Shortcut(keyCode: 17, modifiers: []),
        ])

        #expect(field.shortcutSequence == expected)
    }
}
