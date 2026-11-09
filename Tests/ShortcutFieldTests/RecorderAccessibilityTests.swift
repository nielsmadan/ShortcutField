import AppKit
import Carbon.HIToolbox
@testable import ShortcutField
import Testing

/// What VoiceOver gets from the recorder fields: a name, the shortcut as text, and
/// announcements when recording starts and ends.
@MainActor
@Suite(.serialized)
struct RecorderAccessibilityTests {
    private let rotate = ContinuousShortcut(kind: .rotateClockwise, modifiers: .command)

    /// The element VoiceOver reads for `field`: AppKit ignores the view and exposes its cell.
    private func element(_ field: BaseShortcutRecorderField) throws -> NSCell {
        try #require(NSAccessibility.unignoredDescendant(of: field) as? NSCell)
    }

    @Test func fields_areLabelledShortcut() throws {
        #expect(try element(ShortcutRecorderField()).accessibilityLabel() == "Shortcut")
        #expect(try element(ContinuousShortcutRecorderField()).accessibilityLabel() == "Shortcut")
    }

    @Test func hostLabel_replacesTheDefault() throws {
        let field = ShortcutRecorderField()
        (field as NSView).setAccessibilityLabel("Zoom")
        field.shortcut = DiscreteShortcut(keyCode: UInt16(kVK_ANSI_K), modifiers: .command)

        #expect(try element(field).accessibilityLabel() == "Zoom")
        #expect((field as NSView).accessibilityLabel() == "Zoom")
    }

    @Test func value_isTheShortcutAsTextInEitherStyle() throws {
        let field = ContinuousShortcutRecorderField()
        field.shortcut = rotate
        #expect(try element(field).accessibilityValue() as? String == rotate.displayString)

        field.labelStyle = .compact

        #expect(try element(field).accessibilityValue() as? String == rotate.displayString)
    }

    @Test func value_isEmptyWithoutAShortcut() throws {
        #expect(try element(ShortcutRecorderField()).accessibilityValue() as? String == "")
    }

    @Test func recording_announcesItsStartAndEnd() {
        let field = ContinuousShortcutRecorderField()
        var announcements: [String] = []
        field.announcer = { _, message in announcements.append(message) }

        field.startRecording()
        field.commit(kind: .pinchIn, modifiers: [])

        #expect(announcements == ["Recording shortcut", "Recording ended"])
    }
}
