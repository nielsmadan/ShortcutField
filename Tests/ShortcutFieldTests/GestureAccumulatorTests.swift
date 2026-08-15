import AppKit
@testable import ShortcutField
import Testing

// MARK: - Magnify

@Test func gestureAccumulator_magnify_belowThreshold_returnsNil() {
    var acc = GestureAccumulator()
    let result = acc.consumeMagnify(0.01) // well below DiscreteShortcut.magnifyRecordingThreshold
    #expect(result == nil)
    #expect(acc.pinch == 0.01)
}

@Test func gestureAccumulator_magnify_negativeAtThreshold_returnsPinchIn() {
    var acc = GestureAccumulator()
    let result = acc.consumeMagnify(-DiscreteShortcut.magnifyRecordingThreshold)
    #expect(result == .pinchIn)
}

@Test func gestureAccumulator_magnify_positiveAtThreshold_returnsPinchOut() {
    var acc = GestureAccumulator()
    let result = acc.consumeMagnify(DiscreteShortcut.magnifyRecordingThreshold)
    #expect(result == .pinchOut)
}

@Test func gestureAccumulator_magnify_cumulativeCrossesThreshold() {
    var acc = GestureAccumulator()
    let halfThreshold = DiscreteShortcut.magnifyRecordingThreshold / 2
    #expect(acc.consumeMagnify(-halfThreshold) == nil)
    #expect(acc.consumeMagnify(-halfThreshold) == .pinchIn)
}

@Test func gestureAccumulator_magnify_oppositeSignsCancel() {
    var acc = GestureAccumulator()
    _ = acc.consumeMagnify(DiscreteShortcut.magnifyRecordingThreshold * 0.9)
    let result = acc.consumeMagnify(-DiscreteShortcut.magnifyRecordingThreshold * 0.9)
    #expect(result == nil)
    #expect(abs(acc.pinch) < 0.001)
}

// MARK: - Rotate

@Test func gestureAccumulator_rotate_belowThreshold_returnsNil() {
    var acc = GestureAccumulator()
    let result = acc.consumeRotate(0.5) // below DiscreteShortcut.rotateRecordingThreshold
    #expect(result == nil)
}

@Test func gestureAccumulator_rotate_positiveAtThreshold_returnsCounterClockwise() {
    var acc = GestureAccumulator()
    let result = acc.consumeRotate(DiscreteShortcut.rotateRecordingThreshold)
    #expect(result == .rotateCounterClockwise)
}

@Test func gestureAccumulator_rotate_negativeAtThreshold_returnsClockwise() {
    var acc = GestureAccumulator()
    let result = acc.consumeRotate(-DiscreteShortcut.rotateRecordingThreshold)
    #expect(result == .rotateClockwise)
}

@Test func gestureAccumulator_rotate_cumulativeCrossesThreshold() {
    var acc = GestureAccumulator()
    let halfThreshold = DiscreteShortcut.rotateRecordingThreshold / 2
    #expect(acc.consumeRotate(halfThreshold) == nil)
    #expect(acc.consumeRotate(halfThreshold) == .rotateCounterClockwise)
}

// MARK: - Reset isolation

@Test func gestureAccumulator_resetPinch_doesNotResetRotate() {
    var acc = GestureAccumulator()
    _ = acc.consumeMagnify(0.02)
    _ = acc.consumeRotate(1.5)
    acc.resetPinch()
    #expect(acc.pinch == 0)
    #expect(acc.rotate == 1.5)
}

@Test func gestureAccumulator_resetRotate_doesNotResetPinch() {
    var acc = GestureAccumulator()
    _ = acc.consumeMagnify(0.02)
    _ = acc.consumeRotate(1.5)
    acc.resetRotate()
    #expect(acc.pinch == 0.02)
    #expect(acc.rotate == 0)
}

@Test func gestureAccumulator_resetAll_clearsBoth() {
    var acc = GestureAccumulator()
    _ = acc.consumeMagnify(0.02)
    _ = acc.consumeRotate(1.5)
    acc.resetAll()
    #expect(acc.pinch == 0)
    #expect(acc.rotate == 0)
}

// MARK: - scrollDirectionAboveRecordingThreshold

// CGEvent is not thread-safe. `@MainActor` at struct level serializes this suite
// against the other @MainActor suites that touch CGEvent / TIS / NSSearchField —
// `.serialized` alone only serializes tests within the suite, not across suites.
@MainActor
@Suite(.serialized) struct ScrollDirectionThresholdTests {
    @Test func scrollDirectionAboveRecordingThreshold_belowThreshold_returnsNil() {
        // deltaY = 1 is well below DiscreteShortcut.scrollRecordingThreshold.
        #expect(DiscreteShortcut.scrollDirectionAboveRecordingThreshold(from: scrollEvent(deltaY: 1)) == nil)
    }

    @Test func scrollDirectionAboveRecordingThreshold_positiveY_returnsUp() {
        #expect(DiscreteShortcut.scrollDirectionAboveRecordingThreshold(from: scrollEvent(deltaY: 10)) == .up)
    }

    @Test func scrollDirectionAboveRecordingThreshold_negativeY_returnsDown() {
        #expect(DiscreteShortcut.scrollDirectionAboveRecordingThreshold(from: scrollEvent(deltaY: -10)) == .down)
    }

    @Test func scrollDirectionAboveRecordingThreshold_positiveX_returnsLeft() {
        // CGEvent's wheel2 (X axis) sign and direction map to .left for positive.
        #expect(DiscreteShortcut.scrollDirectionAboveRecordingThreshold(from: scrollEvent(deltaX: 10)) == .left)
    }

    @Test func scrollDirectionAboveRecordingThreshold_negativeX_returnsRight() {
        #expect(DiscreteShortcut.scrollDirectionAboveRecordingThreshold(from: scrollEvent(deltaX: -10)) == .right)
    }
}
