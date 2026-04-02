import AppKit
import ObjectiveC
import ShortcutField
import SwiftUI

@main
struct ShortcutFieldExampleApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .background(BeepSuppressor())
                .onAppear {
                    // When launched directly (not via LaunchServices/open),
                    // the app needs an explicit activation policy to come
                    // to the foreground.
                    NSApp.setActivationPolicy(.regular)
                    NSApp.activate()
                }
        }
    }
}

// MARK: - Beep Suppression

/// Overrides `noResponder(for:)` on the hosting window to suppress the
/// system alert sound during active sequence tracking.
///
/// Uses ObjC runtime to add the override to the existing window class
/// rather than replacing the window, preserving SwiftUI's window lifecycle.
private struct BeepSuppressor: NSViewRepresentable {
    func makeNSView(context _: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            Self.installOverride(on: type(of: window))
        }
        return view
    }

    func updateNSView(_: NSView, context _: Context) {}

    private static var installed = false

    static func installOverride(on windowClass: AnyClass) {
        guard !installed else { return }
        installed = true

        let selector = #selector(NSResponder.noResponder(for:))
        guard let method = class_getInstanceMethod(windowClass, selector) else { return }
        let originalImp = method_getImplementation(method)

        typealias NoResponderFn = @convention(c) (AnyObject, Selector, Selector) -> Void
        let original = unsafeBitCast(originalImp, to: NoResponderFn.self)

        let block: @convention(block) (AnyObject, Selector) -> Void = { obj, eventSelector in
            if eventSelector == #selector(NSResponder.keyDown(with:)),
               ShortcutSequenceTracking.isActive {
                return // suppress beep during sequence tracking
            }
            original(obj, selector, eventSelector)
        }

        let newImp = imp_implementationWithBlock(block)
        method_setImplementation(method, newImp)
    }
}
