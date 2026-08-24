import AppKit
import Carbon.HIToolbox
@testable import ShortcutField
import Testing

/// Runs `body` with `control` installed as the window's first responder, so a
/// text control contributes its genuine AppKit field editor rather than a stub.
/// A unit-test process has no key window, so the responder reaches the gate
/// through ``TextInputFocus/responderOverride``.
@MainActor
private func withFocus<T>(on control: NSControl, _ body: () -> T) -> T {
    let window = NSWindow(contentRect: .init(x: 0, y: 0, width: 200, height: 60),
                          styleMask: [.titled], backing: .buffered, defer: false)
    window.contentView?.addSubview(control)
    window.makeFirstResponder(control)
    let previous = TextInputFocus.responderOverride
    TextInputFocus.responderOverride = { window.firstResponder }
    defer { TextInputFocus.responderOverride = previous }
    return body()
}

@MainActor
private func withTextFieldFocus<T>(_ body: () -> T) -> T {
    withFocus(on: NSTextField(string: ""), body)
}

@MainActor
private func withResponder<T>(_ responder: NSResponder?, _ body: () -> T) -> T {
    let previous = TextInputFocus.responderOverride
    TextInputFocus.responderOverride = { responder }
    defer { TextInputFocus.responderOverride = previous }
    return body()
}

@MainActor
private func result(for shortcut: DiscreteShortcut, _ events: [NSEvent]) -> ShortcutMatchResult {
    let matcher = SequenceMatcher()
    matcher.configure(shortcut: shortcut)
    var last = ShortcutMatchResult.ignored
    for event in events {
        last = matcher.handle(event)
    }
    return last
}

