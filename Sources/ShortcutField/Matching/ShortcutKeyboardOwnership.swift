import AppKit

/// Retain for the presentation's lifetime; releasing the last token restores local shortcut delivery.
/// Release explicitly before hiding a reusable window. Deallocation also releases ownership;
/// off-main deallocation schedules that cleanup on the main actor.
@MainActor
public final class ShortcutKeyboardOwnership {
    private var isReleased = false
    private let releaseOwnership: @MainActor @Sendable () -> Void

    init(releaseOwnership: @escaping @MainActor @Sendable () -> Void) {
        self.releaseOwnership = releaseOwnership
    }

    /// Repeated calls are harmless; other tokens for the window remain effective.
    public func release() {
        guard !isReleased else { return }
        isReleased = true
        releaseOwnership()
    }

    deinit {
        guard !isReleased else { return }
        let releaseOwnership = releaseOwnership
        if Thread.isMainThread {
            MainActor.assumeIsolated { releaseOwnership() }
        } else {
            Task { @MainActor in releaseOwnership() }
        }
    }
}
