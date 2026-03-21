import AppKit
import Carbon.HIToolbox
import SwiftUI

/// View modifier that fires an action when a shortcut is pressed.
@available(macOS 14.0, *)
struct OnShortcutModifier: ViewModifier {
    let shortcut: Shortcut?
    let action: () -> Void

    @State private var eventMonitor: Any?

    func body(content: Content) -> some View {
        content
            .focusable()
            .onKeyPress(phases: .down) { press in
                guard let shortcut, shortcut.matches(press) else {
                    return .ignored
                }
                action()
                return .handled
            }
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

        // Only install for special keys that SwiftUI's focus system intercepts
        // before onKeyPress fires (e.g. Tab, Escape). Regular keys are handled
        // solely by onKeyPress to avoid double-firing.
        guard Self.needsEventMonitor(keyCode: shortcut.keyCode) else { return }

        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
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
    /// Keys that SwiftUI's focus system may intercept before onKeyPress fires.
    private static func needsEventMonitor(keyCode: UInt16) -> Bool {
        switch Int(keyCode) {
        case kVK_Tab, kVK_Escape:
            true
        default:
            false
        }
    }
}

// MARK: - View Extension

public extension View {
    /// Perform an action when the given shortcut is pressed.
    ///
    /// Handles both regular keys (via SwiftUI's `onKeyPress`) and special keys
    /// like Tab (via an NSEvent local monitor).
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
