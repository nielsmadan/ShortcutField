# Sequential Shortcuts Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add support for recording and recognizing multi-step keyboard shortcuts (e.g. `⌘K ⌘C`, `G G`).

**Architecture:** New `ShortcutSequence` model wrapping `[Shortcut]`. Separate recorder field/view and recognition modifier, parallel to the existing single-shortcut components. Shared styling extracted into a protocol extension on `NSSearchField`.

**Tech Stack:** Swift 6.2, AppKit (NSSearchField), SwiftUI (NSViewRepresentable), Swift Testing

**Spec:** `docs/superpowers/specs/2026-03-24-sequential-shortcuts-design.md`

---

## File Structure

| File | Action | Responsibility |
|---|---|---|
| `Sources/ShortcutField/ShortcutSequence.swift` | Create | Model: `[Shortcut]` wrapper with displayString, Codable |
| `Sources/ShortcutField/RecorderFieldStyling.swift` | Create | Protocol + default impl for applyStyle/applyBackgroundColor |
| `Sources/ShortcutField/ShortcutRecorderStyle.swift` | Modify | Remove `ShortcutRecorderField` extension (moved to protocol) |
| `Sources/ShortcutField/ShortcutRecorderField.swift` | Modify | Adopt `RecorderFieldStyling`, remove `applyBackgroundColor()` |
| `Sources/ShortcutField/ShortcutSequenceRecorderField.swift` | Create | AppKit NSSearchField subclass for sequence recording |
| `Sources/ShortcutField/ShortcutSequenceRecorderView.swift` | Create | SwiftUI NSViewRepresentable wrapper |
| `Sources/ShortcutField/OnShortcutSequenceModifier.swift` | Create | `.onShortcutSequence()` view modifier |
| `Tests/ShortcutFieldTests/ShortcutSequenceTests.swift` | Create | Model tests |
| `Tests/ShortcutFieldTests/ShortcutSequenceRecorderFieldTests.swift` | Create | Recorder field tests |
| `Example/ShortcutFieldExample/ContentView.swift` | Modify | Add sequence recorder to workbench + gallery |

---

### Task 1: ShortcutSequence Model

**Files:**
- Create: `Sources/ShortcutField/ShortcutSequence.swift`
- Create: `Tests/ShortcutFieldTests/ShortcutSequenceTests.swift`

- [ ] **Step 1: Write failing tests for ShortcutSequence**

In `Tests/ShortcutFieldTests/ShortcutSequenceTests.swift`:

```swift
import AppKit
import Carbon.HIToolbox
import ShortcutField
import Testing

@Test func sequence_storesSteps() {
    let steps = [
        Shortcut(keyCode: 40, modifiers: .command),  // kVK_ANSI_K
        Shortcut(keyCode: 8, modifiers: .command),   // kVK_ANSI_C
    ]
    let seq = ShortcutSequence(steps: steps)
    #expect(seq.steps.count == 2)
    #expect(seq.steps[0] == steps[0])
    #expect(seq.steps[1] == steps[1])
}

@Test func sequence_equatable_sameSteps_areEqual() {
    let a = ShortcutSequence(steps: [
        Shortcut(keyCode: 40, modifiers: .command),
        Shortcut(keyCode: 8, modifiers: .command),
    ])
    let b = ShortcutSequence(steps: [
        Shortcut(keyCode: 40, modifiers: .command),
        Shortcut(keyCode: 8, modifiers: .command),
    ])
    #expect(a == b)
}

@Test func sequence_equatable_differentSteps_areNotEqual() {
    let a = ShortcutSequence(steps: [
        Shortcut(keyCode: 40, modifiers: .command),
        Shortcut(keyCode: 8, modifiers: .command),
    ])
    let b = ShortcutSequence(steps: [
        Shortcut(keyCode: 40, modifiers: .command),
        Shortcut(keyCode: 12, modifiers: .command),
    ])
    #expect(a != b)
}

@Test func sequence_codableRoundtrip() throws {
    let original = ShortcutSequence(steps: [
        Shortcut(keyCode: 40, modifiers: .command),
        Shortcut(keyCode: 8, modifiers: .command),
    ])
    let data = try JSONEncoder().encode(original)
    let decoded = try JSONDecoder().decode(ShortcutSequence.self, from: data)
    #expect(decoded == original)
}

@Test func sequence_displayString_joinedWithSpace() {
    let seq = ShortcutSequence(steps: [
        Shortcut(keyCode: 40, modifiers: .command),
        Shortcut(keyCode: 8, modifiers: .command),
    ])
    // Each step's displayString joined by " "
    let expected = seq.steps.map(\.displayString).joined(separator: " ")
    #expect(seq.displayString == expected)
}

@Test func sequence_threeSteps() {
    let seq = ShortcutSequence(steps: [
        Shortcut(keyCode: 5, modifiers: []),  // G
        Shortcut(keyCode: 5, modifiers: []),  // G
        Shortcut(keyCode: 5, modifiers: []),  // G
    ])
    #expect(seq.steps.count == 3)
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `just test`
Expected: FAIL — `ShortcutSequence` not found

- [ ] **Step 3: Implement ShortcutSequence**

In `Sources/ShortcutField/ShortcutSequence.swift`:

```swift
import AppKit

