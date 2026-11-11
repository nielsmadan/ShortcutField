import AppKit
import Carbon.HIToolbox
@testable import ShortcutField
import Testing

/// Above ``DiscreteShortcut/scrollRecordingThreshold``.
private let scrollDeltaAboveThreshold: Int32 = 10

/// NSSearchField instantiation can crash when run in parallel in headless CI.
/// `@MainActor` at struct level also serializes against other @MainActor suites
/// that touch CGEvent / NSSearchField / global ShortcutRecordingState.
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
    @Test func recorderField_defaultPlaceholders() {
        let field = ShortcutRecorderField()
        #expect(field.defaultPlaceholder == "Record Shortcut")
        #expect(field.recordingPlaceholder == "Record shortcut\u{2026}")
        #expect(field.placeholderString == "Record Shortcut")
    }

    @MainActor
    @Test func recorderField_recordingSwapsPlaceholderAndRestoresIt() {
        let field = ShortcutRecorderField()
        field.startRecording()
        #expect(field.placeholderString == "Record shortcut\u{2026}")
        field.endRecording()
        #expect(field.placeholderString == "Record Shortcut")
    }

    @MainActor
    @Test func recorderField_setShortcut_updatesDisplay() {
        let field = ShortcutRecorderField()
        let shortcut = DiscreteShortcut(keyCode: UInt16(kVK_Tab), modifiers: .command)
        field.shortcut = shortcut
        #expect(field.shortcut == shortcut)
        #expect(field.stringValue == shortcut.displayString)
    }

    @MainActor
    @Test func recorderField_setMultiStepShortcut_displaysJoinedSteps() {
        let field = ShortcutRecorderField()
        let shortcut = DiscreteShortcut(steps: [
            .init(keyCode: UInt16(kVK_ANSI_K), modifiers: .command),
            .init(keyCode: UInt16(kVK_ANSI_C), modifiers: .command),
        ])
        field.shortcut = shortcut
        #expect(field.shortcut == shortcut)
        #expect(field.stringValue == shortcut.displayString)
    }

    @MainActor
    @Test func recorderField_compactStyle_gestureShowsAttachmentAndTooltip() {
        let field = ShortcutRecorderField()
        field.labelStyle = .compact
        field.shortcut = DiscreteShortcut(kind: .rotateClockwise, modifiers: [])
        var hasAttachment = false
        let attributed = field.attributedStringValue
        attributed.enumerateAttribute(.attachment, in: NSRange(
            location: 0,
            length: attributed.length
        )) { value, _, stop in
            if value != nil {
                hasAttachment = true; stop.pointee = true
            }
        }
        #expect(hasAttachment)
        #expect(field.toolTip == "Rotate CW")
    }

    @MainActor
    @Test func recorderField_compactStyle_attributedValueIsCenteredAndTruncating() {
        let field = ShortcutRecorderField()
        field.labelStyle = .compact
        field.shortcut = DiscreteShortcut(kind: .rotateClockwise, modifiers: [])
        let attributed = field.attributedStringValue
        #expect(attributed.length > 0)
        let paragraph = attributed.attribute(
            .paragraphStyle, at: 0, effectiveRange: nil
        ) as? NSParagraphStyle
        // aligned(_:) must stamp the field's center alignment (attributed strings ignore
        // the control's `alignment`) and restore tail truncation the plain path gets free.
        #expect(paragraph?.alignment == field.alignment)
        #expect(paragraph?.alignment == .center)
        #expect(paragraph?.lineBreakMode == .byTruncatingTail)
    }

    @MainActor
    @Test func recorderField_compactStyle_colorChangeRepaintsAttributedValue() {
        let field = ShortcutRecorderField()
        field.labelStyle = .compact
        field.shortcut = DiscreteShortcut(kind: .mouseButton(number: 1), modifiers: [])
        field.fieldTextColor = .systemRed
        let color = field.attributedStringValue.attribute(
            .foregroundColor, at: 0, effectiveRange: nil
        ) as? NSColor
        #expect(color == .systemRed)
    }

    @MainActor
    @Test func recorderField_startRecording_clearsStaleTooltip() {
        let field = ShortcutRecorderField()
        field.labelStyle = .compact
        field.shortcut = DiscreteShortcut(kind: .rotateClockwise, modifiers: [])
        #expect(field.toolTip == "Rotate CW")
        field.startRecording()
        #expect(field.toolTip == nil)
    }

    @MainActor
    @Test func recorderField_compactStyle_switchingBackToTextRestoresString() {
        let field = ShortcutRecorderField()
        let shortcut = DiscreteShortcut(kind: .rotateClockwise, modifiers: .command)
        field.shortcut = shortcut
        field.labelStyle = .compact
        field.labelStyle = .text
        #expect(field.stringValue == shortcut.displayString)
        #expect(field.toolTip == nil)
    }

    @MainActor
    @Test func recorderField_clearShortcut_clearsDisplay() {
        let field = ShortcutRecorderField()
        field.shortcut = DiscreteShortcut(keyCode: UInt16(kVK_Tab), modifiers: .command)
        field.shortcut = nil
        #expect(field.shortcut == nil)
        #expect(field.stringValue == "")
    }

    @MainActor
    @Test func recorderField_onShortcutChange_notCalledOnProgrammaticSet() {
        let field = ShortcutRecorderField()
        var callCount = 0
        field.onShortcutChange = { _ in callCount += 1 }
        field.shortcut = DiscreteShortcut(keyCode: UInt16(kVK_ANSI_J), modifiers: .command)
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
        // Matching uses `0.5` (see `DiscreteShortcut.scrollDirection(from:)`).
        #expect(DiscreteShortcut.scrollRecordingThreshold > 0.5)
    }

    // MARK: - Set/clear with mixed-kind multi-step shortcut

    @MainActor
    @Test func recorderField_setMixedKindShortcut_displaysCorrectly() {
        let field = ShortcutRecorderField()
        let shortcut = DiscreteShortcut(steps: [
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
        field.shortcut = DiscreteShortcut(steps: [
            .init(kind: .key(keyCode: UInt16(kVK_ANSI_K)), modifiers: .command),
            .init(kind: .rotateClockwise, modifiers: .command),
        ])
        field.shortcut = nil
        #expect(field.shortcut == nil)
        #expect(field.stringValue == "")
    }

    // MARK: - Live recording — single step

    @MainActor
    @Test func recorderField_finalizeAfterSingleKey_setsShortcut() throws {
        let field = ShortcutRecorderField()
        field.startRecording()

        let event = try #require(NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: .command,
            timestamp: 0, windowNumber: 0, context: nil,
            characters: "k", charactersIgnoringModifiers: "k",
            isARepeat: false, keyCode: UInt16(kVK_ANSI_K)
        ))
        _ = field.handleEvent(event)

        var receivedShortcut: DiscreteShortcut?
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

    @MainActor
    @Test func recorderField_capturingStepArmsAndDisarmsIdleTimeout() {
        let field = ShortcutRecorderField()
        field.startRecording()
        #expect(field.timeoutTask == nil)

        _ = field.handleEvent(keyDown(kVK_ANSI_K, .command))
        #expect(field.timeoutTask != nil)

        field.endRecording()
        #expect(field.timeoutTask == nil)
    }

    // MARK: - Tab / multi-step recording

    @MainActor
    @Test func recorderField_resigningFirstResponderFinalizesRecordedSteps() {
        let field = ShortcutRecorderField()
        let (window, other) = hostWindow(field)
        defer { field.removeFromSuperview() }
        #expect(window.makeFirstResponder(field))
        #expect(field.isRecording)
        _ = field.handleEvent(keyDown(kVK_ANSI_T, in: window))
        _ = field.handleEvent(keyDown(kVK_Tab, in: window))

        #expect(window.makeFirstResponder(other))

        let expected = DiscreteShortcut(steps: [
            .init(keyCode: UInt16(kVK_ANSI_T), modifiers: []),
            .init(keyCode: UInt16(kVK_Tab), modifiers: []),
        ])
        #expect(field.shortcut == expected)
        #expect(!field.isRecording)
    }

    @MainActor
    @Test func recorderField_insertTabCommand_recordsTabSteps() {
        let field = ShortcutRecorderField()
        field.startRecording()

        #expect(field.handleCommand(#selector(NSResponder.insertTab(_:)),
                                    event: keyDown(kVK_Tab)))
        #expect(field.handleCommand(#selector(NSResponder.insertTab(_:)),
                                    event: keyDown(kVK_Tab)))
        #expect(field.handleCommand(#selector(NSResponder.insertText(_:)),
                                    event: keyDown(kVK_ANSI_T)) == false)

        _ = field.handleEvent(keyDown(kVK_ANSI_T))
        field.finalizeRecording()

        let expected = DiscreteShortcut(steps: [
            .init(keyCode: UInt16(kVK_Tab), modifiers: []),
            .init(keyCode: UInt16(kVK_Tab), modifiers: []),
            .init(keyCode: UInt16(kVK_ANSI_T), modifiers: []),
        ])
        #expect(field.shortcut == expected)
    }

    // MARK: - Right-click capture

    @MainActor
    @Test func recorderField_rightMouseDown_capturesAsMouseButton1Step() throws {
        let field = ShortcutRecorderField()
        field.startRecording()

        _ = field.handleEvent(keyDown(kVK_ANSI_A))

        let cg = try #require(CGEvent(mouseEventSource: nil,
                                      mouseType: .rightMouseDown,
                                      mouseCursorPosition: .zero,
                                      mouseButton: .right))
        cg.flags = []
        let rmDown = try #require(NSEvent(cgEvent: cg))
        _ = field.handleEvent(rmDown)
        field.finalizeRecording()

        let expected = DiscreteShortcut(steps: [
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
        #expect(ShortcutRecording.isActive)

        field.viewWillMove(toWindow: nil)
        #expect(!ShortcutRecording.isActive)
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

    // MARK: - Escape

    @MainActor
    @Test func recorderField_bareEscape_cancelsAndKeepsTheShortcut() {
        let previous = DiscreteShortcut(keyCode: UInt16(kVK_ANSI_K), modifiers: .command)
        let field = ShortcutRecorderField()
        field.shortcut = previous
        field.startRecording()

        _ = field.handleEvent(keyDown(kVK_ANSI_C, .command))
        #expect(field.handleEvent(keyDown(kVK_Escape)) == nil)

        #expect(!field.isRecording)
        #expect(field.shortcut == previous)
    }

    @MainActor
    @Test(arguments: [NSEvent.ModifierFlags.shift, .control, .option, .command])
    func recorderField_modifiedEscape_isRecorded(modifiers: NSEvent.ModifierFlags) {
        let field = ShortcutRecorderField()
        field.startRecording()
        defer { field.endRecording() }

        #expect(field.handleEvent(keyDown(kVK_Escape, modifiers)) == nil)
        #expect(field.isRecording)
        field.finalizeRecording()

        #expect(field.shortcut == DiscreteShortcut(keyCode: UInt16(kVK_Escape), modifiers: modifiers))
    }

    // MARK: - Tab

    @MainActor
    @Test(arguments: [NSEvent.ModifierFlags(), .shift])
    func recorderField_tabAsTheFirstStep_isRecorded(modifiers: NSEvent.ModifierFlags) {
        let field = ShortcutRecorderField()
        field.shortcut = DiscreteShortcut(keyCode: UInt16(kVK_ANSI_K), modifiers: .command)
        field.startRecording()
        defer { field.endRecording() }

        #expect(field.handleEvent(keyDown(kVK_Tab, modifiers)) == nil)
        #expect(field.isRecording)
        field.finalizeRecording()

        #expect(field.shortcut == DiscreteShortcut(keyCode: UInt16(kVK_Tab), modifiers: modifiers))
    }

    @MainActor
    @Test func recorderField_tabAfterAStep_isRecorded() {
        let field = ShortcutRecorderField()
        field.startRecording()
        defer { field.endRecording() }

        #expect(field.handleEvent(keyDown(kVK_ANSI_K, .command)) == nil)
        #expect(field.handleEvent(keyDown(kVK_Tab)) == nil)
        field.finalizeRecording()

        #expect(field.shortcut == DiscreteShortcut(steps: [
            .init(keyCode: UInt16(kVK_ANSI_K), modifiers: .command),
            .init(keyCode: UInt16(kVK_Tab), modifiers: []),
        ]))
    }

    @MainActor
    @Test func recorderField_modifiedTabBeforeAnyStep_isRecorded() {
        let field = ShortcutRecorderField()
        field.startRecording()
        defer { field.endRecording() }

        #expect(field.handleEvent(keyDown(kVK_Tab, .control)) == nil)
        field.finalizeRecording()

        #expect(field.shortcut == DiscreteShortcut(keyCode: UInt16(kVK_Tab), modifiers: .control))
    }

    @MainActor
    @Test(arguments: [false, true])
    func recorderField_tabThroughTheApp_isRecordedAsTheFirstStep(backward: Bool) {
        let field = ShortcutRecorderField()
        let form = TabForm(field)
        defer { form.close() }
        field.shortcut = DiscreteShortcut(keyCode: UInt16(kVK_ANSI_K), modifiers: .command)
        #expect(form.window.makeFirstResponder(field))
        #expect(field.isRecording)

        NSApplication.shared.sendEvent(tabKey(backward: backward, in: form.window))

        #expect(field.isRecording)
        #expect(field.currentEditor() != nil)
        field.finalizeRecording()
        #expect(field.shortcut == DiscreteShortcut(keyCode: UInt16(kVK_Tab), modifiers: backward ? .shift : []))
    }

    // MARK: - Held keys, disabling and the clear button

    @MainActor
    @Test func recorderField_heldKeyRepeats_recordOneStep() {
        let field = ShortcutRecorderField()
        field.startRecording()
        defer { field.endRecording() }

        #expect(field.handleEvent(keyDown(kVK_ANSI_K, .command)) == nil)
        #expect(field.handleEvent(keyDown(kVK_ANSI_K, .command, isRepeat: true)) == nil)
        #expect(field.handleEvent(keyDown(kVK_ANSI_K, .command, isRepeat: true)) == nil)
        field.finalizeRecording()

        #expect(field.shortcut == DiscreteShortcut(keyCode: UInt16(kVK_ANSI_K), modifiers: .command))
    }

    @MainActor
    @Test func recorderField_heldKeyRepeat_keepsRecordingPastTheIdleTimeout() async {
        let field = ShortcutRecorderField()
        field.recordingTimeout = 2
        field.startRecording()
        defer { field.endRecording() }
        _ = field.handleEvent(keyDown(kVK_ANSI_W, .command))
        let armedByThePress = field.timeoutTask

        _ = field.handleEvent(keyDown(kVK_ANSI_W, .command, isRepeat: true))
        // Waiting with a registered recording would pause every other suite's dispatcher.
        ShortcutRecordingState.end(for: field)
        await armedByThePress?.value

        #expect(field.isRecording)
    }

    @MainActor
    @Test func recorderField_disablingTheField_endsRecordingWithoutCommitting() {
        let baseline = ShortcutRecording.isActive
        let field = ShortcutRecorderField()
        let (window, _) = hostWindow(field)
        defer { field.removeFromSuperview() }
        #expect(window.makeFirstResponder(field))
        _ = field.handleEvent(keyDown(kVK_ANSI_K, .command, in: window))

        field.isEnabled = false

        #expect(!field.isRecording)
        #expect(field.shortcut == nil)
        #expect(ShortcutRecording.isActive == baseline)
    }

    @MainActor
    @Test func recorderField_clearButtonClickWhileRecording_clearsTheShortcut() throws {
        let field = ShortcutRecorderField()
        let (window, _) = hostWindow(field)
        defer { field.removeFromSuperview() }
        field.shortcut = DiscreteShortcut(keyCode: UInt16(kVK_ANSI_K), modifiers: .command)
        var changes: [DiscreteShortcut?] = []
        field.onShortcutChange = { changes.append($0) }
        field.startRecording()

        #expect(try field.handleEvent(clearButtonClick(field, in: window)) == nil)
        #expect(!field.isRecording)
        #expect(field.shortcut == nil)
        #expect(changes == [nil])
    }

    @MainActor
    @Test func recorderField_modifiedClickOnClearButton_recordsAStep() throws {
        let field = ShortcutRecorderField()
        let (window, _) = hostWindow(field)
        defer { field.removeFromSuperview() }
        field.shortcut = DiscreteShortcut(keyCode: UInt16(kVK_ANSI_K), modifiers: .command)
        field.startRecording()
        defer { field.endRecording() }

        #expect(try field.handleEvent(clearButtonClick(field, in: window, .control)) == nil)
        #expect(field.isRecording)
        field.finalizeRecording()
        #expect(field.shortcut == DiscreteShortcut(kind: .mouseButton(number: 0), modifiers: .control))
    }

    @MainActor
    @Test func recorderField_clickWhereTheClearButtonWouldBe_withNoShortcut_keepsRecording() throws {
        let field = ShortcutRecorderField()
        let (window, _) = hostWindow(field)
        defer { field.removeFromSuperview() }
        var changes: [DiscreteShortcut?] = []
        field.onShortcutChange = { changes.append($0) }
        field.startRecording()
        defer { field.endRecording() }

        #expect(try field.handleEvent(clearButtonClick(field, in: window)) == nil)
        #expect(field.isRecording)
        #expect(changes.isEmpty)
    }

    // MARK: - The field's window

    @MainActor
    @Test func recorderField_windowResigningKey_commitsCapturedStepsAndEndsSession() {
        let baseline = ShortcutRecording.isActive
        let field = ShortcutRecorderField()
        let (window, _) = hostWindow(field)
        defer { field.removeFromSuperview() }
        #expect(window.makeFirstResponder(field))
        _ = field.handleEvent(keyDown(kVK_ANSI_K, .command, in: window))

        NotificationCenter.default.post(name: NSWindow.didResignKeyNotification, object: window)

        #expect(!field.isRecording)
        #expect(field.shortcut == DiscreteShortcut(keyCode: UInt16(kVK_ANSI_K), modifiers: .command))
        #expect(ShortcutRecording.isActive == baseline)
        #expect(window.firstResponder === window)
    }

    @MainActor
    @Test func recorderField_windowResigningKeyAfterRecordingEnded_keepsFocus() {
        let field = ShortcutRecorderField()
        let (window, other) = hostWindow(field)
        defer { field.removeFromSuperview() }
        field.startRecording()
        field.endRecording()
        #expect(window.makeFirstResponder(other))
        let focused = window.firstResponder

        NotificationCenter.default.post(name: NSWindow.didResignKeyNotification, object: window)

        #expect(window.firstResponder === focused)
    }

    @MainActor
    @Test func recorderField_windowClosing_endsSessionWithoutCommitting() {
        let baseline = ShortcutRecording.isActive
        let field = ShortcutRecorderField()
        let (window, _) = hostWindow(field)
        defer { field.removeFromSuperview() }
        field.startRecording()
        _ = field.handleEvent(keyDown(kVK_ANSI_K, .command, in: window))

        NotificationCenter.default.post(name: NSWindow.willCloseNotification, object: window)

        #expect(!field.isRecording)
        #expect(field.shortcut == nil)
        #expect(ShortcutRecording.isActive == baseline)
    }

    @MainActor
    @Test func recorderField_eventsForAnotherWindow_passThroughUnrecorded() {
        let field = ShortcutRecorderField()
        let (window, _) = hostWindow(field)
        let (otherWindow, _) = hostWindow(ShortcutRecorderField())
        defer { field.removeFromSuperview() }
        field.startRecording()
        defer { field.endRecording() }

        #expect(field.handleMonitoredEvent(keyDown(kVK_ANSI_X, in: otherWindow)) != nil)
        #expect(field.handleMonitoredEvent(keyDown(kVK_ANSI_K, .command, in: window)) == nil)
        field.finalizeRecording()
        #expect(field.shortcut == DiscreteShortcut(keyCode: UInt16(kVK_ANSI_K), modifiers: .command))
    }

    @MainActor
    @Test func recorderField_clickAtTheFieldsPositionInAnotherWindow_isNotInsideTheField() {
        let field = ShortcutRecorderField()
        let (window, _) = hostWindow(field)
        let (otherWindow, _) = hostWindow(ShortcutRecorderField())
        defer { field.removeFromSuperview() }
        let center = field.convert(NSPoint(x: field.bounds.midX, y: field.bounds.midY), to: nil)

        #expect(field.isInsideField(mouseEvent(.leftMouseDown, at: center, in: window)))
        #expect(!field.isInsideField(mouseEvent(.leftMouseDown, at: center, in: otherWindow)))
    }

    @MainActor
    @Test func recorderField_bareLeftDownOutsideTheField_commitsAndEndsRecording() {
        let field = ShortcutRecorderField()
        let (window, _) = hostWindow(field)
        defer { field.removeFromSuperview() }
        field.startRecording()
        _ = field.handleEvent(keyDown(kVK_ANSI_K, .command, in: window))

        let outside = mouseEvent(.leftMouseDown, at: NSPoint(x: 5, y: 5), in: window)
        #expect(field.handleEvent(outside) != nil)
        #expect(!field.isRecording)
        #expect(field.shortcut == DiscreteShortcut(keyCode: UInt16(kVK_ANSI_K), modifiers: .command))
    }

    @MainActor
    @Test func recorderField_releaseOfTheClickThatFocusedIt_keepsRecording() {
        let field = ShortcutRecorderField()
        let (window, _) = hostWindow(field)
        defer { field.removeFromSuperview() }
        field.startRecording()
        defer { field.endRecording() }
        let center = field.convert(NSPoint(x: field.bounds.midX, y: field.bounds.midY), to: nil)

        #expect(field.handleEvent(mouseEvent(.leftMouseUp, at: center, in: window)) != nil)
        #expect(field.isRecording)
    }

    @MainActor
    @Test func recorderField_bareClickInsideTheFieldDuringRecording_commitsOnRelease() {
        let field = ShortcutRecorderField()
        let (window, _) = hostWindow(field)
        defer { field.removeFromSuperview() }
        field.startRecording()
        _ = field.handleEvent(keyDown(kVK_ANSI_K, .command, in: window))
        let center = field.convert(NSPoint(x: field.bounds.midX, y: field.bounds.midY), to: nil)

        #expect(field.handleEvent(mouseEvent(.leftMouseDown, at: center, in: window)) == nil)
        #expect(field.isRecording)
        #expect(field.handleEvent(mouseEvent(.leftMouseUp, at: center, in: window)) == nil)
        #expect(!field.isRecording)
        #expect(field.shortcut == DiscreteShortcut(keyCode: UInt16(kVK_ANSI_K), modifiers: .command))
    }

    // MARK: - Trackpad bursts

    private static func step(_ kind: DiscreteShortcut.Kind) -> DiscreteShortcut.Step {
        DiscreteShortcut.Step(kind: kind, modifiers: [])
    }

    /// Records `events` into a fresh field, finalizes, and returns what it committed.
    private func recorded(_ events: [NSEvent]) -> DiscreteShortcut? {
        let field = ShortcutRecorderField()
        field.startRecording()
        defer { field.endRecording() }
        for event in events {
            _ = field.handleEvent(event)
        }
        field.finalizeRecording()
        return field.shortcut
    }

    @MainActor
    @Test func recorderField_trackpadScrollBurst_recordsOneStep() {
        let events = [
            scrollEvent(deltaY: -10, phase: .began),
            scrollEvent(deltaY: -10, phase: .changed),
            scrollEvent(deltaY: -10, momentum: .began),
        ]

        #expect(recorded(events) == DiscreteShortcut(steps: [Self.step(.scroll(direction: .down))]))
    }

    @MainActor
    @Test func recorderField_wheelNotches_recordAStepEach() {
        #expect(recorded([scrollEvent(deltaY: 10), scrollEvent(deltaY: 10)]) == DiscreteShortcut(steps: [
            Self.step(.scroll(direction: .up)), Self.step(.scroll(direction: .up)),
        ]))
    }

    @MainActor
    @Test func recorderField_trackpadScrollBurstStartingWithMayBegin_recordsAFreshStep() {
        let events = [
            scrollEvent(deltaY: -10, phase: .began),
            scrollEvent(deltaY: -10, phase: .changed),
            scrollEvent(phase: .mayBegin),
            scrollEvent(deltaY: -10, phase: .changed),
        ]

        #expect(recorded(events) == DiscreteShortcut(steps: [
            Self.step(.scroll(direction: .down)), Self.step(.scroll(direction: .down)),
        ]))
    }

    @MainActor
    @Test func recorderField_wheelNotchAfterAnEndedTrackpadScrollBurst_recordsAStep() {
        let events = [
            scrollEvent(deltaY: -10, phase: .began),
            scrollEvent(deltaY: -10, phase: .changed),
            scrollEvent(phase: .ended),
            scrollEvent(deltaY: 10),
        ]

        #expect(recorded(events) == DiscreteShortcut(steps: [
            Self.step(.scroll(direction: .down)), Self.step(.scroll(direction: .up)),
        ]))
    }

    @MainActor
    @Test func recorderField_pinchBurstStartingWithMayBegin_recordsAFreshStep() {
        let events = [
            gestureEvent(.magnify, 0.06),
            gestureEvent(.magnify, 0, phase: .mayBegin),
            gestureEvent(.magnify, 0.06),
        ]

        #expect(recorded(events) == DiscreteShortcut(steps: [Self.step(.pinchOut), Self.step(.pinchOut)]))
    }

    @MainActor
    @Test func recorderField_eventOfAnotherType_endsThePinchBurst() {
        let events = [
            gestureEvent(.magnify, 0.06),
            keyDown(kVK_ANSI_K, .command),
            gestureEvent(.magnify, 0.06),
        ]

        #expect(recorded(events) == DiscreteShortcut(steps: [
            Self.step(.pinchOut),
            .init(keyCode: UInt16(kVK_ANSI_K), modifiers: .command),
            Self.step(.pinchOut),
        ]))
    }
}

