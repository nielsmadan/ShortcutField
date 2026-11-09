import AppKit

/// The scroll momentum that coasts after a trackpad burst a matcher consumed: consumed too,
/// until its last event, so the content beneath doesn't drift after the shortcut fired.
struct ScrollCoast {
    private var isCoasting = false

    /// Whether to consume a momentum event in `momentumPhase`; the momentum's last event ends the coast.
    mutating func consumeMomentum(_ momentumPhase: NSEvent.Phase) -> Bool {
        guard isCoasting else { return false }
        if momentumPhase.endsGesture {
            isCoasting = false
        }
        return true
    }

    /// Follows a scroll burst: its start ends any earlier coast, and its end starts a coast when the
    /// rest of the burst was consumed.
    mutating func follow(_ position: GestureBurstTracker.Position) {
        switch position {
        case .start:
            isCoasting = false
        case let .end(claim):
            isCoasting = claim == .consumesRest
        case .unphased, .middle:
            break
        }
    }

    /// The matcher reset, so any coast is over.
    mutating func stop() {
        isCoasting = false
    }
}
