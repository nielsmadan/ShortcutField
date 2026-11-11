import AppKit
import Carbon.HIToolbox
@testable import ShortcutField
import Testing

@MainActor
@Suite(.serialized)
struct KeyboardOwnershipTests {
    private func window() -> NSWindow {
        NSWindow(contentRect: NSRect(x: -10000, y: -10000, width: 300, height: 100),
                 styleMask: [.titled], backing: .buffered, defer: false)
    }

    @Test("ownership passes native input through and composes per window")
    func nestedOwnership() {
        let dispatcher = ShortcutEventDispatcher()
        let first = window()
        let second = window()
        let id = UUID()
        var deliveries = 0
        dispatcher.register(id: id) { _ in deliveries += 1; return .fired }
        defer { dispatcher.unregister(id: id) }
        let token = dispatcher.acquireKeyboardOwnership(for: first)
        let nested = dispatcher.acquireKeyboardOwnership(for: first)
        let other = dispatcher.acquireKeyboardOwnership(for: second)
        let firstEvent = keyDown(kVK_Escape, in: first)
        let secondEvent = keyDown(kVK_ANSI_J, .control, in: second)
        #expect(dispatcher.handleEvent(firstEvent) === firstEvent)
        #expect(dispatcher.handleEvent(secondEvent) === secondEvent)
        token.release()
        token.release()
        #expect(dispatcher.handleEvent(firstEvent) === firstEvent)
        nested.release()
        #expect(dispatcher.handleEvent(firstEvent) == nil)
        #expect(deliveries == 1)
        #expect(dispatcher.handleEvent(secondEvent) === secondEvent)
        other.release()
        #expect(dispatcher.handleEvent(secondEvent) == nil)
        #expect(deliveries == 2)
    }

    @Test("token destruction restores delivery without retaining its window")
    func tokenTeardown() {
        let dispatcher = ShortcutEventDispatcher()
        let id = UUID()
        dispatcher.register(id: id) { _ in .fired }
        defer { dispatcher.unregister(id: id) }
        let host = window()
        var token: ShortcutKeyboardOwnership? = dispatcher.acquireKeyboardOwnership(for: host)
        let event = keyDown(kVK_Escape, in: host)
        #expect(dispatcher.handleEvent(event) === event)
        #expect(token != nil)
        token = nil
        #expect(dispatcher.handleEvent(event) == nil)

        weak var weakWindow: NSWindow?
        autoreleasepool {
            let temporary = window()
            temporary.isReleasedWhenClosed = false
            weakWindow = temporary
            token = dispatcher.acquireKeyboardOwnership(for: temporary)
            temporary.close()
        }
        #expect(weakWindow == nil)
        token?.release()
    }

    @Test("first acquisition and last release synchronously interrupt consumers")
    func interruptionBoundaries() {
        let dispatcher = ShortcutEventDispatcher()
        let host = window()
        let id = UUID()
        var interruptions = 0
        dispatcher.register(id: id, onInterruption: { interruptions += 1 }, handler: { _ in .ignored })
        defer { dispatcher.unregister(id: id) }
        let token = dispatcher.acquireKeyboardOwnership(for: host)
        #expect(interruptions == 1)
        let nested = dispatcher.acquireKeyboardOwnership(for: host)
        #expect(interruptions == 1)
        token.release()
        #expect(interruptions == 1)
        nested.release()
        #expect(interruptions == 2)
    }

    @Test("acquiring ownership inside a handler stops the opening event with its consumed status intact",
          arguments: [false, true], [false, true])
    func reentrantAcquisition(releaseImmediately: Bool, alreadyOwned: Bool) {
        let dispatcher = ShortcutEventDispatcher()
        let host = window()
        let palette = window()
        let existing = alreadyOwned ? dispatcher.acquireKeyboardOwnership(for: palette) : nil
        defer { existing?.release() }
        let older = UUID()
        let opener = UUID()
        var delivered: [String] = []
        var token: ShortcutKeyboardOwnership?
        dispatcher.register(id: older) { _ in delivered.append("older"); return .ignored }
        dispatcher.register(id: opener) { _ in
            delivered.append("opener")
            token = dispatcher.acquireKeyboardOwnership(for: palette)
            if releaseImmediately {
                token?.release()
            }
            return .fired
        }
        defer {
            token?.release()
            dispatcher.unregister(id: opener)
            dispatcher.unregister(id: older)
        }
        #expect(dispatcher.handleEvent(keyDown(kVK_ANSI_K, .command, in: host)) == nil)
        #expect(delivered == ["opener"])
    }

