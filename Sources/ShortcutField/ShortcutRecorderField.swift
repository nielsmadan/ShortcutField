import AppKit
import Carbon.HIToolbox

/// An AppKit control that records keyboard shortcuts.
///
/// Subclasses `NSSearchField` to provide a familiar text-field appearance with
/// a clear button. Click to start recording, press a key combination to set the
/// shortcut, press Escape to cancel, or Delete to clear.
///
/// For SwiftUI, use ``ShortcutRecorderView`` instead.
public final class ShortcutRecorderField: NSSearchField, NSSearchFieldDelegate, NSTextViewDelegate {
    /// Whether any recorder instance is currently in recording mode.
    public static var isAnyRecording = false

    private let minimumWidth: CGFloat = 130
    private nonisolated(unsafe) var eventMonitor: Any?
    private var cancelButton: NSButtonCell?
    private var canBecomeKey = false
    private var isStartingRecording = false

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
    public var recordingPlaceholder: String = "Press shortcut..."

    /// The text color for the shortcut display. Nil uses the system default.
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
        Self.isAnyRecording = false
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

        updateDisplay()
    }

    override public var intrinsicContentSize: NSSize {
        var size = super.intrinsicContentSize
        size.width = minimumWidth
        return size
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

    private func startRecording() {
        isStartingRecording = true
        isRecording = true
        Self.isAnyRecording = true
        placeholderString = recordingPlaceholder
        showsCancelButton = shortcut != nil

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
        Self.isAnyRecording = false
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
            self.eventMonitor = nil
        }
        placeholderString = defaultPlaceholder
        showsCancelButton = shortcut != nil
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
        endRecording()
    }

    public func control(_: NSControl, textView _: NSTextView, shouldChangeTextIn _: NSRange,
                        replacementString _: String?) -> Bool {
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

    // MARK: - NSTextViewDelegate

    public func textView(_: NSTextView, shouldChangeTextIn _: NSRange, replacementString _: String?) -> Bool {
        false
    }

    // MARK: - Event Handling

    private func handleEvent(_ event: NSEvent) -> NSEvent? {
        if event.type == .leftMouseUp || event.type == .rightMouseUp {
            let clickPoint = convert(event.locationInWindow, from: nil)
            let clickMargin: CGFloat = 3.0
            if !bounds.insetBy(dx: -clickMargin, dy: -clickMargin).contains(clickPoint) {
                endRecording()
                blur()
                return event
            }
            return nil
        }

        guard event.type == .keyDown else { return event }

        let modifiers = event.modifierFlags
            .intersection(.deviceIndependentFlagsMask)
            .subtracting([.capsLock, .numericPad, .function])

        if modifiers.isEmpty, event.keyCode == UInt16(kVK_Escape) {
            endRecording()
            blur()
            return nil
        }

        if modifiers.isEmpty,
           event.keyCode == UInt16(kVK_Delete) || event.keyCode == UInt16(kVK_ForwardDelete) {
            shortcut = nil
            onShortcutChange?(nil)
            endRecording()
            blur()
            return nil
        }

        let newShortcut = Shortcut(keyCode: event.keyCode, modifiers: modifiers)
        shortcut = newShortcut
        onShortcutChange?(newShortcut)
        endRecording()
        blur()
        return nil
    }
}
