import AppKit
import Carbon.HIToolbox
@testable import ShortcutField
import Testing

/// NSSearchField instantiation can crash when run in parallel in headless CI.
/// `@MainActor` at struct level also serializes against other @MainActor suites
/// that touch CGEvent / NSSearchField / global ShortcutRecordingState.
@MainActor
@Suite(.serialized) struct ContinuousShortcutRecorderFieldTests {
    @MainActor
    @Test func recorderField_defaultState() {
        let field = ContinuousShortcutRecorderField()
        #expect(field.shortcut == nil)
        #expect(!field.isRecording)
        #expect(field.frame.width >= 130)
    }

    @MainActor
    @Test func recorderField_defaultPlaceholders() {
        let field = ContinuousShortcutRecorderField()
        #expect(field.defaultPlaceholder == "Record Continuous")
        #expect(field.recordingPlaceholder == "Scroll / pinch / rotate\u{2026}")
        #expect(field.placeholderString == "Record Continuous")
    }

    @MainActor
    @Test func recorderField_recordingSwapsPlaceholderAndRestoresIt() {
        let field = ContinuousShortcutRecorderField()
        field.startRecording()
        #expect(field.placeholderString == "Scroll / pinch / rotate\u{2026}")
        field.endRecording()
        #expect(field.placeholderString == "Record Continuous")
    }

    @MainActor
    @Test func recorderField_setShortcut_updatesDisplay() {
        let field = ContinuousShortcutRecorderField()
        let cs = ContinuousShortcut(kind: .pinchIn, modifiers: .command, sensitivity: 0.5)
        field.shortcut = cs
        #expect(field.shortcut == cs)
        #expect(field.stringValue == cs.displayString)
    }

    @MainActor
    @Test func recorderField_clearShortcut_clearsDisplay() {
        let field = ContinuousShortcutRecorderField()
        field.shortcut = ContinuousShortcut(kind: .pinchIn, modifiers: .command)
        field.shortcut = nil
        #expect(field.shortcut == nil)
        #expect(field.stringValue == "")
    }

    @MainActor
    @Test func recorderField_onChange_notCalledOnProgrammaticSet() {
        let field = ContinuousShortcutRecorderField()
        var callCount = 0
        field.onShortcutChange = { _ in callCount += 1 }
        field.shortcut = ContinuousShortcut(kind: .pinchIn, modifiers: .command)
        #expect(callCount == 0)
    }

    @MainActor
    @Test func recorderField_compactStyle_showsAttachmentAndTooltip() {
        let field = ContinuousShortcutRecorderField()
        field.labelStyle = .compact
        field.shortcut = ContinuousShortcut(kind: .rotateClockwise, modifiers: [])
        var hasAttachment = false
        let attributed = field.attributedStringValue
        attributed.enumerateAttribute(
            .attachment, in: NSRange(location: 0, length: attributed.length)
        ) { value, _, stop in
            if value != nil {
                hasAttachment = true; stop.pointee = true
            }
        }
        #expect(hasAttachment)
        #expect(field.toolTip == "Rotate CW")
    }

    @MainActor
    @Test func recorderField_compactStyle_clearShortcutClearsTooltip() {
        let field = ContinuousShortcutRecorderField()
        field.labelStyle = .compact
        field.shortcut = ContinuousShortcut(kind: .rotateClockwise, modifiers: [])
        field.shortcut = nil
        #expect(field.toolTip == nil)
        #expect(field.stringValue == "")
    }

    @MainActor
    @Test func recorderField_commit_carriesCommittedSensitivityForward() {
        let field = ContinuousShortcutRecorderField()
        field.shortcut = ContinuousShortcut(kind: .pinchIn, modifiers: [], sensitivity: 0.8)
        field.commit(kind: .rotateClockwise, modifiers: .command)
        #expect(field.shortcut?.kind == .rotateClockwise)
        #expect(field.shortcut?.sensitivity == 0.8)
    }

    @MainActor
    @Test func recorderField_commit_usesLastSensitivityWhenNothingBound() {
        let field = ContinuousShortcutRecorderField()
        field.lastSensitivity = 0.6
        field.commit(kind: .rotateClockwise, modifiers: [])
        #expect(field.shortcut?.sensitivity == 0.6)
    }

    @MainActor
    @Test func recorderField_setShortcut_leavesPushedSensitivityIntact() {
        let field = ContinuousShortcutRecorderField()
        field.lastSensitivity = 0.6
        field.shortcut = ContinuousShortcut(kind: .pinchIn, modifiers: [], sensitivity: 0.25)
        #expect(field.lastSensitivity == 0.6)
    }

