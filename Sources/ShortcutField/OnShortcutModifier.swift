import AppKit
import Carbon.HIToolbox
import SwiftUI

@available(macOS 14.0, *)
enum ShortcutEventResult {
    case ignored
    case advanced(consumeEvent: Bool)
    case matched
}

@available(macOS 14.0, *)
@MainActor
final class ShortcutMatcher {
    private var shortcut: Shortcut?
    private var action: () -> Void = {}
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
            trackingStateDidChange?(isTracking)
        }
    }

    var stepTimeout: TimeInterval = 1.0
    var trackingStateDidChange: ((Bool) -> Void)?

    func configure(shortcut: Shortcut?, action: @escaping () -> Void) {
        reset()
        self.shortcut = shortcut
        self.action = action
    }

    func handle(_ event: NSEvent) -> ShortcutEventResult {
        guard let shortcut else { return .ignored }

        if let preempt = preempt(event) { return preempt }

        let step = shortcut.steps[currentStep]
        guard step.matches(event) else {
            // Continuous-gesture bursts emit many sub-threshold or wrong-direction
            // events; treat those as non-resetting. Discrete kinds reset on miss.
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
            action()
            return .matched
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

    /// Early-return guard for events that shouldn't reach the match step:
    /// phase-end clears for in-progress continuous gestures, momentum scroll
    /// passthrough, and active-gesture suppression once a step has fired.
    private func preempt(_ event: NSEvent) -> ShortcutEventResult? {
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
    private func suppressionTypeIfContinuous(event: NSEvent, step: Shortcut.Step) -> NSEvent.EventType? {
        guard Shortcut.isContinuous(step.kind),
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

@available(macOS 14.0, *)
@MainActor
final class ShortcutEventDispatcher {
    static let shared = ShortcutEventDispatcher()

    typealias Handler = (NSEvent) -> ShortcutEventResult

    private var eventMonitor: Any?
    private var handlers: [UUID: Handler] = [:]
    /// Snapshot of `handlers.values` rebuilt on every register/unregister so the
    /// per-event hot path iterates an array without allocating a fresh snapshot.
    private var handlerSnapshot: [Handler] = []

    func register(id: UUID, handler: @escaping Handler) {
        handlers[id] = handler
        handlerSnapshot = Array(handlers.values)
        installMonitorIfNeeded()
    }

    func unregister(id: UUID) {
        handlers.removeValue(forKey: id)
        handlerSnapshot = Array(handlers.values)
        if handlers.isEmpty {
            removeMonitor()
        }
    }

    func handleEvent(_ event: NSEvent) -> NSEvent? {
        if ShortcutRecordingState.isAnyRecording {
            return event
        }

        var shouldConsume = false
        for handler in handlerSnapshot {
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

/// Whether any `.onShortcut()` modifier with a multi-step shortcut is currently
/// partway through matching (past step 0).
///
/// Use this in a `noResponder(for:)` override to suppress the system alert sound
/// only for key events that are part of an in-progress sequence match. See the
/// package README for details.
@available(macOS 14.0, *)
public enum ShortcutTracking {
    /// `true` when at least one `.onShortcut()` modifier has matched one or more
    /// intermediate steps and is waiting for the next event.
    @MainActor public private(set) static var isActive = false

    @MainActor fileprivate static var activeCount = 0 {
        didSet { isActive = activeCount > 0 }
    }
}

/// View modifier that fires an action when a shortcut is performed.
///
/// Each modifier instance tracks its position in the shortcut independently,
/// while a shared event dispatcher fans events out to every active matcher.
/// This allows shortcuts sharing a prefix to advance in parallel and ensures
/// focus-intercepted keys like Tab are consumed only after every matcher has
/// seen the event. Only the final matching step is consumed.
///
/// 1-step shortcuts fire once on the matching event. Multi-step shortcuts fire
/// once when the full sequence completes within the per-step timeout.
///
/// Because intermediate events propagate through the responder chain,
/// macOS may play the system alert sound for unhandled keys. Check
/// ``ShortcutTracking/isActive`` in a `noResponder(for:)` override to suppress
/// the beep selectively.
@available(macOS 14.0, *)
struct OnShortcutModifier: ViewModifier {
    let shortcut: Shortcut?
    let action: () -> Void

    @State private var matcher = ShortcutMatcher()
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
            .onChange(of: shortcut) { _, _ in
                removeMonitor()
                resetTracking()
                installMonitor()
            }
    }

    private func resetTracking() {
        matcher.reset()
    }

    private func installMonitor() {
        guard shortcut != nil else { return }

        matcher.stepTimeout = stepTimeout
        matcher.trackingStateDidChange = { isTracking in
            ShortcutTracking.activeCount += isTracking ? 1 : -1
        }
        matcher.configure(shortcut: shortcut, action: action)
        ShortcutEventDispatcher.shared.register(id: listenerID) { event in
            matcher.handle(event)
        }
    }

    private func removeMonitor() {
        ShortcutEventDispatcher.shared.unregister(id: listenerID)
    }
}

// MARK: - View Extension

public extension View {
    /// Perform an action when the given shortcut is performed.
    ///
    /// Tracks events in order, firing the action when the full shortcut is
    /// matched. For 1-step shortcuts the action fires immediately on the
    /// matching event. For multi-step shortcuts intermediate events propagate
    /// normally; only the final step is consumed.
    ///
    /// Multiple shortcuts that share a common prefix (e.g. `A B` and `A T`)
    /// work correctly — each modifier tracks independently and the shared
    /// dispatcher delivers every event to all active matchers.
    ///
    /// - Note: Intermediate key events that propagate through the responder
    ///   chain may trigger the macOS system alert sound. Check
    ///   ``ShortcutTracking/isActive`` in a `noResponder(for:)` override
    ///   to suppress the beep selectively. See the package README for details.
    ///
    /// ```swift
    /// MyView()
    ///     .onShortcut(shortcut) {
    ///         print("Shortcut matched!")
    ///     }
    /// ```
    @available(macOS 14.0, *)
    func onShortcut(_ shortcut: Shortcut?, perform action: @escaping () -> Void) -> some View {
        modifier(OnShortcutModifier(shortcut: shortcut, action: action))
    }
}