    @Test("interruption tolerates nested ownership and unregistering another callback")
    func reentrantInterruption() {
        let dispatcher = ShortcutEventDispatcher()
        let first = window()
        let second = window()
        let old = UUID()
        let new = UUID()
        var calls: [String] = []
        var nested: ShortcutKeyboardOwnership?
        dispatcher.register(id: old, onInterruption: { calls.append("removed") }, handler: { _ in .ignored })
        dispatcher.register(id: new, onInterruption: {
            calls.append("new")
            dispatcher.unregister(id: old)
            if nested == nil {
                nested = dispatcher.acquireKeyboardOwnership(for: second)
            }
        }, handler: { _ in .ignored })
        let token = dispatcher.acquireKeyboardOwnership(for: first)
        #expect(calls == ["new"])
        dispatcher.unregister(id: new)
        nested?.release()
        token.release()
    }

    @Test("ownership cancels pending sequences and starts fresh continuous bursts")
    func resetsMatchers() {
        let dispatcher = ShortcutEventDispatcher()
        let host = window()
        let sequence = ShortcutMatcher("cmd+k cmd+c")
        let continuous = ShortcutMatcher(.continuous(ContinuousShortcut(
            kind: .scroll(direction: .up), modifiers: [], sensitivity: 0
        )))
        let id = UUID()
        dispatcher.register(id: id, onInterruption: {
            sequence.interrupt()
            continuous.interrupt()
        }, handler: { sequence.handle($0) })
        defer { dispatcher.unregister(id: id) }
        #expect(sequence.handle(keyDown(kVK_ANSI_K, .command, in: host)) == .advanced(consumeEvent: false))
        #expect(continuous.handle(scrollEvent(deltaY: 10, phase: .began)) == .continuousFired(magnitude: 10))
        let token = dispatcher.acquireKeyboardOwnership(for: host)
        token.release()
        #expect(sequence.handle(keyDown(kVK_ANSI_C, .command, in: host)) == .ignored)
        #expect(continuous.handle(scrollEvent(deltaY: 10, momentum: .began)) == .ignored)
        #expect(continuous.handle(scrollEvent(deltaY: 10, phase: .began)) == .continuousFired(magnitude: 10))
    }

    @Test("a sequence cannot cross concrete or windowless event boundaries")
    func matcherWindowBoundaries() {
        let matcher = ShortcutMatcher("cmd+k cmd+c")
        let first = window()
        let second = window()
        let prefix = keyDown(kVK_ANSI_K, .command, in: first)
        for event in [keyDown(kVK_ANSI_C, .command, in: second), keyDown(kVK_ANSI_C, .command)] {
            #expect(matcher.handle(prefix) == .advanced(consumeEvent: false))
            #expect(matcher.handle(event) == .ignored)
        }
        #expect(matcher.handle(prefix) == .advanced(consumeEvent: false))
        #expect(matcher.handle(keyDown(kVK_ANSI_C, .command, in: first)) == .fired)
    }

    @Test("window changes interrupt custom consumers before delivery, including owned windows")
    func dispatcherWindowBoundaries() {
        let dispatcher = ShortcutEventDispatcher()
        let first = window()
        let second = window()
        let id = UUID()
        var calls: [String] = []
        dispatcher.register(id: id, onInterruption: { calls.append("reset") }, handler: { _ in
            calls.append("event")
            return .ignored
        })
        defer { dispatcher.unregister(id: id) }
        _ = dispatcher.handleEvent(keyDown(kVK_ANSI_K, .command, in: first))
        _ = dispatcher.handleEvent(keyDown(kVK_ANSI_C, .command, in: second))
        #expect(calls == ["event", "reset", "event"])
        let token = dispatcher.acquireKeyboardOwnership(for: first)
        calls = []
        _ = dispatcher.handleEvent(keyDown(kVK_ANSI_C, .command, in: first))
        #expect(calls == ["reset"])
        token.release()
    }

    @Test("recorder capture and ownership release have independent lifetimes")
    func recorderCoexistence() {
        let dispatcher = ShortcutEventDispatcher()
        let recorder = ShortcutRecorderField()
        let (host, other) = hostWindow(recorder)
        host.makeKeyAndOrderFront(nil)
        let id = UUID()
        dispatcher.register(id: id) { _ in .fired }
        defer {
            host.makeFirstResponder(other)
            host.orderOut(nil)
            dispatcher.unregister(id: id)
        }
        let token = dispatcher.acquireKeyboardOwnership(for: host)
        #expect(host.makeFirstResponder(recorder))
        #expect(ShortcutRecording.isActive)
        let event = tabKey(backward: false, in: host)
        #expect(dispatcher.handleEvent(event) === event)
        token.release()
        #expect(ShortcutRecording.isActive)
        #expect(dispatcher.handleEvent(event) === event)
        #expect(host.makeFirstResponder(other))
        #expect(dispatcher.handleEvent(event) == nil)
    }

