import AppKit

/// Matches a `Shortcut` against a stream of `NSEvent`s.
///
/// The public face of matching: construct one with any `Shortcut` (discrete or
/// continuous) and feed it events. Internally delegates to a `SequenceMatcher`
/// for `.discrete` shortcuts and a `ContinuousMatcher` for `.continuous` ones,
/// so callers never branch on kind.
@MainActor
public final class ShortcutMatcher {
    private enum Backing {
        case discrete(SequenceMatcher)
        case continuous(ContinuousMatcher)
    }

    private let backing: Backing
    private weak var lastWindow: NSWindow?
    private var lastWindowID: ObjectIdentifier?
    private var hasReceivedEvent = false

    /// Forwards the in-progress-sequence signal from the backing discrete
    /// matcher. No-op for continuous shortcuts.
    public var trackingStateDidChange: ((Bool) -> Void)? {
        didSet {
            if case let .discrete(sequence) = backing {
                sequence.trackingStateDidChange = trackingStateDidChange
            }
        }
    }

    /// Create a matcher for a discrete or continuous shortcut.
    public init(_ shortcut: Shortcut) {
        switch shortcut {
        case let .discrete(discrete):
            let sequence = SequenceMatcher()
            sequence.configure(shortcut: discrete)
            backing = .discrete(sequence)
        case let .continuous(continuous):
            backing = .continuous(ContinuousMatcher(continuous))
        }
    }

    /// Feed an `NSEvent`. Returns whether it completed a match, and whether the event
    /// should be consumed (see ``ShortcutMatchResult``).
    ///
    /// A discrete shortcut whose first step is a bare key or a ⇧/⌥-only
    /// combination returns `.ignored` while an editable text responder has focus,
    /// even when the event matches the step. Changing the event's window, including to or from
    /// a windowless event, interrupts pending matching before processing the new event.
    public func handle(_ event: NSEvent) -> ShortcutMatchResult {
        let window = event.window
        let windowID = window.map(ObjectIdentifier.init)
        if hasReceivedEvent, windowID != lastWindowID || lastWindow !== window {
            interrupt()
        }
        hasReceivedEvent = true
        lastWindow = window
        lastWindowID = windowID
        return switch backing {
        case let .discrete(sequence): sequence.handle(event)
        case let .continuous(continuous): continuous.handle(event)
        }
    }

    /// Test seam: feed a pre-extracted `ShortcutEventShape` directly.
    /// Only callable from `@testable` imports; no-op for discrete shortcuts.
    func handle(shape: ShortcutEventShape) -> ShortcutMatchResult {
        guard case let .continuous(continuous) = backing else { return .ignored }
        return continuous.handle(shape: shape)
    }

    /// Cancels pending sequences and throttling without firing again in an already-claimed gesture.
    /// Claimed gesture tails and scroll momentum keep their consumption rules until the burst ends;
    /// a new burst starts fresh. Use this in dispatcher interruption callbacks.
    public func interrupt() {
        switch backing {
        case let .discrete(sequence): sequence.interrupt()
        case let .continuous(continuous): continuous.interrupt()
        }
    }

    /// Discards all pending state, including gesture suppression. Use ``interrupt()`` when
    /// cancelling during an active gesture so its remaining events cannot fire again.
    public func reset() {
        hasReceivedEvent = false
        lastWindow = nil
        lastWindowID = nil
        switch backing {
        case let .discrete(sequence): sequence.reset()
        case let .continuous(continuous): continuous.reset()
        }
    }
}
