import AppKit
@testable import ShortcutField
import Testing

@MainActor
@Suite("ContinuousMatcher")
struct ContinuousMatcherTests {
    @Test("matching pinch event at full sensitivity fires with magnitude")
    func firesWithMagnitude() {
        let matcher = ContinuousMatcher(
            ContinuousShortcut(kind: .pinchOut, modifiers: [], sensitivity: 1.0)
        )
        let shape = ContinuousEventShape(type: .magnify, magnification: 0.3)
        let result = matcher.handle(shape: shape)
        #expect(result == .continuousFired(magnitude: 0.3))
    }

    @Test("non-matching event is ignored")
    func nonMatchingIgnored() {
        let matcher = ContinuousMatcher(
            ContinuousShortcut(kind: .pinchOut, modifiers: [], sensitivity: 1.0)
        )
        // pinchIn-direction magnification (negative) does not match pinchOut
        let shape = ContinuousEventShape(type: .magnify, magnification: -0.3)
        #expect(matcher.handle(shape: shape) == .ignored)
    }

    @Test("sensitivity 0 fires once, then consumes but suppresses within the gesture")
    func sensitivityZeroFiresOnce() {
        let matcher = ContinuousMatcher(
            ContinuousShortcut(kind: .pinchOut, modifiers: [], sensitivity: 0.0)
        )
        let shape = ContinuousEventShape(type: .magnify, magnification: 0.1)
        if case .continuousFired = matcher.handle(shape: shape) {} else {
            Issue.record("expected first event to fire")
        }
        #expect(matcher.handle(shape: shape) == .advanced(consumeEvent: true))
    }

    // MARK: - Scroll direction

    @Test("scroll down shortcut fires with correct magnitude")
    func scrollDownFires() {
        let matcher = ContinuousMatcher(
            ContinuousShortcut(kind: .scroll(direction: .down), modifiers: [], sensitivity: 1.0)
        )
        // dy < 0 → .down (dy > 0 is .up per the axis-dominance logic)
        let shape = ContinuousEventShape(type: .scrollWheel, scrollDeltaY: -2.0)
        #expect(matcher.handle(shape: shape) == .continuousFired(magnitude: -2.0))
    }

    @Test("scroll right shortcut fires with the deltaX magnitude")
    func scrollRightFires() {
        let matcher = ContinuousMatcher(
            ContinuousShortcut(kind: .scroll(direction: .right), modifiers: [], sensitivity: 1.0)
        )
        // dx < 0 → .right (dx > 0 is .left); magnitude comes from scrollDeltaX.
        let shape = ContinuousEventShape(type: .scrollWheel, scrollDeltaX: -2.0)
        #expect(matcher.handle(shape: shape) == .continuousFired(magnitude: -2.0))
    }

    @Test("below-threshold scroll is ignored")
    func belowThresholdScrollIgnored() {
        let matcher = ContinuousMatcher(
            ContinuousShortcut(kind: .scroll(direction: .down), modifiers: [], sensitivity: 1.0)
        )
        let shape = ContinuousEventShape(type: .scrollWheel, scrollDeltaY: 0.1)
        #expect(matcher.handle(shape: shape) == .ignored)
    }

    // MARK: - Phase-end reset

    @Test("magnify phase-end resets throttle so next gesture fires again")
    func magnifyPhaseEndResetsThrottle() {
        let matcher = ContinuousMatcher(
            ContinuousShortcut(kind: .pinchOut, modifiers: [], sensitivity: 0.0)
        )
        let matchingShape = ContinuousEventShape(type: .magnify, magnification: 0.1)
        let endShape = ContinuousEventShape(type: .magnify, phase: .ended)

        if case .continuousFired = matcher.handle(shape: matchingShape) {} else {
            Issue.record("expected first event to fire")
        }
        _ = matcher.handle(shape: endShape)
        #expect(matcher.handle(shape: matchingShape) == .continuousFired(magnitude: 0.1))
    }

    @Test("rotate phase-end resets throttle so next gesture fires again")
    func rotatePhaseEndResetsThrottle() {
        let matcher = ContinuousMatcher(
            ContinuousShortcut(kind: .rotateCounterClockwise, modifiers: [], sensitivity: 0.0)
        )
        let matchingShape = ContinuousEventShape(type: .rotate, rotation: 5.0)
        let endShape = ContinuousEventShape(type: .rotate, phase: .ended)

        if case .continuousFired = matcher.handle(shape: matchingShape) {} else {
            Issue.record("expected first event to fire")
        }
        _ = matcher.handle(shape: endShape)
        #expect(matcher.handle(shape: matchingShape) == .continuousFired(magnitude: 5.0))
    }

    @Test("scroll phase-end resets throttle so the next scroll burst fires again")
    func scrollPhaseEndResetsThrottle() {
        let matcher = ContinuousMatcher(
            ContinuousShortcut(kind: .scroll(direction: .down), modifiers: [], sensitivity: 0.0)
        )
        let matchingShape = ContinuousEventShape(type: .scrollWheel, scrollDeltaY: -2.0)
        let endShape = ContinuousEventShape(type: .scrollWheel, phase: .ended)

        if case .continuousFired = matcher.handle(shape: matchingShape) {} else {
            Issue.record("expected first event to fire")
        }
        // Without a phase-end reset the next burst's first event is throttle-suppressed.
        _ = matcher.handle(shape: endShape)
        #expect(matcher.handle(shape: matchingShape) == .continuousFired(magnitude: -2.0))
    }
}
