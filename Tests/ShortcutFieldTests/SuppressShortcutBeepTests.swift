import AppKit
@testable import ShortcutField
import Testing

@MainActor
@Suite("BeepSuppressor")
struct BeepSuppressorTests {
    // Two window classes that inherit `noResponder(for:)` from a shared base, so
    // `class_getInstanceMethod` resolves both to the same Method — the case that
    // would stack the swizzle if dedup keyed on the passed class.
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
    func swizzlesSharedMethodOnce() {
        let method = class_getInstanceMethod(
            SharedBaseWindow.self,
            #selector(NSResponder.noResponder(for:))
        )!

        BeepSuppressor.installOverride(on: WindowClassA.self)
        let afterFirstPatch = method_getImplementation(method)

        // Same class again, then a sibling class resolving to the same method:
        // neither must re-swizzle.
        BeepSuppressor.installOverride(on: WindowClassA.self)
        BeepSuppressor.installOverride(on: WindowClassB.self)

        #expect(method_getImplementation(method) == afterFirstPatch)
    }
}
