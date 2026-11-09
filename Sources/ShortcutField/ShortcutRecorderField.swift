import AppKit
import Carbon.HIToolbox

/// An AppKit control that records a fire-once shortcut: a single input or a
/// multi-step sequence of any combination of keystrokes, modified left-clicks,
/// right/middle/other mouse-button clicks, scroll directions, or trackpad
/// gestures.
///
/// Subclasses `NSSearchField` to provide a familiar text-field appearance.
/// Click to start recording, then perform any combination of inputs. Each
/// captured input becomes one step. Recording finalizes after a 1-second
/// pause OR when the user makes a bare left-click anywhere in the field's
/// window (no modifiers) — the unambiguous "I'm done" gesture.
///
/// Press Escape to cancel without saving. Press Delete (only before any
/// step is captured) to clear the existing shortcut. Tab or Shift-Tab before
/// any step is captured moves focus on and keeps the existing shortcut; after
/// that, Tab is recorded like any other key.
///
/// **Left-click is uniquely special**: a bare left-click (no modifiers) is
/// not capturable as a step — it's reserved for UI interactions and serves
/// as the "finalize recording" gesture. Modified left-clicks (e.g. `⌃Left
/// Click`) are capturable. All other inputs — including right-click and
/// other mouse buttons — can be captured as steps with no modifiers required.
///
/// For SwiftUI, use ``ShortcutRecorderView`` instead. For sensitivity-bearing
/// continuous shortcuts (scroll-to-zoom etc.), use ``ContinuousShortcutRecorderField``.
public final class ShortcutRecorderField: BaseShortcutRecorderField {
    private var recordedSteps: [DiscreteShortcut.Step] = []
    /// Internal (not `private`) so tests can observe whether the idle timeout
    /// is armed.
    var timeoutTask: Task<Void, Never>?
    /// Trackpad bursts that already produced a step. A claim ends with its burst, or when an
    /// event of another type arrives, so the next physical burst can record a fresh step.
    private var bursts = GestureBurstTracker()

    /// Idle interval after the last captured step before recording finalizes.
    /// Internal (not `private`) so tests can shrink it.
    var recordingTimeout: TimeInterval = 1.0

    /// The currently recorded shortcut, or nil if cleared.
    public var shortcut: DiscreteShortcut? {
        didSet {
            updateDisplay()
        }
    }

    /// Called when the user records or clears a shortcut.
    public var onShortcutChange: ((DiscreteShortcut?) -> Void)?

    override var displayedShortcut: (any ShortcutFieldDisplayable)? {
        shortcut
    }

    override class var monitoredEvents: NSEvent.EventTypeMask {
        [
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
        ]
    }

    override func willStartRecording() {
        recordedSteps = []
        resetGestureAccumulators()
    }

    override func willEndRecording() {
        resetGestureAccumulators()
        timeoutTask?.cancel()
        timeoutTask = nil
    }

    override func forceEndRecordingSession() {
        recordedSteps = []
        endRecording()
    }

    override func clearCommittedShortcut() {
        shortcut = nil
        onShortcutChange?(nil)
    }

    private func resetGestureAccumulators() {
        gestures.resetAll()
        bursts.reset()
    }

    func finalizeRecording() {
        commitRecordedSteps()
        endRecording()
        blur()
    }

