import AppKit
import Carbon.HIToolbox
import SwiftUI

@available(macOS 14.0, *)
enum ShortcutSequenceEventResult {
    case ignored
    case advanced(consumeEvent: Bool)
    case matched
}

@available(macOS 14.0, *)
@MainActor
final class ShortcutSequenceMatcher {
    private var sequence: ShortcutSequence?
    private var action: () -> Void = {}
    private var timeoutTask: Task<Void, Never>?

    /// Event types of continuous gestures (`.magnify`, `.rotate`, `.scrollWheel`) that
    /// have already advanced the matcher past a step within the current physical burst.
    /// Subsequent events of the same type are suppressed so a single trackpad burst
    /// doesn't re-fire the matcher. Entries are cleared on the gesture's end-phase
    /// event so the next physical burst can advance the matcher again.
    ///
    /// A Set (rather than a single optional) supports overlapping bursts — e.g. a
    /// sequence `[PinchIn, RotateClockwise]` where the rotate-step's matching event
    /// arrives while the pinch's end-phase hasn't fired yet.
    private var inProgressContinuousEventTypes: Set<NSEvent.EventType> = []

    private(set) var currentStep = 0
    private(set) var isTracking = false {
        didSet {
            guard isTracking != oldValue else { return }
            trackingStateDidChange?(isTracking)
        }
    }

    var stepTimeout: TimeInterval = 1.0
    var trackingStateDidChange: ((Bool) -> Void)?

    func configure(sequence: ShortcutSequence?, action: @escaping () -> Void) {
        reset()
        self.sequence = sequence
        self.action = action
    }

    func handle(_ event: NSEvent) -> ShortcutSequenceEventResult {
        guard let sequence else { return .ignored }

        // Phase-end reset: clear the in-progress flag for this gesture type so the
        // next physical burst can advance the matcher again. Trackpad scrolls also
        // emit `.ended`/`.cancelled`; mouse-wheel events have empty phase and never
        // enter the suppression set in the first place.
        if event.type == .magnify || event.type == .rotate || event.type == .scrollWheel,
           event.phase == .ended || event.phase == .cancelled
        {
            inProgressContinuousEventTypes.remove(event.type)
            return .ignored
        }

        // Momentum scroll passthrough — trackpad inertia after the user lifts.
        if event.type == .scrollWheel, event.momentumPhase != [] {
            return .ignored
        }

        // Active-gesture suppression: once a continuous gesture has advanced the
        // matcher, ignore further events of the same type until the gesture ends.
        if inProgressContinuousEventTypes.contains(event.type) {
            return .ignored
        }

        let step = sequence.steps[currentStep]
        guard step.matches(event) else {
            // Continuous-gesture events arrive in bursts where many are sub-threshold
            // or in the wrong direction. Don't reset progress on those — the user may
            // be mid-gesture toward the expected step. Scroll bursts behave similarly:
            // a single trackpad swipe emits many events, and a non-matching one
            // shouldn't unwind progress. The 1-second step timeout cleans up stale
            // state.
            if event.type == .magnify || event.type == .rotate || event.type == .scrollWheel {
                return .ignored
            }
            reset()
            return .ignored
        }

        // If the matching event is a continuous gesture / trackpad scroll for the
        // matching kind, mark the gesture as in-progress so subsequent events of the
        // same gesture are suppressed — preventing a single physical burst from
        // firing the matcher repeatedly. Mouse-wheel events have empty phase and
        // are *not* added: each wheel notch is a discrete user action.
        //
        // `event.phase` is only valid for gesture / scroll-wheel events; calling it
        // on a key or mouse event throws. Guard the access by event type.
        let isContinuousEvent = event.type == .magnify || event.type == .rotate
            || event.type == .scrollWheel
        let hasPhase = isContinuousEvent && event.phase != []
        let suppressType: NSEvent.EventType? = (
            Shortcut.isContinuous(step.kind) && isContinuousEvent && hasPhase
        ) ? event.type : nil

        let isLast = currentStep == sequence.steps.count - 1
        if isLast {
            reset()
            if let suppressType {
                inProgressContinuousEventTypes.insert(suppressType)
            }
            action()
            return .matched
        }

        currentStep += 1
        beginTracking()
        restartTimeout()
        if let suppressType {
            inProgressContinuousEventTypes.insert(suppressType)
        }

        // `event.keyCode` is only valid for keyboard events; calling it on a
        // mouse, scroll, or gesture event throws.
        let consumeEvent = (event.type == .keyDown)
            && Self.isInterceptedByFocusSystem(keyCode: event.keyCode)
        return .advanced(consumeEvent: consumeEvent)
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
            } catch {
                // Task was cancelled — do nothing
            }
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

@available(macOS 14.0, *)
@MainActor
final class ShortcutSequenceEventDispatcher {
    static let shared = ShortcutSequenceEventDispatcher()

    typealias Handler = (NSEvent) -> ShortcutSequenceEventResult

