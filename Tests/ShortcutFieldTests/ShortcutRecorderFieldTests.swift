import AppKit
import Carbon.HIToolbox
@testable import ShortcutField
import Testing

private func makeKeyEvent(keyCode: UInt16, modifiers: NSEvent.ModifierFlags = []) -> NSEvent {
    let event = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: true)!
    event.flags = CGEventFlags(rawValue: UInt64(modifiers.rawValue))
    return NSEvent(cgEvent: event)!
}

/// Synthesize a scroll-wheel `NSEvent` with no phase information (mouse-wheel-style).
///
/// `CGEvent` doesn't expose `phase`, `magnification`, or `rotation`, so trackpad-burst
/// scroll suppression and gesture sequences (`.magnify` / `.rotate`) cannot be driven
/// through the matcher in tests. Those paths remain visually verified only.
private func makeScrollEvent(deltaY: Int32 = 0, deltaX: Int32 = 0) -> NSEvent {
    let cg = CGEvent(scrollWheelEvent2Source: nil,
                     units: .pixel,
                     wheelCount: 2,
                     wheel1: deltaY,
                     wheel2: deltaX,
                     wheel3: 0)!
    return NSEvent(cgEvent: cg)!
}

/// Above the recording threshold (`Shortcut.scrollRecordingThreshold = 5.0`).
private let scrollDeltaAboveThreshold: Int32 = 10

// NSSearchField instantiation can crash when run in parallel in headless CI.
// `@MainActor` at struct level also serializes against other @MainActor suites
// that touch CGEvent / NSSearchField / global ShortcutRecordingState.
@MainActor
@Suite(.serialized) struct ShortcutRecorderFieldTests {
    // MARK: - Default state

    @MainActor
    @Test func recorderField_defaultState() {
        let field = ShortcutRecorderField()
        #expect(field.shortcut == nil)
        #expect(!field.isRecording)
        #expect(field.frame.width >= 130)
    }

    @MainActor
    @Test func recorderField_setShortcut_updatesDisplay() {
        let field = ShortcutRecorderField()
        let shortcut = Shortcut(keyCode: UInt16(kVK_Tab), modifiers: .command)
        field.shortcut = shortcut
        #expect(field.shortcut == shortcut)
        #expect(field.stringValue == shortcut.displayString)
    }

    @MainActor
    @Test func recorderField_setMultiStepShortcut_displaysJoinedSteps() {
        let field = ShortcutRecorderField()
        let shortcut = Shortcut(steps: [
            .init(keyCode: UInt16(kVK_ANSI_K), modifiers: .command),
            .init(keyCode: UInt16(kVK_ANSI_C), modifiers: .command),
        ])
        field.shortcut = shortcut
        #expect(field.shortcut == shortcut)
        #expect(field.stringValue == shortcut.displayString)
    }

    @MainActor
    @Test func recorderField_clearShortcut_clearsDisplay() {
        let field = ShortcutRecorderField()
        field.shortcut = Shortcut(keyCode: UInt16(kVK_Tab), modifiers: .command)
        field.shortcut = nil
        #expect(field.shortcut == nil)
        #expect(field.stringValue == "")
    }

    @MainActor
    @Test func recorderField_onShortcutChange_notCalledOnProgrammaticSet() {
        let field = ShortcutRecorderField()
        var callCount = 0
        field.onShortcutChange = { _ in callCount += 1 }
        field.shortcut = Shortcut(keyCode: UInt16(kVK_ANSI_J), modifiers: .command)
        #expect(callCount == 0)
    }

    @MainActor
    @Test func recorderField_intrinsicContentSize_hasMinimumWidth() {
        let field = ShortcutRecorderField()
        #expect(field.intrinsicContentSize.width >= 130)
    }

    @Test func scrollRecordingThreshold_isHigherThanMatchingThreshold() {
        // Recording uses a stricter threshold than matching so a tiny stray
        // trackpad twitch can't accidentally finalize a Scroll step.
        // Matching uses `0.5` (see `Shortcut.scrollDirection(from:)`).
        #expect(Shortcut.scrollRecordingThreshold > 0.5)
    }

    // MARK: - Set/clear with mixed-kind multi-step shortcut