// MARK: - Dispatcher / matcher behavior

@MainActor
@Suite(.serialized) struct ShortcutDispatcherTests {
    @MainActor
    @Test func dispatcher_sharedTabPrefix_routesToMatchingShortcut() {
        let dispatcher = ShortcutEventDispatcher()
        let matcherT = SequenceMatcher()
        let matcherQ = SequenceMatcher()

        let shortcutT = DiscreteShortcut(steps: [
            .init(keyCode: UInt16(kVK_Tab), modifiers: []),
            .init(keyCode: UInt16(kVK_Tab), modifiers: []),
            .init(keyCode: UInt16(kVK_ANSI_T), modifiers: []),
        ])
        let shortcutQ = DiscreteShortcut(steps: [
            .init(keyCode: UInt16(kVK_Tab), modifiers: []),
            .init(keyCode: UInt16(kVK_Tab), modifiers: []),
            .init(keyCode: UInt16(kVK_ANSI_Q), modifiers: []),
        ])

        var tCount = 0
        var qCount = 0

        matcherT.configure(shortcut: shortcutT)
        matcherQ.configure(shortcut: shortcutQ)

        let idT = UUID(); let idQ = UUID()
        dispatcher.register(id: idT) {
            let r = matcherT.handle($0); if r == .fired {
                tCount += 1
            }; return r
        }
        dispatcher.register(id: idQ) {
            let r = matcherQ.handle($0); if r == .fired {
                qCount += 1
            }; return r
        }
        defer {
            dispatcher.unregister(id: idT)
            dispatcher.unregister(id: idQ)
        }

        #expect(dispatcher.handleEvent(keyDown(kVK_Tab)) == nil)
        #expect(dispatcher.handleEvent(keyDown(kVK_Tab)) == nil)
        #expect(dispatcher.handleEvent(keyDown(kVK_ANSI_T)) == nil)

        #expect(tCount == 1)
        #expect(qCount == 0)
    }