    private var eventMonitor: Any?
    private var handlers: [UUID: Handler] = [:]

    func register(id: UUID, handler: @escaping Handler) {
        handlers[id] = handler
        installMonitorIfNeeded()
    }

    func unregister(id: UUID) {
        handlers.removeValue(forKey: id)
        if handlers.isEmpty {
            removeMonitor()
        }
    }

    func handleEvent(_ event: NSEvent) -> NSEvent? {
        if ShortcutRecorderField.isAnyRecording {
            return event
        }

        let currentHandlers = Array(handlers.values)

        var shouldConsume = false
        for handler in currentHandlers {
            switch handler(event) {
            case .ignored:
                continue
            case let .advanced(consumeEvent):
                shouldConsume = shouldConsume || consumeEvent
            case .matched:
                shouldConsume = true
            }
        }

        return shouldConsume ? nil : event
    }

    private func installMonitorIfNeeded() {
        guard eventMonitor == nil, !handlers.isEmpty else { return }

        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [
            .keyDown,
            .leftMouseDown,
            .rightMouseDown,
            .otherMouseDown,
            .scrollWheel,
            .magnify,
            .rotate,
            .smartMagnify,
        ]) { [weak self] event in
            guard let self else { return event }
            return handleEvent(event)
        }
    }

    private func removeMonitor() {
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
            self.eventMonitor = nil
        }
    }
}

/// Whether any `.onShortcutSequence()` modifier is currently partway
/// through matching a sequence (past step 0).
///
/// Use this in a `noResponder(for:)` override to suppress the system
/// alert sound only for key events that are part of an in-progress
/// sequence match. See the package README for details.
@available(macOS 14.0, *)
public enum ShortcutSequenceTracking {
    /// `true` when at least one sequence modifier has matched one or more
    /// intermediate steps and is waiting for the next key press.
    @MainActor public private(set) static var isActive = false

    @MainActor fileprivate static var activeCount = 0 {
        didSet { isActive = activeCount > 0 }
    }
}

/// View modifier that fires an action when a shortcut sequence is performed.
///
/// Each modifier instance tracks its position in the sequence independently,
/// while a shared event dispatcher fans events out to every active matcher.
/// This allows sequences sharing a prefix to advance in parallel and ensures
/// focus-intercepted keys like Tab are consumed only after every matcher has
/// seen the event. Only the final matching step is consumed.
///
/// Because intermediate events propagate through the responder chain,
/// macOS may play the system alert sound for unhandled keys. Check
/// ``ShortcutSequenceTracking/isActive`` in a `noResponder(for:)` override
/// to suppress the beep selectively.
@available(macOS 14.0, *)
struct OnShortcutSequenceModifier: ViewModifier {
    let sequence: ShortcutSequence?
    let action: () -> Void

    @State private var matcher = ShortcutSequenceMatcher()
    @State private var listenerID = UUID()

    private let stepTimeout: TimeInterval = 1.0

    func body(content: Content) -> some View {
        content
            .onAppear {
                installMonitor()
            }
            .onDisappear {
                removeMonitor()
                resetTracking()
            }
            .onChange(of: sequence) { _, _ in
                removeMonitor()
                resetTracking()
                installMonitor()
            }
    }

    private func resetTracking() {
        matcher.reset()
    }

    private func installMonitor() {
        guard sequence != nil else { return }

        matcher.stepTimeout = stepTimeout
        matcher.trackingStateDidChange = { isTracking in
            ShortcutSequenceTracking.activeCount += isTracking ? 1 : -1
        }
        matcher.configure(sequence: sequence, action: action)
        ShortcutSequenceEventDispatcher.shared.register(id: listenerID) { event in
            matcher.handle(event)
        }
    }

    private func removeMonitor() {
        ShortcutSequenceEventDispatcher.shared.unregister(id: listenerID)
    }
}

// MARK: - View Extension

public extension View {
    /// Perform an action when the given shortcut sequence is performed.
    ///
    /// Tracks events in order, firing the action when the full sequence is
    /// matched. Intermediate steps propagate normally; only the final step
    /// is consumed.
    ///
    /// Multiple sequences that share a common prefix (e.g. `A B` and `A T`)
    /// work correctly — each modifier tracks independently and the shared
    /// dispatcher delivers every event to all active matchers.
    ///
    /// - Note: Intermediate key events that propagate through the responder
    ///   chain may trigger the macOS system alert sound. Check
    ///   ``ShortcutSequenceTracking/isActive`` in a `noResponder(for:)` override
    ///   to suppress the beep selectively. See the package README for details.
    ///
    /// ```swift
    /// MyView()
    ///     .onShortcutSequence(sequence) {
    ///         print("Sequence matched!")
    ///     }
    /// ```
    @available(macOS 14.0, *)
    func onShortcutSequence(_ sequence: ShortcutSequence?, perform action: @escaping () -> Void) -> some View {
        modifier(OnShortcutSequenceModifier(sequence: sequence, action: action))
    }
}