    @MainActor
    @Test func recorderField_setMixedKindShortcut_displaysCorrectly() {
        let field = ShortcutRecorderField()
        let shortcut = Shortcut(steps: [
            .init(kind: .key(keyCode: UInt16(kVK_ANSI_K)), modifiers: .command),
            .init(kind: .mouseButton(number: 1), modifiers: []),
            .init(kind: .pinchIn, modifiers: []),
            .init(kind: .smartMagnify, modifiers: []),
        ])
        field.shortcut = shortcut
        #expect(field.shortcut == shortcut)
        // Letter glyph from `UCKeyTranslate` is layout-dependent and lowercase
        // by default; assert structural prefix/suffix.
        #expect(field.stringValue.hasPrefix("⌘"))
        #expect(field.stringValue.hasSuffix(" Right Click Pinch In Smart Magnify"))
    }

    @MainActor
    @Test func recorderField_clearMixedKindShortcut_clearsDisplay() {
        let field = ShortcutRecorderField()
        field.shortcut = Shortcut(steps: [
            .init(kind: .key(keyCode: UInt16(kVK_ANSI_K)), modifiers: .command),
            .init(kind: .rotateClockwise, modifiers: .command),
        ])
        field.shortcut = nil
        #expect(field.shortcut == nil)
        #expect(field.stringValue == "")
    }

    // MARK: - Live recording — single step

    @MainActor
    @Test func recorderField_finalizeAfterSingleKey_setsShortcut() {
        let field = ShortcutRecorderField()
        field.startRecording()

        let event = NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: .command,
            timestamp: 0, windowNumber: 0, context: nil,
            characters: "k", charactersIgnoringModifiers: "k",
            isARepeat: false, keyCode: UInt16(kVK_ANSI_K)
        )!
        _ = field.handleEvent(event)

        var receivedShortcut: Shortcut?
        field.onShortcutChange = { receivedShortcut = $0 }

        field.finalizeRecording()

        #expect(!field.isRecording)
        #expect(field.shortcut?.steps.count == 1)
        #expect(receivedShortcut != nil)
        #expect(receivedShortcut == field.shortcut)
    }

    @MainActor
    @Test func recorderField_finalizeWithNoSteps_doesNotSetShortcut() {
        let field = ShortcutRecorderField()
        field.startRecording()

        var callbackCalled = false
        field.onShortcutChange = { _ in callbackCalled = true }

        field.finalizeRecording()

        #expect(!field.isRecording)
        #expect(field.shortcut == nil)
        #expect(!callbackCalled)
    }

    // MARK: - Tab / multi-step recording

    @MainActor
    @Test func recorderField_resigningFirstResponderFinalizesRecordedSteps() {
        let field = ShortcutRecorderField()
        field.startRecording()
        _ = field.handleEvent(makeKeyEvent(keyCode: UInt16(kVK_Tab)))
        _ = field.handleEvent(makeKeyEvent(keyCode: UInt16(kVK_ANSI_T)))

        field.finalizeRecording()

        let expected = Shortcut(steps: [
            .init(keyCode: UInt16(kVK_Tab), modifiers: []),
            .init(keyCode: UInt16(kVK_ANSI_T), modifiers: []),
        ])
        #expect(field.shortcut == expected)
        #expect(!field.isRecording)
    }

    @MainActor
    @Test func recorderField_insertTabCommand_recordsTabSteps() {
        let field = ShortcutRecorderField()
        field.startRecording()

        #expect(field.handleCommand(#selector(NSResponder.insertTab(_:)),
                                    event: makeKeyEvent(keyCode: UInt16(kVK_Tab))))
        #expect(field.handleCommand(#selector(NSResponder.insertTab(_:)),
                                    event: makeKeyEvent(keyCode: UInt16(kVK_Tab))))
        #expect(field.handleCommand(#selector(NSResponder.insertText(_:)),
                                    event: makeKeyEvent(keyCode: UInt16(kVK_ANSI_T))) == false)

        _ = field.handleEvent(makeKeyEvent(keyCode: UInt16(kVK_ANSI_T)))
        field.finalizeRecording()

        let expected = Shortcut(steps: [
            .init(keyCode: UInt16(kVK_Tab), modifiers: []),
            .init(keyCode: UInt16(kVK_Tab), modifiers: []),
            .init(keyCode: UInt16(kVK_ANSI_T), modifiers: []),
        ])
        #expect(field.shortcut == expected)
    }

    // MARK: - Right-click capture

    @MainActor
    @Test func recorderField_rightMouseDown_capturesAsMouseButton1Step() {
        let field = ShortcutRecorderField()
        field.startRecording()

        _ = field.handleEvent(makeKeyEvent(keyCode: UInt16(kVK_ANSI_A)))

        let cg = CGEvent(mouseEventSource: nil,
                         mouseType: .rightMouseDown,
                         mouseCursorPosition: .zero,
                         mouseButton: .right)!
        let rmDown = NSEvent(cgEvent: cg)!
        _ = field.handleEvent(rmDown)
        field.finalizeRecording()

        let expected = Shortcut(steps: [
            .init(keyCode: UInt16(kVK_ANSI_A), modifiers: []),
            .init(kind: .mouseButton(number: 1), modifiers: []),
        ])
        #expect(field.shortcut == expected, "recorder should produce [A, RightClick]")
    }

    // MARK: - Recording state ownership

    @MainActor
    @Test func recordingState_clearsWhenRecorderLeavesWindow() {
        let field = ShortcutRecorderField()
        field.startRecording()
        #expect(ShortcutRecorderField.isAnyRecording)

        field.viewWillMove(toWindow: nil)
        #expect(!ShortcutRecorderField.isAnyRecording)
    }

    @MainActor
    @Test func recorderField_secondRecorderTakesOwnership() {
        let first = ShortcutRecorderField()
        let second = ShortcutRecorderField()

        first.startRecording()
        #expect(first.isRecording)

        second.startRecording()

        #expect(!first.isRecording)
        #expect(second.isRecording)
    }
}

