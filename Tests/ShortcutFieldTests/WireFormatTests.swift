import AppKit
import Carbon.HIToolbox
import Foundation
@testable import ShortcutField
import Testing

// Hosts persist these JSON shapes; a fixture changing here breaks their saved data.

private let command = NSEvent.ModifierFlags.command
private let allModifiers: NSEvent.ModifierFlags = [.command, .option, .control, .shift]

private let discreteFixtures: [(DiscreteShortcut, String)] = [
    (DiscreteShortcut(keyCode: UInt16(kVK_ANSI_K), modifiers: command),
     #"{"steps":[{"keyCode":40,"modifiers":1048576,"type":"key"}]}"#),
    (DiscreteShortcut(keyCode: UInt16(kVK_Tab), modifiers: allModifiers),
     #"{"steps":[{"keyCode":48,"modifiers":1966080,"type":"key"}]}"#),
    (DiscreteShortcut(kind: .mouseButton(number: 3), modifiers: .option),
     #"{"steps":[{"buttonNumber":3,"modifiers":524288,"type":"mouseButton"}]}"#),
    (DiscreteShortcut(kind: .scroll(direction: .up), modifiers: .shift),
     #"{"steps":[{"direction":"up","modifiers":131072,"type":"scroll"}]}"#),
    (DiscreteShortcut(kind: .scroll(direction: .down), modifiers: []),
     #"{"steps":[{"direction":"down","modifiers":0,"type":"scroll"}]}"#),
    (DiscreteShortcut(kind: .scroll(direction: .left), modifiers: []),
     #"{"steps":[{"direction":"left","modifiers":0,"type":"scroll"}]}"#),
    (DiscreteShortcut(kind: .scroll(direction: .right), modifiers: []),
     #"{"steps":[{"direction":"right","modifiers":0,"type":"scroll"}]}"#),
    (DiscreteShortcut(kind: .pinchIn, modifiers: .control),
     #"{"steps":[{"modifiers":262144,"type":"pinchIn"}]}"#),
    (DiscreteShortcut(kind: .pinchOut, modifiers: []),
     #"{"steps":[{"modifiers":0,"type":"pinchOut"}]}"#),
    (DiscreteShortcut(kind: .rotateClockwise, modifiers: []),
     #"{"steps":[{"modifiers":0,"type":"rotateClockwise"}]}"#),
    (DiscreteShortcut(kind: .rotateCounterClockwise, modifiers: []),
     #"{"steps":[{"modifiers":0,"type":"rotateCounterClockwise"}]}"#),
    (DiscreteShortcut(kind: .smartMagnify, modifiers: command),
     #"{"steps":[{"modifiers":1048576,"type":"smartMagnify"}]}"#),
    (DiscreteShortcut(steps: [
        .init(keyCode: UInt16(kVK_ANSI_K), modifiers: command),
        .init(keyCode: UInt16(kVK_ANSI_C), modifiers: command),
    ]),
    #"{"steps":[{"keyCode":40,"modifiers":1048576,"type":"key"},{"keyCode":8,"modifiers":1048576,"type":"key"}]}"#),
]

private let continuousFixtures: [(ContinuousShortcut, String)] = [
    (ContinuousShortcut(kind: .scroll(direction: .down), modifiers: command, sensitivity: 0.5),
     #"{"direction":"down","modifiers":1048576,"sensitivity":0.5,"type":"scroll"}"#),
    (ContinuousShortcut(kind: .pinchIn, modifiers: .option, sensitivity: 0.25),
     #"{"modifiers":524288,"sensitivity":0.25,"type":"pinchIn"}"#),
    (ContinuousShortcut(kind: .pinchOut, modifiers: [], sensitivity: 0),
     #"{"modifiers":0,"sensitivity":0,"type":"pinchOut"}"#),
    (ContinuousShortcut(kind: .rotateClockwise, modifiers: .shift, sensitivity: 0.75),
     #"{"modifiers":131072,"sensitivity":0.75,"type":"rotateClockwise"}"#),
    (ContinuousShortcut(kind: .rotateCounterClockwise, modifiers: .control, sensitivity: 0.5),
     #"{"modifiers":262144,"sensitivity":0.5,"type":"rotateCounterClockwise"}"#),
]

private let umbrellaFixtures: [(Shortcut, String)] = [
    (.discrete(DiscreteShortcut(keyCode: UInt16(kVK_ANSI_S), modifiers: command)),
     #"{"discrete":{"steps":[{"keyCode":1,"modifiers":1048576,"type":"key"}]},"kind":"discrete"}"#),
    (.continuous(ContinuousShortcut(kind: .pinchOut, modifiers: command, sensitivity: 0.5)),
     #"{"continuous":{"modifiers":1048576,"sensitivity":0.5,"type":"pinchOut"},"kind":"continuous"}"#),
]

private func sortedJSON(_ value: some Encodable) throws -> String? {
    let encoder = JSONEncoder()
    encoder.outputFormatting = .sortedKeys
    return try String(bytes: encoder.encode(value), encoding: .utf8)
}

private func decode<T: Decodable>(_: T.Type, _ json: String) throws -> T {
    try JSONDecoder().decode(T.self, from: Data(json.utf8))
}

struct WireFormatTests {
    @Test(arguments: discreteFixtures)
    func discreteShortcut_encodesToGoldenJSON(shortcut: DiscreteShortcut, json: String) throws {
        #expect(try sortedJSON(shortcut) == json)
    }

    @Test(arguments: discreteFixtures)
    func discreteShortcut_decodesGoldenJSON(shortcut: DiscreteShortcut, json: String) throws {
        #expect(try decode(DiscreteShortcut.self, json) == shortcut)
    }

    @Test(arguments: continuousFixtures)
    func continuousShortcut_encodesToGoldenJSON(shortcut: ContinuousShortcut, json: String) throws {
        #expect(try sortedJSON(shortcut) == json)
    }

    @Test(arguments: continuousFixtures)
    func continuousShortcut_decodesGoldenJSON(shortcut: ContinuousShortcut, json: String) throws {
        #expect(try decode(ContinuousShortcut.self, json) == shortcut)
    }

    @Test(arguments: umbrellaFixtures)
    func shortcut_encodesToGoldenJSON(shortcut: Shortcut, json: String) throws {
        #expect(try sortedJSON(shortcut) == json)
    }

    @Test(arguments: umbrellaFixtures)
    func shortcut_decodesGoldenJSON(shortcut: Shortcut, json: String) throws {
        #expect(try decode(Shortcut.self, json) == shortcut)
    }
}