/// A sequential keyboard shortcut composed of multiple steps.
///
/// Each step is a ``Shortcut`` (key code + modifiers). The sequence
/// matches when all steps are pressed in order.
public struct ShortcutSequence: Sendable, Equatable, Codable {
    /// The ordered steps that make up this sequence (minimum 2).
    public let steps: [Shortcut]

    /// Create a shortcut sequence from an array of steps.
    ///
    /// - Precondition: `steps.count >= 2`
    public init(steps: [Shortcut]) {
        precondition(steps.count >= 2, "ShortcutSequence requires at least 2 steps")
        self.steps = steps
    }

    /// Human-readable display string, e.g. "⌘K ⌘C".
    public var displayString: String {
        steps.map(\.displayString).joined(separator: " ")
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `just test`
Expected: All tests PASS

- [ ] **Step 5: Commit**

```bash
git add Sources/ShortcutField/ShortcutSequence.swift Tests/ShortcutFieldTests/ShortcutSequenceTests.swift
git commit -m "feat: add ShortcutSequence model"
```

---

### Task 2: Extract Shared Styling Protocol

**Files:**
- Create: `Sources/ShortcutField/RecorderFieldStyling.swift`
- Modify: `Sources/ShortcutField/ShortcutRecorderStyle.swift`
- Modify: `Sources/ShortcutField/ShortcutRecorderField.swift`

- [ ] **Step 1: Run existing tests as baseline**

Run: `just test`
Expected: All tests PASS

- [ ] **Step 2: Create RecorderFieldStyling protocol**

In `Sources/ShortcutField/RecorderFieldStyling.swift`:

```swift
import AppKit

/// Shared styling for recorder fields that subclass NSSearchField.
protocol RecorderFieldStyling: NSSearchField {
    var fieldBackgroundColor: NSColor? { get }
}

extension RecorderFieldStyling {
    /// Apply a visual style to the recorder field.
    func applyStyle(_ style: ShortcutRecorderStyle) {
        switch style {
        case .rounded:
            isBezeled = true
            isBordered = true
            bezelStyle = .roundedBezel
        case .plain:
            isBezeled = true
            isBordered = true
            bezelStyle = .squareBezel
        case .borderless:
            isBezeled = false
            isBordered = false
        }
    }

    /// Apply the current background color via a layer.
    ///
    /// NSSearchFieldCell does not render `NSTextField.backgroundColor`,
    /// so we use a layer-backed background instead.
    func applyBackgroundColor() {
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
}
```

- [ ] **Step 3: Update ShortcutRecorderStyle.swift — remove the field extension**

Replace the entire `extension ShortcutRecorderField { ... }` block (lines 13–30) in `ShortcutRecorderStyle.swift`, leaving only the enum definition:

```swift
import AppKit

/// Visual style for the shortcut recorder.
public enum ShortcutRecorderStyle: Sendable, Hashable {
    /// Default rounded appearance matching NSSearchField.
    case rounded
    /// Minimal flat border.
    case plain
    /// No visible border — just text.
    case borderless
}
```

- [ ] **Step 4: Update ShortcutRecorderField — adopt protocol, remove applyBackgroundColor**

In `ShortcutRecorderField.swift`:

1. Add `RecorderFieldStyling` conformance to the class declaration:
   ```swift
   public final class ShortcutRecorderField: NSSearchField, NSSearchFieldDelegate, NSTextViewDelegate, RecorderFieldStyling {
   ```

2. Remove the private `applyBackgroundColor()` method (lines 63–77). The protocol extension provides it.

3. Change the `fieldBackgroundColor` didSet to call the protocol method explicitly — but since it's the same name, it should just work. The didSet already calls `applyBackgroundColor()`.

- [ ] **Step 5: Run tests to verify nothing broke**

Run: `just test`
Expected: All tests PASS

- [ ] **Step 6: Build example app to verify styling still works**

Run: `just example`
Expected: Builds and runs, all gallery items render correctly

- [ ] **Step 7: Commit**

```bash
git add Sources/ShortcutField/RecorderFieldStyling.swift Sources/ShortcutField/ShortcutRecorderStyle.swift Sources/ShortcutField/ShortcutRecorderField.swift
git commit -m "refactor: extract RecorderFieldStyling protocol for shared styling"
```

---

### Task 3: ShortcutSequenceRecorderField

**Files:**
- Create: `Sources/ShortcutField/ShortcutSequenceRecorderField.swift`
- Create: `Tests/ShortcutFieldTests/ShortcutSequenceRecorderFieldTests.swift`

- [ ] **Step 1: Write failing tests**

In `Tests/ShortcutFieldTests/ShortcutSequenceRecorderFieldTests.swift`:

```swift
import AppKit
import Carbon.HIToolbox
import ShortcutField
import Testing

// NSSearchField instantiation can crash when run in parallel in headless CI
@Suite(.serialized) struct ShortcutSequenceRecorderFieldTests {

@MainActor
@Test func sequenceRecorderField_defaultState() {
    let field = ShortcutSequenceRecorderField()
    #expect(field.shortcutSequence == nil)
    #expect(!field.isRecording)
    #expect(field.frame.width >= 130)
}

@MainActor
@Test func sequenceRecorderField_setSequence_updatesDisplay() {
    let field = ShortcutSequenceRecorderField()
    let seq = ShortcutSequence(steps: [
        Shortcut(keyCode: 40, modifiers: .command),
        Shortcut(keyCode: 8, modifiers: .command),
    ])
    field.shortcutSequence = seq
    #expect(field.shortcutSequence == seq)
    #expect(field.stringValue == seq.displayString)
}

@MainActor
@Test func sequenceRecorderField_clearSequence_clearsDisplay() {
    let field = ShortcutSequenceRecorderField()
    field.shortcutSequence = ShortcutSequence(steps: [
        Shortcut(keyCode: 40, modifiers: .command),
        Shortcut(keyCode: 8, modifiers: .command),
    ])
    field.shortcutSequence = nil
    #expect(field.shortcutSequence == nil)
    #expect(field.stringValue == "")
}

@MainActor
@Test func sequenceRecorderField_onSequenceChange_notCalledOnProgrammaticSet() {
    let field = ShortcutSequenceRecorderField()
    var callCount = 0
    field.onShortcutSequenceChange = { _ in
        callCount += 1
    }
    field.shortcutSequence = ShortcutSequence(steps: [
        Shortcut(keyCode: 40, modifiers: .command),
        Shortcut(keyCode: 8, modifiers: .command),
    ])
    #expect(callCount == 0)
}

@MainActor
@Test func sequenceRecorderField_intrinsicContentSize_hasMinimumWidth() {
    let field = ShortcutSequenceRecorderField()
    #expect(field.intrinsicContentSize.width >= 130)
}

@MainActor
@Test func sequenceRecorderField_setSequence_preservedWhenCleared() {
    let field = ShortcutSequenceRecorderField()
    let seq = ShortcutSequence(steps: [
        Shortcut(keyCode: 40, modifiers: .command),
        Shortcut(keyCode: 8, modifiers: .command),
    ])
    field.shortcutSequence = seq
    field.shortcutSequence = nil
    #expect(field.shortcutSequence == nil)
    // Re-set to verify field still works after clearing
    field.shortcutSequence = seq
    #expect(field.stringValue == seq.displayString)
}

}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `just test`
Expected: FAIL — `ShortcutSequenceRecorderField` not found

- [ ] **Step 3: Implement ShortcutSequenceRecorderField**

In `Sources/ShortcutField/ShortcutSequenceRecorderField.swift`:

```swift
import AppKit
import Carbon.HIToolbox

/// An AppKit control that records sequential keyboard shortcuts.
///
/// Subclasses `NSSearchField` to provide a familiar text-field appearance.
/// Click to start recording, press key combinations in sequence (finalized
/// after a 1-second timeout), press Escape to cancel, or Delete to clear.
///
/// For SwiftUI, use ``ShortcutSequenceRecorderView`` instead.
public final class ShortcutSequenceRecorderField: NSSearchField, NSSearchFieldDelegate, NSTextViewDelegate,
    RecorderFieldStyling
{
    private let minimumWidth: CGFloat = 130
    private nonisolated(unsafe) var eventMonitor: Any?
    private var cancelButton: NSButtonCell?
    private var canBecomeKey = false
    private var isStartingRecording = false
    private var recordedSteps: [Shortcut] = []
    private var timeoutTimer: Timer?

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
    public var fieldBackgroundColor: NSColor? {
        didSet {
            applyBackgroundColor()
        }
    }

    private var showsCancelButton: Bool {
        get { (cell as? NSSearchFieldCell)?.cancelButtonCell != nil }
        set { (cell as? NSSearchFieldCell)?.cancelButtonCell = newValue ? cancelButton : nil }
    }

    deinit {
        timeoutTimer?.invalidate()
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
        if let shortcutSequence {
            stringValue = shortcutSequence.displayString
            showsCancelButton = true
        } else {
            stringValue = ""
            showsCancelButton = false
        }
    }

    private func startRecording() {
        isStartingRecording = true
        isRecording = true
        recordedSteps = []
        placeholderString = recordingPlaceholder
        showsCancelButton = shortcutSequence != nil

        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [
            .keyDown,
            .leftMouseUp,
            .rightMouseUp,
        ]) { [weak self] event in
            guard let self, isRecording else { return event }
            return handleEvent(event)
        }
        isStartingRecording = false
    }

    private func endRecording() {
        guard isRecording else { return }
        isRecording = false
        timeoutTimer?.invalidate()
        timeoutTimer = nil
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
            self.eventMonitor = nil
        }
        placeholderString = defaultPlaceholder
        showsCancelButton = shortcutSequence != nil
    }

