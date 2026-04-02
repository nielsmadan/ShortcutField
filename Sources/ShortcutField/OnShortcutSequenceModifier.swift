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

        let step = sequence.steps[currentStep]
        guard step.matches(event) else {
            reset()
            return .ignored
        }

        let isLast = currentStep == sequence.steps.count - 1
        if isLast {
            reset()
            action()
            return .matched
        }

        currentStep += 1
        beginTracking()
        restartTimeout()
        return .advanced(consumeEvent: Self.isInterceptedByFocusSystem(keyCode: event.keyCode))
    }

    func reset() {
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
                try await Task.sleep(for: .seconds(self.stepTimeout))
                self.reset()
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

        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
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

/// View modifier that fires an action when a shortcut sequence is pressed.
///
/// Each modifier instance tracks its position in the sequence independently,
/// while a shared event dispatcher fans key events out to every active matcher.
/// This allows sequences sharing a prefix to advance in parallel and ensures
/// focus-intercepted keys like Tab are consumed only after every matcher has
/// seen the event. Only the final matching step is consumed.
///
/// Because intermediate key events propagate through the responder chain,
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
    /// Perform an action when the given shortcut sequence is pressed.
    ///
    /// Tracks key presses in order, firing the action when the full sequence
    /// is matched. Intermediate steps propagate normally; only the final
    /// step is consumed.
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
