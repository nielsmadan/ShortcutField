import AppKit
import Carbon.HIToolbox

@MainActor
final class SequenceMatcher {
    private var shortcut: DiscreteShortcut?
    private var timeoutTask: Task<Void, Never>?

    /// Trackpad bursts that advanced or fired the matcher, so a single burst doesn't match
    /// twice. A fired burst consumes its rest so it doesn't also reach the view beneath.
    /// Claims survive sequence resets, so a burst can't start the sequence again, and are per
    /// type, so a `[PinchIn, RotateClockwise]` rotate can match while the pinch is still going.
    private var bursts = GestureBurstTracker()

    private var scrollCoast = ScrollCoast()

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
    /// Test seam: how a matcher dropped mid-sequence ends its count in ``ShortcutTracking``.
    private let endDroppedTracking: @MainActor @Sendable () -> Void

    /// Test hook: the in-flight per-step timeout task, if any. Awaiting its
    /// `value` lets a test observe the timeout-driven reset deterministically,
    /// without racing a wall-clock sleep.
    var pendingTimeoutTask: Task<Void, Never>? {
        timeoutTask
    }

    init(
        stepTimeout: TimeInterval = 1.0,
        endDroppedTracking: @escaping @MainActor @Sendable () -> Void = { ShortcutTracking.activeCount -= 1 }
    ) {
        self.stepTimeout = stepTimeout
        self.endDroppedTracking = endDroppedTracking
    }

    /// A matcher dropped mid-sequence never reaches `reset()`, so it ends its tracking here.
    /// `deinit` is nonisolated: off the main thread the decrement hops to the main actor.
    deinit {
        guard isTracking else { return }
        let endDroppedTracking = endDroppedTracking
        if Thread.isMainThread {
            MainActor.assumeIsolated { endDroppedTracking() }
        } else {
            Task { @MainActor in endDroppedTracking() }
        }
    }

    func configure(shortcut: DiscreteShortcut?) {
        reset()
        self.shortcut = shortcut
    }

    func handle(_ event: NSEvent) -> ShortcutMatchResult {
        guard let shortcut else { return .ignored }

        if let preempt = preempt(event) {
            return preempt
        }

        if currentStep > 0, event.type == .keyDown, event.isARepeat {
            return handleRepeat(event, previousStep: shortcut.steps[currentStep - 1])
        }

        let step = shortcut.steps[currentStep]
        guard step.matches(event) else {
            // Continuous-gesture bursts emit many sub-threshold or wrong-direction
            // events; treat those as non-resetting.
            if event.type.isContinuousGesture || currentStep == 0 {
                return .ignored
            }
            return restart(with: event)
        }

        if yieldsToTextInput(event: event, step: step) {
            return .ignored
        }

        let isLast = currentStep == shortcut.steps.count - 1
        if isLast {
            resetSequence()
            claimBurst(of: event, matching: step, .consumesRest)
            return .fired
        }

        currentStep += 1
        beginTracking()
        restartTimeout()
        claimBurst(of: event, matching: step, .ignoresRest)

        // `event.keyCode` is only valid for keyboard events; calling it on a
        // mouse, scroll, or gesture event throws.
        let consumeEvent = (event.type == .keyDown)
            && Self.isInterceptedByFocusSystem(keyCode: event.keyCode)
        return .advanced(consumeEvent: consumeEvent)
    }

    /// Runs the event that broke the sequence again as its first step (⌘K ⌘K ⌘C), so a restart
    /// reports one tracking change rather than an end and a fresh start.
    private func restart(with event: NSEvent) -> ShortcutMatchResult {
        currentStep = 0
        timeoutTask?.cancel()
        timeoutTask = nil
        let result = handle(event)
        if result == .ignored {
            resetSequence()
        }
        return result
    }

