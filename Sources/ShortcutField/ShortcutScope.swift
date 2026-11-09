/// Which events an `.onShortcut` binding responds to.
public enum ShortcutScope: Sendable, Hashable {
    /// Events for every window of the app: each mounted `.onShortcut` with this scope
    /// fires on a matching event, whichever window it was sent to.
    case app
    /// Only events sent to the window that contains the view carrying the modifier. A
    /// binding inside a sheet, panel or popover acts on that sheet, panel or popover,
    /// each a window of its own. Events sent to no window never fire it, and neither does
    /// anything before the view is placed in a window. A key press or click in another
    /// window ends a multi-step sequence in progress.
    case window
}
