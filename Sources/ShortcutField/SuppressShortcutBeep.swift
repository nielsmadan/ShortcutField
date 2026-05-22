import AppKit
import ObjectiveC
import SwiftUI

public extension View {
    /// Suppresses the macOS system alert sound for key events that are part of
    /// an in-progress multi-step shortcut match (see ``ShortcutTracking/isActive``).
    ///
    /// Apply this to a SwiftUI view whose hosting window you don't control —
    /// e.g. a `WindowGroup` scene. It installs a one-time, class-level
    /// `noResponder(for:)` override (an Objective-C runtime swizzle) on the
    /// hosting window's class. AppKit hosts that own their `NSWindow` subclass
    /// should override `noResponder(for:)` directly instead.
    func suppressShortcutBeep() -> some View {
        background(BeepSuppressor())
    }
}

/// Installs a class-level `noResponder(for:)` override on the hosting window so
/// the system alert sound is suppressed while a multi-step match is in progress.
///
/// The override is added to the existing window class via the Objective-C
/// runtime rather than by replacing the window, preserving SwiftUI's window
/// lifecycle.
struct BeepSuppressor: NSViewRepresentable {
    func makeNSView(context _: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            Self.installOverride(on: type(of: window))
        }
        return view
    }

    func updateNSView(_: NSView, context _: Context) {}

    /// Methods already patched. `class_getInstanceMethod` resolves
    /// `noResponder(for:)` to whichever class in the hierarchy defines it —
    /// often a superclass shared by several window classes — so dedupe on the
    /// resolved method, not the passed class, to avoid stacking the swizzle.
    @MainActor private static var patchedMethods: Set<OpaquePointer> = []

    @MainActor
    static func installOverride(on windowClass: AnyClass) {
        let selector = #selector(NSResponder.noResponder(for:))
        guard let method = class_getInstanceMethod(windowClass, selector) else { return }
        guard !patchedMethods.contains(method) else { return }
        patchedMethods.insert(method)

        let originalImp = method_getImplementation(method)

        typealias NoResponderFn = @convention(c) (AnyObject, Selector, Selector) -> Void
        let original = unsafeBitCast(originalImp, to: NoResponderFn.self)

        let block: @convention(block) (AnyObject, Selector) -> Void = { obj, eventSelector in
            if eventSelector == #selector(NSResponder.keyDown(with:)),
               ShortcutTracking.isActive
            {
                return // suppress beep during in-progress multi-step matches
            }
            original(obj, selector, eventSelector)
        }

        method_setImplementation(method, imp_implementationWithBlock(block))
    }
}
