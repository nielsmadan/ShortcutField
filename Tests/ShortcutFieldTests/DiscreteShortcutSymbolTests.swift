import AppKit
import Carbon.HIToolbox
@testable import ShortcutField
import Testing

@MainActor
@Suite struct DiscreteShortcutSymbolTests {
    // MARK: - symbolName

    @Test func symbolName_gestures() {
        #expect(DiscreteShortcut.Kind.rotateClockwise.symbolName == "arrow.clockwise")
        #expect(DiscreteShortcut.Kind.rotateCounterClockwise.symbolName == "arrow.counterclockwise")
        #expect(DiscreteShortcut.Kind.pinchIn.symbolName == "arrow.down.right.and.arrow.up.left")
        #expect(DiscreteShortcut.Kind.pinchOut.symbolName == "arrow.up.left.and.arrow.down.right")
        #expect(DiscreteShortcut.Kind.smartMagnify.symbolName == "plus.magnifyingglass")
    }

    @Test func symbolName_scrollDirections() {
        #expect(DiscreteShortcut.Kind.scroll(direction: .up).symbolName == "arrow.up")
        #expect(DiscreteShortcut.Kind.scroll(direction: .down).symbolName == "arrow.down")
        #expect(DiscreteShortcut.Kind.scroll(direction: .left).symbolName == "arrow.left")
        #expect(DiscreteShortcut.Kind.scroll(direction: .right).symbolName == "arrow.right")
    }

    @Test func symbolName_nilForKeysAndMouse() {
        #expect(DiscreteShortcut.Kind.key(keyCode: UInt16(kVK_ANSI_K)).symbolName == nil)
        #expect(DiscreteShortcut.Kind.mouseButton(number: 0).symbolName == nil)
        #expect(DiscreteShortcut.Kind.mouseButton(number: 1).symbolName == nil)
        #expect(DiscreteShortcut.Kind.mouseButton(number: 2).symbolName == nil)
    }

