import AppKit

/// Test seam: a value-typed snapshot of the fields of a continuous `NSEvent`
/// (`.scrollWheel`, `.magnify`, `.rotate`) that `ContinuousMatcher` reads.
/// Gesture `NSEvent`s cannot be synthesized in tests, so the matcher's core
/// runs on this shape.
struct ContinuousEventShape: Equatable {
    var type: NSEvent.EventType
    var modifierFlags: NSEvent.ModifierFlags
    var magnification: Double
    var rotation: Double // degrees
    var scrollDeltaX: Double
    var scrollDeltaY: Double
    var phase: NSEvent.Phase

    init(
        type: NSEvent.EventType,
        modifierFlags: NSEvent.ModifierFlags = [],
        magnification: Double = 0,
        rotation: Double = 0,
        scrollDeltaX: Double = 0,
        scrollDeltaY: Double = 0,
        phase: NSEvent.Phase = []
    ) {
        self.type = type
        self.modifierFlags = modifierFlags
        self.magnification = magnification
        self.rotation = rotation
        self.scrollDeltaX = scrollDeltaX
        self.scrollDeltaY = scrollDeltaY
        self.phase = phase
    }

    init(_ event: NSEvent) {
        type = event.type
        modifierFlags = event.modifierFlags
        magnification = (event.type == .magnify) ? Double(event.magnification) : 0
        rotation = (event.type == .rotate) ? Double(event.rotation) : 0
        scrollDeltaX = (event.type == .scrollWheel) ? Double(event.scrollingDeltaX) : 0
        scrollDeltaY = (event.type == .scrollWheel) ? Double(event.scrollingDeltaY) : 0
        phase = (event.type == .magnify || event.type == .rotate || event.type == .scrollWheel)
            ? event.phase : []
    }
}

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
        return handle(shape: ContinuousEventShape(event))
    }

    func handle(shape: ContinuousEventShape) -> ShortcutMatchResult {
        // Phase-end: reset throttle so the next physical gesture starts fresh.
        let isContinuousType = shape.type == .magnify || shape.type == .rotate
            || shape.type == .scrollWheel
        if isContinuousType, shape.phase == .ended || shape.phase == .cancelled {
            if Self.eventTypeMatchesKind(shape.type, shortcut.kind) {
                throttle.reset()
            }
            return .ignored
        }

        guard matches(shape) else { return .ignored }

        var fired = false
        throttle.handleEvent { fired = true }
        // Consume even when throttled, so the gesture doesn't reach the view beneath.
        guard fired else { return .advanced(consumeEvent: true) }
        return .continuousFired(magnitude: magnitude(of: shape))
    }

    private func matches(_ shape: ContinuousEventShape) -> Bool {
        let mods = DiscreteShortcut.canonicalModifiers(shape.modifierFlags)
        guard mods == shortcut.modifiers else { return false }
        switch shortcut.kind {
        case let .scroll(direction):
            guard shape.type == .scrollWheel else { return false }
            return scrollDirection(of: shape) == direction
        case .pinchIn:
            return shape.type == .magnify && shape.magnification < -DiscreteShortcut.magnifyEventThreshold
        case .pinchOut:
            return shape.type == .magnify && shape.magnification > DiscreteShortcut.magnifyEventThreshold
        case .rotateClockwise:
            return shape.type == .rotate && shape.rotation < -DiscreteShortcut.rotateEventThreshold
        case .rotateCounterClockwise:
            return shape.type == .rotate && shape.rotation > DiscreteShortcut.rotateEventThreshold
        }
    }

    /// Signed per-event magnitude for the shortcut's kind.
    private func magnitude(of shape: ContinuousEventShape) -> Double {
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

    private func scrollDirection(of shape: ContinuousEventShape) -> DiscreteShortcut.ScrollDirection? {
        DiscreteShortcut.scrollDirection(dx: shape.scrollDeltaX, dy: shape.scrollDeltaY)
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
