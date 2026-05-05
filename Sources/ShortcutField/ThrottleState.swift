import Foundation

struct ThrottleDecision: Equatable {
    var shouldFire: Bool
    var rearmAfter: Duration?
}

@MainActor
final class ThrottleState {
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

    /// Evaluate against `now` and fire the action if the throttle decision allows it.
    /// If the decision requests a rearm delay, schedule the suppression flag to clear
    /// after that delay (cancelling any prior pending rearm).
    func handleEvent(action: () -> Void) {
        let decision = ThrottleState.evaluate(state: self, now: .now)
        if decision.shouldFire {
            action()
        }
        guard let delay = decision.rearmAfter else { return }
        rearmWorkItem?.cancel()
        let workItem = DispatchWorkItem {
            MainActor.assumeIsolated { self.suppressed = false }
        }
        rearmWorkItem = workItem
        let milliseconds = Int(delay.components.seconds * 1000
            + delay.components.attoseconds / 1_000_000_000_000_000)
        DispatchQueue.main.asyncAfter(
            deadline: .now() + .milliseconds(milliseconds),
            execute: workItem
        )
    }

    /// Cooldown in seconds for a sensitivity value in (0, 1).
    nonisolated static func cooldownSeconds(for sensitivity: Double) -> Double {
        max(0, (1.0 - sensitivity) / 0.75)
    }

    // Mutates state.suppressed / .lastFireInstant as side effects; no I/O, no time reads.
    static func evaluate(
        state: ThrottleState,
        now: ContinuousClock.Instant
    ) -> ThrottleDecision {
        let sensitivity = state.sensitivity

        if sensitivity >= 1.0 {
            state.lastFireInstant = now
            return ThrottleDecision(shouldFire: true, rearmAfter: nil)
        }

        if sensitivity <= 0.0 {
            let fire = !state.suppressed
            state.suppressed = true
            return ThrottleDecision(shouldFire: fire, rearmAfter: .milliseconds(350))
        }

        let cooldown: Duration = .seconds(cooldownSeconds(for: sensitivity))
        if let last = state.lastFireInstant, (now - last) < cooldown {
            return ThrottleDecision(shouldFire: false, rearmAfter: nil)
        }
        state.lastFireInstant = now
        return ThrottleDecision(shouldFire: true, rearmAfter: nil)
    }
}