    @Test("native field editing and marked text continue while shortcuts are suppressed")
    func nativeFieldInput() throws {
        let dispatcher = ShortcutEventDispatcher.shared
        let host = window()
        let field = NSSearchField(frame: NSRect(x: 10, y: 30, width: 260, height: 24))
        host.contentView?.addSubview(field)
        host.makeKeyAndOrderFront(nil)
        #expect(host.makeFirstResponder(field))
        let editor = try #require(field.currentEditor() as? NSTextView)
        let id = UUID()
        var fires = 0
        dispatcher.register(id: id) { _ in fires += 1; return .fired }
        defer {
            dispatcher.unregister(id: id)
            host.makeFirstResponder(nil)
            host.orderOut(nil)
        }
        let letter = try #require(NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
            windowNumber: host.windowNumber, context: nil, characters: "a", charactersIgnoringModifiers: "a",
            isARepeat: false, keyCode: UInt16(kVK_ANSI_A)
        ))
        NSApplication.shared.sendEvent(letter)
        #expect(fires == 1)
        #expect(editor.string == "")
        let token = dispatcher.acquireKeyboardOwnership(for: host)
        defer { token.release() }
        NSApplication.shared.sendEvent(letter)
        #expect(editor.string == "a")
        editor.setMarkedText("に", selectedRange: NSRange(location: 1, length: 0),
                             replacementRange: NSRange(location: NSNotFound, length: 0))
        #expect(editor.hasMarkedText())
        for event in [keyDown(kVK_Escape, in: host), keyDown(kVK_ANSI_J, .control, in: host),
                      keyDown(kVK_UpArrow, .command, in: host)]
        {
            #expect(dispatcher.handleEvent(event) === event)
        }
        #expect(editor.hasMarkedText())
        editor.insertText("日本", replacementRange: NSRange(location: NSNotFound, length: 0))
        #expect(editor.string == "a日本")
        #expect(fires == 1)
    }

    @Test("releasing tokens for a deallocated window leaves other consumers undisturbed")
    func deadWindowRelease() {
        let dispatcher = ShortcutEventDispatcher()
        let id = UUID()
        var interruptions = 0
        dispatcher.register(id: id, onInterruption: { interruptions += 1 }, handler: { _ in .ignored })
        defer { dispatcher.unregister(id: id) }
        var tokens: [ShortcutKeyboardOwnership] = []
        weak var deadWindow: NSWindow?
        autoreleasepool {
            let host = window()
            host.isReleasedWhenClosed = false
            deadWindow = host
            tokens = [dispatcher.acquireKeyboardOwnership(for: host), dispatcher.acquireKeyboardOwnership(for: host)]
            host.close()
        }
        #expect(deadWindow == nil)
        #expect(interruptions == 1)
        tokens.forEach { $0.release() }
        #expect(interruptions == 1)
    }

    @Test("off-main token destruction releases ownership on the main actor")
    func offMainTokenDestruction() async throws {
        let dispatcher = ShortcutEventDispatcher()
        let host = window()
        let id = UUID()
        var interruptions = 0
        dispatcher.register(id: id, onInterruption: { interruptions += 1 }, handler: { _ in .fired })
        defer { dispatcher.unregister(id: id) }
        await Task.detached {
            var token: ShortcutKeyboardOwnership? = await MainActor.run {
                dispatcher.acquireKeyboardOwnership(for: host)
            }
            #expect(token != nil)
            Self.releaseOnWorker(&token)
        }.value
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while interruptions < 2, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(5))
        }
        #expect(interruptions == 2)
        #expect(dispatcher.handleEvent(keyDown(kVK_Escape, in: host)) == nil)
    }

    private nonisolated static func releaseOnWorker(_ token: inout ShortcutKeyboardOwnership?) {
        #expect(!Thread.isMainThread)
        token = nil
    }

    @Test("interruption preserves claimed gesture suppression until a fresh burst",
          arguments: [false, true])
    func interruptedGestureDoesNotRefire(continuous: Bool) {
        let shortcut: Shortcut = continuous
            ? .continuous(ContinuousShortcut(kind: .scroll(direction: .up), modifiers: [], sensitivity: 1))
            : .discrete(DiscreteShortcut(steps: [.init(kind: .scroll(direction: .up), modifiers: [])]))
        let matcher = ShortcutMatcher(shortcut)
        let dispatcher = ShortcutEventDispatcher()
        let host = window()
        let id = UUID()
        dispatcher.register(id: id, onInterruption: { matcher.interrupt() }, handler: { matcher.handle($0) })
        defer { dispatcher.unregister(id: id) }
        let first = scrollEvent(deltaY: 10, phase: .began)
        #expect(dispatcher.handleEvent(first) == nil)
        let token = dispatcher.acquireKeyboardOwnership(for: host)
        token.release()
        #expect(matcher.handle(scrollEvent(deltaY: 10, phase: .changed)) == .advanced(consumeEvent: true))
        #expect(matcher.handle(scrollEvent(phase: .ended)) == .ignored)
        #expect(matcher.handle(scrollEvent(deltaY: 10, momentum: .began)) == .advanced(consumeEvent: true))
        #expect(matcher.handle(scrollEvent(momentum: .ended)) == .advanced(consumeEvent: true))
        let fresh = matcher.handle(scrollEvent(deltaY: 10, phase: .began))
        #expect(fresh == (continuous ? .continuousFired(magnitude: 10) : .fired))
    }
}
