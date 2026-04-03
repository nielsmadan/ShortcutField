import AppKit
import Carbon.HIToolbox

/// An AppKit control that records mouse button presses and scroll wheel inputs.
///
/// Subclasses `NSSearchField` to provide a familiar text-field appearance with
/// a clear button. Click to start recording, then press a mouse button or scroll
/// the wheel to set the input. Press Escape to cancel, or Delete to clear.
///
/// Bare left clicks (no modifiers) are reserved for UI interaction and will not
/// be captured. Left clicks with modifiers (e.g. ⌃Left Click) are captured.
///
/// For SwiftUI, use ``MouseInputRecorderView`` instead.
public final class MouseInputRecorderField: NSSearchField, NSSearchFieldDelegate, NSTextViewDelegate,
    ActiveShortcutRecorder
{
    override public class var cellClass: AnyClass? {
        get { CenteredSearchFieldCell.self }
        set { super.cellClass = newValue }
    }

    /// Whether any recorder instance is currently in recording mode.
    public static var isAnyRecording: Bool { ShortcutRecordingState.isAnyRecording }

    private let minimumWidth: CGFloat = 130
    private var bezeledHeight: CGFloat = 0
    private nonisolated(unsafe) var eventMonitor: Any?
    private var cancelButton: NSButtonCell?
    private var canBecomeKey = false
    private var isStartingRecording = false
    private var scrollCaptured = false

    /// Whether this field is currently recording a mouse input.
    public private(set) var isRecording = false

    override public var canBecomeKeyView: Bool { canBecomeKey }

    /// The currently recorded mouse input, or nil if cleared.
    public var mouseInput: MouseInput? {
        didSet {
            updateDisplay()
        }
    }

    /// Called when the user records or clears a mouse input.
    public var onMouseInputChange: ((MouseInput?) -> Void)?

    /// The placeholder text shown when not recording and no input is set.
    public var defaultPlaceholder: String = "Record Mouse" {
        didSet {
            if !isRecording {
                placeholderString = defaultPlaceholder
            }
        }
    }

    /// The placeholder text shown during recording.
    public var recordingPlaceholder: String = "Click or scroll\u{2026}"

    /// The text color for the mouse input display. Nil uses the system default.
    public var fieldTextColor: NSColor? {
        didSet { textColor = fieldTextColor }
    }

    /// The background color of the field. Nil uses the system default.
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
        if let mouseInput {
            stringValue = mouseInput.displayString
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
        scrollCaptured = false
        ShortcutRecordingState.begin(for: self)
        placeholderString = recordingPlaceholder
        showsCancelButton = mouseInput != nil

        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [
            .leftMouseDown,
            .rightMouseDown,
            .otherMouseDown,
            .scrollWheel,
            .keyDown,
        ]) { [weak self] event in
            guard let self, isRecording else { return event }
            return handleEvent(event)
        }
        isStartingRecording = false
    }

    func endRecording() {
        guard isRecording else { return }
        isRecording = false
        scrollCaptured = false
        ShortcutRecordingState.end(for: self)
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
            self.eventMonitor = nil
        }
        placeholderString = defaultPlaceholder
        showsCancelButton = mouseInput != nil
    }

    private func blur() {
        window?.makeFirstResponder(nil)
    }

    func forceEndRecordingSession() {
        endRecording()
    }

    // MARK: - NSSearchFieldDelegate

    public func controlTextDidEndEditing(_: Notification) {
        guard !isStartingRecording else { return }
        endRecording()
    }

    public func control(_: NSControl, textView _: NSTextView, shouldChangeTextIn _: NSRange,
                        replacementString _: String?) -> Bool
    {
        false
    }

    public func searchFieldDidEndSearching(_: NSSearchField) {
        mouseInput = nil
        onMouseInputChange?(nil)
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

        endRecording()
        return true
    }

    // MARK: - NSTextViewDelegate

    public func textView(_: NSTextView, shouldChangeTextIn _: NSRange, replacementString _: String?) -> Bool {
        false
    }

    // MARK: - Event Handling

    private func handleEvent(_ event: NSEvent) -> NSEvent? {
        // Handle keyboard events (Escape to cancel, Delete to clear)
        if event.type == .keyDown {
            return handleKeyEvent(event)
        }

        // Handle scroll wheel
        if event.type == .scrollWheel {
            return handleScrollEvent(event)
        }

        // Handle mouse button events
        return handleMouseButtonEvent(event)
    }

    private func handleKeyEvent(_ event: NSEvent) -> NSEvent? {
        let modifiers = event.modifierFlags
            .intersection(.deviceIndependentFlagsMask)
            .subtracting([.capsLock, .numericPad, .function])

        if modifiers.isEmpty, event.keyCode == UInt16(kVK_Escape) {
            endRecording()
            blur()
            return nil
        }

        if modifiers.isEmpty,
           event.keyCode == UInt16(kVK_Delete) || event.keyCode == UInt16(kVK_ForwardDelete)
        {
            mouseInput = nil
            onMouseInputChange?(nil)
            endRecording()
            blur()
            return nil
        }

        // Ignore other key events during mouse recording
        return event
    }

    private func handleScrollEvent(_ event: NSEvent) -> NSEvent? {
        guard !scrollCaptured else { return nil }

        // Ignore momentum scroll events (trackpad inertia)
        if event.momentumPhase != [] {
            return nil
        }

        guard let direction = MouseInput.scrollDirection(from: event) else {
            return nil
        }

        scrollCaptured = true

        let modifiers = event.modifierFlags
            .intersection(.deviceIndependentFlagsMask)
            .intersection([.shift, .control, .option, .command])

        let newInput = MouseInput(kind: .scroll(direction), modifiers: modifiers)
        mouseInput = newInput
        onMouseInputChange?(newInput)
        endRecording()
        blur()
        return nil
    }

    private func handleMouseButtonEvent(_ event: NSEvent) -> NSEvent? {
        let clickPoint = convert(event.locationInWindow, from: nil)
        let clickMargin: CGFloat = 3.0
        let isInsideField = bounds.insetBy(dx: -clickMargin, dy: -clickMargin).contains(clickPoint)

        let modifiers = event.modifierFlags
            .intersection(.deviceIndependentFlagsMask)
            .intersection([.shift, .control, .option, .command])

        // Left mouse button
        if event.type == .leftMouseDown {
            if !isInsideField {
                // Click outside — end recording
                endRecording()
                blur()
                return event
            }

            // Bare left click inside — ignore (reserved for UI)
            if modifiers.isEmpty {
                return nil
            }

            // Modified left click inside — capture
            let newInput = MouseInput(kind: .button(event.buttonNumber), modifiers: modifiers)
            mouseInput = newInput
            onMouseInputChange?(newInput)
            endRecording()
            blur()
            return nil
        }

        // Right click or other mouse buttons — always capture
        let newInput = MouseInput(kind: .button(event.buttonNumber), modifiers: modifiers)
        mouseInput = newInput
        onMouseInputChange?(newInput)
        endRecording()
        blur()
        return nil
    }
}
