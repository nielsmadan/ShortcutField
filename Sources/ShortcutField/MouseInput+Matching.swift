import AppKit

// MARK: - NSEvent Matching

public extension MouseInput {
    /// Match against an NSEvent (mouse button or scroll wheel).
    func matches(_ event: NSEvent) -> Bool {
        let eventMods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            .intersection([.shift, .control, .option, .command])
        guard eventMods == modifiers else { return false }

        switch kind {
        case let .button(number):
            guard event.type == .leftMouseDown || event.type == .rightMouseDown
                || event.type == .otherMouseDown
            else {
                return false
            }
            return event.buttonNumber == number
        case let .scroll(direction):
            guard event.type == .scrollWheel else { return false }
            return Self.scrollDirection(from: event) == direction
        }
    }

    /// Determine the discrete scroll direction from a scroll wheel event.
    ///
    /// Returns nil if the scroll deltas are below the noise threshold.
    static func scrollDirection(from event: NSEvent) -> ScrollDirection? {
        let dx = event.scrollingDeltaX
        let dy = event.scrollingDeltaY
        let threshold: CGFloat = 0.5

        if abs(dy) >= abs(dx) {
            guard abs(dy) >= threshold else { return nil }
            return dy > 0 ? .up : .down
        } else {
            guard abs(dx) >= threshold else { return nil }
            return dx > 0 ? .left : .right
        }
    }
}
