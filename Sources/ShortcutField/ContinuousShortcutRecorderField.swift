import AppKit
import Carbon.HIToolbox

/// An AppKit control that records a sensitivity-bearing continuous shortcut:
/// a scroll direction or trackpad gesture (pinch / rotate) that fires throttled
/// when the user performs the gesture later via `.onShortcut`.
///
/// Subclasses `NSSearchField`. Click to start recording, then perform a
/// scroll, pinch, or rotate (or pick from the chevron menu). The first
/// matching gesture finalizes the recording.
///
/// Discrete inputs (keys, mouse buttons, smart magnify) are not capturable
/// by this recorder — use ``ShortcutRecorderField`` for those.
///
/// For SwiftUI, use ``ContinuousShortcutRecorderView`` instead.
public final class ContinuousShortcutRecorderField: BaseShortcutRecorderField {
    private var chevronButton: NSButton?
    private var scrollCaptured = false

    /// Sensitivity carried forward across kind changes so a re-record doesn't
    /// zero the user's chosen sensitivity. Internal: `ContinuousShortcutRecorderView`
    /// writes the SwiftUI slider value here on every non-recording update so the
    /// field always uses the user's last-set value when constructing a new shortcut.
    var lastSensitivity: Double = 0.0

    /// The currently recorded continuous shortcut, or nil if cleared.
    public var shortcut: ContinuousShortcut? {
        didSet {
            updateDisplay()
        }
    }

    /// Called when the user records or clears a continuous shortcut.
    public var onShortcutChange: ((ContinuousShortcut?) -> Void)?

    override var displayedShortcut: (any ShortcutFieldDisplayable)? { shortcut }

    override class var monitoredEvents: NSEvent.EventTypeMask {
        [
            .keyDown,
            .leftMouseDown,
            .rightMouseDown,
            .otherMouseDown,
            .scrollWheel,
            .magnify,
            .rotate,
        ]
    }

    override func cancelButtonVisibilityDidChange(_ visible: Bool) {
        // Chevron and cancel button share the same trailing slot — never both at once.
        chevronButton?.isHidden = visible
    }

    override func willStartRecording() {
        scrollCaptured = false
        gestures.resetAll()
        chevronButton?.isEnabled = false
    }

    override func willEndRecording() {
        scrollCaptured = false
        gestures.resetAll()
        chevronButton?.isEnabled = true
    }

    override func clearCommittedShortcut() {
        shortcut = nil
        onShortcutChange?(nil)
    }

    override func configureAccessories() {
        defaultPlaceholder = "Record Continuous"
        recordingPlaceholder = "Scroll / pinch / rotate\u{2026}"
        configureChevronButton()
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
        let menu = Self.makeContinuousShortcutMenu(target: self, labelStyle: labelStyle)
        let location = NSPoint(x: 0, y: sender.bounds.height + 2)
        menu.popUp(positioning: nil, at: location, in: sender)
    }

    // MARK: - Event Handling

    override func handleEvent(_ event: NSEvent) -> NSEvent? {
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
        let modifiers = DiscreteShortcut.canonicalModifiers(event.modifierFlags)

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

        return nil
    }

    private func handleMouseButtonEvent(_ event: NSEvent) -> NSEvent? {
        // Bare outside left-click dismisses; everything else is dropped (this recorder
        // doesn't capture mouse buttons, and inside left-click is reserved for UI focus).
        if event.type == .leftMouseDown {
            let modifiers = DiscreteShortcut.canonicalModifiers(event.modifierFlags)
            if !isInsideField(event), modifiers.isEmpty {
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
        guard let direction = DiscreteShortcut.scrollDirectionAboveRecordingThreshold(from: event) else {
            return nil
        }

        scrollCaptured = true
        let modifiers = DiscreteShortcut.canonicalModifiers(event.modifierFlags)
        commit(kind: .scroll(direction: direction), modifiers: modifiers)
        return nil
    }

    private func handleGestureEvent(_ event: NSEvent) -> NSEvent? {
        let modifiers = DiscreteShortcut.canonicalModifiers(event.modifierFlags)

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
                commit(kind: continuousKind, modifiers: modifiers)
            }
            return nil
        case .rotate:
            if let kind = gestures.consumeRotate(Double(event.rotation)),
               let continuousKind = ContinuousShortcut.Kind(kind)
            {
                commit(kind: continuousKind, modifiers: modifiers)
            }
            return nil
        default:
            return event
        }
    }

    /// Record `kind` as the shortcut and end the session. The single commit path,
    /// shared by the gesture, scroll, and chevron-menu routes.
    func commit(kind: ContinuousShortcut.Kind, modifiers: NSEvent.ModifierFlags) {
        // Carry the committed shortcut's sensitivity forward; `lastSensitivity` covers
        // the case where nothing is bound yet (a slider adjustment before recording).
        let sensitivity = shortcut?.sensitivity ?? lastSensitivity
        let new = ContinuousShortcut(kind: kind, modifiers: modifiers, sensitivity: sensitivity)
        shortcut = new
        onShortcutChange?(new)
        endRecording()
        blur()
    }
}