    @MainActor
    @Test func dispatcher_sharedTabPrefix_canMatchSiblingAfterReset() {
        let dispatcher = ShortcutEventDispatcher()
        let matcherT = SequenceMatcher()
        let matcherQ = SequenceMatcher()

        let shortcutT = DiscreteShortcut(steps: [
            .init(keyCode: UInt16(kVK_Tab), modifiers: []),
            .init(keyCode: UInt16(kVK_Tab), modifiers: []),
            .init(keyCode: UInt16(kVK_ANSI_T), modifiers: []),
        ])
        let shortcutQ = DiscreteShortcut(steps: [
            .init(keyCode: UInt16(kVK_Tab), modifiers: []),
            .init(keyCode: UInt16(kVK_Tab), modifiers: []),
            .init(keyCode: UInt16(kVK_ANSI_Q), modifiers: []),
        ])

        var tCount = 0
        var qCount = 0

        matcherT.configure(shortcut: shortcutT)
        matcherQ.configure(shortcut: shortcutQ)

        let idT = UUID(); let idQ = UUID()
        dispatcher.register(id: idT) {
            let r = matcherT.handle($0); if r == .fired {
                tCount += 1
            }; return r
        }
        dispatcher.register(id: idQ) {
            let r = matcherQ.handle($0); if r == .fired {
                qCount += 1
            }; return r
        }
        defer {
            dispatcher.unregister(id: idT)
            dispatcher.unregister(id: idQ)
        }

        _ = dispatcher.handleEvent(keyDown(kVK_Tab))
        _ = dispatcher.handleEvent(keyDown(kVK_Tab))
        _ = dispatcher.handleEvent(keyDown(kVK_ANSI_Q))
        #expect(qCount == 1)
        #expect(tCount == 0)

        // T variant after Q matched — must not be blocked by stale state.
        _ = dispatcher.handleEvent(keyDown(kVK_Tab))
        _ = dispatcher.handleEvent(keyDown(kVK_Tab))
        _ = dispatcher.handleEvent(keyDown(kVK_ANSI_T))
        #expect(tCount == 1)
        #expect(qCount == 1)
    }

