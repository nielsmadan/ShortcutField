/// Whether any `ShortcutMatcher` is partway through matching a multi-step
/// discrete shortcut (past step 0).
///
/// Use this in a `noResponder(for:)` override to suppress the system alert sound
/// only for key events that are part of an in-progress sequence match. Every
/// `ShortcutMatcher` — whether built by the `.onShortcut()` modifier or
/// constructed directly — contributes to this flag automatically.
public enum ShortcutTracking {
    /// `true` when at least one matcher has matched one or more intermediate
    /// steps and is waiting for the next event.
    @MainActor public private(set) static var isActive = false

    @MainActor static var activeCount = 0 {
        didSet { isActive = activeCount > 0 }
    }
}