// MARK: - Dispatcher / matcher behavior

@MainActor
@Suite(.serialized) struct ShortcutDispatcherTests {
    @MainActor
    @Test func dispatcher_sharedTabPrefix_routesToMatchingShortcut() {
        let dispatcher = ShortcutEventDispatcher()
        let matcherT = ShortcutMatcher()
        let matcherQ = ShortcutMatcher()

        let shortcutT = Shortcut(steps: [
            .init(keyCode: UInt16(kVK_Tab), modifiers: []),
            .init(keyCode: UInt16(kVK_Tab), modifiers: []),
            .init(keyCode: UInt16(kVK_ANSI_T), modifiers: []),
        ])
        let shortcutQ = Shortcut(steps: [
            .init(keyCode: UInt16(kVK_Tab), modifiers: []),
            .init(keyCode: UInt16(kVK_Tab), modifiers: []),
            .init(keyCode: UInt16(kVK_ANSI_Q), modifiers: []),
        ])

        var tCount = 0
        var qCount = 0

        matcherT.configure(shortcut: shortcutT) { tCount += 1 }
        matcherQ.configure(shortcut: shortcutQ) { qCount += 1 }

        let idT = UUID(); let idQ = UUID()
        dispatcher.register(id: idT) { matcherT.handle($0) }
        dispatcher.register(id: idQ) { matcherQ.handle($0) }
        defer {
            dispatcher.unregister(id: idT)
            dispatcher.unregister(id: idQ)
        }

        #expect(dispatcher.handleEvent(makeKeyEvent(keyCode: UInt16(kVK_Tab))) == nil)
        #expect(dispatcher.handleEvent(makeKeyEvent(keyCode: UInt16(kVK_Tab))) == nil)
        #expect(dispatcher.handleEvent(makeKeyEvent(keyCode: UInt16(kVK_ANSI_T))) == nil)

        #expect(tCount == 1)
        #expect(qCount == 0)
    }

