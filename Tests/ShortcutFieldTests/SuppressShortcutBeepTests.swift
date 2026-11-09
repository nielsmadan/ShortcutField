import AppKit
@testable import ShortcutField
import SwiftUI
import Testing

@MainActor
@Suite("BeepSuppressor", .serialized)
struct BeepSuppressorTests {
    /// Two window classes that inherit `noResponder(for:)` from a shared base, so
    /// `class_getInstanceMethod` resolves both to the same Method — the case that
    /// would stack the swizzle if dedup keyed on the passed class.
    class SharedBaseWindow: NSWindow {
        // Overridden so this class owns its own `noResponder(for:)` Method —
        // the test swizzles that, not the shared `NSWindow` one.
        // swiftlint:disable:next unneeded_override
        override func noResponder(for eventSelector: Selector) {
            super.noResponder(for: eventSelector)
        }
    }

    final class WindowClassA: SharedBaseWindow {}
    final class WindowClassB: SharedBaseWindow {}

    @Test("installOverride swizzles a shared inherited method exactly once")
    func swizzlesSharedMethodOnce() throws {
        let method = try #require(class_getInstanceMethod(
            SharedBaseWindow.self,
            #selector(NSResponder.noResponder(for:))
        ))

        BeepSuppressor.installOverride(on: WindowClassA.self)
        let afterFirstPatch = method_getImplementation(method)

        // Same class again, then a sibling class resolving to the same method:
        // neither must re-swizzle.
        BeepSuppressor.installOverride(on: WindowClassA.self)
        BeepSuppressor.installOverride(on: WindowClassB.self)

        #expect(method_getImplementation(method) == afterFirstPatch)
    }

    /// Overrides `noResponder(for:)`, so it doesn't reach `NSResponder`'s and needs its own
    /// patch; records each selector that reaches it.
    final class OwnNoResponderWindow: NSWindow {
        nonisolated(unsafe) static var forwarded: [Selector] = []

        override dynamic func noResponder(for eventSelector: Selector) {
            Self.forwarded.append(eventSelector)
        }
    }

    /// The `NSResponder` patch is process-wide and never removed, so only the first mount of the
    /// modifier can show when it installs. This is the process's only mount of it, and checks the
    /// window-less install before the window one.
    @Test("the modifier installs suppression before its view is in a window, and on a window class of its own")
    func modifierInstallsAtOnceAndOnItsWindowClass() throws {
        try #require(!BeepSuppressor.isPatched(NSResponder.self), "another test patched NSResponder first")
        let windowless = NSHostingView(rootView: Text("beep").suppressShortcutBeep())
        windowless.layoutSubtreeIfNeeded()
        #expect(BeepSuppressor.isPatched(NSResponder.self))

        let window = OwnNoResponderWindow(
            contentRect: NSRect(x: -10000, y: -10000, width: 80, height: 40),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = NSHostingView(rootView: Text("beep").suppressShortcutBeep())
        window.contentView?.layoutSubtreeIfNeeded()
        defer { window.contentView = nil }

        let savedCount = ShortcutTracking.activeCount
        defer { ShortcutTracking.activeCount = savedCount }
        ShortcutTracking.activeCount = 1
        OwnNoResponderWindow.forwarded = []
        window.noResponder(for: #selector(NSResponder.keyDown(with:)))
        window.noResponder(for: #selector(NSResponder.mouseDown(with:)))
        #expect(OwnNoResponderWindow.forwarded == [#selector(NSResponder.mouseDown(with:))])
    }
}
