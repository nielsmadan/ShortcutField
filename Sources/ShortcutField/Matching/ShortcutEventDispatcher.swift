import AppKit

/// The app-wide singleton `NSEvent` local monitor that fans keyboard and gesture
/// events out to all registered handlers.
///
/// Consumers register a ``Handler`` closure under a caller-supplied `UUID`; the
/// dispatcher calls every active handler **newest-first** (reverse registration
/// order) and consumes the event (returns `nil` from the system monitor) if any
/// handler returns `.fired`, `.continuousFired`, or `.advanced(consumeEvent: true)`.
/// Every handler still sees every event — newest-first is an ordering guarantee,
/// not early termination — so prefix-sharing matchers all advance in parallel.
///
/// The underlying `NSEvent` local monitor is installed lazily on the first
/// `register` call and torn down automatically when the last handler is removed.
///
/// - Note: All methods must be called on the main actor.
@MainActor
public final class ShortcutEventDispatcher {
    /// The shared, app-wide dispatcher instance. This is the only supported way
    /// to obtain a dispatcher; external construction is intentionally unavailable.
    public static let shared = ShortcutEventDispatcher()

    /// A closure that inspects an `NSEvent` and returns a ``ShortcutMatchResult``.
    ///
    /// The dispatcher consumes the event (passes `nil` back to the system) if any
    /// registered handler returns `.fired`, `.continuousFired`, or
    /// `.advanced(consumeEvent: true)`; otherwise the event passes through.
    public typealias Handler = (NSEvent) -> ShortcutMatchResult

    // `internal` (not `public`) so @testable import can create isolated instances
    // in tests, while external consumers have no access to the initializer.
    init() {}

    private var eventMonitor: Any?
    /// Registered handlers in registration order. Kept ordered (rather than a
    /// dictionary) so `handleEvent` can consult them newest-first.
    private var handlers: [(id: UUID, handler: Handler)] = []
    /// Newest-first snapshot of the handler closures, rebuilt on every
    /// register/unregister so the per-event hot path neither reverses nor
    /// allocates per event.
    private var handlerSnapshot: [Handler] = []

    /// Test hook: the number of currently-registered handlers.
    var handlerCount: Int { handlers.count }

    private func rebuildSnapshot() {
        handlerSnapshot = handlers.reversed().map(\.handler)
    }

    /// Registers a handler under `id`.
    ///
    /// If a handler is already registered for `id`, it is **replaced in place** by
    /// the new one — its position in the newest-first ordering is preserved. The
    /// system event monitor is installed lazily on the first registration.
    ///
    /// - Parameters:
    ///   - id: A caller-supplied `UUID` used to identify the handler for later removal.
    ///   - handler: The closure to invoke for each incoming event.
    public func register(id: UUID, handler: @escaping Handler) {
        if let index = handlers.firstIndex(where: { $0.id == id }) {
            handlers[index].handler = handler
        } else {
            handlers.append((id: id, handler: handler))
        }
        rebuildSnapshot()
        installMonitorIfNeeded()
    }

    /// Removes the handler registered under `id`.
    ///
    /// If no handler is registered for `id`, this is a no-op. When the last
    /// handler is removed, the underlying system event monitor is torn down.
    ///
    /// - Parameter id: The `UUID` that was passed to `register(id:handler:)`.
    public func unregister(id: UUID) {
        handlers.removeAll { $0.id == id }
        rebuildSnapshot()
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
            case .fired:
                shouldConsume = true
            case .continuousFired:
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
