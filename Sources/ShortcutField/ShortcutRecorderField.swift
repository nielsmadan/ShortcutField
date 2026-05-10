import AppKit
import Carbon.HIToolbox

@MainActor
protocol ActiveShortcutRecorder: AnyObject {
    func forceEndRecordingSession()
}

enum ShortcutRecordingState {
    private nonisolated(unsafe) static var activeRecorders: Set<ObjectIdentifier> = []
    private nonisolated(unsafe) weak static var activeRecorder: (any ActiveShortcutRecorder)?

    static var isAnyRecording: Bool {
        !activeRecorders.isEmpty
    }

    @MainActor
    static func begin(for recorder: AnyObject & ActiveShortcutRecorder) {
        if let activeRecorder, activeRecorder !== recorder {
            activeRecorder.forceEndRecordingSession()
        }
        activeRecorders.insert(ObjectIdentifier(recorder))
        activeRecorder = recorder
    }

    @MainActor
    static func end(for recorder: AnyObject) {
        activeRecorders.remove(ObjectIdentifier(recorder))
        if let activeRecorder, activeRecorder === recorder as AnyObject {
            self.activeRecorder = nil
        }
    }

    static func endOnDeinit(for recorder: AnyObject) {
        activeRecorders.remove(ObjectIdentifier(recorder))
    }

    @MainActor
    static func beginTestRecording(for recorder: AnyObject) {
        activeRecorders.insert(ObjectIdentifier(recorder))
    }

    @MainActor
    static func endTestRecording(for recorder: AnyObject) {
        activeRecorders.remove(ObjectIdentifier(recorder))
    }
}

/// NSSearchFieldCell subclass that vertically centers text when the bezel
/// is disabled.
class CenteredSearchFieldCell: NSSearchFieldCell {
    override func drawInterior(withFrame cellFrame: NSRect, in controlView: NSView) {
        super.drawInterior(withFrame: centeredFrame(cellFrame), in: controlView)
    }

    override func edit(withFrame rect: NSRect, in controlView: NSView,
                       editor textObj: NSText, delegate: Any?, event: NSEvent?)
    {
        super.edit(withFrame: centeredFrame(rect), in: controlView, editor: textObj,
                   delegate: delegate, event: event)
    }

    override func select(withFrame rect: NSRect, in controlView: NSView,
                         editor textObj: NSText, delegate: Any?,
                         start selStart: Int, length selLength: Int)
    {
        super.select(withFrame: centeredFrame(rect), in: controlView, editor: textObj,
                     delegate: delegate, start: selStart, length: selLength)
    }

    private func centeredFrame(_ frame: NSRect) -> NSRect {
        guard !isBezeled else { return frame }
        let minimumHeight = cellSize(forBounds: frame).height
        var adjusted = frame
        adjusted.origin.y += (frame.height - minimumHeight) / 2
        adjusted.size.height = minimumHeight
        return adjusted
    }
}

