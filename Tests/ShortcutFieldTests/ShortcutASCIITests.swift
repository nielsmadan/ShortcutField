import AppKit
import Carbon.HIToolbox
@testable import ShortcutField
import Testing

@Suite("Shortcut text syntax")
struct ShortcutASCIITests {
    @Test("discrete round-trips: key + modifiers")
    func discreteKeyRoundTrip() throws {
        let s = try DiscreteShortcut(ascii: "cmd+s")
        #expect(s == DiscreteShortcut(keyCode: UInt16(kVK_ANSI_S), modifiers: .command))
        #expect(s.ascii == "cmd+s")
    }

    @Test("discrete round-trips: multiple modifiers, order-insensitive parse")
    func multiModifier() throws {
        let s = try DiscreteShortcut(ascii: "shift+cmd+a")
        #expect(s == DiscreteShortcut(keyCode: UInt16(kVK_ANSI_A), modifiers: [.command, .shift]))
        #expect(s.ascii == "shift+cmd+a")
    }

    @Test("discrete round-trips: multi-step")
    func multiStep() throws {
        let s = try DiscreteShortcut(ascii: "cmd+k cmd+c")
        #expect(s.steps.count == 2)
        #expect(s.ascii == "cmd+k cmd+c")
    }

    @Test("discrete round-trips: mouse, scroll, gesture, special keys")
    func nonKeyForms() throws {
        #expect(try DiscreteShortcut(ascii: "ctrl+right-click").ascii == "ctrl+right-click")
        #expect(try DiscreteShortcut(ascii: "shift+scroll-up").ascii == "shift+scroll-up")
        #expect(try DiscreteShortcut(ascii: "cmd+pinch-in").ascii == "cmd+pinch-in")
        #expect(try DiscreteShortcut(ascii: "tab").ascii == "tab")
        #expect(try DiscreteShortcut(ascii: "escape").ascii == "escape")
    }

    @Test("umbrella resolves bare gesture to continuous")
    func umbrellaContinuousResolution() throws {
        let s = try Shortcut(ascii: "cmd+pinch-out @0.5")
        guard case let .continuous(cs) = s else {
            Issue.record("expected .continuous"); return
        }
        #expect(cs.kind == .pinchOut)
        #expect(cs.sensitivity == 0.5)
        #expect(s.ascii == "cmd+pinch-out @0.5")
    }

    @Test("umbrella resolves key/multistep to discrete")
    func umbrellaDiscreteResolution() throws {
        guard case .discrete = try Shortcut(ascii: "cmd+s") else {
            Issue.record("expected .discrete"); return
        }
        guard case .discrete = try Shortcut(ascii: "cmd+k cmd+c") else {
            Issue.record("expected .discrete"); return
        }
    }

    @Test("ExpressibleByStringLiteral produces a Shortcut")
    func stringLiteral() {
        let s: Shortcut = "cmd+s"
        #expect(s == .discrete(DiscreteShortcut(keyCode: UInt16(kVK_ANSI_S), modifiers: .command)))
    }

    @Test("parse errors")
    func parseErrors() {
        #expect(throws: ShortcutParsingError.empty) { try DiscreteShortcut(ascii: "") }
        #expect(throws: ShortcutParsingError.unknownModifier("hyper")) {
            try DiscreteShortcut(ascii: "hyper+s")
        }
        #expect(throws: ShortcutParsingError.unknownKey("notakey")) {
            try DiscreteShortcut(ascii: "cmd+notakey")
        }
        #expect(throws: ShortcutParsingError.sensitivityOnDiscrete) {
            try DiscreteShortcut(ascii: "cmd+s @0.5")
        }
        #expect(throws: ShortcutParsingError.malformedSensitivity("abc")) {
            try Shortcut(ascii: "pinch-in @abc")
        }
        #expect(throws: ShortcutParsingError.emptyStep) {
            try DiscreteShortcut(ascii: "cmd++s")
        }
    }

    @Test("punctuation key round-trips")
    func punctuationKeyRoundTrips() throws {
        #expect(try DiscreteShortcut(ascii: "cmd+semicolon").ascii == "cmd+semicolon")
        #expect(try DiscreteShortcut(ascii: "cmd+left-bracket").ascii == "cmd+left-bracket")
        #expect(try DiscreteShortcut(ascii: "cmd+right-bracket").ascii == "cmd+right-bracket")
        #expect(try DiscreteShortcut(ascii: "opt+minus").ascii == "opt+minus")
        #expect(try DiscreteShortcut(ascii: "shift+equal").ascii == "shift+equal")
        #expect(try DiscreteShortcut(ascii: "cmd+comma").ascii == "cmd+comma")
        #expect(try DiscreteShortcut(ascii: "cmd+period").ascii == "cmd+period")
        #expect(try DiscreteShortcut(ascii: "cmd+slash").ascii == "cmd+slash")
        #expect(try DiscreteShortcut(ascii: "cmd+backslash").ascii == "cmd+backslash")
        #expect(try DiscreteShortcut(ascii: "cmd+quote").ascii == "cmd+quote")
        #expect(try DiscreteShortcut(ascii: "cmd+grave").ascii == "cmd+grave")
    }

    @Test("key<N> numeric fallback round-trips")
    func keyNFallbackRoundTrip() throws {
        // A keycode not in any table should round-trip via key<N>
        let highCode = DiscreteShortcut(keyCode: 200, modifiers: .command)
        let ascii = highCode.ascii
        #expect(ascii == "cmd+key200")
        #expect(try DiscreteShortcut(ascii: ascii) == highCode)
    }

    @Test("button<N> generic mouse-button round-trips")
    func buttonNFallbackRoundTrip() throws {
        let b6 = DiscreteShortcut.Step(kind: .mouseButton(number: 5), modifiers: [])
        let ascii = b6.ascii
        #expect(ascii == "button6")
        let parsed = try DiscreteShortcut.Step.parse(ascii: ascii)
        #expect(parsed == b6)
    }

    @Test("bare scroll-up resolves to continuous")
    func bareScrollContinuous() throws {
        let s = try Shortcut(ascii: "scroll-up")
        guard case let .continuous(cs) = s else {
            Issue.record("expected .continuous"); return
        }
        #expect(cs.kind == .scroll(direction: .up))
        #expect(cs.sensitivity == 0.0)
    }

    @Test("continuous shortcut explicit round-trip")
    func continuousRoundTrip() throws {
        let s = Shortcut.continuous(ContinuousShortcut(kind: .pinchOut, modifiers: .command, sensitivity: 0.5))
        #expect(try Shortcut(ascii: s.ascii) == s)
    }
}
