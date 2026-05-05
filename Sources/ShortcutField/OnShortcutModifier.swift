import AppKit
import SwiftUI

/// View modifier that fires an action when a shortcut is detected.
///
/// Uses an NSEvent local monitor to match all relevant event types (key,
/// mouse, scroll, gesture) globally within the app, so the view does not need
/// focus. Matching is disabled while any recorder field is active. Continuous
/// kinds (scroll, pinch, rotate) are throttled per the shortcut's `sensitivity`.
@available(macOS 14.0, *)
struct OnShortcutModifier: ViewModifier {
    let shortcut: Shortcut?
    let action: () -> Void

    @State private var eventMonitor: Any?
    @State private var throttleState = ThrottleState()

    func body(content: Content) -> some View {
        content
            .onAppear {
                throttleState.sensitivity = shortcut?.sensitivity ?? 0.0
                installMonitor()
            }
            .onDisappear {
                removeMonitor()
                throttleState.reset()
            }
            .onChange(of: shortcut) { old, new in
                throttleState.sensitivity = new?.sensitivity ?? 0.0
                throttleState.reset()
                if old?.kind != new?.kind || old?.modifiers != new?.modifiers {
                    removeMonitor()
                    installMonitor()
                }
            }
    }

    private func installMonitor() {
        guard let shortcut, eventMonitor == nil else { return }
        let throttle = throttleState

        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [
            .keyDown,
            .leftMouseDown,
            .rightMouseDown,
            .otherMouseDown,
            .scrollWheel,
            .magnify,
            .rotate,
            .smartMagnify,
        ]) { event in
            if ShortcutRecordingState.isAnyRecording {
                return event
            }

            // Skip trackpad scroll momentum entirely — system-driven inertial events.
            // Always pass through so unrelated views (e.g. ScrollView) keep receiving them;
            // never consume here, even if `shortcut.matches(event)` would be true.
            if event.type == .scrollWheel, event.momentumPhase != [] {
                return event
            }

            // Reset throttle on gesture end so the next physical gesture starts fresh.
            // `phase` is only meaningful for .magnify and .rotate; .smartMagnify is
            // discrete and we don't see end-phase events for it.
            let isContinuousType = event.type == .magnify || event.type == .rotate
            if isContinuousType, event.phase == .ended || event.phase == .cancelled {
                // Only reset if the bound shortcut actually corresponds to this event type;
                // a stray rotate-ended shouldn't wipe a scroll shortcut's throttle.
                if Self.eventTypeMatchesContinuousKind(event.type, shortcut.kind) {
                    throttle.reset()
                }
                return event
            }

            guard shortcut.matches(event) else {
                return event
            }

            if Shortcut.isContinuous(shortcut.kind) {
                throttle.handleEvent(action: action)
            } else {
                action()
            }
            return nil
        }
    }

    private func removeMonitor() {
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
            self.eventMonitor = nil
        }
    }

    /// Whether a continuous gesture event type (.magnify / .rotate) corresponds to
    /// the bound shortcut's kind. Used to scope throttle resets so a stray
    /// rotate-ended event doesn't wipe a scroll shortcut's throttle.
    private static func eventTypeMatchesContinuousKind(
        _ eventType: NSEvent.EventType,
        _ kind: Shortcut.Kind
    ) -> Bool {
        switch (eventType, kind) {
        case (.magnify, .pinchIn), (.magnify, .pinchOut): true
        case (.rotate, .rotateClockwise), (.rotate, .rotateCounterClockwise): true
        default: false
        }
    }
}

// MARK: - View Extension

public extension View {
    /// Perform an action when the given shortcut is detected.
    ///
    /// Uses an `NSEvent` local monitor to match key, mouse, scroll, and trackpad
    /// gesture events globally within the app, including special keys like Tab
    /// that SwiftUI's focus system would normally intercept. The view does not
    /// need focus. Matching is automatically disabled while any recorder field
    /// is active. Continuous kinds (scroll, pinch, rotate) are throttled per
    /// the shortcut's `sensitivity`.
    ///
    /// ```swift
    /// MyView()
    ///     .onShortcut(shortcut) {
    ///         print("Shortcut fired!")
    ///     }
    /// ```
    @available(macOS 14.0, *)
    func onShortcut(_ shortcut: Shortcut?, perform action: @escaping () -> Void) -> some View {
        modifier(OnShortcutModifier(shortcut: shortcut, action: action))
    }
}