    @MainActor
    @Test func dispatcher_doesNotMatchWhileRecorderIsActive() {
        let dispatcher = ShortcutEventDispatcher()
        let matcher = SequenceMatcher()
        let token = NSObject()

        let shortcut = DiscreteShortcut(steps: [
            .init(keyCode: UInt16(kVK_Tab), modifiers: []),
            .init(keyCode: UInt16(kVK_Tab), modifiers: []),
            .init(keyCode: UInt16(kVK_ANSI_T), modifiers: []),
        ])

        var fireCount = 0
        matcher.configure(shortcut: shortcut)
        let listenerID = UUID()
        dispatcher.register(id: listenerID) {
            let r = matcher.handle($0); if r == .fired {
                fireCount += 1
            }; return r
        }
        defer { dispatcher.unregister(id: listenerID) }

        ShortcutRecordingState.beginTestRecording(for: token)
        defer { ShortcutRecordingState.endTestRecording(for: token) }

        #expect(dispatcher.handleEvent(keyDown(kVK_Tab)) != nil)
        #expect(dispatcher.handleEvent(keyDown(kVK_Tab)) != nil)
        #expect(dispatcher.handleEvent(keyDown(kVK_ANSI_T)) != nil)
        #expect(fireCount == 0)
    }

    @MainActor
    @Test func dispatcher_singleScroll_firesPerNotch_forMouseWheel() {
        // Mouse-wheel events have empty phase; each notch is a discrete user action.
        let dispatcher = ShortcutEventDispatcher()
        let listenerID = UUID()
        let matcher = SequenceMatcher()
        let shortcut = DiscreteShortcut(kind: .scroll(direction: .up), modifiers: [])
        var fireCount = 0
        matcher.configure(shortcut: shortcut)
        dispatcher.register(id: listenerID) {
            let r = matcher.handle($0); if r == .fired {
                fireCount += 1
            }; return r
        }
        defer { dispatcher.unregister(id: listenerID) }

        _ = dispatcher.handleEvent(scrollEvent(deltaY: scrollDeltaAboveThreshold))
        _ = dispatcher.handleEvent(scrollEvent(deltaY: scrollDeltaAboveThreshold))

        #expect(fireCount == 2, "expected each mouse-wheel notch to fire the matcher")
    }

