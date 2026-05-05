import AppKit
import Carbon.HIToolbox
@testable import ShortcutField
import Testing

// NSSearchField instantiation can crash when run in parallel in headless CI
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
    @Test func recorderField_setGesture_updatesDisplay() {
        let field = ShortcutRecorderField()
        field.shortcut = Shortcut(kind: .pinchIn, modifiers: .command)
        #expect(field.stringValue == "⌘Pinch In")
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
        field.onShortcutChange = { _ in
            callCount += 1
        }

        field.shortcut = Shortcut(keyCode: 38, modifiers: .command)
        #expect(callCount == 0)
    }

    @MainActor
    @Test func recorderField_intrinsicContentSize_hasMinimumWidth() {
        let field = ShortcutRecorderField()
        #expect(field.intrinsicContentSize.width >= 130)
    }

    @Test func scrollRecordingThreshold_isHigherThanMatchingThreshold() {
        // Recording uses a stricter threshold than matching so a tiny stray
        // trackpad twitch can't accidentally finalize a Scroll shortcut.
        // Matching uses `0.5` (see `Shortcut.scrollDirection(from:)`).
        #expect(Shortcut.scrollRecordingThreshold > 0.5)
    }

    @MainActor
    @Test func recorderField_defaultPlaceholder() {
        let field = ShortcutRecorderField()
        #expect(field.defaultPlaceholder == "Record Shortcut")
    }

    // MARK: - Sensitivity persistence

    @MainActor
    @Test func setShortcut_continuousKind_persistsSensitivityAcrossDiscreteRoundtrip() {
        let field = ShortcutRecorderField()
        // Set a continuous gesture with non-zero sensitivity.
        field.shortcut = Shortcut(kind: .pinchIn, modifiers: [], sensitivity: 0.5)
        #expect(field.shortcut?.sensitivity == 0.5)

        // Pick a discrete kind via the menu — sensitivity is forced to 0 by init.
        let menu = ShortcutRecorderField.makeShortcutMenu(target: field)
        guard let smartItem = menu.items.first(where: { $0.title == "Smart Magnify" }) else {
            Issue.record("expected Smart Magnify menu item")
            return
        }
        field.menuPicked(smartItem)
        #expect(field.shortcut?.kind == .smartMagnify)
        #expect(field.shortcut?.sensitivity == 0.0)

        // Pick another continuous kind — sensitivity should restore from the last
        // continuous-kind value (0.5), not 0.
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
}

@MainActor
struct ShortcutRecorderFieldMenuTests {
    @Test func shortcutMenu_listsAllNonKeyboardKinds() {
        let menu = ShortcutRecorderField.makeShortcutMenu(target: nil)
        let titles = collectMenuTitles(menu)
        // 2 pinch + 2 rotate + 1 smart magnify + 2 mouse (right + middle, no bare left)
        // + 4 scroll = 11. Bare Left Click is intentionally omitted because the live
        // recorder reserves it for UI interaction.
        #expect(titles.count == 11)
    }

    @Test func shortcutMenu_includesPinchInOut() {
        let menu = ShortcutRecorderField.makeShortcutMenu(target: nil)
        let titles = collectMenuTitles(menu)
        #expect(titles.contains("Pinch In"))
        #expect(titles.contains("Pinch Out"))
    }

    @Test func shortcutMenu_includesRotate() {
        let menu = ShortcutRecorderField.makeShortcutMenu(target: nil)
        let titles = collectMenuTitles(menu)
        #expect(titles.contains("Rotate CW"))
        #expect(titles.contains("Rotate CCW"))
    }

    @Test func shortcutMenu_includesSmartMagnify() {
        let menu = ShortcutRecorderField.makeShortcutMenu(target: nil)
        let titles = collectMenuTitles(menu)
        #expect(titles.contains("Smart Magnify"))
    }

    @Test func shortcutMenu_includesMouseButtons() {
        let menu = ShortcutRecorderField.makeShortcutMenu(target: nil)
        let titles = collectMenuTitles(menu)
        // Bare Left Click is intentionally not offered by the menu — see the
        // comment in `ShortcutRecorderField+Menu.swift`.
        #expect(!titles.contains("Left Click"))
        #expect(titles.contains("Right Click"))
        #expect(titles.contains("Middle Click"))
    }

    @Test func shortcutMenu_includesScrollDirections() {
        let menu = ShortcutRecorderField.makeShortcutMenu(target: nil)
        let titles = collectMenuTitles(menu)
        #expect(titles.contains("Scroll Up"))
        #expect(titles.contains("Scroll Down"))
        #expect(titles.contains("Scroll Left"))
        #expect(titles.contains("Scroll Right"))
    }

    @Test func menuPicked_setsShortcutAndFiresCallback() {
        let field = ShortcutRecorderField()
        var captured: Shortcut?
        field.onShortcutChange = { captured = $0 }
        let menu = ShortcutRecorderField.makeShortcutMenu(target: field)
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
        let field = ShortcutRecorderField()
        // Force the recorder into recording state without going through becomeFirstResponder
        // (which requires a window). startRecording is internal.
        field.startRecording()
        #expect(field.isRecording == true)

        let menu = ShortcutRecorderField.makeShortcutMenu(target: field)
        guard let pinchSubmenu = menu.items.first(where: { $0.title == "Pinch" })?.submenu,
              let pinchInItem = pinchSubmenu.items.first(where: { $0.title == "Pinch In" })
        else {
            Issue.record("expected Pinch > Pinch In menu structure")
            return
        }

        field.menuPicked(pinchInItem)
        #expect(field.isRecording == false)
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

// MARK: - Throttle helpers (lifted from old MouseInputTests)

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
