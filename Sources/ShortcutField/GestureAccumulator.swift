import AppKit

/// Per-burst threshold detection for continuous trackpad gestures (magnify /
/// rotate) and scroll wheel events. Used by both `ShortcutRecorderField` and
/// `ContinuousShortcutRecorderField` so the threshold-and-direction logic lives
/// in one place.
struct GestureAccumulator {
    private(set) var pinch: Double = 0
    private(set) var rotate: Double = 0

    /// Accumulate a `.magnify` event delta, returning the captured kind once the
    /// cumulative magnification crosses the recording threshold. Returns nil while
    /// still under threshold.
    mutating func consumeMagnify(_ delta: Double) -> Shortcut.Kind? {
        pinch += delta
        guard abs(pinch) >= Shortcut.magnifyRecordingThreshold else { return nil }
        return pinch < 0 ? .pinchIn : .pinchOut
    }

    /// Accumulate a `.rotate` event delta (degrees), returning the captured kind
    /// once the cumulative rotation crosses the recording threshold.
    mutating func consumeRotate(_ delta: Double) -> Shortcut.Kind? {
        rotate += delta
        guard abs(rotate) >= Shortcut.rotateRecordingThreshold else { return nil }
        return rotate > 0 ? .rotateCounterClockwise : .rotateClockwise
    }

    mutating func resetPinch() { pinch = 0 }
    mutating func resetRotate() { rotate = 0 }
    mutating func resetAll() {
        pinch = 0
        rotate = 0
    }
}

extension Shortcut {
    /// Direction of a `.scrollWheel` event when its delta crosses the recording
    /// threshold. Returns nil for sub-threshold events (used to filter out stray
    /// trackpad twitches).
    static func scrollDirectionAboveRecordingThreshold(from event: NSEvent) -> ScrollDirection? {
        let dx = abs(event.scrollingDeltaX)
        let dy = abs(event.scrollingDeltaY)
        guard dx >= scrollRecordingThreshold || dy >= scrollRecordingThreshold else {
            return nil
        }
        return scrollDirection(from: event)
    }
}
