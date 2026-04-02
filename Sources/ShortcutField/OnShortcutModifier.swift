import AppKit
import SwiftUI

/// View modifier that fires an action when a shortcut is pressed.
///
/// Uses an NSEvent local monitor to match key events globally within the app,
/// so the view does not need focus. Matching is disabled while any recorder
/// field is active.
@available(macOS 14.0, *)
struct OnShortcutModifier: ViewModifier {
    let shortcut: Shortcut?
    let action: () -> Void

    @State private var eventMonitor: Any?

    func body(content: Content) -> some View {
        content
            .onAppear {
                installMonitor()
            }
            .onDisappear {
                removeMonitor()
            }
            .onChange(of: shortcut) { _, _ in
                removeMonitor()
                installMonitor()
            }
    }

    private func installMonitor() {
        guard let shortcut, eventMonitor == nil else { return }

        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if ShortcutRecorderField.isAnyRecording {
                return event
            }
            if shortcut.matches(event) {
                action()
                return nil
            }
            return event
        }
    }

    private func removeMonitor() {
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
            self.eventMonitor = nil
        }
    }
}

// MARK: - View Extension

public extension View {
    /// Perform an action when the given shortcut is pressed.
    ///
    /// Uses an NSEvent local monitor to match key events, including special
    /// keys like Tab that SwiftUI's focus system would normally intercept.
    /// The view does not need focus. Matching is automatically disabled
    /// while any recorder field is active.
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
