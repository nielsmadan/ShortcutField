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
        let shape = ShortcutEventShape(type: .magnify, magnification: 0.3)
        let result = matcher.handle(shape: shape)
        #expect(result == .continuousFired(magnitude: 0.3))
    }

    @Test("non-matching event is ignored")
    func nonMatchingIgnored() {
        let matcher = ContinuousMatcher(
            ContinuousShortcut(kind: .pinchOut, modifiers: [], sensitivity: 1.0)
        )
        // pinchIn-direction magnification (negative) does not match pinchOut
        let shape = ShortcutEventShape(type: .magnify, magnification: -0.3)
        #expect(matcher.handle(shape: shape) == .ignored)
    }

    @Test("sensitivity 0 fires once, then consumes but suppresses within the gesture")
    func sensitivityZeroFiresOnce() {
        let matcher = ContinuousMatcher(
            ContinuousShortcut(kind: .pinchOut, modifiers: [], sensitivity: 0.0)
        )
        let shape = ShortcutEventShape(type: .magnify, magnification: 0.1)
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
        let shape = ShortcutEventShape(type: .scrollWheel, scrollDeltaY: -2.0)
        #expect(matcher.handle(shape: shape) == .continuousFired(magnitude: -2.0))
    }

    @Test("scroll right shortcut fires with the deltaX magnitude")
    func scrollRightFires() {
        let matcher = ContinuousMatcher(
            ContinuousShortcut(kind: .scroll(direction: .right), modifiers: [], sensitivity: 1.0)
        )
        // dx < 0 → .right (dx > 0 is .left); magnitude comes from scrollDeltaX.
        let shape = ShortcutEventShape(type: .scrollWheel, scrollDeltaX: -2.0)
        #expect(matcher.handle(shape: shape) == .continuousFired(magnitude: -2.0))
    }

    @Test("below-threshold scroll is ignored")
    func belowThresholdScrollIgnored() {
        let matcher = ContinuousMatcher(
            ContinuousShortcut(kind: .scroll(direction: .down), modifiers: [], sensitivity: 1.0)
        )
        let shape = ShortcutEventShape(type: .scrollWheel, scrollDeltaY: 0.1)
        #expect(matcher.handle(shape: shape) == .ignored)
    }

    // MARK: - Phase-end reset

    @Test("magnify phase-end resets throttle so next gesture fires again")
    func magnifyPhaseEndResetsThrottle() {
        let matcher = ContinuousMatcher(
            ContinuousShortcut(kind: .pinchOut, modifiers: [], sensitivity: 0.0)
        )
        let matchingShape = ShortcutEventShape(type: .magnify, magnification: 0.1)
        let endShape = ShortcutEventShape(type: .magnify, phase: .ended)

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
        let matchingShape = ShortcutEventShape(type: .rotate, rotation: 5.0)
        let endShape = ShortcutEventShape(type: .rotate, phase: .ended)

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
        let matchingShape = ShortcutEventShape(type: .scrollWheel, scrollDeltaY: -2.0)
        let endShape = ShortcutEventShape(type: .scrollWheel, phase: .ended)

        if case .continuousFired = matcher.handle(shape: matchingShape) {} else {
            Issue.record("expected first event to fire")
        }
        // Without a phase-end reset the next burst's first event is throttle-suppressed.
        _ = matcher.handle(shape: endShape)
        #expect(matcher.handle(shape: matchingShape) == .continuousFired(magnitude: -2.0))
    }

    // MARK: - Trackpad bursts

    @Test("a scroll burst at sensitivity 0 fires once, consumes the rest and its momentum, and fires again next burst")
    func phasedScrollBurstAtSensitivityZero() {
        let matcher = ContinuousMatcher(
            ContinuousShortcut(kind: .scroll(direction: .up), modifiers: [], sensitivity: 0.0)
        )
        let consumed = ShortcutMatchResult.advanced(consumeEvent: true)
        #expect(matcher.handle(scrollEvent(deltaY: 10, phase: .began)) == .continuousFired(magnitude: 10))
        #expect(matcher.handle(scrollEvent(deltaY: 10, phase: .changed)) == consumed)
        #expect(matcher.handle(scrollEvent(phase: .ended)) == .ignored)
        #expect(matcher.handle(scrollEvent(deltaY: 10, momentum: .began)) == consumed)
        #expect(matcher.handle(scrollEvent(momentum: .ended)) == consumed)
        #expect(matcher.handle(scrollEvent(deltaY: 10, momentum: .began)) == .ignored)
        #expect(matcher.handle(scrollEvent(deltaY: 10, phase: .began)) == .continuousFired(magnitude: 10))
    }

    @Test("a scroll burst that never matches passes through with its momentum")
    func unmatchedScrollBurstPassesThrough() {
        let matcher = ContinuousMatcher(
            ContinuousShortcut(kind: .scroll(direction: .up), modifiers: [], sensitivity: 0.0)
        )
        #expect(matcher.handle(scrollEvent(deltaY: -10, phase: .began)) == .ignored)
        #expect(matcher.handle(scrollEvent(phase: .ended)) == .ignored)
        #expect(matcher.handle(scrollEvent(deltaY: -10, momentum: .began)) == .ignored)
    }

    @Test("a new burst ends the coast of an earlier matched one, even if its own end never arrives")
    func newBurstStopsCoast() {
        let matcher = ContinuousMatcher(
            ContinuousShortcut(kind: .scroll(direction: .up), modifiers: [], sensitivity: 0.0)
        )
        #expect(matcher.handle(scrollEvent(deltaY: 10, phase: .began)) == .continuousFired(magnitude: 10))
        #expect(matcher.handle(scrollEvent(phase: .ended)) == .ignored)
        #expect(matcher.handle(scrollEvent(deltaY: 10, momentum: .began)) == .advanced(consumeEvent: true))
        #expect(matcher.handle(scrollEvent(deltaY: -10, phase: .began)) == .ignored)
        #expect(matcher.handle(scrollEvent(deltaY: -10, momentum: .began)) == .ignored)
    }

    @Test("a mid sensitivity fires, then consumes events inside its cooldown")
    func midSensitivityCoolsDown() {
        let matcher = ContinuousMatcher(
            ContinuousShortcut(kind: .scroll(direction: .up), modifiers: [], sensitivity: 0.5)
        )
        #expect(matcher.handle(scrollEvent(deltaY: 10, phase: .began)) == .continuousFired(magnitude: 10))
        #expect(matcher.handle(scrollEvent(deltaY: 10, phase: .changed)) == .advanced(consumeEvent: true))
    }

    // MARK: - A claimed burst

    @Test("the rest of a burst that matched is consumed even where it stops matching")
    func claimedBurstConsumesItsRest() {
        let matcher = ContinuousMatcher(
            ContinuousShortcut(kind: .scroll(direction: .up), modifiers: .command, sensitivity: 1.0)
        )
        let up = ShortcutEventShape(type: .scrollWheel, modifierFlags: .command, scrollDeltaY: 5, phase: .began)
        #expect(matcher.handle(shape: up) == .continuousFired(magnitude: 5))

        for rest in [
            ShortcutEventShape(type: .scrollWheel, modifierFlags: .command, scrollDeltaY: -5, phase: .changed),
            ShortcutEventShape(type: .scrollWheel, modifierFlags: .command, scrollDeltaY: 0, phase: .changed),
            ShortcutEventShape(type: .scrollWheel, scrollDeltaY: 5, phase: .changed),
        ] {
            #expect(matcher.handle(shape: rest) == .advanced(consumeEvent: true))
        }
        // Other gesture types and mouse-wheel notches belong to no claimed scroll burst.
        let pinch = ShortcutEventShape(type: .magnify, magnification: 0.1, phase: .changed)
        #expect(matcher.handle(shape: pinch) == .ignored)
        #expect(matcher.handle(shape: ShortcutEventShape(type: .scrollWheel, scrollDeltaY: -5)) == .ignored)
        #expect(matcher.handle(shape: ShortcutEventShape(type: .scrollWheel, phase: .ended)) == .ignored)
    }

    @Test("a burst that never matched passes through")
    func unclaimedBurstPassesThrough() {
        let matcher = ContinuousMatcher(
            ContinuousShortcut(kind: .scroll(direction: .up), modifiers: .command, sensitivity: 1.0)
        )
        let down = ShortcutEventShape(type: .scrollWheel, modifierFlags: .command, scrollDeltaY: -5, phase: .began)

        #expect(matcher.handle(shape: down) == .ignored)
        #expect(matcher
            .handle(shape: ShortcutEventShape(type: .scrollWheel, scrollDeltaY: 5, phase: .changed)) == .ignored)
    }
}
