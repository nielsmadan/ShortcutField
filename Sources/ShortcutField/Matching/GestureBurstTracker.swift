import AppKit

/// The phased trackpad bursts a matcher or recorder has claimed, per event type. A burst runs from
/// `.mayBegin`/`.began` to `.ended`/`.cancelled`; its start also drops a claim left by a burst
/// whose end never arrived (the app lost focus mid-gesture).
struct GestureBurstTracker {
    /// What happens to the rest of a claimed burst. The tracker only stores it and the matchers act
    /// on it. The fire-once recorder consumes every event anyway, so it claims with the default and
    /// reads back only whether a burst is claimed.
    enum Claim: Equatable {
        /// Its remaining events are consumed.
        case consumesRest
        /// Its remaining events are ignored, and reach the view beneath.
        case ignoresRest
    }

    /// Where an event sits in its burst.
    enum Position: Equatable {
        /// A phase-less event, such as a mouse-wheel notch, which belongs to no burst.
        case unphased
        case start
        /// Within the burst, with the claim on it, if any.
        case middle(Claim?)
        /// The burst's last event, with the claim it held.
        case end(Claim?)
    }

    private var claims: [NSEvent.EventType: Claim] = [:]

    /// Places an event within its burst, and drops the claim on its type when the burst starts or
    /// ends.
    mutating func track(_ shape: ShortcutEventShape) -> Position {
        let phase = shape.phase
        if phase == [] {
            return .unphased
        }
        if phase.startsGesture {
            claims[shape.type] = nil
            return .start
        }
        if phase.endsGesture {
            return .end(claims.removeValue(forKey: shape.type))
        }
        return .middle(claims[shape.type])
    }

    /// Claims the burst `shape` belongs to, for an event `track` placed at its start or middle. A
    /// phase-less event, such as a mouse-wheel notch, belongs to no burst and claims nothing.
    mutating func claim(_ shape: ShortcutEventShape, _ claim: Claim = .consumesRest) {
        guard shape.phase != [] else { return }
        claims[shape.type] = claim
    }

    func isClaimed(_ type: NSEvent.EventType) -> Bool {
        claims[type] != nil
    }

    /// Drops every claim except the one on `type`.
    mutating func keepOnly(_ type: NSEvent.EventType) {
        claims = claims.filter { $0.key == type }
    }

    mutating func reset() {
        claims.removeAll()
    }
}