    @MainActor
    @Test func dispatcher_sharedTabPrefix_canMatchSiblingAfterReset() {
        let dispatcher = ShortcutEventDispatcher()
        let matcherT = ShortcutMatcher()
        let matcherQ = ShortcutMatcher()

        let shortcutT = Shortcut(steps: [
            .init(keyCode: UInt16(kVK_Tab), modifiers: []),
            .init(keyCode: UInt16(kVK_Tab), modifiers: []),
            .init(keyCode: UInt16(kVK_ANSI_T), modifiers: []),
        ])
        let shortcutQ = Shortcut(steps: [
            .init(keyCode: UInt16(kVK_Tab), modifiers: []),
            .init(keyCode: UInt16(kVK_Tab), modifiers: []),
            .init(keyCode: UInt16(kVK_ANSI_Q), modifiers: []),
        ])

        var tCount = 0
        var qCount = 0

        matcherT.configure(shortcut: shortcutT) { tCount += 1 }
        matcherQ.configure(shortcut: shortcutQ) { qCount += 1 }

        let idT = UUID(); let idQ = UUID()
        dispatcher.register(id: idT) { matcherT.handle($0) }
        dispatcher.register(id: idQ) { matcherQ.handle($0) }
        defer {
            dispatcher.unregister(id: idT)
            dispatcher.unregister(id: idQ)
        }

        _ = dispatcher.handleEvent(makeKeyEvent(keyCode: UInt16(kVK_Tab)))
        _ = dispatcher.handleEvent(makeKeyEvent(keyCode: UInt16(kVK_Tab)))
        _ = dispatcher.handleEvent(makeKeyEvent(keyCode: UInt16(kVK_ANSI_Q)))
        #expect(qCount == 1)
        #expect(tCount == 0)

        // T variant after Q matched — must not be blocked by stale state.
        _ = dispatcher.handleEvent(makeKeyEvent(keyCode: UInt16(kVK_Tab)))
        _ = dispatcher.handleEvent(makeKeyEvent(keyCode: UInt16(kVK_Tab)))
        _ = dispatcher.handleEvent(makeKeyEvent(keyCode: UInt16(kVK_ANSI_T)))
        #expect(tCount == 1)
        #expect(qCount == 1)
    }

    @MainActor
    @Test func dispatcher_doesNotMatchWhileRecorderIsActive() {
        let dispatcher = ShortcutEventDispatcher()
        let matcher = ShortcutMatcher()
        let token = NSObject()

        let shortcut = Shortcut(steps: [
            .init(keyCode: UInt16(kVK_Tab), modifiers: []),
            .init(keyCode: UInt16(kVK_Tab), modifiers: []),
            .init(keyCode: UInt16(kVK_ANSI_T), modifiers: []),
        ])

        var fireCount = 0
        matcher.configure(shortcut: shortcut) { fireCount += 1 }
        let listenerID = UUID()
        dispatcher.register(id: listenerID) { matcher.handle($0) }
        defer { dispatcher.unregister(id: listenerID) }

        ShortcutRecordingState.beginTestRecording(for: token)
        defer { ShortcutRecordingState.endTestRecording(for: token) }

        #expect(dispatcher.handleEvent(makeKeyEvent(keyCode: UInt16(kVK_Tab))) != nil)
        #expect(dispatcher.handleEvent(makeKeyEvent(keyCode: UInt16(kVK_Tab))) != nil)
        #expect(dispatcher.handleEvent(makeKeyEvent(keyCode: UInt16(kVK_ANSI_T))) != nil)
        #expect(fireCount == 0)
    }

    @MainActor
    @Test func dispatcher_singleScroll_firesPerNotch_forMouseWheel() {
        // Mouse-wheel events have empty phase; each notch is a discrete user action.
        let dispatcher = ShortcutEventDispatcher()
        let listenerID = UUID()
        let matcher = ShortcutMatcher()
        let shortcut = Shortcut(kind: .scroll(direction: .up), modifiers: [])
        var fireCount = 0
        matcher.configure(shortcut: shortcut) { fireCount += 1 }
        dispatcher.register(id: listenerID) { matcher.handle($0) }
        defer { dispatcher.unregister(id: listenerID) }

        _ = dispatcher.handleEvent(makeScrollEvent(deltaY: scrollDeltaAboveThreshold))
        _ = dispatcher.handleEvent(makeScrollEvent(deltaY: scrollDeltaAboveThreshold))

        #expect(fireCount == 2, "expected each mouse-wheel notch to fire the matcher")
    }

    @MainActor
    @Test func dispatcher_keyThenScroll_fires() {
        let dispatcher = ShortcutEventDispatcher()
        let listenerID = UUID()
        let matcher = ShortcutMatcher()
        let shortcut = Shortcut(steps: [
            .init(keyCode: UInt16(kVK_ANSI_A), modifiers: []),
            .init(kind: .scroll(direction: .up), modifiers: []),
        ])
        var fireCount = 0
        matcher.configure(shortcut: shortcut) { fireCount += 1 }
        dispatcher.register(id: listenerID) { matcher.handle($0) }
        defer { dispatcher.unregister(id: listenerID) }

        _ = dispatcher.handleEvent(makeKeyEvent(keyCode: UInt16(kVK_ANSI_A)))
        _ = dispatcher.handleEvent(makeScrollEvent(deltaY: scrollDeltaAboveThreshold))

        #expect(fireCount == 1, "expected sequence [A, Scroll Up] to fire once")
    }