    @MainActor
    @Test func dispatcher_keyThenScroll_fires() {
        let dispatcher = ShortcutEventDispatcher()
        let listenerID = UUID()
        let matcher = SequenceMatcher()
        let shortcut = DiscreteShortcut(steps: [
            .init(keyCode: UInt16(kVK_ANSI_A), modifiers: []),
            .init(kind: .scroll(direction: .up), modifiers: []),
        ])
        var fireCount = 0
        matcher.configure(shortcut: shortcut)
        dispatcher.register(id: listenerID) {
            let r = matcher.handle($0); if r == .fired {
                fireCount += 1
            }; return r
        }
        defer { dispatcher.unregister(id: listenerID) }

        _ = dispatcher.handleEvent(keyDown(kVK_ANSI_A))
        _ = dispatcher.handleEvent(scrollEvent(deltaY: scrollDeltaAboveThreshold))

        #expect(fireCount == 1, "expected sequence [A, Scroll Up] to fire once")
    }

    @MainActor
    @Test func dispatcher_scrollThenKey_survivesScrollBurst() {
        let dispatcher = ShortcutEventDispatcher()
        let listenerID = UUID()
        let matcher = SequenceMatcher()
        let shortcut = DiscreteShortcut(steps: [
            .init(kind: .scroll(direction: .up), modifiers: []),
            .init(keyCode: UInt16(kVK_ANSI_A), modifiers: []),
        ])
        var fireCount = 0
        matcher.configure(shortcut: shortcut)
        dispatcher.register(id: listenerID) {
            let r = matcher.handle($0); if r == .fired {
                fireCount += 1
            }; return r
        }
        defer { dispatcher.unregister(id: listenerID) }

        _ = dispatcher.handleEvent(scrollEvent(deltaY: scrollDeltaAboveThreshold))
        _ = dispatcher.handleEvent(scrollEvent(deltaY: scrollDeltaAboveThreshold))
        _ = dispatcher.handleEvent(keyDown(kVK_ANSI_A))

        #expect(fireCount == 1, "expected [Scroll Up, A] to survive an extra scroll event")
    }

