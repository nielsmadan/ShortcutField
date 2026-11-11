import AppKit

/// Matches a single `ContinuousShortcut` against a stream of continuous gesture
/// events, applying the shortcut's `sensitivity` throttle. Internal — wrapped by
/// the public `ShortcutMatcher`.
@MainActor
final class ContinuousMatcher {
    private let shortcut: ContinuousShortcut
    private let throttle = ThrottleState()
    /// The burst that matched the shortcut: its rest, and its scroll momentum, are consumed.
    private var bursts = GestureBurstTracker()
    private var scrollCoast = ScrollCoast()
    private var isInterrupted = false

    init(_ shortcut: ContinuousShortcut) {
        self.shortcut = shortcut
        throttle.sensitivity = shortcut.sensitivity
    }

    func interrupt() {
        throttle.reset()
        isInterrupted = bursts.hasClaims
    }

    func reset() {
        isInterrupted = false
        throttle.reset()
        bursts.reset()
        scrollCoast.stop()
    }

    func handle(_ event: NSEvent) -> ShortcutMatchResult {
        if event.isMomentumScroll {
            return scrollCoast.consumeMomentum(event.momentumPhase) ? .advanced(consumeEvent: true) : .ignored
        }
        return handle(shape: ShortcutEventShape(event))
    }

    func handle(shape: ShortcutEventShape) -> ShortcutMatchResult {
        // Bursts of other event types are never this shortcut's.
        let position = Self.eventTypeMatchesKind(shape.type, shortcut.kind) ? bursts.track(shape) : nil
        if shape.type == .scrollWheel, let position {
            scrollCoast.follow(position)
        }
        if case .start = position {
            isInterrupted = false
        }
        if isInterrupted, position == .middle(.consumesRest) {
            return .advanced(consumeEvent: true)
        }
        if case .end = position {
            isInterrupted = false
            // Reset the throttle so the next physical gesture starts fresh. The end itself
            // reaches the view beneath so that view can close the gesture.
            throttle.reset()
            return .ignored
        }

        guard shortcut.asDiscreteStep.matches(shape) else {
            // The rest of a burst this shortcut claimed stays with it, even where a delta
            // reverses or a modifier is released.
            return position == .middle(.consumesRest) ? .advanced(consumeEvent: true) : .ignored
        }
        bursts.claim(shape, .consumesRest)

        var fired = false
        throttle.handleEvent { fired = true }
        // Consume even when throttled, so the gesture doesn't reach the view beneath.
        guard fired else { return .advanced(consumeEvent: true) }
        return .continuousFired(magnitude: magnitude(of: shape))
    }

    /// Signed per-event magnitude for the shortcut's kind.
    private func magnitude(of shape: ShortcutEventShape) -> Double {
        switch shortcut.kind {
        case let .scroll(direction):
            switch direction {
            case .up, .down: shape.scrollDeltaY
            case .left, .right: shape.scrollDeltaX
            }
        case .pinchIn, .pinchOut:
            shape.magnification
        case .rotateClockwise, .rotateCounterClockwise:
            shape.rotation
        }
    }

    private static func eventTypeMatchesKind(
        _ eventType: NSEvent.EventType,
        _ kind: ContinuousShortcut.Kind
    ) -> Bool {
        switch (eventType, kind) {
        case (.magnify, .pinchIn), (.magnify, .pinchOut): true
        case (.rotate, .rotateClockwise), (.rotate, .rotateCounterClockwise): true
        case (.scrollWheel, .scroll): true
        default: false
        }
    }
}
