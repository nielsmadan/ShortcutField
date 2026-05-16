/// The outcome of a single-event matching attempt.
public enum ShortcutMatchResult: Sendable, Equatable {
    /// The event did not match.
    case ignored
    /// The event matched but did not complete a fire — and should be consumed
    /// per `consumeEvent`. Two cases produce this:
    /// - A discrete multi-step shortcut advanced past an intermediate step.
    ///   `consumeEvent` is `true` for focus-intercepted keys (Tab, Escape) so the
    ///   event does not also drive focus, `false` otherwise.
    /// - A continuous shortcut matched the gesture but its sensitivity throttle
    ///   suppressed this fire; `consumeEvent` is `true` so the gesture does not
    ///   also reach the view beneath.
    case advanced(consumeEvent: Bool)
    /// A discrete shortcut completed on this event.
    case fired
    /// A continuous shortcut produced a throttled fire. `magnitude` is this
    /// event's signed delta (scroll `scrollingDeltaY`/`X`, magnify
    /// `magnification`, rotate `rotation` in degrees).
    case continuousFired(magnitude: Double)
}
