import AppKit
import Carbon.HIToolbox

/// An AppKit control that records sequential shortcuts.
///
/// Subclasses `NSSearchField` to provide a familiar text-field appearance.
/// Click to start recording, then perform any combination of: keystrokes,
/// modified left-clicks, right/middle/other mouse-button clicks, scroll
/// directions, or trackpad gestures (pinch, rotate, smart magnify). Each
/// captured input becomes one step in the sequence; recording finalizes
/// after a 1-second pause.
///
/// Press Escape to cancel without saving. Press Delete (only before any
/// step is captured) to clear the existing sequence.
///
/// **Left-click is uniquely special**: a bare left-click (no modifiers) is
/// not capturable as a step — it's reserved for UI interactions (focusing
/// the field, clicking other controls). Bare left-clicks outside the field
/// finalize the recording (the unambiguous "click away to dismiss"
/// gesture). All other inputs — including right-click and other mouse
/// buttons — can be captured as steps with no modifiers required.
///
/// For SwiftUI, use ``ShortcutSequenceRecorderView`` instead.
public final class ShortcutSequenceRecorderField: NSSearchField, NSSearchFieldDelegate, NSTextViewDelegate,
    ActiveShortcutRecorder
{
    override public class var cellClass: AnyClass? {
        get { CenteredSearchFieldCell.self }
        set { super.cellClass = newValue }
    }

    private let minimumWidth: CGFloat = 130
    private var bezeledHeight: CGFloat = 0
    private nonisolated(unsafe) var eventMonitor: Any?
    private var cancelButton: NSButtonCell?
    private var canBecomeKey = false
    private var isStartingRecording = false
    private var recordedSteps: [Shortcut] = []
    private var timeoutTask: Task<Void, Never>?

    /// Cumulative magnification accumulated within the current pinch gesture.
    private var pinchAccumulator: Double = 0
    /// Cumulative rotation (degrees) accumulated within the current rotate gesture.
    private var rotateAccumulator: Double = 0
    /// Whether the current scroll burst has already been captured as a step.
    private var scrollCaptured: Bool = false
    /// Whether the current pinch gesture has already been captured as a step.
    /// Cleared on the gesture's `.ended`/`.cancelled` phase or when a non-`.magnify`
    /// event arrives, so the next physical pinch can record a fresh step.
    private var pinchCaptured: Bool = false
    /// Same as `pinchCaptured`, but for rotate gestures.
    private var rotateCaptured: Bool = false

    /// Timeout interval in seconds before finalizing a recording.
    private let recordingTimeout: TimeInterval = 1.0

    /// Whether this field is currently recording a sequence.
    public private(set) var isRecording = false

    override public var canBecomeKeyView: Bool { canBecomeKey }

    /// The currently recorded shortcut sequence, or nil if cleared.
    public var shortcutSequence: ShortcutSequence? {
        didSet {
            updateDisplay()
        }
    }

    /// Called when the user records or clears a shortcut sequence.
    public var onShortcutSequenceChange: ((ShortcutSequence?) -> Void)?

    /// The placeholder text shown when not recording and no sequence is set.
    public var defaultPlaceholder: String = "Record Sequence" {
        didSet {
            if !isRecording {
                placeholderString = defaultPlaceholder
            }
        }
    }

    /// The placeholder text shown during recording.
    public var recordingPlaceholder: String = "Record sequence\u{2026}"

    /// The text color for the sequence display. Nil uses the system default.
    public var fieldTextColor: NSColor? {
        didSet { textColor = fieldTextColor }
    }

    /// The background color of the field. Nil uses the system default.
    ///
    /// Setting a background color replaces the default bezel with a custom
    /// layer-backed rounded rectangle so the color is fully visible.
    public var fieldBackgroundColor: NSColor? {
        didSet {
            applyBackgroundColor()
        }
    }

    private func applyBackgroundColor() {
        if let color = fieldBackgroundColor {
            isBezeled = false
            layer?.backgroundColor = color.cgColor
            layer?.cornerRadius = 6
            layer?.borderWidth = 0.5
            layer?.borderColor = NSColor.separatorColor.cgColor
        } else {
            isBezeled = true
            layer?.backgroundColor = nil
            layer?.cornerRadius = 0
            layer?.borderWidth = 0
            layer?.borderColor = nil
        }
    }

    private var showsCancelButton: Bool {
        get { (cell as? NSSearchFieldCell)?.cancelButtonCell != nil }
        set { (cell as? NSSearchFieldCell)?.cancelButtonCell = newValue ? cancelButton : nil }
    }

    deinit {
        ShortcutRecordingState.endOnDeinit(for: self)
        // timeoutTask uses [weak self] so it's safe to let it fire after dealloc.
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
        }
    }

    override public init(frame _: NSRect) {
        super.init(frame: NSRect(x: 0, y: 0, width: minimumWidth, height: 24))
        setup()
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    public convenience init() {
        self.init(frame: .zero)
    }

    private func setup() {
        delegate = self
        placeholderString = defaultPlaceholder
        alignment = .center
        (cell as? NSSearchFieldCell)?.searchButtonCell = nil
        wantsLayer = true
        setContentHuggingPriority(.defaultHigh, for: .vertical)
        setContentHuggingPriority(.defaultHigh, for: .horizontal)

        cancelButton = (cell as? NSSearchFieldCell)?.cancelButtonCell
        bezeledHeight = super.intrinsicContentSize.height
        updateDisplay()
    }

    override public var intrinsicContentSize: NSSize {
        NSSize(width: minimumWidth, height: bezeledHeight)
    }

    override public func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow == nil {
            recordedSteps = []
            endRecording()
        }
        super.viewWillMove(toWindow: newWindow)
    }

    override public func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard window != nil else { return }

        canBecomeKey = false
        DispatchQueue.main.async { [weak self] in
            self?.canBecomeKey = true
        }
    }

    private func updateDisplay() {
        if let shortcutSequence {
            stringValue = shortcutSequence.displayString
            showsCancelButton = true
        } else {
            stringValue = ""
            showsCancelButton = false
        }
    }

    func startRecording() {
        guard !isRecording else { return }

        isStartingRecording = true
        isRecording = true
        ShortcutRecordingState.begin(for: self)
        recordedSteps = []
        resetGestureAccumulators()
        placeholderString = recordingPlaceholder
        showsCancelButton = shortcutSequence != nil

        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [
            .keyDown,
            .leftMouseDown,
            .rightMouseDown,
            .otherMouseDown,
            .scrollWheel,
            .magnify,
            .rotate,
            .smartMagnify,
            .leftMouseUp,
            .rightMouseUp,
        ]) { [weak self] event in
            guard let self, isRecording else { return event }
            return handleEvent(event)
        }
        isStartingRecording = false
    }

    func endRecording() {
        guard isRecording else { return }
        isRecording = false
        resetGestureAccumulators()
        ShortcutRecordingState.end(for: self)
        timeoutTask?.cancel()
        timeoutTask = nil
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
            self.eventMonitor = nil
        }
        placeholderString = defaultPlaceholder
        updateDisplay()
    }

    private func resetGestureAccumulators() {
        pinchAccumulator = 0
        rotateAccumulator = 0
        scrollCaptured = false
        pinchCaptured = false
        rotateCaptured = false
    }

    func finalizeRecording() {
        if !recordedSteps.isEmpty {
            let seq = ShortcutSequence(steps: recordedSteps)
            shortcutSequence = seq
            onShortcutSequenceChange?(seq)
        }
        recordedSteps = []
        endRecording()
        blur()
    }

    private func forceEndRecording() {
        recordedSteps = []
        endRecording()
    }

    private func resetTimeout() {
        timeoutTask?.cancel()
        timeoutTask = Task { @MainActor [weak self] in
            do {
                guard let self else { return }
                try await Task.sleep(for: .seconds(recordingTimeout))
                finalizeRecording()
            } catch {
                // Task was cancelled — do nothing
            }
        }
    }

    private func blur() {
        window?.makeFirstResponder(nil)
    }

    // MARK: - NSSearchFieldDelegate

    public func controlTextDidEndEditing(_: Notification) {
        // Guard against reentrant calls from startRecording() — setting placeholderString
        // can trigger controlTextDidEndEditing synchronously, which would call endRecording()
        // and set isRecording=false before startRecording() finishes.
        guard !isStartingRecording else { return }

        // Submit any in-progress steps (e.g. when clicking to another field).
        // Don't call finalizeRecording() here — its blur() would interfere with
        // the first-responder transition already in progress.
        if !recordedSteps.isEmpty {
            let seq = ShortcutSequence(steps: recordedSteps)
            shortcutSequence = seq
            onShortcutSequenceChange?(seq)
            recordedSteps = []
        }
        endRecording()
    }

    public func control(_: NSControl, textView _: NSTextView, shouldChangeTextIn _: NSRange,
                        replacementString _: String?) -> Bool
    {
        false
    }

    public func searchFieldDidEndSearching(_: NSSearchField) {
        shortcutSequence = nil
        onShortcutSequenceChange?(nil)
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

        if !recordedSteps.isEmpty {
            finalizeRecording()
        } else {
            endRecording()
        }
        return true
    }

    // MARK: - NSTextViewDelegate

    public func textView(_: NSTextView, shouldChangeTextIn _: NSRange, replacementString _: String?) -> Bool {
        false
    }

    public func textView(_: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        handleCommand(commandSelector, event: NSApp.currentEvent)
    }

    // MARK: - Event Handling

    func handleCommand(_ commandSelector: Selector, event: NSEvent?) -> Bool {
        guard isRecording else { return false }
        guard shouldHandleCommand(commandSelector) else { return false }
        guard let event, event.type == .keyDown else { return true }
        _ = handleEvent(event)
        return true
    }

    private func shouldHandleCommand(_ commandSelector: Selector) -> Bool {
        commandSelector == #selector(NSResponder.insertTab(_:)) ||
            commandSelector == #selector(NSResponder.insertBacktab(_:)) ||
            commandSelector == #selector(NSResponder.cancelOperation(_:)) ||
            commandSelector == #selector(NSResponder.deleteBackward(_:)) ||
            commandSelector == #selector(NSResponder.deleteForward(_:))
    }

    func handleEvent(_ event: NSEvent) -> NSEvent? {
        guard isRecording else { return event }

        // A non-scroll event ends any in-progress scroll burst.
        if event.type != .scrollWheel {
            scrollCaptured = false
        }
        // Same idea for pinch / rotate — defensive against missed `.ended` events.
        if event.type != .magnify {
            pinchCaptured = false
        }
        if event.type != .rotate {
            rotateCaptured = false
        }

        switch event.type {
        case .leftMouseUp, .rightMouseUp:
            return handleMouseUpEvent(event)
        case .keyDown:
            return handleKeyEvent(event)
        case .leftMouseDown, .rightMouseDown, .otherMouseDown:
            return handleMouseButtonEvent(event)
        case .scrollWheel:
            return handleScrollEvent(event)
        case .magnify, .rotate, .smartMagnify:
            return handleGestureEvent(event)
        default:
            return event
        }
    }

    private func handleMouseUpEvent(_ event: NSEvent) -> NSEvent? {
        // Asymmetry: left-click outside finalizes; right-click outside doesn't.
        //
        // Bare left-click can't be a sequence step (it's reserved for UI — focusing
        // controls, dismissing the recorder), so a left-click outside the field
        // unambiguously means "I'm done — dismiss." We finalize on mouseUp.
        //
        // Right-click (and other mouse buttons), in contrast, *can* be steps with
        // no modifiers required. The down event was just captured as a step, and
        // the user may continue with more steps. We let the 1-second step timeout
        // (or first-responder loss) close the recording when they actually stop.
        if event.type == .rightMouseUp {
            return nil
        }
        let clickPoint = convert(event.locationInWindow, from: nil)
        let clickMargin: CGFloat = 3.0
        if !bounds.insetBy(dx: -clickMargin, dy: -clickMargin).contains(clickPoint) {
            finalizeRecording()
            return event
        }
        return nil
    }

    private func handleKeyEvent(_ event: NSEvent) -> NSEvent? {
        let modifiers = Shortcut.canonicalModifiers(event.modifierFlags)

        // Escape cancels without saving
        if modifiers.isEmpty, event.keyCode == UInt16(kVK_Escape) {
            recordedSteps = []
            endRecording()
            blur()
            return nil
        }

        // Delete clears the current sequence (only when no steps recorded yet)
        if modifiers.isEmpty, recordedSteps.isEmpty,
           event.keyCode == UInt16(kVK_Delete) || event.keyCode == UInt16(kVK_ForwardDelete)
        {
            shortcutSequence = nil
            onShortcutSequenceChange?(nil)
            endRecording()
            blur()
            return nil
        }

        let step = Shortcut(keyCode: event.keyCode, modifiers: modifiers)
        appendStep(step)
        return nil
    }

    private func handleMouseButtonEvent(_ event: NSEvent) -> NSEvent? {
        let clickPoint = convert(event.locationInWindow, from: nil)
        let clickMargin: CGFloat = 3.0
        let isInsideField = bounds.insetBy(dx: -clickMargin, dy: -clickMargin).contains(clickPoint)

        let modifiers = Shortcut.canonicalModifiers(event.modifierFlags)

        // Left mouse button
        if event.type == .leftMouseDown {
            if !isInsideField {
                // Click outside — let the mouseUp handler finalize the recording.
                return event
            }

            // Bare left click inside — ignore (reserved for UI)
            if modifiers.isEmpty {
                return nil
            }

            // Modified left click inside — capture as a step
            let step = Shortcut(kind: .mouseButton(number: event.buttonNumber), modifiers: modifiers)
            appendStep(step)
            return nil
        }

        // Right click or other mouse buttons — always capture as a step
        let step = Shortcut(kind: .mouseButton(number: event.buttonNumber), modifiers: modifiers)
        appendStep(step)
        return nil
    }

    private func handleScrollEvent(_ event: NSEvent) -> NSEvent? {
        // Ignore momentum scroll events (trackpad inertia)
        if event.momentumPhase != [] {
            return nil
        }

        // Fresh scroll burst (trackpad finger touch-down) clears any prior capture flag.
        if event.phase == .began {
            scrollCaptured = false
        }

        // Suppress repeats within the same scroll burst.
        if scrollCaptured {
            return nil
        }

        // Stricter threshold for recording than for matching, so a tiny stray
        // trackpad twitch doesn't accidentally append a Scroll step.
        let dx = abs(event.scrollingDeltaX)
        let dy = abs(event.scrollingDeltaY)
        guard dx >= Shortcut.scrollRecordingThreshold || dy >= Shortcut.scrollRecordingThreshold else {
            return nil
        }

        guard let direction = Shortcut.scrollDirection(from: event) else {
            return nil
        }

        // Suppress further events only for trackpad bursts (which have phase info).
        // Mouse-wheel notches have no phase — each is a distinct user action and
        // should be capturable as its own step.
        if event.phase != [] {
            scrollCaptured = true
        }

        let modifiers = Shortcut.canonicalModifiers(event.modifierFlags)

        let step = Shortcut(kind: .scroll(direction: direction), modifiers: modifiers)
        appendStep(step)
        return nil
    }

    private func handleGestureEvent(_ event: NSEvent) -> NSEvent? {
        let modifiers = Shortcut.canonicalModifiers(event.modifierFlags)

        // Reset accumulators / captured flags when a continuous gesture ends, so the
        // next physical gesture starts fresh.
        let isContinuousType = event.type == .magnify || event.type == .rotate
        if isContinuousType, event.phase == .ended || event.phase == .cancelled {
            pinchAccumulator = 0
            rotateAccumulator = 0
            pinchCaptured = false
            rotateCaptured = false
            return nil
        }

        // Fresh gesture burst clears any prior capture flag — defensive against
        // missed `.ended` events from the OS.
        if event.type == .magnify, event.phase == .began {
            pinchCaptured = false
            pinchAccumulator = 0
        }
        if event.type == .rotate, event.phase == .began {
            rotateCaptured = false
            rotateAccumulator = 0
        }

        switch event.type {
        case .magnify:
            // Suppress further captures within the same physical pinch.
            if pinchCaptured { return nil }
            pinchAccumulator += Double(event.magnification)
            if abs(pinchAccumulator) >= Shortcut.magnifyRecordingThreshold {
                let kind: Shortcut.Kind = pinchAccumulator < 0 ? .pinchIn : .pinchOut
                let step = Shortcut(kind: kind, modifiers: modifiers)
                appendStep(step)
                pinchCaptured = true
            }
            return nil
        case .rotate:
            if rotateCaptured { return nil }
            rotateAccumulator += Double(event.rotation)
            if abs(rotateAccumulator) >= Shortcut.rotateRecordingThreshold {
                let kind: Shortcut.Kind = rotateAccumulator > 0
                    ? .rotateCounterClockwise
                    : .rotateClockwise
                let step = Shortcut(kind: kind, modifiers: modifiers)
                appendStep(step)
                rotateCaptured = true
            }
            return nil
        case .smartMagnify:
            let step = Shortcut(kind: .smartMagnify, modifiers: modifiers)
            appendStep(step)
            return nil
        default:
            return event
        }
    }

    /// Append a recorded step, refresh the in-progress display, reset the timeout,
    /// and clear gesture accumulators for the next step.
    ///
    /// `scrollCaptured` / `pinchCaptured` / `rotateCaptured` are intentionally NOT
    /// reset here — a single physical gesture burst should produce at most one step.
    /// Each flag is cleared by either a non-matching event type (see `handleEvent`)
    /// or by the gesture's `.ended` / `.cancelled` phase.
    private func appendStep(_ step: Shortcut) {
        recordedSteps.append(step)
        stringValue = recordedSteps.map(\.displayString).joined(separator: " ") + " …"
        resetTimeout()
        pinchAccumulator = 0
        rotateAccumulator = 0
    }

    func forceEndRecordingSession() {
        forceEndRecording()
    }
}
