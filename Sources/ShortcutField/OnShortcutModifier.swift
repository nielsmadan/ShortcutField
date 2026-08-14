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

struct OnShortcutModifier: ViewModifier {
    let shortcut: Shortcut?
    let action: () -> Void

    @State private var matcher: ShortcutMatcher?
    @State private var listenerID = UUID()
    @State private var actionBox = ActionBox()

    func body(content: Content) -> some View {
        actionBox.action = action
        return content
            .onAppear { install(shortcut) }
            .onDisappear { teardown() }
            .onChange(of: shortcut) { newValue in
                teardown()
                install(newValue)
            }
    }

    /// - Parameter shortcut: passed explicitly rather than read from `self`.
    ///   The macOS 13 `onChange(of:perform:)` invokes the closure captured from
    ///   the *pre-change* body evaluation, so `self.shortcut` would still hold
    ///   the stale (usually `nil`) value here.
    private func install(_ shortcut: Shortcut?) {
        guard let shortcut else { return }
        let m = ShortcutMatcher(shortcut)
        matcher = m
        let box = actionBox
        ShortcutEventDispatcher.shared.register(id: listenerID) { event in
            let result = m.handle(event)
            switch result {
            case .fired, .continuousFired:
                box.action()
            case .advanced, .ignored:
                break
            }
            return result
        }
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
    /// - Note: Intermediate key events of a multi-step match propagate through
    ///   the responder chain and may trigger the macOS system alert sound. Check
    ///   ``ShortcutTracking/isActive`` in a `noResponder(for:)` override to
    ///   suppress the beep selectively.
    func onShortcut(_ shortcut: Shortcut?, perform action: @escaping () -> Void) -> some View {
        modifier(OnShortcutModifier(shortcut: shortcut, action: action))
    }
}
