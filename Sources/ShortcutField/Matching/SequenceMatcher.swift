import AppKit
import Carbon.HIToolbox

@MainActor
final class SequenceMatcher {
    private var shortcut: DiscreteShortcut?
    private var timeoutTask: Task<Void, Never>?

    /// Event types of continuous gestures (`.magnify`, `.rotate`, `.scrollWheel`) that
    /// have already advanced the matcher past a step within the current physical burst.
    /// Subsequent events of the same type are suppressed so a single trackpad burst
    /// doesn't re-fire the matcher. Entries are cleared on the gesture's end-phase
    /// event so the next physical burst can advance the matcher again.
    ///
    /// A Set (rather than a single optional) supports overlapping bursts — e.g. a
    /// shortcut `[PinchIn, RotateClockwise]` where the rotate-step's matching event
    /// arrives while the pinch's end-phase hasn't fired yet.
    private var inProgressContinuousEventTypes: Set<NSEvent.EventType> = []

    private(set) var currentStep = 0
    private(set) var isTracking = false {
        didSet {
            guard isTracking != oldValue else { return }
            ShortcutTracking.activeCount += isTracking ? 1 : -1
            trackingStateDidChange?(isTracking)
        }
    }

    let stepTimeout: TimeInterval
    var trackingStateDidChange: ((Bool) -> Void)?

    /// Test hook: the in-flight per-step timeout task, if any. Awaiting its
    /// `value` lets a test observe the timeout-driven reset deterministically,
    /// without racing a wall-clock sleep.
    var pendingTimeoutTask: Task<Void, Never>? { timeoutTask }

    init(stepTimeout: TimeInterval = 1.0) {
        self.stepTimeout = stepTimeout
    }

    // Released only from main-actor code; `reset()` may never be called mid-sequence.
    deinit {
        MainActor.assumeIsolated {
            if isTracking { ShortcutTracking.activeCount -= 1 }
        }
    }

    func configure(shortcut: DiscreteShortcut?) {
        reset()
        self.shortcut = shortcut
    }

    func handle(_ event: NSEvent) -> ShortcutMatchResult {
        guard let shortcut else { return .ignored }

        if let preempt = preempt(event) { return preempt }

        let step = shortcut.steps[currentStep]
        guard step.matches(event) else {
            // Continuous-gesture bursts emit many sub-threshold or wrong-direction
            // events; treat those as non-resetting.
            if !Self.isContinuousEventType(event.type) {
                reset()
            }
            return .ignored
        }

        let suppressType = suppressionTypeIfContinuous(event: event, step: step)
        let isLast = currentStep == shortcut.steps.count - 1
        if isLast {
            reset()
            if let suppressType { inProgressContinuousEventTypes.insert(suppressType) }
            return .fired
        }

        currentStep += 1
        beginTracking()
        restartTimeout()
        if let suppressType { inProgressContinuousEventTypes.insert(suppressType) }

        // `event.keyCode` is only valid for keyboard events; calling it on a
        // mouse, scroll, or gesture event throws.
        let consumeEvent = (event.type == .keyDown)
            && Self.isInterceptedByFocusSystem(keyCode: event.keyCode)
        return .advanced(consumeEvent: consumeEvent)
    }

    /// Events that must not reach the step matcher.
    private func preempt(_ event: NSEvent) -> ShortcutMatchResult? {
        if Self.isContinuousEventType(event.type),
           event.phase == .ended || event.phase == .cancelled
        {
            inProgressContinuousEventTypes.remove(event.type)
            return .ignored
        }
        if event.type == .scrollWheel, event.momentumPhase != [] {
            return .ignored
        }
        if inProgressContinuousEventTypes.contains(event.type) {
            return .ignored
        }
        return nil
    }

    /// If the matching event is a phased continuous gesture for a continuous-kind
    /// step, return the event type to insert into the suppression set so subsequent
    /// events of the same physical burst don't re-fire the matcher. Mouse-wheel
    /// notches have empty phase and intentionally never suppress.
    ///
    /// `event.phase` is only valid for gesture / scroll-wheel events; calling it
    /// on a key or mouse event throws. Guard via `isContinuousEventType`.
    private func suppressionTypeIfContinuous(event: NSEvent, step: DiscreteShortcut.Step) -> NSEvent.EventType? {
        guard DiscreteShortcut.isContinuous(step.kind),
              Self.isContinuousEventType(event.type),
              event.phase != []
        else { return nil }
        return event.type
    }

    private static func isContinuousEventType(_ type: NSEvent.EventType) -> Bool {
        type == .magnify || type == .rotate || type == .scrollWheel
    }

    func reset() {
        currentStep = 0
        isTracking = false
        inProgressContinuousEventTypes.removeAll()
        timeoutTask?.cancel()
        timeoutTask = nil
    }

    private func beginTracking() {
        isTracking = true
    }

    private func restartTimeout() {
        timeoutTask?.cancel()
        timeoutTask = Task { @MainActor [weak self] in
            do {
                guard let self else { return }
                try await Task.sleep(for: .seconds(stepTimeout))
                reset()
            } catch {}
        }
    }

    /// Keys that the focus system intercepts before the responder chain.
    /// These must be consumed on intermediate matches to prevent focus changes.
    private static func isInterceptedByFocusSystem(keyCode: UInt16) -> Bool {
        switch Int(keyCode) {
        case kVK_Tab, kVK_Escape:
            true
        default:
            false
        }
    }
}