@MainActor
@Suite("Text-focus gate", .serialized)
struct FocusGateTests {
    @Test("bare key yields to a focused text field")
    func bareKeySuppressed() {
        #expect(withTextFieldFocus { result(for: DiscreteShortcut(keyCode: UInt16(kVK_ANSI_K), modifiers: []),
                                            [keyDown(kVK_ANSI_K)]) == .ignored })
    }

    @Test("shift-only combination yields to a focused text field")
    func shiftOnlySuppressed() {
        #expect(withTextFieldFocus { result(for: DiscreteShortcut(keyCode: UInt16(kVK_ANSI_K), modifiers: .shift),
                                            [keyDown(kVK_ANSI_K, .shift)]) == .ignored })
    }

    @Test("option-only combination yields to a focused text field")
    func optionOnlySuppressed() {
        #expect(withTextFieldFocus { result(for: DiscreteShortcut(keyCode: UInt16(kVK_ANSI_K), modifiers: .option),
                                            [keyDown(kVK_ANSI_K, .option)]) == .ignored })
    }

    @Test("command shortcut fires over a focused text field")
    func commandFires() {
        #expect(withTextFieldFocus { result(for: DiscreteShortcut(keyCode: UInt16(kVK_ANSI_K), modifiers: .command),
                                            [keyDown(kVK_ANSI_K, .command)]) == .fired })
    }

    @Test("control shortcut fires over a focused text field")
    func controlFires() {
        #expect(withTextFieldFocus { result(for: DiscreteShortcut(keyCode: UInt16(kVK_ANSI_K), modifiers: .control),
                                            [keyDown(kVK_ANSI_K, .control)]) == .fired })
    }

    @Test("escape fires over a focused text field")
    func escapeFires() {
        #expect(withTextFieldFocus { result(for: DiscreteShortcut(keyCode: UInt16(kVK_Escape), modifiers: []),
                                            [keyDown(kVK_Escape)]) == .fired })
    }

    @Test("a chord's bare second step completes over a focused text field")
    func chordCompletes() {
        let chord = DiscreteShortcut(steps: [
            .init(keyCode: UInt16(kVK_ANSI_K), modifiers: .command),
            .init(keyCode: UInt16(kVK_ANSI_S), modifiers: []),
        ])
        #expect(withTextFieldFocus {
            result(for: chord, [keyDown(kVK_ANSI_K, .command), keyDown(kVK_ANSI_S)]) == .fired
        })
    }

    @Test("bare key fires when no responder has focus")
    func bareKeyFiresWithoutTextFocus() {
        #expect(withResponder(nil) {
            result(for: DiscreteShortcut(keyCode: UInt16(kVK_ANSI_K), modifiers: []),
                   [keyDown(kVK_ANSI_K)]) == .fired
        })
    }

    @Test("bare key fires when focus rests on a non-text responder")
    func bareKeyFiresWithButtonFocus() {
        #expect(withResponder(NSButton(title: "Go", target: nil, action: nil)) {
            result(for: DiscreteShortcut(keyCode: UInt16(kVK_ANSI_K), modifiers: []),
                   [keyDown(kVK_ANSI_K)]) == .fired
        })
    }

    @Test("bare key fires when the focused text view is read-only")
    func bareKeyFiresWhenTextViewNotEditable() {
        let textView = NSTextView(frame: .init(x: 0, y: 0, width: 100, height: 40))
        textView.isEditable = false
        #expect(withResponder(textView) {
            result(for: DiscreteShortcut(keyCode: UInt16(kVK_ANSI_K), modifiers: []),
                   [keyDown(kVK_ANSI_K)]) == .fired
        })
    }

    // MARK: - Shapes the gate must not touch

    @Test("bare function key fires over a focused text field")
    func functionKeyFires() {
        #expect(withTextFieldFocus { result(for: DiscreteShortcut(keyCode: UInt16(kVK_F5), modifiers: []),
                                            [keyDown(kVK_F5)]) == .fired })
    }

    @Test("shift+command shortcut fires over a focused text field")
    func shiftCommandFires() {
        #expect(withTextFieldFocus {
            result(for: DiscreteShortcut(keyCode: UInt16(kVK_ANSI_K), modifiers: [.shift, .command]),
                   [keyDown(kVK_ANSI_K, [.shift, .command])]) == .fired
        })
    }

    @Test("a mouse-button shortcut fires over a focused text field")
    func mouseButtonStepFires() {
        let click = NSEvent.mouseEvent(with: .leftMouseDown, location: .zero, modifierFlags: [],
                                       timestamp: 0, windowNumber: 0, context: nil,
                                       eventNumber: 0, clickCount: 1, pressure: 1)!
        #expect(withTextFieldFocus {
            result(for: DiscreteShortcut(kind: .mouseButton(number: 0), modifiers: []), [click]) == .fired
        })
    }

    @Test("a scroll shortcut fires over a focused text field")
    func scrollStepFires() {
        #expect(withTextFieldFocus {
            result(for: DiscreteShortcut(kind: .scroll(direction: .up), modifiers: []),
                   [scrollEvent(deltaY: 10)]) == .fired
        })
    }

    @Test("a secure text field suppresses a bare key")
    func secureTextFieldSuppresses() {
        #expect(withFocus(on: NSSecureTextField(string: "")) {
            result(for: DiscreteShortcut(keyCode: UInt16(kVK_ANSI_K), modifiers: []),
                   [keyDown(kVK_ANSI_K)]) == .ignored
        })
    }

    // MARK: - State after suppression

    @Test("a sequence whose first step is bare never starts while text has focus")
    func bareFirstStepDoesNotStartSequence() {
        let sequence = DiscreteShortcut(steps: [
            .init(keyCode: UInt16(kVK_ANSI_K), modifiers: []),
            .init(keyCode: UInt16(kVK_ANSI_S), modifiers: []),
        ])
        let matcher = SequenceMatcher()
        matcher.configure(shortcut: sequence)
        withTextFieldFocus {
            #expect(matcher.handle(keyDown(kVK_ANSI_K)) == .ignored)
            #expect(matcher.currentStep == 0)
            #expect(!matcher.isTracking)
            #expect(matcher.handle(keyDown(kVK_ANSI_S)) == .ignored)
        }
    }

    @Test("a shortcut suppressed while typing fires again once focus leaves the field")
    func suppressedShortcutRecoversAfterFocusLeaves() {
        let matcher = SequenceMatcher()
        matcher.configure(shortcut: DiscreteShortcut(keyCode: UInt16(kVK_ANSI_K), modifiers: []))
        withTextFieldFocus {
            #expect(matcher.handle(keyDown(kVK_ANSI_K)) == .ignored)
        }
        #expect(withResponder(nil) { matcher.handle(keyDown(kVK_ANSI_K)) } == .fired)
        #expect(ShortcutTracking.isActive == false)
    }
}
