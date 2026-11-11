import AppKit

/// A committed shortcut that a recorder field can render.
protocol ShortcutFieldDisplayable {
    var displayString: String { get }
    @MainActor func attributedDisplayString(
        style: ShortcutLabelStyle, font: NSFont, color: NSColor?
    ) -> NSAttributedString
}

extension DiscreteShortcut: ShortcutFieldDisplayable {}
extension ContinuousShortcut: ShortcutFieldDisplayable {}

/// Implementation detail. Not intended for external use or subclassing.
///
/// Shared `NSSearchField` plumbing for the two concrete recorder fields,
/// ``ShortcutRecorderField`` and ``ContinuousShortcutRecorderField``: cell class,
/// intrinsic sizing, key-view eligibility, the click hit-test, and the recording
/// session lifecycle. Subclasses supply the event mask, the event handler, and the
/// shortcut being displayed; everything else is shared.
///
/// It is `public` only because a public class's superclass must be public,
/// and `public` rather than `open` so external code cannot subclass it.
public class BaseShortcutRecorderField: NSSearchField, NSSearchFieldDelegate, NSTextViewDelegate,
    ActiveShortcutRecorder
{
    override public class var cellClass: AnyClass? {
        get { CenteredSearchFieldCell.self }
        set { super.cellClass = newValue }
    }

    /// Minimum intrinsic width. SwiftUI's `.frame(width:)` overrides this; the
    /// floor only matters when no explicit frame is set. Defaults to 160.
    public var minimumWidth: CGFloat = 160 {
        didSet { invalidateIntrinsicContentSize() }
    }

    /// The text color for the shortcut display. Nil uses the system default.
    public var fieldTextColor: NSColor? {
        didSet {
            textColor = fieldTextColor
            // In `.compact` style the color is baked into the attributed value, so a
            // plain `textColor` change wouldn't repaint it — re-render to pick it up.
            refreshDisplay()
        }
    }

    /// How the recorded shortcut is rendered in the field. Defaults to `.text`.
    /// In `.compact` style, gestures/scroll show SF Symbols and mouse clicks show
    /// short abbreviations, with the full text meaning surfaced as the field's
    /// tooltip. Changing it mid-recording is ignored until recording finalizes.
    public var labelStyle: ShortcutLabelStyle = .text {
        didSet {
            guard labelStyle != oldValue else { return }
            refreshDisplay()
        }
    }

    /// Disabling the field (AppKit `isEnabled` or SwiftUI `.disabled`) ends a recording
    /// session without committing it.
    override public var isEnabled: Bool {
        didSet {
            guard !isEnabled, isRecording else { return }
            forceEndRecordingSession()
            blur()
        }
    }

    /// Whether this field is currently recording.
    public internal(set) var isRecording = false

    /// The placeholder text shown when not recording and no shortcut is set.
    public var defaultPlaceholder: String = "Record Shortcut" {
        didSet {
            if !isRecording {
                placeholderString = defaultPlaceholder
            }
        }
    }

    /// The placeholder text shown during recording.
    public var recordingPlaceholder: String = "Record shortcut\u{2026}"

    var bezeledHeight: CGFloat = 0
    nonisolated(unsafe) var eventMonitor: Any?
    /// End the session when the field's window resigns key or closes.
    private nonisolated(unsafe) var windowObservers: [NSObjectProtocol] = []
    var cancelButton: NSButtonCell?
    /// Test seam: asks VoiceOver to speak `message` for `element`.
    var announcer: (Any, String) -> Void = { element, message in
        NSAccessibility.post(element: element, notification: .announcementRequested, userInfo: [
            .announcement: message,
            .priority: NSAccessibilityPriorityLevel.high.rawValue,
        ])
    }

    var canBecomeKey = false
    var isStartingRecording = false
    var gestures = GestureAccumulator()

    /// The committed shortcut as text, for VoiceOver: a compact style's symbols would read as
    /// object-replacement characters.
    var accessibilityText: String {
        displayedShortcut?.displayString ?? ""
    }

    /// Sets the name VoiceOver reads for the field, which defaults to "Shortcut". AppKit exposes
    /// the field to VoiceOver through its cell, so the name is stored on the cell.
    override public func setAccessibilityLabel(_ label: String?) {
        cell?.setAccessibilityLabel(label)
    }

    /// The name VoiceOver reads for the field, as stored on its cell.
    override public func accessibilityLabel() -> String? {
        cell?.accessibilityLabel()
    }

    override public var canBecomeKeyView: Bool {
        canBecomeKey
    }

    override public var intrinsicContentSize: NSSize {
        NSSize(width: minimumWidth, height: bezeledHeight)
    }

    override public init(frame _: NSRect) {
        super.init(frame: NSRect(x: 0, y: 0, width: 160, height: 24))
        setup()
    }

    @available(*, unavailable)
    public required init?(coder _: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    /// Create a recorder field at the default size.
    public convenience init() {
        self.init(frame: .zero)
    }

    deinit {
        ShortcutRecordingState.endOnDeinit(for: self)
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
        }
        windowObservers.forEach(NotificationCenter.default.removeObserver)
    }

    private func setup() {
        delegate = self
        alignment = .center
        (cell as? NSSearchFieldCell)?.searchButtonCell = nil
        wantsLayer = true
        // High vertical hugging keeps the field at its intrinsic height (don't
        // stretch tall). Low horizontal hugging lets `.frame(width:)` expand it
        // beyond the intrinsic minimumWidth.
        setContentHuggingPriority(.defaultHigh, for: .vertical)
        setContentHuggingPriority(.defaultLow, for: .horizontal)

        cancelButton = (cell as? NSSearchFieldCell)?.cancelButtonCell
        cell?.setAccessibilityLabel("Shortcut")
        captureBezeledHeight()
        configureAccessories()
        placeholderString = defaultPlaceholder
        updateDisplay()
    }

    // MARK: - Subclass hooks

    /// Event types the recording monitor observes.
    class var monitoredEvents: NSEvent.EventTypeMask {
        []
    }

    /// The committed shortcut to render, or nil when cleared.
    var displayedShortcut: (any ShortcutFieldDisplayable)? {
        nil
    }

    /// Add subclass-specific subviews during `setup()`.
    func configureAccessories() {}

    /// Reset per-session capture state as a recording session begins.
    func willStartRecording() {}

    /// Tear down per-session capture state as a recording session ends.
    func willEndRecording() {}

    /// Commit whatever the session captured so far, without blurring. Called when
    /// focus leaves the field mid-recording.
    func commitInProgressCapture() {}

    /// Discard the committed shortcut, in response to the cancel button.
    func clearCommittedShortcut() {}

    /// Inspect an event during recording. Return nil to consume it.
    func handleEvent(_ event: NSEvent) -> NSEvent? {
        event
    }

    /// End the session from a first-responder change, committing if appropriate.
    func endRecordingOnResign() {
        endRecording()
    }

    /// React to the cancel button appearing or disappearing.
    func cancelButtonVisibilityDidChange(_: Bool) {}

    // MARK: - Recording lifecycle

    func startRecording() {
        guard !isRecording else { return }
        // Drop any committed-shortcut tooltip so the in-progress preview doesn't
        // show a stale full-text meaning from the previous shortcut.
        toolTip = nil
        isStartingRecording = true
        isRecording = true
        ShortcutRecordingState.begin(for: self)
        willStartRecording()
        placeholderString = recordingPlaceholder
        showsCancelButton = displayedShortcut != nil

        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: Self.monitoredEvents) { [weak self] event in
            guard let self, isRecording else { return event }
            return handleMonitoredEvent(event)
        }
        observeWindow()
        isStartingRecording = false
        announcer(cell ?? self, "Recording shortcut")
    }

    /// The monitor sees every event in the app; only events sent to this field's window
    /// are recorded, and the rest pass through.
    func handleMonitoredEvent(_ event: NSEvent) -> NSEvent? {
        guard event.window === window else { return event }
        return handleEvent(event)
    }

    private func observeWindow() {
        guard let window else { return }
        let center = NotificationCenter.default
        let resign = NSWindow.didResignKeyNotification
        let close = NSWindow.willCloseNotification
        windowObservers = [
            center.addObserver(forName: resign, object: window, queue: nil) { [weak self] _ in
                MainActor.assumeIsolated { self?.windowDidResignKey() }
            },
            center.addObserver(forName: close, object: window, queue: nil) { [weak self] _ in
                MainActor.assumeIsolated { self?.forceEndRecordingSession() }
            },
        ]
    }

    /// Keystrokes now go to another window: keep what was captured and stop recording.
    private func windowDidResignKey() {
        commitInProgressCapture()
        endRecording()
        blur()
    }

    func endRecording() {
        guard isRecording else { return }
        isRecording = false
        willEndRecording()
        ShortcutRecordingState.end(for: self)
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
            self.eventMonitor = nil
        }
        windowObservers.forEach(NotificationCenter.default.removeObserver)
        windowObservers = []
        placeholderString = defaultPlaceholder
        updateDisplay()
        announcer(cell ?? self, "Recording ended")
    }

    func forceEndRecordingSession() {
        endRecording()
    }

    // MARK: - Display

    var showsCancelButton: Bool {
        get { (cell as? NSSearchFieldCell)?.cancelButtonCell != nil }
        set {
            (cell as? NSSearchFieldCell)?.cancelButtonCell = newValue ? cancelButton : nil
            cancelButtonVisibilityDidChange(newValue)
        }
    }

    func updateDisplay() {
        guard let displayedShortcut else {
            stringValue = ""
            toolTip = nil
            showsCancelButton = false
            return
        }
        switch labelStyle {
        case .text:
            stringValue = displayedShortcut.displayString
            toolTip = nil
        case .compact:
            attributedStringValue = aligned(displayedShortcut.attributedDisplayString(
                style: .compact, font: displayFont, color: fieldTextColor
            ))
            toolTip = displayedShortcut.displayString
        }
        showsCancelButton = true
    }

    /// Re-render the committed shortcut using the current `labelStyle`. No-ops while
    /// recording so an in-progress live preview isn't clobbered.
    func refreshDisplay() {
        guard !isRecording else { return }
        updateDisplay()
    }

    /// Font used to size inline symbol attachments; falls back to the system font.
    var displayFont: NSFont {
        font ?? .systemFont(ofSize: NSFont.systemFontSize)
    }

    /// Stamp the field's `alignment` onto an attributed value. Unlike `stringValue`,
    /// an attributed string carries its own paragraph style and ignores the control's
    /// alignment, so the icon/text would otherwise render left-aligned.
    func aligned(_ attributed: NSAttributedString) -> NSAttributedString {
        let mutable = NSMutableAttributedString(attributedString: attributed)
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = alignment
        // Our paragraph style replaces the cell's default, so restore tail truncation
        // that the plain-string path would otherwise get for free on overflow.
        paragraph.lineBreakMode = .byTruncatingTail
        mutable.addAttribute(
            .paragraphStyle, value: paragraph, range: NSRange(location: 0, length: mutable.length)
        )
        return mutable
    }

    // MARK: - Geometry & focus

    override public func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard window != nil else { return }

        canBecomeKey = false
        DispatchQueue.main.async { [weak self] in
            self?.canBecomeKey = true
        }
    }

    override public func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow == nil {
            forceEndRecordingSession()
        }
        super.viewWillMove(toWindow: newWindow)
    }

    /// Captures the field's natural bezeled height. Resolved here so `super` refers
    /// to `NSSearchField` rather than this class's `intrinsicContentSize` override.
    func captureBezeledHeight() {
        bezeledHeight = super.intrinsicContentSize.height
    }

    /// Relinquishes first-responder so further input flows to the host UI after
    /// recording finalizes or is cancelled — without this, the now-idle field
    /// keeps key focus.
    func blur() {
        window?.makeFirstResponder(nil)
    }

    /// Whether `event`'s location falls within the field's bounds (plus a small
    /// margin) — distinguishes clicks targeting the recorder from clicks
    /// elsewhere in the window.
    func isInsideField(_ event: NSEvent) -> Bool {
        guard event.window === window else { return false }
        let clickMargin: CGFloat = 3.0
        let point = convert(event.locationInWindow, from: nil)
        return bounds.insetBy(dx: -clickMargin, dy: -clickMargin).contains(point)
    }

    /// Whether `event` is a bare left-down on the clear (x) button, which shows while recording
    /// a field that holds a shortcut.
    func isClearButtonClick(_ event: NSEvent) -> Bool {
        guard event.type == .leftMouseDown, event.window === window, showsCancelButton,
              DiscreteShortcut.canonicalModifiers(event.modifierFlags).isEmpty,
              let cell = cell as? NSSearchFieldCell else { return false }
        return cell.cancelButtonRect(forBounds: bounds).contains(convert(event.locationInWindow, from: nil))
    }

    /// The recording monitor consumes clicks on the clear button, so the button's own action
    /// never runs mid-recording: clear here, dropping whatever the session captured.
    func clearFromButtonWhileRecording() {
        forceEndRecordingSession()
        clearCommittedShortcut()
        blur()
    }

    override public func becomeFirstResponder() -> Bool {
        guard window != nil else { return false }

        let shouldBecomeFirstResponder = super.becomeFirstResponder()
        guard shouldBecomeFirstResponder else { return false }

        startRecording()

        DispatchQueue.main.async { [weak self] in
            if let textView = self?.currentEditor() as? NSTextView {
                textView.insertionPointColor = .clear
                textView.delegate = self
            }
        }

        return true
    }

    override public func resignFirstResponder() -> Bool {
        let shouldResignFirstResponder = super.resignFirstResponder()
        guard shouldResignFirstResponder else { return false }
        guard !isStartingRecording else { return true }
        // controlTextDidEndEditing may have already ended recording during
        // this first-responder transition — skip if already handled.
        guard isRecording else { return true }

        endRecordingOnResign()
        return true
    }

    // MARK: - Delegates

    public func controlTextDidEndEditing(_: Notification) {
        // Guard against reentrant calls from startRecording() — setting placeholderString
        // can trigger controlTextDidEndEditing synchronously, which would call endRecording()
        // and set isRecording=false before startRecording() finishes.
        guard !isStartingRecording else { return }

        // Don't blur here — it would interfere with the first-responder transition
        // already in progress.
        commitInProgressCapture()
        endRecording()
    }

    public func control(_: NSControl, textView _: NSTextView, shouldChangeTextIn _: NSRange,
                        replacementString _: String?) -> Bool
    {
        false
    }

    public func searchFieldDidEndSearching(_: NSSearchField) {
        clearCommittedShortcut()
    }

    public func textView(_: NSTextView, shouldChangeTextIn _: NSRange, replacementString _: String?) -> Bool {
        false
    }
}