    /// Record the captured steps as the shortcut, if any. The single commit path,
    /// shared by the idle-timeout, click-away, and focus-change routes.
    private func commitRecordedSteps() {
        guard !recordedSteps.isEmpty else { return }
        let new = DiscreteShortcut(steps: recordedSteps)
        shortcut = new
        onShortcutChange?(new)
        recordedSteps = []
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

    override func commitInProgressCapture() {
        commitRecordedSteps()
    }

    override func endRecordingOnResign() {
        if !recordedSteps.isEmpty {
            finalizeRecording()
        } else {
            endRecording()
        }
    }

    // MARK: - NSTextViewDelegate

    public func textView(_: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        handleCommand(commandSelector, event: NSApp.currentEvent)
    }

    // MARK: - Event Handling

    func handleCommand(_ commandSelector: Selector, event: NSEvent?) -> Bool {
        guard isRecording, shouldHandleCommand(commandSelector) else { return false }
        guard let event, event.type == .keyDown else { return true }
        return handleEvent(event) == nil
    }

    private func shouldHandleCommand(_ commandSelector: Selector) -> Bool {
        commandSelector == #selector(NSResponder.insertTab(_:)) ||
            commandSelector == #selector(NSResponder.insertBacktab(_:)) ||
            commandSelector == #selector(NSResponder.cancelOperation(_:)) ||
            commandSelector == #selector(NSResponder.deleteBackward(_:)) ||
            commandSelector == #selector(NSResponder.deleteForward(_:))
    }

    override func handleEvent(_ event: NSEvent) -> NSEvent? {
        guard isRecording else { return event }

        // A different event type ends any in-progress gesture burst.
        bursts.keepOnly(event.type)

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

        let modifiers = DiscreteShortcut.canonicalModifiers(event.modifierFlags)
        if !modifiers.isEmpty {
            // Modified left-up — paired with the modified left-down captured as a step.
            // Don't treat as finalize.
            return nil
        }

        let inside = isInsideField(event)

        finalizeRecording()
        // Pass the event through if the click was outside the field, so other UI
        // (buttons, links, etc.) still receives the click. Inside-field clicks are
        // consumed since they're targeting the recorder itself.
        return inside ? nil : event
    }

    private func handleKeyEvent(_ event: NSEvent) -> NSEvent? {
        // A held key is one press: its auto-repeats are swallowed, not recorded as steps. They
        // keep the idle timeout from finalizing mid-hold, which would let the rest reach the app.
        if event.isARepeat {
            if !recordedSteps.isEmpty {
                resetTimeout()
            }
            return nil
        }
        if recordedSteps.isEmpty, isFocusTab(event) {
            forceEndRecordingSession()
            return event
        }
        let modifiers = DiscreteShortcut.canonicalModifiers(event.modifierFlags)

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

        let step = DiscreteShortcut.Step(keyCode: event.keyCode, modifiers: modifiers)
        appendStep(step)
        return nil
    }

    private func handleMouseButtonEvent(_ event: NSEvent) -> NSEvent? {
        let modifiers = DiscreteShortcut.canonicalModifiers(event.modifierFlags)

        if event.type == .leftMouseDown {
            if isClearButtonClick(event) {
                clearFromButtonWhileRecording()
                return nil
            }
            // Bare left-click is reserved for UI / finalize. Outside the field it finalizes
            // on the down, since a control with its own tracking loop may swallow the up,
            // and passes through so the target still gets the click. Inside, the up commits.
            if modifiers.isEmpty {
                guard !isInsideField(event) else { return nil }
                finalizeRecording()
                return event
            }

            let step = DiscreteShortcut.Step(kind: .mouseButton(number: event.buttonNumber), modifiers: modifiers)
            appendStep(step)
            return nil
        }

        let step = DiscreteShortcut.Step(kind: .mouseButton(number: event.buttonNumber), modifiers: modifiers)
        appendStep(step)
        return nil
    }

    private func handleScrollEvent(_ event: NSEvent) -> NSEvent? {
        guard !event.isMomentumScroll else { return nil }

        if case .end = bursts.track(ShortcutEventShape(event)) {
            return nil
        }
        guard !bursts.isClaimed(.scrollWheel),
              let direction = DiscreteShortcut.scrollDirectionAboveRecordingThreshold(from: event)
        else {
            return nil
        }

        // A trackpad burst records one step; a mouse-wheel notch has no phase, so each records its own.
        bursts.claim(ShortcutEventShape(event))

        let modifiers = DiscreteShortcut.canonicalModifiers(event.modifierFlags)
        let step = DiscreteShortcut.Step(kind: .scroll(direction: direction), modifiers: modifiers)
        appendStep(step)
        return nil
    }

    private func handleGestureEvent(_ event: NSEvent) -> NSEvent? {
        let modifiers = DiscreteShortcut.canonicalModifiers(event.modifierFlags)

        // A burst's end resets the accumulators, and a new burst resets its own, so a dropped
        // `.ended` can't leave residue that trips the threshold in the wrong direction.
        if event.type == .magnify || event.type == .rotate {
            switch bursts.track(ShortcutEventShape(event)) {
            case .end:
                gestures.resetAll()
                return nil
            case .start:
                if event.type == .magnify {
                    gestures.resetPinch()
                } else {
                    gestures.resetRotate()
                }
            case .unphased, .middle:
                break
            }
        }

        switch event.type {
        case .magnify:
            return captureBurstStep(event, modifiers: modifiers) {
                gestures.consumeMagnify(Double(event.magnification))
            }
        case .rotate:
            return captureBurstStep(event, modifiers: modifiers) {
                gestures.consumeRotate(Double(event.rotation))
            }
        case .smartMagnify:
            let step = DiscreteShortcut.Step(kind: .smartMagnify, modifiers: modifiers)
            appendStep(step)
            return nil
        default:
            return event
        }
    }

    /// Append one step per physical burst: ignores the event once this burst has
    /// already produced a step, and only consumes the accumulator until it does.
    private func captureBurstStep(
        _ event: NSEvent,
        modifiers: NSEvent.ModifierFlags,
        consume: () -> DiscreteShortcut.Kind?
    ) -> NSEvent? {
        guard !bursts.isClaimed(event.type) else { return nil }
        if let kind = consume() {
            appendStep(DiscreteShortcut.Step(kind: kind, modifiers: modifiers))
            bursts.claim(ShortcutEventShape(event))
        }
        return nil
    }

    private func appendStep(_ step: DiscreteShortcut.Step) {
        recordedSteps.append(step)
        let preview = DiscreteShortcut(steps: recordedSteps)
        switch labelStyle {
        case .text:
            stringValue = preview.displayString + " …"
        case .compact:
            let elements = preview.displayElements(style: .compact) + [ShortcutDisplayElement.text(" …")]
            attributedStringValue = aligned(
                shortcutAttributedString(from: elements, font: displayFont, color: fieldTextColor)
            )
        }
        resetTimeout()
        gestures.resetAll()
    }
}
