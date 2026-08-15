import AppKit

/// Test seam: a value-typed snapshot of the `NSEvent` fields that scroll and
/// gesture matching reads. Gesture `NSEvent`s cannot be synthesized in tests, so
/// both matchers run their thresholds against this shape.
struct ShortcutEventShape: Equatable {
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
