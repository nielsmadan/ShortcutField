import AppKit
import SwiftUI

/// Holds the latest `onShortcut` action. The dispatcher handler is registered
/// once (on appear / shortcut change) and captures this box, not the action
/// directly — so a re-rendered modifier carrying a fresh closure stays current
/// without forcing a re-registration.
@MainActor
private final class ActionBox {
    var action: () -> Void = {}
    nonisolated init() {}
}

/// The window hosting an `.onShortcut` view, held weakly.
@MainActor
private final class HostWindowBox {
    weak var window: NSWindow?
    nonisolated init() {}

    /// Whether `event` was sent to the host window; never while the view is in no window.
    func owns(_ event: NSEvent) -> Bool {
        window != nil && event.window === window
    }
}

/// Records the window it is placed in, so a window-scoped `.onShortcut` can compare it
/// with `event.window`.
private struct HostWindowReader: NSViewRepresentable {
    let box: HostWindowBox

    func makeNSView(context _: Context) -> NSView {
        HostWindowView(box: box)
    }

    func updateNSView(_: NSView, context _: Context) {}

    private final class HostWindowView: NSView {
        let box: HostWindowBox

        init(box: HostWindowBox) {
            self.box = box
            super.init(frame: .zero)
        }

        @available(*, unavailable)
        required init?(coder _: NSCoder) {
            fatalError("init(coder:) is not supported")
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            box.window = window
        }

        override func hitTest(_: NSPoint) -> NSView? {
            nil
        }
    }
}

struct OnShortcutModifier: ViewModifier {
    let shortcut: Shortcut?
    let scope: ShortcutScope
    let action: () -> Void

    private struct BindingKey: Equatable {
        let shortcut: Shortcut?
        let scope: ShortcutScope
    }

    @State private var matcher: ShortcutMatcher?
    @State private var listenerID = UUID()
    @State private var actionBox = ActionBox()
    @State private var hostWindow = HostWindowBox()

    func body(content: Content) -> some View {
        actionBox.action = action
        return content
            .background {
                if scope == .window {
                    HostWindowReader(box: hostWindow)
                }
            }
            .onAppear { install(shortcut, scope: scope) }
            .onDisappear { teardown() }
            // One key for both values: separate handlers would each read the other value
            // from a stale capture when both change in the same update.
            .onChange(of: BindingKey(shortcut: shortcut, scope: scope)) { newValue in
                teardown()
                install(newValue.shortcut, scope: newValue.scope)
            }
    }

    /// - Parameters: passed explicitly rather than read from `self`. The macOS 13
    ///   `onChange(of:perform:)` invokes the closure captured from the *pre-change*
    ///   body evaluation, so `self` would still hold the stale value here.
    private func install(_ shortcut: Shortcut?, scope: ShortcutScope) {
        guard let shortcut else { return }
        let m = ShortcutMatcher(shortcut)
        matcher = m
        let box = actionBox
        let hostWindow = hostWindow
        ShortcutEventDispatcher.shared.register(id: listenerID, onInterruption: { m.interrupt() }, handler: { event in
            if scope == .window, !hostWindow.owns(event) {
                return .ignored
            }
            let result = m.handle(event)
            switch result {
            case .fired, .continuousFired:
                box.action()
            case .advanced, .ignored:
                break
            }
            return result
        })
    }

    private func teardown() {
        ShortcutEventDispatcher.shared.unregister(id: listenerID)
        matcher?.reset()
        matcher = nil
    }
}

// MARK: - View Extension

public extension View {
    /// Perform an action when `shortcut` is performed.
    ///
    /// For `.discrete` shortcuts the action fires once on completion. For
    /// `.continuous` shortcuts it fires repeatedly, throttled by the shortcut's
    /// `sensitivity`. Multi-step discrete shortcuts fire once when the full
    /// sequence completes within the per-step timeout.
    ///
    /// While an editable text responder has focus, a discrete shortcut whose
    /// first step is a bare key or a ⇧/⌥-only combination does not fire — the
    /// keystroke goes to the field instead. Steps carrying ⌘ or ⌃, and keys that
    /// produce no text (Escape, F1–F20), always fire. Later steps of a multi-step
    /// shortcut always fire once its first step has matched.
    ///
    /// Keyboard ownership pauses delivery in the owned window. Ownership transitions and
    /// event-window changes reset pending matching state.
    ///
    /// It responds to events in every window of the app; use
    /// ``SwiftUICore/View/onShortcut(_:scope:perform:)`` with ``ShortcutScope/window``
    /// to limit it to the window containing this view.
    ///
    /// - Note: Intermediate key events of a multi-step match propagate through
    ///   the responder chain and may trigger the macOS system alert sound. Check
    ///   ``ShortcutTracking/isActive`` in a `noResponder(for:)` override to
    ///   suppress the beep selectively.
    func onShortcut(_ shortcut: Shortcut?, perform action: @escaping () -> Void) -> some View {
        modifier(OnShortcutModifier(shortcut: shortcut, scope: .app, action: action))
    }

    /// Perform an action when `shortcut` is performed, limited to `scope`.
    ///
    /// With ``ShortcutScope/window`` only events sent to the window containing this
    /// view fire the action, so in an app with several windows each window's binding
    /// acts on its own window alone. ``ShortcutScope/app`` responds to every window,
    /// like ``SwiftUICore/View/onShortcut(_:perform:)``. Changing `scope` takes effect
    /// on the next event.
    ///
    /// For `.discrete` shortcuts the action fires once on completion, a multi-step
    /// sequence within the per-step timeout. For `.continuous` shortcuts it fires
    /// repeatedly, throttled by the shortcut's `sensitivity`. While an editable text
    /// responder has focus, a discrete shortcut whose first step is a bare key or a
    /// ⇧/⌥-only combination does not fire.
    func onShortcut(
        _ shortcut: Shortcut?,
        scope: ShortcutScope,
        perform action: @escaping () -> Void
    ) -> some View {
        modifier(OnShortcutModifier(shortcut: shortcut, scope: scope, action: action))
    }
}