    @MainActor
    @Test func dispatcher_scrollThenKey_survivesScrollBurst() {
        let dispatcher = ShortcutEventDispatcher()
        let listenerID = UUID()
        let matcher = ShortcutMatcher()
        let shortcut = Shortcut(steps: [
            .init(kind: .scroll(direction: .up), modifiers: []),
            .init(keyCode: UInt16(kVK_ANSI_A), modifiers: []),
        ])
        var fireCount = 0
        matcher.configure(shortcut: shortcut) { fireCount += 1 }
        dispatcher.register(id: listenerID) { matcher.handle($0) }
        defer { dispatcher.unregister(id: listenerID) }

        _ = dispatcher.handleEvent(makeScrollEvent(deltaY: scrollDeltaAboveThreshold))
        _ = dispatcher.handleEvent(makeScrollEvent(deltaY: scrollDeltaAboveThreshold))
        _ = dispatcher.handleEvent(makeKeyEvent(keyCode: UInt16(kVK_ANSI_A)))

        #expect(fireCount == 1, "expected [Scroll Up, A] to survive an extra scroll event")
    }

    @MainActor
    @Test func dispatcher_scrollThenKey_wrongDirectionDoesNotAdvance() {
        let dispatcher = ShortcutEventDispatcher()
        let listenerID = UUID()
        let matcher = ShortcutMatcher()
        let shortcut = Shortcut(steps: [
            .init(kind: .scroll(direction: .up), modifiers: []),
            .init(keyCode: UInt16(kVK_ANSI_A), modifiers: []),
        ])
        var fireCount = 0
        matcher.configure(shortcut: shortcut) { fireCount += 1 }
        dispatcher.register(id: listenerID) { matcher.handle($0) }
        defer { dispatcher.unregister(id: listenerID) }

        _ = dispatcher.handleEvent(makeScrollEvent(deltaY: -scrollDeltaAboveThreshold))
        _ = dispatcher.handleEvent(makeKeyEvent(keyCode: UInt16(kVK_ANSI_A)))

        #expect(fireCount == 0, "wrong-direction scroll must not advance the matcher")
    }

    @MainActor
    @Test func dispatcher_keyThenRightClick_fires() {
        let dispatcher = ShortcutEventDispatcher()
        let listenerID = UUID()
        let matcher = ShortcutMatcher()
        let shortcut = Shortcut(steps: [
            .init(keyCode: UInt16(kVK_ANSI_A), modifiers: []),
            .init(kind: .mouseButton(number: 1), modifiers: []),
        ])
        var fireCount = 0
        matcher.configure(shortcut: shortcut) { fireCount += 1 }
        dispatcher.register(id: listenerID) { matcher.handle($0) }
        defer { dispatcher.unregister(id: listenerID) }

        _ = dispatcher.handleEvent(makeKeyEvent(keyCode: UInt16(kVK_ANSI_A)))

        let cg = CGEvent(mouseEventSource: nil,
                         mouseType: .rightMouseDown,
                         mouseCursorPosition: .zero,
                         mouseButton: .right)!
        let rmDown = NSEvent(cgEvent: cg)!
        _ = dispatcher.handleEvent(rmDown)

        #expect(fireCount == 1, "expected sequence [A, RightClick] to fire once")
    }

    @MainActor
    @Test func dispatcher_handlerSnapshot_updatesOnRegisterAndUnregister() {
        let dispatcher = ShortcutEventDispatcher()
        let listenerID = UUID()

        var fireCount = 0
        let matcher = ShortcutMatcher()
        let shortcut = Shortcut(keyCode: UInt16(kVK_ANSI_A), modifiers: [])
        matcher.configure(shortcut: shortcut) { fireCount += 1 }

        _ = dispatcher.handleEvent(makeKeyEvent(keyCode: UInt16(kVK_ANSI_A)))
        #expect(fireCount == 0)

        dispatcher.register(id: listenerID) { matcher.handle($0) }
        _ = dispatcher.handleEvent(makeKeyEvent(keyCode: UInt16(kVK_ANSI_A)))
        #expect(fireCount == 1)

        dispatcher.unregister(id: listenerID)
        _ = dispatcher.handleEvent(makeKeyEvent(keyCode: UInt16(kVK_ANSI_A)))
        #expect(fireCount == 1)
    }
}

// MARK: - Throttle helpers (used by ContinuousShortcut / OnContinuousShortcutModifier)