    @MainActor
    @Test func recorderField_compactStyle_cancelledRecordingRestoresTooltip() {
        let field = ContinuousShortcutRecorderField()
        field.labelStyle = .compact
        field.shortcut = ContinuousShortcut(kind: .rotateClockwise, modifiers: [])
        #expect(field.toolTip == "Rotate CW")

        field.startRecording()
        #expect(field.toolTip == nil)

        _ = field.handleEvent(keyDown(kVK_Escape))

        #expect(!field.isRecording)
        #expect(field.shortcut != nil)
        #expect(field.toolTip == "Rotate CW")
    }

    @MainActor
    @Test(arguments: [NSEvent.ModifierFlags(), .shift])
    func recorderField_tab_endsRecordingAndPassesTheTabOn(modifiers: NSEvent.ModifierFlags) {
        let baseline = ShortcutRecording.isActive
        let original = ContinuousShortcut(kind: .pinchIn, modifiers: .command, sensitivity: 0.5)
        let field = ContinuousShortcutRecorderField()
        field.shortcut = original
        var changes: [ContinuousShortcut?] = []
        field.onShortcutChange = { changes.append($0) }
        field.startRecording()

        #expect(field.handleEvent(keyDown(kVK_Tab, modifiers)) != nil)
        #expect(!field.isRecording)
        #expect(field.shortcut == original)
        #expect(changes.isEmpty)
        #expect(ShortcutRecording.isActive == baseline)
    }

    @MainActor
    @Test(arguments: [false, true])
    func recorderField_tabThroughTheApp_movesFocusToTheAdjacentField(backward: Bool) {
        let field = ContinuousShortcutRecorderField()
        let form = TabForm(field)
        defer { form.close() }
        // A set shortcut hides the chevron, which would otherwise be the next key view.
        field.shortcut = ContinuousShortcut(kind: .pinchIn, modifiers: [])
        #expect(form.window.makeFirstResponder(field))
        #expect(field.isRecording)

        NSApplication.shared.sendEvent(tabKey(backward: backward, in: form.window))

        #expect(!field.isRecording)
        #expect((backward ? form.previous : form.next).currentEditor() != nil)
    }

    @MainActor
    @Test func recorderField_clearButtonClickWhileRecording_clearsTheShortcut() throws {
        let field = ContinuousShortcutRecorderField()
        let (window, _) = hostWindow(field)
        defer { field.removeFromSuperview() }
        field.shortcut = ContinuousShortcut(kind: .pinchIn, modifiers: [])
        field.startRecording()

        #expect(try field.handleEvent(clearButtonClick(field, in: window)) == nil)
        #expect(!field.isRecording)
        #expect(field.shortcut == nil)
    }

    @MainActor
    @Test func recorderField_bareLeftDownOutsideTheField_endsRecordingAndPassesThrough() {
        let field = ContinuousShortcutRecorderField()
        let (window, _) = hostWindow(field)
        defer { field.removeFromSuperview() }
        field.startRecording()

        let outside = mouseEvent(.leftMouseDown, at: NSPoint(x: 5, y: 5), in: window)
        #expect(field.handleEvent(outside) != nil)
        #expect(!field.isRecording)
    }

    @MainActor
    @Test func recorderField_burstStartingWithMayBegin_dropsTheLeftoverPinch() {
        let field = ContinuousShortcutRecorderField()
        field.startRecording()
        defer { field.endRecording() }

        _ = field.handleEvent(gestureEvent(.magnify, 0.04))
        _ = field.handleEvent(gestureEvent(.magnify, 0, phase: .mayBegin))
        _ = field.handleEvent(gestureEvent(.magnify, 0.02))

        #expect(field.isRecording)
    }
}

// MARK: - Menu

@MainActor
@Suite(.serialized) struct ContinuousShortcutRecorderFieldMenuTests {
    @Test func menu_listsContinuousKindsOnly() {
        let menu = ContinuousShortcutRecorderField.makeContinuousShortcutMenu(target: nil)
        let titles = collectMenuTitles(menu)
        // 2 pinch + 2 rotate + 4 scroll = 8. No keys, mouse buttons, or smartMagnify.
        #expect(titles.count == 8)
    }

    @Test func menu_includesPinch() {
        let menu = ContinuousShortcutRecorderField.makeContinuousShortcutMenu(target: nil)
        let titles = collectMenuTitles(menu)
        #expect(titles.contains("Pinch In"))
        #expect(titles.contains("Pinch Out"))
    }

    @Test func menu_includesRotate() {
        let menu = ContinuousShortcutRecorderField.makeContinuousShortcutMenu(target: nil)
        let titles = collectMenuTitles(menu)
        #expect(titles.contains("Rotate CW"))
        #expect(titles.contains("Rotate CCW"))
    }