    /// A held key's auto-repeat mid-sequence: it keeps the sequence alive while it repeats the step
    /// just matched, and never counts as the next step.
    private func handleRepeat(_ event: NSEvent, previousStep: DiscreteShortcut.Step) -> ShortcutMatchResult {
        guard previousStep.matches(event) else {
            resetSequence()
            return .ignored
        }
        restartTimeout()
        return .advanced(consumeEvent: Self.isInterceptedByFocusSystem(keyCode: event.keyCode))
    }

    /// Events that must not reach the step matcher: scroll momentum, and the rest of a
    /// trackpad burst that already advanced or fired it. A burst that fired the shortcut is
    /// consumed with its momentum, except its end, which reaches the view beneath so that
    /// view can close the gesture.
    private func preempt(_ event: NSEvent) -> ShortcutMatchResult? {
        // `event.phase` throws on key and mouse events.
        guard event.type.isContinuousGesture else { return nil }
        if event.isMomentumScroll {
            return scrollCoast.consumeMomentum(event.momentumPhase) ? .advanced(consumeEvent: true) : .ignored
        }
        let position = bursts.track(ShortcutEventShape(event))
        if event.type == .scrollWheel {
            scrollCoast.follow(position)
        }
        switch position {
        case .start:
            return nil
        case .end:
            return .ignored
        case .middle(.consumesRest):
            return .advanced(consumeEvent: true)
        case .middle(.ignoresRest):
            return .ignored
        case .unphased, .middle(nil):
            return nil
        }
    }

    /// Claims the trackpad burst of an event that matched a continuous-kind step, so the rest of
    /// the burst can't match again.
    private func claimBurst(
        of event: NSEvent,
        matching step: DiscreteShortcut.Step,
        _ claim: GestureBurstTracker.Claim
    ) {
        guard DiscreteShortcut.isContinuous(step.kind) else { return }
        bursts.claim(ShortcutEventShape(event), claim)
    }

    /// Whether a matching keystroke must be surrendered to a focused text editor.
    ///
    /// Derived from the step's shape: a step carrying ⌘ or ⌃, or bound to a key
    /// that produces no text, is not something the user could have typed, so it
    /// fires wherever focus sits. A bare key, or a ⇧/⌥-only combination, is a
    /// character the user plausibly meant for the field.
    ///
    /// Only consulted at `currentStep == 0`. Pressing the first step of a
    /// multi-step shortcut commits to the sequence, so later steps — which are
    /// often bare keys — always fire.
    private func yieldsToTextInput(event: NSEvent, step: DiscreteShortcut.Step) -> Bool {
        guard currentStep == 0, event.type == .keyDown, case let .key(keyCode) = step.kind,
              !Self.producesNoText(keyCode: keyCode), step.modifiers.isDisjoint(with: [
                  .command,
                  .control,
              ]) else { return false }
        return TextInputFocus.isEditingText
    }

    /// Keys a user cannot reach by typing, so a bare shortcut bound to one still
    /// fires while a text field has focus.
    ///
    /// Navigation and editing keys (arrows, Home/End, Page Up/Down, Tab, Return,
    /// Space, Delete) are excluded on purpose: each one acts on the text, so the
    /// field must keep receiving them.
    private static func producesNoText(keyCode: UInt16) -> Bool {
        switch Int(keyCode) {
        case kVK_Escape,
             kVK_F1, kVK_F2, kVK_F3, kVK_F4, kVK_F5, kVK_F6, kVK_F7,
             kVK_F8, kVK_F9, kVK_F10, kVK_F11, kVK_F12, kVK_F13, kVK_F14,
             kVK_F15, kVK_F16, kVK_F17, kVK_F18, kVK_F19, kVK_F20:
            true
        default:
            false
        }
    }

    func interrupt() {
        resetSequence()
    }

    func reset() {
        resetSequence()
        bursts.reset()
        scrollCoast.stop()
    }

    /// Back to the first step, still remembering bursts in progress so their remaining
    /// events can't start the sequence again.
    private func resetSequence() {
        currentStep = 0
        isTracking = false
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
                resetSequence()
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