    private func finalizeRecording() {
        if recordedSteps.count >= 2 {
            let seq = ShortcutSequence(steps: recordedSteps)
            shortcutSequence = seq
            onShortcutSequenceChange?(seq)
        }
        // If fewer than 2 steps, discard (don't change current sequence)
        recordedSteps = []
        endRecording()
        blur()
    }

    private func resetTimeout() {
        timeoutTimer?.invalidate()
        timeoutTimer = Timer.scheduledTimer(withTimeInterval: recordingTimeout, repeats: false) { [weak self] _ in
            self?.finalizeRecording()
        }
    }

    private func blur() {
        window?.makeFirstResponder(nil)
    }

    // MARK: - NSSearchFieldDelegate

    public func controlTextDidEndEditing(_: Notification) {
        guard !isStartingRecording else { return }
        finalizeRecording()
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

        // Delete clears the current sequence
        if modifiers.isEmpty, recordedSteps.isEmpty,
           event.keyCode == UInt16(kVK_Delete) || event.keyCode == UInt16(kVK_ForwardDelete)
        {
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
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `just test`
Expected: All tests PASS

- [ ] **Step 5: Commit**

```bash
git add Sources/ShortcutField/ShortcutSequenceRecorderField.swift Tests/ShortcutFieldTests/ShortcutSequenceRecorderFieldTests.swift
git commit -m "feat: add ShortcutSequenceRecorderField for recording sequential shortcuts"
```

---

### Task 4: ShortcutSequenceRecorderView (SwiftUI)

**Files:**
- Create: `Sources/ShortcutField/ShortcutSequenceRecorderView.swift`

- [ ] **Step 1: Implement ShortcutSequenceRecorderView**

In `Sources/ShortcutField/ShortcutSequenceRecorderView.swift`:

```swift
import SwiftUI

/// A SwiftUI view that lets users record a sequential keyboard shortcut.
///
/// ```swift
/// @State private var sequence: ShortcutSequence?
///
/// ShortcutSequenceRecorderView($sequence)
///     .placeholder("Record Sequence")
///     .style(.rounded)
/// ```
public struct ShortcutSequenceRecorderView: NSViewRepresentable {
    @Binding var shortcutSequence: ShortcutSequence?

    private var placeholderText: String = "Record Sequence"
    private var recordingPlaceholderText: String = "Press keys..."
    private var style: ShortcutRecorderStyle = .rounded
    private var textColorValue: NSColor?
    private var backgroundColorValue: NSColor?

    /// Create a sequence recorder bound to the given sequence value.
    public init(_ shortcutSequence: Binding<ShortcutSequence?>) {
        _shortcutSequence = shortcutSequence
    }

    public func makeNSView(context _: Context) -> ShortcutSequenceRecorderField {
        let field = ShortcutSequenceRecorderField()
        field.shortcutSequence = shortcutSequence
        field.defaultPlaceholder = placeholderText
        field.recordingPlaceholder = recordingPlaceholderText
        field.applyStyle(style)
        field.fieldTextColor = textColorValue
        field.fieldBackgroundColor = backgroundColorValue
        field.onShortcutSequenceChange = { newSequence in
            DispatchQueue.main.async {
                shortcutSequence = newSequence
            }
        }
        return field
    }

    public func updateNSView(_ nsView: ShortcutSequenceRecorderField, context _: Context) {
        guard !nsView.isRecording else { return }
        nsView.shortcutSequence = shortcutSequence
        nsView.defaultPlaceholder = placeholderText
        nsView.recordingPlaceholder = recordingPlaceholderText
        nsView.applyStyle(style)
        nsView.fieldTextColor = textColorValue
        nsView.fieldBackgroundColor = backgroundColorValue
    }
}

// MARK: - Modifiers

public extension ShortcutSequenceRecorderView {
    /// Set the placeholder text shown when no sequence is recorded.
    func placeholder(_ text: String) -> ShortcutSequenceRecorderView {
        var view = self
        view.placeholderText = text
        return view
    }

    /// Set the placeholder text shown during recording.
    func recordingPlaceholder(_ text: String) -> ShortcutSequenceRecorderView {
        var view = self
        view.recordingPlaceholderText = text
        return view
    }

    /// Set the visual style of the recorder.
    func style(_ style: ShortcutRecorderStyle) -> ShortcutSequenceRecorderView {
        var view = self
        view.style = style
        return view
    }

    /// Set the text color of the sequence display.
    func textColor(_ color: NSColor) -> ShortcutSequenceRecorderView {
        var view = self
        view.textColorValue = color
        return view
    }

    /// Set the background color of the field.
    func fieldBackgroundColor(_ color: NSColor) -> ShortcutSequenceRecorderView {
        var view = self
        view.backgroundColorValue = color
        return view
    }
}
```

- [ ] **Step 2: Build to verify compilation**

Run: `just build`
Expected: Build succeeds

- [ ] **Step 3: Commit**

```bash
git add Sources/ShortcutField/ShortcutSequenceRecorderView.swift
git commit -m "feat: add ShortcutSequenceRecorderView SwiftUI wrapper"
```

---

### Task 5: OnShortcutSequenceModifier (Recognition)

**Files:**
- Create: `Sources/ShortcutField/OnShortcutSequenceModifier.swift`

- [ ] **Step 1: Implement OnShortcutSequenceModifier**

In `Sources/ShortcutField/OnShortcutSequenceModifier.swift`:

```swift
import AppKit
import Carbon.HIToolbox
import SwiftUI

/// View modifier that fires an action when a shortcut sequence is pressed.
@available(macOS 14.0, *)
struct OnShortcutSequenceModifier: ViewModifier {
    let sequence: ShortcutSequence?
    let action: () -> Void

    @State private var eventMonitor: Any?
    @State private var currentStep = 0
    @State private var timeoutTask: Task<Void, Never>?

    /// Timeout interval in seconds before resetting partial match state.
    private let stepTimeout: TimeInterval = 1.0

    func body(content: Content) -> some View {
        content
            .focusable()
            .onKeyPress(phases: .down) { press in
                guard let sequence else { return .ignored }
                let step = sequence.steps[currentStep]

                // Only handle regular keys via onKeyPress
                guard !Self.needsEventMonitor(keyCode: step.keyCode) else {
                    return .ignored
                }

                guard step.matches(press) else {
                    resetTracking()
                    return .ignored
                }

                return advanceStep(isLast: currentStep == sequence.steps.count - 1)
            }
            .onAppear {
                installMonitor()
            }
            .onDisappear {
                removeMonitor()
                resetTracking()
            }
            .onChange(of: sequence) { _, _ in
                removeMonitor()
                resetTracking()
                installMonitor()
            }
    }

    private func advanceStep(isLast: Bool) -> KeyPress.Result {
        if isLast {
            resetTracking()
            action()
            return .handled
        } else {
            currentStep += 1
            restartTimeout()
            // Intermediate steps propagate
            return .ignored
        }
    }

    private func resetTracking() {
        currentStep = 0
        timeoutTask?.cancel()
        timeoutTask = nil
    }

    private func restartTimeout() {
        timeoutTask?.cancel()
        timeoutTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(stepTimeout))
            guard !Task.isCancelled else { return }
            resetTracking()
        }
    }

    private func installMonitor() {
        guard let sequence, eventMonitor == nil else { return }

        // Only install if any step in the sequence uses special keys
        guard sequence.steps.contains(where: { Self.needsEventMonitor(keyCode: $0.keyCode) }) else { return }

        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard let sequence = self.sequence else { return event }
            let step = sequence.steps[currentStep]

            // Only handle special keys via monitor
            guard Self.needsEventMonitor(keyCode: step.keyCode) else {
                return event
            }

            guard step.matches(event) else {
                resetTracking()
                return event
            }

            let result = advanceStep(isLast: currentStep == sequence.steps.count - 1)
            return result == .handled ? nil : event
        }
    }

