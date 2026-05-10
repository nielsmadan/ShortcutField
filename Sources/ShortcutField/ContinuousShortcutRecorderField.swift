import AppKit
import Carbon.HIToolbox

/// An AppKit control that records a sensitivity-bearing continuous shortcut:
/// a scroll direction or trackpad gesture (pinch / rotate) that fires throttled
/// when the user performs the gesture later via `.onContinuousShortcut`.
///
/// Subclasses `NSSearchField`. Click to start recording, then perform a
/// scroll, pinch, or rotate (or pick from the chevron menu). The first
/// matching gesture finalizes the recording.
///
/// Discrete inputs (keys, mouse buttons, smart magnify) are not capturable
/// by this recorder — use ``ShortcutRecorderField`` for those.
///
/// For SwiftUI, use ``ContinuousShortcutRecorderView`` instead.
public final class ContinuousShortcutRecorderField: NSSearchField, NSSearchFieldDelegate, NSTextViewDelegate,
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

    private var bezeledHeight: CGFloat = 0
    private nonisolated(unsafe) var eventMonitor: Any?
    private var cancelButton: NSButtonCell?
    private var chevronButton: NSButton?
    private var canBecomeKey = false
    private var isStartingRecording = false
    private var scrollCaptured = false

    private var gestures = GestureAccumulator()

    /// Sensitivity carried forward across kind changes so a re-record doesn't
    /// zero the user's chosen sensitivity. Internal: `ContinuousShortcutRecorderView`
    /// writes the SwiftUI view's @State value here on every render so the field
    /// always uses the user's last-set value when constructing a new shortcut.
    var lastSensitivity: Double = 0.0

    /// Whether this field is currently recording.
    public private(set) var isRecording = false

    override public var canBecomeKeyView: Bool { canBecomeKey }

    /// The currently recorded continuous shortcut, or nil if cleared.
    public var shortcut: ContinuousShortcut? {
        didSet {
            if let s = shortcut {
                lastSensitivity = s.sensitivity
            }
            updateDisplay()
        }
    }

    /// Called when the user records or clears a continuous shortcut.
    public var onShortcutChange: ((ContinuousShortcut?) -> Void)?

    /// The placeholder text shown when not recording and no shortcut is set.
    public var defaultPlaceholder: String = "Record Continuous" {
        didSet {
            if !isRecording {
                placeholderString = defaultPlaceholder
            }
        }
    }

    /// The placeholder text shown during recording.
    public var recordingPlaceholder: String = "Scroll / pinch / rotate\u{2026}"

    /// The text color for the shortcut display. Nil uses the system default.
    public var fieldTextColor: NSColor? {
        didSet { textColor = fieldTextColor }
    }

    private var showsCancelButton: Bool {
        get { (cell as? NSSearchFieldCell)?.cancelButtonCell != nil }
        set {
            (cell as? NSSearchFieldCell)?.cancelButtonCell = newValue ? cancelButton : nil
            // Chevron and cancel button share the same trailing slot — never both at once.
            chevronButton?.isHidden = newValue
        }
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
        // High vertical hugging keeps the field at its intrinsic height (don't
        // stretch tall). Low horizontal hugging lets `.frame(width:)` expand it
        // beyond the intrinsic minimumWidth.
        setContentHuggingPriority(.defaultHigh, for: .vertical)
        setContentHuggingPriority(.defaultLow, for: .horizontal)

        cancelButton = (cell as? NSSearchFieldCell)?.cancelButtonCell
        bezeledHeight = super.intrinsicContentSize.height
        configureChevronButton()
        updateDisplay()
    }

    private func configureChevronButton() {
        let button = NSButton(frame: .zero)
        button.bezelStyle = .smallSquare
        button.isBordered = false
        button.focusRingType = .none
        button.image = NSImage(systemSymbolName: "chevron.down", accessibilityDescription: "Pick continuous kind")
        button.imagePosition = .imageOnly
        button.contentTintColor = .secondaryLabelColor
        button.target = self
        button.action = #selector(showShortcutPickerMenu(_:))
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setContentHuggingPriority(.required, for: .horizontal)
        button.setContentCompressionResistancePriority(.required, for: .horizontal)
        addSubview(button)
        NSLayoutConstraint.activate([
            button.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            button.centerYAnchor.constraint(equalTo: centerYAnchor),
            button.widthAnchor.constraint(equalToConstant: 16),
            button.heightAnchor.constraint(equalToConstant: 16),
        ])
        chevronButton = button
    }

    @objc private func showShortcutPickerMenu(_ sender: NSButton) {
        let menu = Self.makeContinuousShortcutMenu(target: self)
        let location = NSPoint(x: 0, y: sender.bounds.height + 2)
        menu.popUp(positioning: nil, at: location, in: sender)
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
        scrollCaptured = false
        gestures.resetAll()
        ShortcutRecordingState.begin(for: self)
        placeholderString = recordingPlaceholder
        showsCancelButton = shortcut != nil
        chevronButton?.isEnabled = false

        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [
            .keyDown,
            .leftMouseDown,
            .rightMouseDown,
            .otherMouseDown,
            .scrollWheel,
            .magnify,
            .rotate,
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
        gestures.resetAll()
        ShortcutRecordingState.end(for: self)
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
            self.eventMonitor = nil
        }
        placeholderString = defaultPlaceholder
        showsCancelButton = shortcut != nil
        chevronButton?.isEnabled = true
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

        endRecording()
        return true
    }

    // MARK: - NSTextViewDelegate

    public func textView(_: NSTextView, shouldChangeTextIn _: NSRange, replacementString _: String?) -> Bool {
        false
    }

    // MARK: - Event Handling

    func handleEvent(_ event: NSEvent) -> NSEvent? {
        switch event.type {
        case .keyDown:
            handleKeyEvent(event)
        case .scrollWheel:
            handleScrollEvent(event)
        case .leftMouseDown, .rightMouseDown, .otherMouseDown:
            handleMouseButtonEvent(event)
        case .magnify, .rotate:
            handleGestureEvent(event)
        default:
            event
        }
    }

    private func handleKeyEvent(_ event: NSEvent) -> NSEvent? {
        let modifiers = Shortcut.canonicalModifiers(event.modifierFlags)

        if modifiers.isEmpty, event.keyCode == UInt16(kVK_Escape) {
            endRecording()
            blur()
            return nil
        }

        if modifiers.isEmpty,
           event.keyCode == UInt16(kVK_Delete) || event.keyCode == UInt16(kVK_ForwardDelete)
        {
            shortcut = nil
            onShortcutChange?(nil)
            endRecording()
            blur()
            return nil
        }

        // Other key events are dropped — this recorder only captures continuous gestures.
        return nil
    }

    private func handleMouseButtonEvent(_ event: NSEvent) -> NSEvent? {
        // Bare outside left-click dismisses; everything else is dropped (this recorder
        // doesn't capture mouse buttons, and inside left-click is reserved for UI focus).
        if event.type == .leftMouseDown {
            let modifiers = Shortcut.canonicalModifiers(event.modifierFlags)
            let clickPoint = convert(event.locationInWindow, from: nil)
            let clickMargin: CGFloat = 3.0
            let isInsideField = bounds.insetBy(dx: -clickMargin, dy: -clickMargin).contains(clickPoint)

            if !isInsideField, modifiers.isEmpty {
                endRecording()
                blur()
                return event
            }
        }
        return nil
    }

    private func handleScrollEvent(_ event: NSEvent) -> NSEvent? {
        guard !scrollCaptured else { return nil }
        if event.momentumPhase != [] { return nil }
        guard let direction = Shortcut.scrollDirectionAboveRecordingThreshold(from: event) else {
            return nil
        }

        scrollCaptured = true
        let modifiers = Shortcut.canonicalModifiers(event.modifierFlags)
        applyKind(.scroll(direction: direction), modifiers: modifiers)
        endRecording()
        blur()
        return nil
    }

    private func handleGestureEvent(_ event: NSEvent) -> NSEvent? {
        let modifiers = Shortcut.canonicalModifiers(event.modifierFlags)

        // Reset accumulators when a continuous gesture ends so the next gesture starts fresh.
        if event.phase == .ended || event.phase == .cancelled {
            gestures.resetAll()
            return nil
        }

        // Defensive reset on .began — if the OS dropped the prior gesture's .ended,
        // residual accumulator could otherwise immediately satisfy the threshold and
        // record the wrong direction.
        if event.phase == .began {
            if event.type == .magnify { gestures.resetPinch() }
            if event.type == .rotate { gestures.resetRotate() }
        }

        switch event.type {
        case .magnify:
            if let kind = gestures.consumeMagnify(Double(event.magnification)),
               let continuousKind = ContinuousShortcut.Kind(kind)
            {
                finalize(kind: continuousKind, modifiers: modifiers)
            }
            return nil
        case .rotate:
            if let kind = gestures.consumeRotate(Double(event.rotation)),
               let continuousKind = ContinuousShortcut.Kind(kind)
            {
                finalize(kind: continuousKind, modifiers: modifiers)
            }
            return nil
        default:
            return event
        }
    }

    private func applyKind(_ kind: ContinuousShortcut.Kind, modifiers: NSEvent.ModifierFlags) {
        let new = ContinuousShortcut(kind: kind, modifiers: modifiers, sensitivity: lastSensitivity)
        shortcut = new
        onShortcutChange?(new)
    }

    /// Internal entry point for the menu picker. Sets the shortcut, ends recording,
    /// blurs the field — same teardown sequence as live-recording finalize.
    func handleMenuPickedKind(_ kind: ContinuousShortcut.Kind, modifiers: NSEvent.ModifierFlags) {
        applyKind(kind, modifiers: modifiers)
        endRecording()
        blur()
    }

    private func finalize(kind: ContinuousShortcut.Kind, modifiers: NSEvent.ModifierFlags) {
        applyKind(kind, modifiers: modifiers)
        endRecording()
        blur()
    }
}
