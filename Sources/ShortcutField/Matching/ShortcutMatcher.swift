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

    /// Feed an `NSEvent`. Returns whether it advanced or completed a match.
    ///
    /// A discrete shortcut whose first step is a bare key or a ⇧/⌥-only
    /// combination returns `.ignored` while an editable text responder has focus,
    /// even when the event matches the step.
    public func handle(_ event: NSEvent) -> ShortcutMatchResult {
        switch backing {
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

    /// Discard in-progress state: the step-sequence position for discrete
    /// shortcuts, or the throttle accumulator for continuous ones.
    public func reset() {
        switch backing {
        case let .discrete(sequence): sequence.reset()
        case let .continuous(continuous): continuous.reset()
        }
    }
}