    @Test func symbolName_allSymbolsResolveAtRuntime() throws {
        let kinds: [DiscreteShortcut.Kind] = [
            .rotateClockwise, .rotateCounterClockwise, .pinchIn, .pinchOut, .smartMagnify,
            .scroll(direction: .up), .scroll(direction: .down),
            .scroll(direction: .left), .scroll(direction: .right),
        ]
        for kind in kinds {
            let name = try #require(kind.symbolName)
            #expect(
                NSImage(systemSymbolName: name, accessibilityDescription: nil) != nil,
                "SF Symbol \(name) should resolve on this OS"
            )
        }
    }

    // MARK: - compactLabel

    @Test func compactLabel_mouseButtons() {
        #expect(DiscreteShortcut.Kind.mouseButton(number: 0).compactLabel?.short == "LMB")
        #expect(DiscreteShortcut.Kind.mouseButton(number: 0).compactLabel?.label == "Left Click")
        #expect(DiscreteShortcut.Kind.mouseButton(number: 1).compactLabel?.short == "RMB")
        #expect(DiscreteShortcut.Kind.mouseButton(number: 1).compactLabel?.label == "Right Click")
        #expect(DiscreteShortcut.Kind.mouseButton(number: 2).compactLabel?.short == "MMB")
        #expect(DiscreteShortcut.Kind.mouseButton(number: 2).compactLabel?.label == "Middle Click")
        #expect(DiscreteShortcut.Kind.mouseButton(number: 3).compactLabel?.short == "Mouse4")
    }

    @Test func compactLabel_nilForNonMouse() {
        #expect(DiscreteShortcut.Kind.pinchIn.compactLabel == nil)
        #expect(DiscreteShortcut.Kind.key(keyCode: UInt16(kVK_ANSI_K)).compactLabel == nil)
    }

    // MARK: - displayElements

    @Test func displayElements_compactStyle_gestureBecomesSymbol() {
        let step = DiscreteShortcut.Step(kind: .rotateClockwise, modifiers: [])
        #expect(step.displayElements(style: .compact) == [.symbol(name: "arrow.clockwise", label: "Rotate CW")])
    }

    @Test func displayElements_compactStyle_mouseBecomesAbbreviation() {
        let step = DiscreteShortcut.Step(kind: .mouseButton(number: 0), modifiers: [])
        #expect(step.displayElements(style: .compact) == [.abbreviation(short: "LMB", label: "Left Click")])
    }

    @Test func displayElements_compactStyle_keyStaysText() {
        let step = DiscreteShortcut.Step(kind: .key(keyCode: UInt16(kVK_Tab)), modifiers: [])
        #expect(step.displayElements(style: .compact) == [.text("Tab")])
    }

    @Test func displayElements_textStyle_alwaysText() {
        let step = DiscreteShortcut.Step(kind: .rotateClockwise, modifiers: .command)
        #expect(step.displayElements(style: .text) == [.text("⌘Rotate CW")])
    }

    @Test func displayElements_compactStyle_modifierPrefixLeadsAsText() {
        let step = DiscreteShortcut.Step(kind: .pinchIn, modifiers: .command)
        #expect(step.displayElements(style: .compact) == [
            .text("⌘"),
            .symbol(name: "arrow.down.right.and.arrow.up.left", label: "Pinch In"),
        ])
    }

    @Test func displayElements_compactStyle_keyMergesModifier() {
        let step = DiscreteShortcut.Step(kind: .key(keyCode: UInt16(kVK_Tab)), modifiers: .command)
        #expect(step.displayElements(style: .compact) == [.text("⌘Tab")])
    }

    @Test func displayElements_multiStepJoinedWithSpace() {
        let shortcut = DiscreteShortcut(steps: [
            DiscreteShortcut.Step(kind: .rotateClockwise, modifiers: []),
            DiscreteShortcut.Step(kind: .mouseButton(number: 1), modifiers: []),
        ])
        #expect(shortcut.displayElements(style: .compact) == [
            .symbol(name: "arrow.clockwise", label: "Rotate CW"),
            .text(" "),
            .abbreviation(short: "RMB", label: "Right Click"),
        ])
    }

    @Test func displayElements_tooltipLabelMatchesText() {
        // The label carried by icon/abbreviation elements is exactly the text-style
        // meaning — this is the tooltip contract ShortcutLabel relies on.
        for kind in [DiscreteShortcut.Kind.pinchOut, .scroll(direction: .left), .mouseButton(number: 2)] {
            let element = kind.displayElement(style: .compact)
            let label: String = switch element {
            case let .symbol(_, l): l
            case let .abbreviation(_, l): l
            case let .text(t): t
            }
            #expect(label == kind.displayLabel)
        }
    }

    // MARK: - attributedDisplayString

    @Test func attributedDisplayString_compactStyle_hasAttachmentForSymbol() {
        let shortcut = DiscreteShortcut(steps: [.init(kind: .rotateClockwise, modifiers: [])])
        let attributed = shortcut.attributedDisplayString(
            style: .compact, font: .systemFont(ofSize: 13), color: nil
        )
        #expect(containsAttachment(attributed))
    }

    @Test func attributedDisplayString_textStyle_matchesDisplayString() {
        let shortcut = DiscreteShortcut(steps: [.init(kind: .rotateClockwise, modifiers: .command)])
        let attributed = shortcut.attributedDisplayString(
            style: .text, font: .systemFont(ofSize: 13), color: nil
        )
        #expect(!containsAttachment(attributed))
        #expect(attributed.string == shortcut.displayString)
    }

    @Test func attributedDisplayString_compactStyle_mouseRendersAbbreviationText() {
        let shortcut = DiscreteShortcut(steps: [.init(kind: .mouseButton(number: 1), modifiers: [])])
        let attributed = shortcut.attributedDisplayString(
            style: .compact, font: .systemFont(ofSize: 13), color: nil
        )
        #expect(!containsAttachment(attributed))
        #expect(attributed.string == "RMB")
    }

    @Test func attributedDisplayString_compactStyle_attachmentHasImageAndBaselineOffset() {
        let shortcut = DiscreteShortcut(steps: [.init(kind: .rotateClockwise, modifiers: [])])
        let font = NSFont.systemFont(ofSize: 13)
        let attributed = shortcut.attributedDisplayString(style: .compact, font: font, color: .labelColor)
        var attachment: NSTextAttachment?
        attributed.enumerateAttribute(
            .attachment, in: NSRange(location: 0, length: attributed.length)
        ) { value, _, stop in
            if let found = value as? NSTextAttachment { attachment = found; stop.pointee = true }
        }
        let found = attachment
        #expect(found?.image != nil)
        #expect((found?.bounds.width ?? 0) > 0)
        #expect((found?.bounds.height ?? 0) > 0)
        // Glyph is centered on the cap-height midline, so it's shifted below baseline.
        #expect((found?.bounds.origin.y ?? 0) < 0)
    }

    private func containsAttachment(_ attributed: NSAttributedString) -> Bool {
        var found = false
        attributed.enumerateAttribute(
            .attachment, in: NSRange(location: 0, length: attributed.length)
        ) { value, _, stop in
            if value != nil {
                found = true
                stop.pointee = true
            }
        }
        return found
    }
}