    @MainActor
    @Test func dispatcher_scrollThenKey_wrongDirectionDoesNotAdvance() {
        let dispatcher = ShortcutEventDispatcher()
        let listenerID = UUID()
        let matcher = SequenceMatcher()
        let shortcut = DiscreteShortcut(steps: [
            .init(kind: .scroll(direction: .up), modifiers: []),
            .init(keyCode: UInt16(kVK_ANSI_A), modifiers: []),
        ])
        var fireCount = 0
        matcher.configure(shortcut: shortcut)
        dispatcher.register(id: listenerID) {
            let r = matcher.handle($0); if r == .fired {
                fireCount += 1
            }; return r
        }
        defer { dispatcher.unregister(id: listenerID) }

        _ = dispatcher.handleEvent(scrollEvent(deltaY: -scrollDeltaAboveThreshold))
        _ = dispatcher.handleEvent(keyDown(kVK_ANSI_A))

        #expect(fireCount == 0, "wrong-direction scroll must not advance the matcher")
    }

    @MainActor
    @Test func dispatcher_keyThenRightClick_fires() throws {
        let dispatcher = ShortcutEventDispatcher()
        let listenerID = UUID()
        let matcher = SequenceMatcher()
        let shortcut = DiscreteShortcut(steps: [
            .init(keyCode: UInt16(kVK_ANSI_A), modifiers: []),
            .init(kind: .mouseButton(number: 1), modifiers: []),
        ])
        var fireCount = 0
        matcher.configure(shortcut: shortcut)
        dispatcher.register(id: listenerID) {
            let r = matcher.handle($0); if r == .fired {
                fireCount += 1
            }; return r
        }
        defer { dispatcher.unregister(id: listenerID) }

        _ = dispatcher.handleEvent(keyDown(kVK_ANSI_A))

        let cg = try #require(CGEvent(mouseEventSource: nil,
                                      mouseType: .rightMouseDown,
                                      mouseCursorPosition: .zero,
                                      mouseButton: .right))
        cg.flags = []
        let rmDown = try #require(NSEvent(cgEvent: cg))
        _ = dispatcher.handleEvent(rmDown)

        #expect(fireCount == 1, "expected sequence [A, RightClick] to fire once")
    }

    @MainActor
    @Test func dispatcher_handlerSnapshot_updatesOnRegisterAndUnregister() {
        let dispatcher = ShortcutEventDispatcher()
        let listenerID = UUID()

        var fireCount = 0
        let matcher = SequenceMatcher()
        let shortcut = DiscreteShortcut(keyCode: UInt16(kVK_ANSI_A), modifiers: [])
        matcher.configure(shortcut: shortcut)

        _ = dispatcher.handleEvent(keyDown(kVK_ANSI_A))
        #expect(fireCount == 0)

        dispatcher.register(id: listenerID) {
            let r = matcher.handle($0); if r == .fired {
                fireCount += 1
            }; return r
        }
        _ = dispatcher.handleEvent(keyDown(kVK_ANSI_A))
        #expect(fireCount == 1)

        dispatcher.unregister(id: listenerID)
        _ = dispatcher.handleEvent(keyDown(kVK_ANSI_A))
        #expect(fireCount == 1)
    }
}

