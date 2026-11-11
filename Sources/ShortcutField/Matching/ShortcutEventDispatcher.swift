import AppKit

/// The app-wide singleton `NSEvent` local monitor that fans keyboard and gesture
/// events out to all registered handlers.
///
/// Consumers register a ``Handler`` closure under a caller-supplied `UUID`; the
/// dispatcher calls every active handler **newest-first** (reverse registration
/// order) and consumes the event (returns `nil` from the system monitor) if any
/// handler returns `.fired`, `.continuousFired`, or `.advanced(consumeEvent: true)`.
/// Handlers advance in parallel unless recording or keyboard ownership interrupts delivery.
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
    public typealias Handler = (NSEvent) -> ShortcutMatchResult

    /// `internal` (not `public`) so @testable import can create isolated instances
    /// in tests, while external consumers have no access to the initializer.
    init() {}

    private var eventMonitor: Any?
    private struct Registration {
        let id: UUID
        let revision = UUID()
        let handler: Handler
        let onInterruption: () -> Void
    }

    private struct OwnedWindow {
        weak var window: NSWindow?
    }

    private var handlers: [Registration] = []
    private var handlerSnapshot: [Registration] = []
    private var activeRevisions: Set<UUID> = []
    private var ownedWindows: [UUID: OwnedWindow] = [:]
    private var deliveryGeneration: UInt64 = 0
    private var isInterrupting = false
    private weak var lastWindow: NSWindow?
    private var lastWindowID: ObjectIdentifier?
    private var hasReceivedEvent = false

    /// Test hook: the number of currently-registered handlers.
    var handlerCount: Int {
        handlers.count
    }

    private func rebuildSnapshot() {
        handlerSnapshot = Array(handlers.reversed())
        activeRevisions = Set(handlers.map(\.revision))
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
        register(id: id, onInterruption: {}, handler: handler)
    }

    /// The interruption callback runs synchronously on ownership boundaries and event-window changes.
    /// Interrupt matchers and cancel queued deliveries here, including any batch already being flushed.
    /// Notifications apply to all registrations, even when only one window acquires ownership.
    public func register(id: UUID, onInterruption: @escaping () -> Void, handler: @escaping Handler) {
        let registration = Registration(id: id, handler: handler, onInterruption: onInterruption)
        if let index = handlers.firstIndex(where: { $0.id == id }) {
            handlers[index] = registration
        } else {
            handlers.append(registration)
        }
        rebuildSnapshot()
        installMonitorIfNeeded()
    }

    /// Suppresses dispatcher handlers for this window while native responder input continues unchanged.
    /// All local shortcut kinds are suppressed. Recorders and independently installed monitors remain independent.
    /// The token holds the window weakly; retain it until the presentation ends. Sheets and child windows
    /// need their own tokens. Releasing a token after its window deallocates does not notify consumers.
    public func acquireKeyboardOwnership(for window: NSWindow) -> ShortcutKeyboardOwnership {
        let wasOwned = owns(window)
        let id = UUID()
        ownedWindows[id] = OwnedWindow(window: window)
        if wasOwned {
            deliveryGeneration &+= 1
        } else {
            interrupt()
        }
        return ShortcutKeyboardOwnership { [weak self] in self?.releaseOwnership(id: id) }
    }

    private func owns(_ window: NSWindow?) -> Bool {
        guard let window else { return false }
        return ownedWindows.values.contains { $0.window === window }
    }

    private func releaseOwnership(id: UUID) {
        guard let window = ownedWindows.removeValue(forKey: id)?.window, !owns(window) else { return }
        interrupt()
    }

    private func interrupt() {
        deliveryGeneration &+= 1
        guard !isInterrupting else { return }
        isInterrupting = true
        defer { isInterrupting = false }
        for registration in handlerSnapshot {
            guard activeRevisions.contains(registration.revision) else { continue }
            registration.onInterruption()
        }
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
            hasReceivedEvent = false
            lastWindow = nil
            lastWindowID = nil
        }
    }

    func handleEvent(_ event: NSEvent) -> NSEvent? {
        guard !isInterrupting else { return event }
        let window = event.window
        let windowID = window.map(ObjectIdentifier.init)
        let changedWindow = hasReceivedEvent && (windowID != lastWindowID || lastWindow !== window)
        lastWindow = window
        lastWindowID = windowID
        hasReceivedEvent = true
        if changedWindow {
            interrupt()
        }
        guard !ShortcutRecordingState.isAnyRecording, !owns(window) else { return event }

        let generation = deliveryGeneration
        var shouldConsume = false
        for registration in handlerSnapshot {
            guard generation == deliveryGeneration, !ShortcutRecordingState.isAnyRecording else { break }
            guard activeRevisions.contains(registration.revision) else { continue }
            switch registration.handler(event) {
            case .ignored:
                break
            case let .advanced(consumeEvent):
                shouldConsume = shouldConsume || consumeEvent
            case .fired, .continuousFired:
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