    private func removeMonitor() {
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
            self.eventMonitor = nil
        }
    }

    /// Keys that SwiftUI's focus system may intercept before onKeyPress fires.
    private static func needsEventMonitor(keyCode: UInt16) -> Bool {
        switch Int(keyCode) {
        case kVK_Tab, kVK_Escape:
            true
        default:
            false
        }
    }
}

// MARK: - View Extension

public extension View {
    /// Perform an action when the given shortcut sequence is pressed.
    ///
    /// Tracks key presses in order, firing the action when the full sequence
    /// is matched. Intermediate steps propagate normally; only the final
    /// step is consumed.
    ///
    /// ```swift
    /// MyView()
    ///     .onShortcutSequence(sequence) {
    ///         print("Sequence matched!")
    ///     }
    /// ```
    @available(macOS 14.0, *)
    func onShortcutSequence(_ sequence: ShortcutSequence?, perform action: @escaping () -> Void) -> some View {
        modifier(OnShortcutSequenceModifier(sequence: sequence, action: action))
    }
}
```

- [ ] **Step 2: Build to verify compilation**

Run: `just build`
Expected: Build succeeds

- [ ] **Step 3: Run all tests to make sure nothing broke**

Run: `just test`
Expected: All tests PASS

- [ ] **Step 4: Commit**

```bash
git add Sources/ShortcutField/OnShortcutSequenceModifier.swift
git commit -m "feat: add .onShortcutSequence() view modifier for sequence recognition"
```

---

### Task 6: Example App Integration

**Files:**
- Modify: `Example/ShortcutFieldExample/ContentView.swift`

- [ ] **Step 1: Add sequence recorder to WorkbenchTab**

In `ContentView.swift`, add a `@State private var sequence: ShortcutSequence?` to `WorkbenchTab` and add a sequence recorder section below the existing single-shortcut recorder in the workbench view. Add a second fire counter for sequences.

Key additions:
- `@State private var sequence: ShortcutSequence?` state property
- A `ShortcutSequenceRecorderView($sequence)` in the left panel below the existing recorder
- Display of `sequence?.displayString` below it
- A second fire counter using `.onShortcutSequence(sequence)`

- [ ] **Step 2: Add sequence items to GalleryTab**

Add sequence recorder gallery items to `GalleryItem.allItems`. Create a new `SequenceGalleryCard` that uses `ShortcutSequenceRecorderView` instead of `ShortcutRecorderView`. Add a few items showing different styles with the sequence recorder.

- [ ] **Step 3: Build and run example app**

Run: `just example`
Expected: App builds, both workbench and gallery show sequence recorders alongside single-shortcut recorders

- [ ] **Step 4: Commit**

```bash
git add Example/ShortcutFieldExample/ContentView.swift
git commit -m "feat: add sequence recorder to example app workbench and gallery"
```

---

### Task 7: Lint, Format, and Final Verification

- [ ] **Step 1: Run linter and formatter**

Run: `just format && just lint`
Expected: No errors. Fix any warnings.

- [ ] **Step 2: Run full test suite**

Run: `just test`
Expected: All tests PASS (existing + new)

- [ ] **Step 3: Build example app**

Run: `just example`
Expected: Builds and runs successfully

- [ ] **Step 4: Fix any issues and commit if needed**

```bash
git add -A
git commit -m "chore: lint and format sequential shortcuts"
```
