import AppKit
import SwiftUI

/// Whether any `.onShortcut()` modifier with a multi-step discrete shortcut is
/// partway through matching (past step 0).
///
/// Use this in a `noResponder(for:)` override to suppress the system alert sound
/// only for key events that are part of an in-progress sequence match.
public enum ShortcutTracking {
    /// `true` when at least one `.onShortcut()` modifier has matched one or more
    /// intermediate steps and is waiting for the next event.
    @MainActor public private(set) static var isActive = false

    @MainActor fileprivate static var activeCount = 0 {
        didSet { isActive = activeCount > 0 }
    }
}

/// View modifier backing `.onShortcut`.
struct OnShortcutModifier: ViewModifier {
    let shortcut: Shortcut?
    let action: () -> Void

    @State private var matcher: ShortcutMatcher?
    @State private var listenerID = UUID()

    func body(content: Content) -> some View {
        content
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
        m.trackingStateDidChange = { isTracking in
            ShortcutTracking.activeCount += isTracking ? 1 : -1
        }
        matcher = m
        ShortcutEventDispatcher.shared.register(id: listenerID) { event in
            let result = m.handle(event)
            switch result {
            case .fired, .continuousFired:
                action()
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