// MARK: - Throttle helpers (used by ContinuousShortcut / .onShortcut)

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

    @Test func snap_discreteMode_movesToNearestTick() {
        #expect(SensitivityMode.discrete.snap(0.3) == 0.25)
        #expect(SensitivityMode.discrete.snap(0.6) == 0.5)
        #expect(SensitivityMode.discrete.snap(0.9) == 1.0)
        #expect(SensitivityMode.discrete.snap(0.25) == 0.25)
    }

    @Test func snap_continuousMode_clampsWithoutSnapping() {
        #expect(SensitivityMode.continuous.snap(0.3) == 0.3)
        #expect(SensitivityMode.continuous.snap(1.4) == 1.0)
        #expect(SensitivityMode.continuous.snap(-0.2) == 0.0)
    }

    @Test func snap_discreteMode_clampsOutOfRangeToEndTicks() {
        #expect(SensitivityMode.discrete.snap(1.4) == 1.0)
        #expect(SensitivityMode.discrete.snap(-0.2) == 0.0)
    }

    @Test func snap_nan_degradesToZero() {
        #expect(SensitivityMode.discrete.snap(.nan) == 0.0)
        #expect(SensitivityMode.continuous.snap(.nan) == 0.0)
    }

    @Test func continuousShortcut_init_clampsOutOfRangeSensitivity() {
        #expect(ContinuousShortcut(kind: .pinchIn, modifiers: [], sensitivity: 1.4).sensitivity == 1.0)
        #expect(ContinuousShortcut(kind: .pinchIn, modifiers: [], sensitivity: -0.2).sensitivity == 0.0)
    }

    @Test func ascii_outOfRangeSensitivity_throwsRatherThanClamping() {
        #expect(throws: (any Error).self) {
            _ = try Shortcut(ascii: "scroll-up @1.4")
        }
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