@MainActor
struct ShortcutThrottleTests {
    @Test func cooldownSeconds_atQuarter_isOneSecond() {
        #expect(ThrottleState.cooldownSeconds(for: 0.25) == 1.0)
    }

    @Test func cooldownSeconds_atHalf() {
        #expect(abs(ThrottleState.cooldownSeconds(for: 0.5) - 0.667) < 0.001)
    }

    @Test func cooldownSeconds_atThreeQuarters() {
        #expect(abs(ThrottleState.cooldownSeconds(for: 0.75) - 0.333) < 0.001)
    }

    @Test func cooldownSeconds_atOne_isZero() {
        #expect(ThrottleState.cooldownSeconds(for: 1.0) == 0.0)
    }

    @Test func cooldownSeconds_nearZero_isLarge() {
        #expect(ThrottleState.cooldownSeconds(for: 0.01) > 1.3)
    }

    @Test func discreteIndex_mapsCorrectly() {
        #expect(SensitivityMode.discreteIndex(for: 0.0) == 0)
        #expect(SensitivityMode.discreteIndex(for: 0.25) == 1)
        #expect(SensitivityMode.discreteIndex(for: 0.5) == 2)
        #expect(SensitivityMode.discreteIndex(for: 0.75) == 3)
        #expect(SensitivityMode.discreteIndex(for: 1.0) == 4)
    }

    @Test func discreteIndex_roundsToNearest() {
        #expect(SensitivityMode.discreteIndex(for: 0.1) == 0)
        #expect(SensitivityMode.discreteIndex(for: 0.3) == 1)
        #expect(SensitivityMode.discreteIndex(for: 0.6) == 2)
        #expect(SensitivityMode.discreteIndex(for: 0.8) == 3)
    }

    @Test func evaluate_maxSensitivity_alwaysFires() {
        let state = ThrottleState()
        state.sensitivity = 1.0
        let t0 = ContinuousClock.now
        let d1 = ThrottleState.evaluate(state: state, now: t0)
        #expect(d1.shouldFire == true)
        #expect(d1.rearmAfter == nil)

        let d2 = ThrottleState.evaluate(state: state, now: t0)
        #expect(d2.shouldFire == true)
    }

    @Test func evaluate_fireOnce_suppressesAfterFirstFire() {
        let state = ThrottleState()
        state.sensitivity = 0.0
        let t0 = ContinuousClock.now
        let d1 = ThrottleState.evaluate(state: state, now: t0)
        #expect(d1.shouldFire == true)
        #expect(d1.rearmAfter == .milliseconds(350))

        let t1 = t0.advanced(by: .milliseconds(100))
        let d2 = ThrottleState.evaluate(state: state, now: t1)
        #expect(d2.shouldFire == false)
        #expect(d2.rearmAfter == .milliseconds(350))
    }

    @Test func evaluate_fireOnce_refiresAfterReset() {
        let state = ThrottleState()
        state.sensitivity = 0.0
        _ = ThrottleState.evaluate(state: state, now: ContinuousClock.now)
        state.reset()
        let d = ThrottleState.evaluate(state: state, now: ContinuousClock.now)
        #expect(d.shouldFire == true)
    }

    @Test func evaluate_cooldown_blocksWithinInterval() {
        let state = ThrottleState()
        state.sensitivity = 0.5
        let t0 = ContinuousClock.now
        let d1 = ThrottleState.evaluate(state: state, now: t0)
        #expect(d1.shouldFire == true)

        let t1 = t0.advanced(by: .milliseconds(500))
        let d2 = ThrottleState.evaluate(state: state, now: t1)
        #expect(d2.shouldFire == false)
    }

    @Test func evaluate_cooldown_firesAfterInterval() {
        let state = ThrottleState()
        state.sensitivity = 0.5
        let t0 = ContinuousClock.now
        _ = ThrottleState.evaluate(state: state, now: t0)
        let t1 = t0.advanced(by: .milliseconds(800))
        let d = ThrottleState.evaluate(state: state, now: t1)
        #expect(d.shouldFire == true)
    }

    @Test func evaluate_cooldown_firesFirstEventUnconditionally() {
        let state = ThrottleState()
        state.sensitivity = 0.5
        let d = ThrottleState.evaluate(state: state, now: ContinuousClock.now)
        #expect(d.shouldFire == true)
        #expect(d.rearmAfter == nil)
    }
}
