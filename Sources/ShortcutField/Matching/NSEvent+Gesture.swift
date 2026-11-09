import AppKit

extension NSEvent.Phase {
    /// The first event of a trackpad burst (`.mayBegin` comes first when fingers touch down).
    var startsGesture: Bool {
        !isDisjoint(with: [.began, .mayBegin])
    }

    /// The last event of a trackpad burst or of its momentum.
    var endsGesture: Bool {
        !isDisjoint(with: [.ended, .cancelled])
    }
}

extension NSEvent.EventType {
    /// Magnify, rotate or scroll-wheel: the types that come in phased trackpad bursts.
    /// `NSEvent.phase` is valid only for these; reading it on a key or mouse event throws.
    var isContinuousGesture: Bool {
        self == .magnify || self == .rotate || self == .scrollWheel
    }
}

extension NSEvent {
    /// A scroll-wheel event of the momentum coast after a trackpad burst.
    var isMomentumScroll: Bool {
        type == .scrollWheel && momentumPhase != []
    }
}
