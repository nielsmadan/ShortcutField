import AppKit
import Carbon.HIToolbox
import ShortcutField
import Testing

// NSSearchField instantiation can crash when run in parallel in headless CI
@Suite(.serialized) struct ShortcutRecorderFieldTests {

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

}