/// An AppKit control that records a fire-once shortcut: a single input or a
/// multi-step sequence of any combination of keystrokes, modified left-clicks,
/// right/middle/other mouse-button clicks, scroll directions, or trackpad
/// gestures.
///
/// Subclasses `NSSearchField` to provide a familiar text-field appearance.
/// Click to start recording, then perform any combination of inputs. Each
/// captured input becomes one step. Recording finalizes after a 1-second
/// pause OR when the user makes a bare left-click anywhere (no modifiers) —
/// the unambiguous "I'm done" gesture.
///
/// Press Escape to cancel without saving. Press Delete (only before any
/// step is captured) to clear the existing shortcut.
///
/// **Left-click is uniquely special**: a bare left-click (no modifiers) is
/// not capturable as a step — it's reserved for UI interactions and serves
/// as the "finalize recording" gesture. Modified left-clicks (e.g. `⌃Left
/// Click`) are capturable. All other inputs — including right-click and
/// other mouse buttons — can be captured as steps with no modifiers required.
///
/// For SwiftUI, use ``ShortcutRecorderView`` instead. For sensitivity-bearing
/// continuous shortcuts (scroll-to-zoom etc.), use ``ContinuousShortcutRecorderField``.
public final class ShortcutRecorderField: NSSearchField, NSSearchFieldDelegate, NSTextViewDelegate,
    ActiveShortcutRecorder
{
    override public class var cellClass: AnyClass? {
        get { CenteredSearchFieldCell.self }
        set { super.cellClass = newValue }
    }

    /// Whether any recorder instance is currently in recording mode.
    public static var isAnyRecording: Bool { ShortcutRecordingState.isAnyRecording }

    /// Minimum intrinsic width. SwiftUI's `.frame(width:)` overrides this; the
    /// floor only matters when no explicit frame is set. Defaults to 130.
    public var minimumWidth: CGFloat = 130 {
        didSet { invalidateIntrinsicContentSize() }
    }

    private var bezeledHeight: CGFloat = 0
    private nonisolated(unsafe) var eventMonitor: Any?
    private var cancelButton: NSButtonCell?
    private var canBecomeKey = false
    private var isStartingRecording = false
    private var recordedSteps: [Shortcut.Step] = []
    private var timeoutTask: Task<Void, Never>?

    private var gestures = GestureAccumulator()
    /// Whether the current scroll burst has already been captured as a step.
    private var scrollCaptured: Bool = false
    /// Whether the current pinch gesture has already been captured as a step.
    /// Cleared on the gesture's `.ended`/`.cancelled` phase or when a non-`.magnify`
    /// event arrives, so the next physical pinch can record a fresh step.
    private var pinchCaptured: Bool = false
    /// Same as `pinchCaptured`, but for rotate gestures.
    private var rotateCaptured: Bool = false

    private let recordingTimeout: TimeInterval = 1.0

    /// Whether this field is currently recording a shortcut.
    public private(set) var isRecording = false

    override public var canBecomeKeyView: Bool { canBecomeKey }

    /// The currently recorded shortcut, or nil if cleared.
    public var shortcut: Shortcut? {
        didSet {
            updateDisplay()
        }
    }

    /// Called when the user records or clears a shortcut.
    public var onShortcutChange: ((Shortcut?) -> Void)?

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

    /// The text color for the shortcut display. Nil uses the system default.
    public var fieldTextColor: NSColor? {
        didSet { textColor = fieldTextColor }
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
        // High vertical hugging keeps the field at its intrinsic height (don't
        // stretch tall). Low horizontal hugging lets `.frame(width:)` expand it
        // beyond the intrinsic minimumWidth.
        setContentHuggingPriority(.defaultHigh, for: .vertical)
        setContentHuggingPriority(.defaultLow, for: .horizontal)

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
        if let shortcut {
            stringValue = shortcut.displayString
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
        showsCancelButton = shortcut != nil

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
        gestures.resetAll()
        scrollCaptured = false
        pinchCaptured = false
        rotateCaptured = false
    }

    func finalizeRecording() {
        if !recordedSteps.isEmpty {
            let new = Shortcut(steps: recordedSteps)
            shortcut = new
            onShortcutChange?(new)
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
            } catch {}
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
            let new = Shortcut(steps: recordedSteps)
            shortcut = new
            onShortcutChange?(new)
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
        shortcut = nil
        onShortcutChange?(nil)
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
        // Bare left-click finalizes (it's reserved for UI, can't be a step). Right-click
        // and other buttons can be steps, so we let the timeout close the recording instead.
        if event.type == .rightMouseUp {
            return nil
        }

        let modifiers = Shortcut.canonicalModifiers(event.modifierFlags)
        if !modifiers.isEmpty {
            // Modified left-up — paired with the modified left-down captured as a step.
            // Don't treat as finalize.
            return nil
        }

        let clickPoint = convert(event.locationInWindow, from: nil)
        let clickMargin: CGFloat = 3.0
        let isInsideField = bounds.insetBy(dx: -clickMargin, dy: -clickMargin).contains(clickPoint)

        finalizeRecording()
        // Pass the event through if the click was outside the field, so other UI
        // (buttons, links, etc.) still receives the click. Inside-field clicks are
        // consumed since they're targeting the recorder itself.
        return isInsideField ? nil : event
    }

    private func handleKeyEvent(_ event: NSEvent) -> NSEvent? {
        let modifiers = Shortcut.canonicalModifiers(event.modifierFlags)

        if modifiers.isEmpty, event.keyCode == UInt16(kVK_Escape) {
            recordedSteps = []
            endRecording()
            blur()
            return nil
        }

        // Delete with no steps recorded clears the existing shortcut. Once the
        // user has captured at least one step, Delete becomes a recordable step.
        if modifiers.isEmpty, recordedSteps.isEmpty,
           event.keyCode == UInt16(kVK_Delete) || event.keyCode == UInt16(kVK_ForwardDelete)
        {
            shortcut = nil
            onShortcutChange?(nil)
            endRecording()
            blur()
            return nil
        }

        let step = Shortcut.Step(keyCode: event.keyCode, modifiers: modifiers)
        appendStep(step)
        return nil
    }

    private func handleMouseButtonEvent(_ event: NSEvent) -> NSEvent? {
        let modifiers = Shortcut.canonicalModifiers(event.modifierFlags)

        if event.type == .leftMouseDown {
            // Bare left-click is reserved for UI / finalize — pass outside clicks
            // through so the target sees both down and up; mouseUp handler commits.
            if modifiers.isEmpty {
                let clickPoint = convert(event.locationInWindow, from: nil)
                let clickMargin: CGFloat = 3.0
                let isInsideField = bounds.insetBy(dx: -clickMargin, dy: -clickMargin).contains(clickPoint)
                return isInsideField ? nil : event
            }

            let step = Shortcut.Step(kind: .mouseButton(number: event.buttonNumber), modifiers: modifiers)
            appendStep(step)
            return nil
        }

        let step = Shortcut.Step(kind: .mouseButton(number: event.buttonNumber), modifiers: modifiers)
        appendStep(step)
        return nil
    }

    private func handleScrollEvent(_ event: NSEvent) -> NSEvent? {
        if event.momentumPhase != [] { return nil }

        // Fresh scroll burst (trackpad finger touch-down) clears any prior capture flag.
        if event.phase == .began {
            scrollCaptured = false
        }
        if scrollCaptured { return nil }

        guard let direction = Shortcut.scrollDirectionAboveRecordingThreshold(from: event) else {
            return nil
        }

        // Suppress further events only for trackpad bursts (which have phase info).
        // Mouse-wheel notches have no phase — each is a distinct user action and
        // should be capturable as its own step.
        if event.phase != [] {
            scrollCaptured = true
        }

        let modifiers = Shortcut.canonicalModifiers(event.modifierFlags)
        let step = Shortcut.Step(kind: .scroll(direction: direction), modifiers: modifiers)
        appendStep(step)
        return nil
    }

    private func handleGestureEvent(_ event: NSEvent) -> NSEvent? {
        let modifiers = Shortcut.canonicalModifiers(event.modifierFlags)

        // Reset accumulators / captured flags when a continuous gesture ends, so the
        // next physical gesture starts fresh.
        let isContinuousType = event.type == .magnify || event.type == .rotate
        if isContinuousType, event.phase == .ended || event.phase == .cancelled {
            gestures.resetAll()
            pinchCaptured = false
            rotateCaptured = false
            return nil
        }

        // Fresh gesture burst clears any prior capture flag — defensive against
        // missed `.ended` events from the OS.
        if event.type == .magnify, event.phase == .began {
            pinchCaptured = false
            gestures.resetPinch()
        }
        if event.type == .rotate, event.phase == .began {
            rotateCaptured = false
            gestures.resetRotate()
        }

        switch event.type {
        case .magnify:
            // Suppress further captures within the same physical pinch.
            if pinchCaptured { return nil }
            if let kind = gestures.consumeMagnify(Double(event.magnification)) {
                appendStep(Shortcut.Step(kind: kind, modifiers: modifiers))
                pinchCaptured = true
            }
            return nil
        case .rotate:
            if rotateCaptured { return nil }
            if let kind = gestures.consumeRotate(Double(event.rotation)) {
                appendStep(Shortcut.Step(kind: kind, modifiers: modifiers))
                rotateCaptured = true
            }
            return nil
        case .smartMagnify:
            let step = Shortcut.Step(kind: .smartMagnify, modifiers: modifiers)
            appendStep(step)
            return nil
        default:
            return event
        }
    }

    /// `scrollCaptured` / `pinchCaptured` / `rotateCaptured` are intentionally NOT
    /// reset here — a single physical gesture burst should produce at most one step.
    /// Each flag is cleared by either a non-matching event type (see `handleEvent`)
    /// or by the gesture's `.ended` / `.cancelled` phase.
    private func appendStep(_ step: Shortcut.Step) {
        recordedSteps.append(step)
        stringValue = recordedSteps.map(\.displayString).joined(separator: " ") + " …"
        resetTimeout()
        gestures.resetAll()
    }

    func forceEndRecordingSession() {
        forceEndRecording()
    }
}
