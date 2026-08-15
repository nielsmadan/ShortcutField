import AppKit
import Carbon.HIToolbox
@testable import ShortcutField
import Testing

// Each test uses an isolated `ShortcutEventDispatcher()` rather than `.shared`:
// the internal `init()` exists precisely so tests don't mutate app-wide state.
// `register` installs a real `NSEvent` monitor, so every test still unregisters
// (via `defer`) to tear that monitor down.
@MainActor
@Suite("ShortcutEventDispatcher")
struct ShortcutEventDispatcherTests {
    @Test("a registered handler receives events; unregister stops delivery")
    func registerUnregister() {
        let dispatcher = ShortcutEventDispatcher()
        let id = UUID()
        var received = 0
        dispatcher.register(id: id) { _ in
            received += 1
            return .ignored
        }
        defer { dispatcher.unregister(id: id) }

        _ = dispatcher.handleEvent(keyDown(kVK_ANSI_S, .command))
        #expect(received == 1)

        dispatcher.unregister(id: id)
        _ = dispatcher.handleEvent(keyDown(kVK_ANSI_S, .command))
        #expect(received == 1)
    }

    @Test("a .fired result consumes the event")
    func firedConsumes() {
        let dispatcher = ShortcutEventDispatcher()
        let id = UUID()
        dispatcher.register(id: id) { _ in .fired }
        defer { dispatcher.unregister(id: id) }
        #expect(dispatcher.handleEvent(keyDown(kVK_ANSI_S, .command)) == nil)
    }

    @Test(".advanced(consumeEvent: true) consumes; .advanced(consumeEvent: false) passes through")
    func advancedConsumption() {
        let event = keyDown(kVK_Tab, .command)

        let consuming = ShortcutEventDispatcher()
        let consumingId = UUID()
        consuming.register(id: consumingId) { _ in .advanced(consumeEvent: true) }
        defer { consuming.unregister(id: consumingId) }
        #expect(consuming.handleEvent(event) == nil)

        let passing = ShortcutEventDispatcher()
        let passingId = UUID()
        passing.register(id: passingId) { _ in .advanced(consumeEvent: false) }
        defer { passing.unregister(id: passingId) }
        #expect(passing.handleEvent(event) == event)
    }

    @Test("handlers are consulted newest-first")
    func newestFirstOrdering() {
        let dispatcher = ShortcutEventDispatcher()
        var order: [Int] = []
        let firstID = UUID()
        let secondID = UUID()
        dispatcher.register(id: firstID) { _ in order.append(1); return .ignored }
        dispatcher.register(id: secondID) { _ in order.append(2); return .ignored }
        defer {
            dispatcher.unregister(id: firstID)
            dispatcher.unregister(id: secondID)
        }
        _ = dispatcher.handleEvent(keyDown(kVK_ANSI_S, .command))
        #expect(order == [2, 1])
    }
}
