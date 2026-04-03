import AppKit
import SwiftUI

struct ScrollThrottleDecision: Equatable {
    var shouldFire: Bool
    var rearmAfter: Duration?
}

@MainActor
final class ScrollThrottleState {
    var sensitivity: Double = 0.0
    var lastFireInstant: ContinuousClock.Instant?
    var suppressed = false
    var rearmWorkItem: DispatchWorkItem?

    func reset() {
        lastFireInstant = nil
        suppressed = false
        rearmWorkItem?.cancel()
        rearmWorkItem = nil
    }

    /// Cooldown in seconds for a sensitivity value in (0, 1).
    nonisolated static func cooldownSeconds(for sensitivity: Double) -> Double {
        max(0, (1.0 - sensitivity) / 0.75)
    }

    // Mutates state.suppressed / .lastFireInstant as side effects; no I/O, no time reads.
    static func evaluate(
        state: ScrollThrottleState,
        now: ContinuousClock.Instant
    ) -> ScrollThrottleDecision {
        let sensitivity = state.sensitivity

        if sensitivity >= 1.0 {
            state.lastFireInstant = now
            return ScrollThrottleDecision(shouldFire: true, rearmAfter: nil)
        }

        if sensitivity <= 0.0 {
            let fire = !state.suppressed
            state.suppressed = true
            return ScrollThrottleDecision(shouldFire: fire, rearmAfter: .milliseconds(350))
        }

        let cooldown: Duration = .seconds(cooldownSeconds(for: sensitivity))
        if let last = state.lastFireInstant, (now - last) < cooldown {
            return ScrollThrottleDecision(shouldFire: false, rearmAfter: nil)
        }
        state.lastFireInstant = now
        return ScrollThrottleDecision(shouldFire: true, rearmAfter: nil)
    }
}

/// View modifier that fires an action when a mouse input is detected.
///
/// Uses an NSEvent local monitor to match mouse button and scroll wheel events
/// globally within the app, so the view does not need focus. Matching is disabled
/// while any recorder field is active. Scroll events are throttled according to
/// the input's `scrollSensitivity` value.
@available(macOS 14.0, *)
struct OnMouseInputModifier: ViewModifier {
    let mouseInput: MouseInput?
    let action: () -> Void

    @State private var eventMonitor: Any?
    @State private var throttleState = ScrollThrottleState()

    func body(content: Content) -> some View {
        content
            .onAppear {
                throttleState.sensitivity = mouseInput?.scrollSensitivity ?? 0.0
                installMonitor()
            }
            .onDisappear {
                removeMonitor()
                throttleState.reset()
            }
            .onChange(of: mouseInput) { old, new in
                throttleState.sensitivity = new?.scrollSensitivity ?? 0.0
                throttleState.reset()
                if old?.kind != new?.kind || old?.modifiers != new?.modifiers {
                    removeMonitor()
                    installMonitor()
                }
            }
    }

    private func installMonitor() {
        guard let mouseInput, eventMonitor == nil else { return }

        let throttle = throttleState

        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [
            .leftMouseDown,
            .rightMouseDown,
            .otherMouseDown,
            .scrollWheel,
        ]) { event in
            if ShortcutRecordingState.isAnyRecording {
                return event
            }
            guard mouseInput.matches(event) else {
                return event
            }
            if event.type == .scrollWheel {
                // Skip trackpad momentum — OS after-effect of the gesture, not a new gesture.
                if event.momentumPhase != [] {
                    return nil
                }
                Self.handleScroll(throttle: throttle, action: action)
                return nil
            }
            action()
            return nil
        }
    }

    private static func handleScroll(throttle: ScrollThrottleState, action: () -> Void) {
        let decision = ScrollThrottleState.evaluate(state: throttle, now: .now)
        if decision.shouldFire {
            action()
        }
        if let delay = decision.rearmAfter {
            throttle.rearmWorkItem?.cancel()
            let workItem = DispatchWorkItem {
                MainActor.assumeIsolated {
                    throttle.suppressed = false
                }
            }
            throttle.rearmWorkItem = workItem
            let milliseconds = Int(delay.components.seconds * 1000
                + delay.components.attoseconds / 1_000_000_000_000_000)
            DispatchQueue.main.asyncAfter(
                deadline: .now() + .milliseconds(milliseconds),
                execute: workItem
            )
        }
    }

    private func removeMonitor() {
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
            self.eventMonitor = nil
        }
    }
}

public extension View {
    /// Perform an action when the given mouse input is detected.
    ///
    /// Uses an NSEvent local monitor to match mouse button and scroll wheel
    /// events globally within the app. The view does not need focus. Matching
    /// is automatically disabled while any recorder field is active.
    /// Scroll events are throttled according to the input's `scrollSensitivity`.
    ///
    /// ```swift
    /// MyView()
    ///     .onMouseInput(mouseInput) {
    ///         print("Mouse input fired!")
    ///     }
    /// ```
    @available(macOS 14.0, *)
    func onMouseInput(_ mouseInput: MouseInput?, perform action: @escaping () -> Void) -> some View {
        modifier(OnMouseInputModifier(mouseInput: mouseInput, action: action))
    }
}
