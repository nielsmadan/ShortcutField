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
/// is disabled (e.g. when a custom background color is applied).
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

/// An AppKit control that records any kind of in-app shortcut: keyboard, mouse
/// button, scroll, or trackpad gesture.
///
/// Subclasses `NSSearchField`. Click to start recording, then press a key, click
/// a (modified) mouse button, scroll, or perform a trackpad gesture. Press Escape
/// to cancel, or Delete to clear. A chevron menu provides a click-only path for
/// non-keyboard kinds.
///
/// Bare left clicks (no modifiers) are reserved for UI interaction and will not
/// be captured as a shortcut. Modified left clicks (e.g. `⌃Left Click`) are.
///
/// For SwiftUI, use ``ShortcutRecorderView`` instead.
public final class ShortcutRecorderField: NSSearchField, NSSearchFieldDelegate, NSTextViewDelegate,
    ActiveShortcutRecorder
{
    override public class var cellClass: AnyClass? {
        get { CenteredSearchFieldCell.self }
        set { super.cellClass = newValue }
    }

    /// Whether any recorder instance is currently in recording mode.
    public static var isAnyRecording: Bool { ShortcutRecordingState.isAnyRecording }

    private let minimumWidth: CGFloat = 160
    private var bezeledHeight: CGFloat = 0
    private nonisolated(unsafe) var eventMonitor: Any?
    private var cancelButton: NSButtonCell?
    private var chevronButton: NSButton?
    private var canBecomeKey = false
    private var isStartingRecording = false
    private var scrollCaptured = false

    /// Cumulative magnification accumulated within the current pinch gesture.
    private var pinchAccumulator: Double = 0
    /// Cumulative rotation (degrees) accumulated within the current rotate gesture.
    private var rotateAccumulator: Double = 0

    /// Sensitivity carried forward across kind changes so a discrete-kind detour
    /// doesn't zero the user's chosen sensitivity for continuous kinds.
    private var lastContinuousSensitivity: Double = 0.0

    /// Whether this field is currently recording a shortcut.
    public private(set) var isRecording = false

    override public var canBecomeKeyView: Bool { canBecomeKey }

    /// The currently recorded shortcut, or nil if cleared.
    public var shortcut: Shortcut? {
        didSet {
            if let s = shortcut, Shortcut.isContinuous(s.kind) {
                lastContinuousSensitivity = s.sensitivity
            }
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
    public var recordingPlaceholder: String = "Press / click / scroll / gesture\u{2026}"

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
        setContentHuggingPriority(.defaultHigh, for: .vertical)
        setContentHuggingPriority(.defaultHigh, for: .horizontal)

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
        button.image = NSImage(systemSymbolName: "chevron.down", accessibilityDescription: "Pick shortcut kind")
        button.imagePosition = .imageOnly
        button.contentTintColor = .secondaryLabelColor
        button.target = self
        button.action = #selector(showShortcutPickerMenu(_:))
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setContentHuggingPriority(.required, for: .horizontal)
        button.setContentCompressionResistancePriority(.required, for: .horizontal)
        addSubview(button)
        NSLayoutConstraint.activate([
            // Same trailing slot as the search-field cancel button; the two are mutually
            // exclusive (see `showsCancelButton`).
            button.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            button.centerYAnchor.constraint(equalTo: centerYAnchor),
            button.widthAnchor.constraint(equalToConstant: 16),
            button.heightAnchor.constraint(equalToConstant: 16),
        ])
        chevronButton = button
    }

    @objc private func showShortcutPickerMenu(_ sender: NSButton) {
        let menu = Self.makeShortcutMenu(target: self)
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
        pinchAccumulator = 0
        rotateAccumulator = 0
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
            .smartMagnify,
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
        pinchAccumulator = 0
        rotateAccumulator = 0
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
        // Guard against reentrant calls from startRecording() — setting placeholderString
        // can trigger controlTextDidEndEditing synchronously, which would call endRecording()
        // and set isRecording=false before startRecording() finishes.
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

    private func handleEvent(_ event: NSEvent) -> NSEvent? {
        switch event.type {
        case .keyDown:
            handleKeyEvent(event)
        case .scrollWheel:
            handleScrollEvent(event)
        case .leftMouseDown, .rightMouseDown, .otherMouseDown:
            handleMouseButtonEvent(event)
        case .magnify, .rotate, .smartMagnify:
            handleGestureEvent(event)
        default:
            event
        }
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
            shortcut = nil
            onShortcutChange?(nil)
            endRecording()
            blur()
            return nil
        }

        let new = Shortcut(kind: .key(keyCode: event.keyCode), modifiers: modifiers)
        finalize(new)
        return nil
    }

    private func handleScrollEvent(_ event: NSEvent) -> NSEvent? {
        guard !scrollCaptured else { return nil }

        // Ignore momentum scroll events (trackpad inertia)
        if event.momentumPhase != [] {
            return nil
        }

        // Stricter threshold for recording than for matching, so a tiny stray
        // trackpad twitch (e.g. while the user is reaching for a key) doesn't
        // accidentally finalize as a Scroll shortcut. Consume the event but don't
        // finalize until the user makes a deliberate scroll gesture.
        let dx = abs(event.scrollingDeltaX)
        let dy = abs(event.scrollingDeltaY)
        guard dx >= Shortcut.scrollRecordingThreshold || dy >= Shortcut.scrollRecordingThreshold else {
            return nil
        }

        guard let direction = Shortcut.scrollDirection(from: event) else {
            return nil
        }

        scrollCaptured = true

        let modifiers = event.modifierFlags
            .intersection(.deviceIndependentFlagsMask)
            .intersection([.shift, .control, .option, .command])

        applyKind(.scroll(direction: direction), modifiers: modifiers)
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
            applyKind(.mouseButton(number: event.buttonNumber), modifiers: modifiers)
            endRecording()
            blur()
            return nil
        }

        // Right click or other mouse buttons — always capture
        applyKind(.mouseButton(number: event.buttonNumber), modifiers: modifiers)
        endRecording()
        blur()
        return nil
    }

    private func handleGestureEvent(_ event: NSEvent) -> NSEvent? {
        let modifiers = event.modifierFlags
            .intersection(.deviceIndependentFlagsMask)
            .intersection([.shift, .control, .option, .command])

        // Reset accumulators when a continuous gesture ends so the next gesture starts fresh.
        let isContinuousType = event.type == .magnify || event.type == .rotate
        if isContinuousType, event.phase == .ended || event.phase == .cancelled {
            pinchAccumulator = 0
            rotateAccumulator = 0
            return nil
        }

        switch event.type {
        case .magnify:
            pinchAccumulator += Double(event.magnification)
            if abs(pinchAccumulator) >= Shortcut.magnifyRecordingThreshold {
                let kind: Shortcut.Kind = pinchAccumulator < 0 ? .pinchIn : .pinchOut
                finalize(kind: kind, modifiers: modifiers)
                return nil
            }
            return nil
        case .rotate:
            rotateAccumulator += Double(event.rotation)
            if abs(rotateAccumulator) >= Shortcut.rotateRecordingThreshold {
                let kind: Shortcut.Kind = rotateAccumulator > 0
                    ? .rotateCounterClockwise
                    : .rotateClockwise
                finalize(kind: kind, modifiers: modifiers)
                return nil
            }
            return nil
        case .smartMagnify:
            finalize(kind: .smartMagnify, modifiers: modifiers)
            return nil
        default:
            return event
        }
    }

    private func applyKind(_ kind: Shortcut.Kind, modifiers: NSEvent.ModifierFlags) {
        let sensitivity = Shortcut.isContinuous(kind) ? lastContinuousSensitivity : 0.0
        let new = Shortcut(kind: kind, modifiers: modifiers, sensitivity: sensitivity)
        shortcut = new
        onShortcutChange?(new)
    }

    /// Internal entry point for the menu picker. Sets the shortcut, ends recording,
    /// blurs the field — same teardown sequence as live-recording finalize.
    func handleMenuPickedKind(_ kind: Shortcut.Kind, modifiers: NSEvent.ModifierFlags) {
        applyKind(kind, modifiers: modifiers)
        endRecording()
        blur()
    }

    private func finalize(kind: Shortcut.Kind, modifiers: NSEvent.ModifierFlags) {
        applyKind(kind, modifiers: modifiers)
        endRecording()
        blur()
    }

    private func finalize(_ shortcut: Shortcut) {
        self.shortcut = shortcut
        onShortcutChange?(shortcut)
        endRecording()
        blur()
    }
}
