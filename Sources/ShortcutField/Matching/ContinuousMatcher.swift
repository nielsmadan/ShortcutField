import AppKit

/// Matches a single `ContinuousShortcut` against a stream of continuous gesture
/// events, applying the shortcut's `sensitivity` throttle. Internal — wrapped by
/// the public `ShortcutMatcher`.
@MainActor
final class ContinuousMatcher {
    private let shortcut: ContinuousShortcut
    private let throttle = ThrottleState()

    init(_ shortcut: ContinuousShortcut) {
        self.shortcut = shortcut
        throttle.sensitivity = shortcut.sensitivity
    }

    func reset() {
        throttle.reset()
    }

    func handle(_ event: NSEvent) -> ShortcutMatchResult {
        if event.type == .scrollWheel, event.momentumPhase != [] {
            return .ignored
        }
        return handle(shape: ShortcutEventShape(event))
    }

    func handle(shape: ShortcutEventShape) -> ShortcutMatchResult {
        // Phase-end: reset throttle so the next physical gesture starts fresh.
        let isContinuousType = shape.type == .magnify || shape.type == .rotate
            || shape.type == .scrollWheel
        if isContinuousType, shape.phase == .ended || shape.phase == .cancelled {
            if Self.eventTypeMatchesKind(shape.type, shortcut.kind) {
                throttle.reset()
            }
            return .ignored
        }

        guard shortcut.asDiscreteStep.matches(shape) else { return .ignored }

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