    @Test func menu_includesScrollDirections() {
        let menu = ContinuousShortcutRecorderField.makeContinuousShortcutMenu(target: nil)
        let titles = collectMenuTitles(menu)
        #expect(titles.contains("Scroll Up"))
        #expect(titles.contains("Scroll Down"))
        #expect(titles.contains("Scroll Left"))
        #expect(titles.contains("Scroll Right"))
    }

    @Test func menu_excludesDiscreteKinds() {
        let menu = ContinuousShortcutRecorderField.makeContinuousShortcutMenu(target: nil)
        let titles = collectMenuTitles(menu)
        #expect(!titles.contains("Smart Magnify"))
        #expect(!titles.contains("Left Click"))
        #expect(!titles.contains("Right Click"))
        #expect(!titles.contains("Middle Click"))
    }

    @Test func menuPicked_setsShortcutAndFiresCallback() {
        let field = ContinuousShortcutRecorderField()
        var captured: ContinuousShortcut?
        field.onShortcutChange = { captured = $0 }
        let menu = ContinuousShortcutRecorderField.makeContinuousShortcutMenu(target: field)
        guard let pinchSubmenu = menu.items.first(where: { $0.title == "Pinch" })?.submenu,
              let pinchInItem = pinchSubmenu.items.first(where: { $0.title == "Pinch In" })
        else {
            Issue.record("expected Pinch > Pinch In menu structure")
            return
        }
        field.menuPicked(pinchInItem)
        #expect(field.shortcut?.kind == .pinchIn)
        #expect(captured?.kind == .pinchIn)
    }

    @Test func menuPicked_endsRecordingState() {
        let field = ContinuousShortcutRecorderField()
        field.startRecording()
        #expect(field.isRecording == true)

        let menu = ContinuousShortcutRecorderField.makeContinuousShortcutMenu(target: field)
        guard let pinchSubmenu = menu.items.first(where: { $0.title == "Pinch" })?.submenu,
              let pinchInItem = pinchSubmenu.items.first(where: { $0.title == "Pinch In" })
        else {
            Issue.record("expected Pinch > Pinch In menu structure")
            return
        }

        field.menuPicked(pinchInItem)
        #expect(field.isRecording == false)
    }

    @Test func menuPicked_preservesSensitivityAcrossPicks() {
        let field = ContinuousShortcutRecorderField()
        field.shortcut = ContinuousShortcut(kind: .pinchIn, modifiers: [], sensitivity: 0.5)

        let menu = ContinuousShortcutRecorderField.makeContinuousShortcutMenu(target: field)
        guard let rotateSubmenu = menu.items.first(where: { $0.title == "Rotate" })?.submenu,
              let rotateCWItem = rotateSubmenu.items.first(where: { $0.title == "Rotate CW" })
        else {
            Issue.record("expected Rotate > Rotate CW menu structure")
            return
        }
        field.menuPicked(rotateCWItem)
        #expect(field.shortcut?.kind == .rotateClockwise)
        #expect(field.shortcut?.sensitivity == 0.5)
    }

    @Test func menu_textStyle_hasNoImages() {
        let menu = ContinuousShortcutRecorderField.makeContinuousShortcutMenu(target: nil, labelStyle: .text)
        #expect(collectMenuLeafItems(menu).allSatisfy { $0.image == nil })
    }

    @Test func menu_compactStyle_setsImages() {
        let menu = ContinuousShortcutRecorderField.makeContinuousShortcutMenu(target: nil, labelStyle: .compact)
        let leaves = collectMenuLeafItems(menu)
        #expect(!leaves.isEmpty)
        #expect(leaves.allSatisfy { $0.image != nil })
        #expect(leaves.contains { $0.title == "Rotate CW" })
    }

    private func collectMenuLeafItems(_ menu: NSMenu) -> [NSMenuItem] {
        var items: [NSMenuItem] = []
        for item in menu.items {
            if let submenu = item.submenu {
                items.append(contentsOf: collectMenuLeafItems(submenu))
            } else if !item.isSeparatorItem, !item.title.isEmpty {
                items.append(item)
            }
        }
        return items
    }

    private func collectMenuTitles(_ menu: NSMenu) -> [String] {
        var titles: [String] = []
        for item in menu.items {
            if let submenu = item.submenu {
                titles.append(contentsOf: collectMenuTitles(submenu))
            } else if !item.isSeparatorItem, !item.title.isEmpty {
                titles.append(item.title)
            }
        }
        return titles
    }
}
