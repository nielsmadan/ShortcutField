import AppKit
import Carbon.HIToolbox
@testable import ShortcutField
import Testing

// `displayString` on a `.key` shortcut falls through to `keyToCharacter`, which
// uses the TIS / UCKeyTranslate keyboard-layout APIs — not thread-safe.
// `@MainActor` at struct level serializes this suite against the other
// @MainActor suites that touch CGEvent / TIS / NSSearchField.
@MainActor
@Suite("Shortcut umbrella enum", .serialized)
struct ShortcutTests {
    private var sampleDiscrete: DiscreteShortcut {
        DiscreteShortcut(keyCode: UInt16(kVK_ANSI_S), modifiers: .command)
    }

    private var sampleContinuous: ContinuousShortcut {
        ContinuousShortcut(kind: .pinchOut, modifiers: .command, sensitivity: 0.5)
    }

    @Test("kind reflects the case")
    func kind() {
        #expect(Shortcut.discrete(sampleDiscrete).kind == .discrete)
        #expect(Shortcut.continuous(sampleContinuous).kind == .continuous)
    }

    @Test("displayString forwards to the inner value")
    func displayString() {
        #expect(Shortcut.discrete(sampleDiscrete).displayString == sampleDiscrete.displayString)
        #expect(Shortcut.continuous(sampleContinuous).displayString == sampleContinuous.displayString)
    }

    @Test("Codable round-trips both cases")
    func codableRoundTrip() throws {
        for shortcut in [Shortcut.discrete(sampleDiscrete), .continuous(sampleContinuous)] {
            let data = try JSONEncoder().encode(shortcut)
            let decoded = try JSONDecoder().decode(Shortcut.self, from: data)
            #expect(decoded == shortcut)
        }
    }

    @Test("Hashable distinguishes the cases")
    func hashable() {
        let a = Shortcut.discrete(sampleDiscrete)
        let b = Shortcut.continuous(sampleContinuous)
        #expect(a != b)
        #expect(Set([a, b, a]).count == 2)
    }
}
