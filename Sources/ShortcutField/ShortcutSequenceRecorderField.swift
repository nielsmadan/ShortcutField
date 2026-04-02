import AppKit
import Carbon.HIToolbox

/// An AppKit control that records sequential keyboard shortcuts.
///
/// Subclasses `NSSearchField` to provide a familiar text-field appearance.
/// Click to start recording, press key combinations in sequence (finalized
/// after a 1-second timeout), press Escape to cancel, or Delete to clear.
///
/// For SwiftUI, use ``ShortcutSequenceRecorderView`` instead.
public final class ShortcutSequenceRecorderField: NSSearchField, NSSearchFieldDelegate, NSTextViewDelegate, ActiveShortcutRecorder {
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
    public var recordingPlaceholder: String = "Press keys..."

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

    private func startRecording() {
        guard !isRecording else { return }

        isStartingRecording = true
        isRecording = true
        ShortcutRecordingState.begin(for: self)
        recordedSteps = []
        placeholderString = recordingPlaceholder
        showsCancelButton = shortcutSequence != nil

        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [
            .keyDown,
            .leftMouseUp,
            .rightMouseUp
        ]) { [weak self] event in
            guard let self, isRecording else { return event }
            return handleEvent(event)
        }
        isStartingRecording = false
    }

    private func endRecording() {
        guard isRecording else { return }
        isRecording = false
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

    private func finalizeRecording() {
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
                try await Task.sleep(for: .seconds(self.recordingTimeout))
                self.finalizeRecording()
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
                        replacementString _: String?) -> Bool {
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

    private func handleCommand(_ commandSelector: Selector, event: NSEvent?) -> Bool {
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

    private func handleEvent(_ event: NSEvent) -> NSEvent? {
        guard isRecording else { return event }

        if event.type == .leftMouseUp || event.type == .rightMouseUp {
            let clickPoint = convert(event.locationInWindow, from: nil)
            let clickMargin: CGFloat = 3.0
            if !bounds.insetBy(dx: -clickMargin, dy: -clickMargin).contains(clickPoint) {
                finalizeRecording()
                return event
            }
            return nil
        }

        guard event.type == .keyDown else { return event }

        let modifiers = event.modifierFlags
            .intersection(.deviceIndependentFlagsMask)
            .subtracting([.capsLock, .numericPad, .function])

        // Escape cancels without saving
        if modifiers.isEmpty, event.keyCode == UInt16(kVK_Escape) {
            recordedSteps = []
            endRecording()
            blur()
            return nil
        }

        // Delete clears the current sequence (only when no steps recorded yet)
        if modifiers.isEmpty, recordedSteps.isEmpty,
           event.keyCode == UInt16(kVK_Delete) || event.keyCode == UInt16(kVK_ForwardDelete) {
            shortcutSequence = nil
            onShortcutSequenceChange?(nil)
            endRecording()
            blur()
            return nil
        }

        // Append step and show progress
        let step = Shortcut(keyCode: event.keyCode, modifiers: modifiers)
        recordedSteps.append(step)
        stringValue = recordedSteps.map(\.displayString).joined(separator: " ") + " …"
        resetTimeout()
        return nil
    }

    func _startRecordingForTesting() {
        startRecording()
    }

    func _endRecordingForTesting() {
        endRecording()
    }

    func _handleEventForTesting(_ event: NSEvent) -> NSEvent? {
        handleEvent(event)
    }

    func _finalizeRecordingForTesting() {
        finalizeRecording()
    }

    func _handleCommandForTesting(_ commandSelector: Selector, event: NSEvent?) -> Bool {
        handleCommand(commandSelector, event: event)
    }

    func forceEndRecordingSession() {
        forceEndRecording()
    }

    func _resignFirstResponderForTesting() {
        if !recordedSteps.isEmpty {
            finalizeRecording()
        } else {
            endRecording()
        }
    }

    func _controlTextDidEndEditingForTesting() {
        controlTextDidEndEditing(Notification(name: NSControl.textDidEndEditingNotification))
    }
}
