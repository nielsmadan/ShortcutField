import AppKit

@MainActor
protocol ActiveShortcutRecorder: AnyObject {
    func forceEndRecordingSession()
}

@MainActor
enum ShortcutRecordingState {
    private static var activeRecorders: Set<ObjectIdentifier> = []
    private weak static var activeRecorder: (any ActiveShortcutRecorder)?

    static var isAnyRecording: Bool {
        !activeRecorders.isEmpty
    }

    static func begin(for recorder: AnyObject & ActiveShortcutRecorder) {
        if let activeRecorder, activeRecorder !== recorder {
            activeRecorder.forceEndRecordingSession()
        }
        activeRecorders.insert(ObjectIdentifier(recorder))
        activeRecorder = recorder
    }

    static func end(for recorder: AnyObject) {
        activeRecorders.remove(ObjectIdentifier(recorder))
        if let activeRecorder, activeRecorder === recorder as AnyObject {
            self.activeRecorder = nil
        }
    }

    /// `deinit` is non-isolated under Swift 6 strict concurrency. Recorder fields are
    /// `NSView`s and deallocate on the main thread, so remove the entry synchronously
    /// there — a deferred removal leaves `isAnyRecording` briefly stale and races
    /// parallel tests. The `Task` path is a fallback for off-main release.
    nonisolated static func endOnDeinit(for recorder: AnyObject) {
        let id = ObjectIdentifier(recorder)
        if Thread.isMainThread {
            MainActor.assumeIsolated { _ = activeRecorders.remove(id) }
        } else {
            Task { @MainActor in activeRecorders.remove(id) }
        }
    }

    static func beginTestRecording(for recorder: AnyObject) {
        activeRecorders.insert(ObjectIdentifier(recorder))
    }

    static func endTestRecording(for recorder: AnyObject) {
        activeRecorders.remove(ObjectIdentifier(recorder))
    }
}

/// `@MainActor` namespace exposing whether any recorder field — fire-once or
/// continuous — is currently capturing input. Useful for hosts that need to
/// suppress their own keyboard handling while a shortcut is being recorded.
public enum ShortcutRecording {
    @MainActor public static var isActive: Bool { ShortcutRecordingState.isAnyRecording }
}
