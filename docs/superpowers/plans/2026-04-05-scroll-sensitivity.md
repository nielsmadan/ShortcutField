# Scroll Sensitivity Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a `scrollSensitivity` property (0.0-1.0) to `MouseInput` that throttles how often `.onMouseInput()` fires during continuous scrolling, with stepper/slider/hidden UI modes in the recorder.

**Architecture:** The `MouseInput` model gains an immutable `scrollSensitivity: Double` field. `OnMouseInputModifier` uses a `ScrollThrottleState` reference type to track cooldown/suppression state inside the NSEvent monitor closure. The recorder field conditionally shows an NSStepper or NSSlider based on a `sensitivityMode` configuration.

**Tech Stack:** Swift 6.2, AppKit (NSSearchField, NSStepper, NSSlider), SwiftUI (NSViewRepresentable, ViewModifier)

**Spec:** `docs/superpowers/specs/2026-04-04-scroll-sensitivity-design.md`

---

### Task 1: Add `scrollSensitivity` to `MouseInput` model

**Files:**
- Modify: `Sources/ShortcutField/MouseInput.swift`

- [ ] **Step 1: Add the property and update init**

In `MouseInput.swift`, add the `scrollSensitivity` property after `modifiers`, and add it to the `init` with a default of `0.0`:

```swift
/// Scroll sensitivity from 0.0 (fire once per gesture) to 1.0 (every event).
/// Only meaningful for `.scroll` inputs; ignored for `.button` inputs.
public let scrollSensitivity: Double

public init(kind: InputKind, modifiers: NSEvent.ModifierFlags, scrollSensitivity: Double = 0.0) {
    self.kind = kind
    self.modifiers = modifiers.intersection([.shift, .control, .option, .command])
    self.scrollSensitivity = min(1.0, max(0.0, scrollSensitivity))
}
```

- [ ] **Step 2: Add `scrollSensitivity` to CodingKeys and update Codable**

Add `.scrollSensitivity` case to the `CodingKeys` enum in the `Codable` extension. Update `init(from:)` to decode with `decodeIfPresent` (backward compat). Update `encode(to:)` to encode the value.

In `init(from:)`, after the modifiers decode:
```swift
scrollSensitivity = min(1.0, max(0.0,
    try container.decodeIfPresent(Double.self, forKey: .scrollSensitivity) ?? 0.0
))
```

In `encode(to:)`, after encoding modifiers:
```swift
try container.encode(scrollSensitivity, forKey: .scrollSensitivity)
```

- [ ] **Step 3: Build**

Run: `just build`
Expected: Build succeeds. The `MouseInputRecorderField` call sites that create `MouseInput` without `scrollSensitivity` still compile because the parameter has a default value.

### Task 2: Add `ScrollSensitivityMode` enum

**Files:**
- Create: `Sources/ShortcutField/ScrollSensitivityMode.swift`

- [ ] **Step 1: Create the enum file**

```swift
import Foundation

/// Controls how scroll sensitivity is presented in the recorder UI.
public enum ScrollSensitivityMode: Sendable {
    /// User adjusts sensitivity via a discrete 1-5 stepper (default).
    /// Maps to values: 0.0, 0.25, 0.5, 0.75, 1.0.
    case stepper
    /// User adjusts sensitivity via a continuous 0.0-1.0 slider.
    case continuous
    /// Sensitivity UI is hidden. The developer sets sensitivity programmatically
    /// via the MouseInput value in the binding.
    case hidden

    /// The five discrete stepper values.
    static let stepperValues: [Double] = [0.0, 0.25, 0.5, 0.75, 1.0]

    /// Returns the stepper index (0-4) closest to the given sensitivity value.
    static func stepperIndex(for sensitivity: Double) -> Int {
        let clamped = min(1.0, max(0.0, sensitivity))
        var bestIndex = 0
        var bestDist = Double.greatestFiniteMagnitude
        for (i, val) in stepperValues.enumerated() {
            let dist = abs(val - clamped)
            if dist < bestDist {
                bestDist = dist
                bestIndex = i
            }
        }
        return bestIndex
    }
}
```

- [ ] **Step 2: Build**

Run: `just build`
Expected: Build succeeds.

### Task 3: Add `ScrollThrottleState` and throttling to `OnMouseInputModifier`

**Files:**
- Modify: `Sources/ShortcutField/OnMouseInputModifier.swift`

- [ ] **Step 1: Add `ScrollThrottleState` class**

Add before the `OnMouseInputModifier` struct:

```swift
@MainActor
final class ScrollThrottleState {
    var lastFireDate: Date?
    var suppressed = false
    var rearmWorkItem: DispatchWorkItem?

    func reset() {
        lastFireDate = nil
        suppressed = false
        rearmWorkItem?.cancel()
        rearmWorkItem = nil
    }

    /// Cooldown in seconds for a given sensitivity value (0.0 < s < 1.0).
    /// Formula: cooldownSeconds = (1.0 - s) / 0.75
    static func cooldown(for sensitivity: Double) -> TimeInterval {
        max(0, (1.0 - sensitivity) / 0.75)
    }
}
```

- [ ] **Step 2: Add throttle state and update the monitor closure**

Add to `OnMouseInputModifier`:
```swift
@State private var throttleState = ScrollThrottleState()
```

Replace the body of `installMonitor()` to add throttling for scroll events. The full updated method:

```swift
private func installMonitor() {
    guard let mouseInput, eventMonitor == nil else { return }

    let throttle = throttleState

    eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [
        .leftMouseDown,
        .rightMouseDown,
        .otherMouseDown,
        .scrollWheel,
    ]) { event in
        if ShortcutRecordingState.isAnyRecording {
            return event
        }
        if mouseInput.matches(event) {
            if event.type == .scrollWheel {
                return Self.handleScrollThrottle(
                    sensitivity: mouseInput.scrollSensitivity,
                    throttle: throttle,
                    action: action
                ) ? nil : event
            }
            action()
            return nil
        }
        return event
    }
}
```

Add the static throttle handler:

```swift
private static func handleScrollThrottle(
    sensitivity: Double,
    throttle: ScrollThrottleState,
    action: () -> Void
) -> Bool {
    // Level 1.0: no throttling
    if sensitivity >= 1.0 {
        action()
        return true
    }

    // Level 0.0: fire once per gesture
    if sensitivity <= 0.0 {
        if throttle.suppressed {
            // Reschedule re-arm
            throttle.rearmWorkItem?.cancel()
            let workItem = DispatchWorkItem { @MainActor in
                throttle.suppressed = false
            }
            throttle.rearmWorkItem = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: workItem)
            return true // consume but don't fire
        }
        // First fire — suppress further until idle
        throttle.suppressed = true
        let workItem = DispatchWorkItem { @MainActor in
            throttle.suppressed = false
        }
        throttle.rearmWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: workItem)
        action()
        return true
    }

    // Cooldown-based throttling (0.0 < s < 1.0)
    let cooldown = ScrollThrottleState.cooldown(for: sensitivity)
    let now = Date()
    if let lastFire = throttle.lastFireDate,
       now.timeIntervalSince(lastFire) < cooldown
    {
        return true // consume but don't fire
    }
    throttle.lastFireDate = now
    action()
    return true
}
```

- [ ] **Step 3: Reset throttle state on input change and disappear**

Update the `onChange` handler and add cleanup on disappear:

```swift
func body(content: Content) -> some View {
    content
        .onAppear {
            installMonitor()
        }
        .onDisappear {
            removeMonitor()
            throttleState.reset()
        }
        .onChange(of: mouseInput) { _, _ in
            removeMonitor()
            throttleState.reset()
            installMonitor()
        }
}
```

- [ ] **Step 4: Build**

Run: `just build`
Expected: Build succeeds.

### Task 4: Add sensitivity stepper/slider to `MouseInputRecorderField`

**Files:**
- Modify: `Sources/ShortcutField/MouseInputRecorderField.swift`

- [ ] **Step 1: Add `sensitivityMode` property and sensitivity control views**

Add properties after the existing `fieldBackgroundColor`:

```swift
/// Controls how scroll sensitivity is presented. Default: `.stepper`.
public var sensitivityMode: ScrollSensitivityMode = .stepper {
    didSet {
        updateSensitivityControl()
    }
}

private var sensitivityStepper: NSStepper?
private var sensitivitySlider: NSSlider?
private var sensitivityLabel: NSTextField?
```

- [ ] **Step 2: Add sensitivity control setup and management methods**

Add methods to create, show/hide, and handle the sensitivity controls:

```swift
private func setupSensitivityControls() {
    // Stepper
    let stepper = NSStepper()
    stepper.minValue = 0
    stepper.maxValue = 4
    stepper.increment = 1
    stepper.integerValue = 0
    stepper.valueWraps = false
    stepper.target = self
    stepper.action = #selector(sensitivityStepperChanged(_:))
    stepper.controlSize = .small
    stepper.isHidden = true
    addSubview(stepper)
    sensitivityStepper = stepper

    // Slider
    let slider = NSSlider()
    slider.minValue = 0.0
    slider.maxValue = 1.0
    slider.doubleValue = 0.0
    slider.target = self
    slider.action = #selector(sensitivitySliderChanged(_:))
    slider.controlSize = .small
    slider.isHidden = true
    addSubview(slider)
    sensitivitySlider = slider

    // Label (shows stepper value as "1" through "5")
    let label = NSTextField(labelWithString: "1")
    label.font = .systemFont(ofSize: 10)
    label.alignment = .center
    label.isHidden = true
    addSubview(label)
    sensitivityLabel = label
}

private func updateSensitivityControl() {
    let isScroll: Bool
    if case .scroll = mouseInput?.kind {
        isScroll = true
    } else {
        isScroll = false
    }

    let showStepper = isScroll && sensitivityMode == .stepper
    let showSlider = isScroll && sensitivityMode == .continuous

    sensitivityStepper?.isHidden = !showStepper
    sensitivityLabel?.isHidden = !showStepper
    sensitivitySlider?.isHidden = !showSlider

    if showStepper, let input = mouseInput {
        let idx = ScrollSensitivityMode.stepperIndex(for: input.scrollSensitivity)
        sensitivityStepper?.integerValue = idx
        sensitivityLabel?.stringValue = "\(idx + 1)"
    }

    if showSlider, let input = mouseInput {
        sensitivitySlider?.doubleValue = input.scrollSensitivity
    }

    needsLayout = true
}

@objc private func sensitivityStepperChanged(_ sender: NSStepper) {
    guard let mouseInput, case .scroll = mouseInput.kind else { return }
    let value = ScrollSensitivityMode.stepperValues[sender.integerValue]
    sensitivityLabel?.stringValue = "\(sender.integerValue + 1)"
    let newInput = MouseInput(kind: mouseInput.kind, modifiers: mouseInput.modifiers, scrollSensitivity: value)
    self.mouseInput = newInput
    onMouseInputChange?(newInput)
}

@objc private func sensitivitySliderChanged(_ sender: NSSlider) {
    guard let mouseInput, case .scroll = mouseInput.kind else { return }
    let newInput = MouseInput(kind: mouseInput.kind, modifiers: mouseInput.modifiers, scrollSensitivity: sender.doubleValue)
    self.mouseInput = newInput
    onMouseInputChange?(newInput)
}
```

- [ ] **Step 3: Call setup in `setup()` and layout the controls**

In `setup()`, add at the end:
```swift
setupSensitivityControls()
```

Override `layout()` to position the controls to the right of the text:

```swift
override public func layout() {
    super.layout()

    let controlWidth: CGFloat = 50
    let controlHeight: CGFloat = 16
    let labelWidth: CGFloat = 14
    let padding: CGFloat = 4
    let rightEdge = bounds.width - 24 // leave room for cancel button
    let centerY = (bounds.height - controlHeight) / 2

    if sensitivityStepper?.isHidden == false {
        let stepperWidth: CGFloat = 19
        sensitivityLabel?.frame = NSRect(
            x: rightEdge - stepperWidth - padding - labelWidth,
            y: centerY,
            width: labelWidth,
            height: controlHeight
        )
        sensitivityStepper?.frame = NSRect(
            x: rightEdge - stepperWidth,
            y: centerY,
            width: stepperWidth,
            height: controlHeight
        )
    }

    if sensitivitySlider?.isHidden == false {
        sensitivitySlider?.frame = NSRect(
            x: rightEdge - controlWidth,
            y: centerY,
            width: controlWidth,
            height: controlHeight
        )
    }
}
```

- [ ] **Step 4: Call `updateSensitivityControl()` from `updateDisplay()`**

At the end of `updateDisplay()`, add:
```swift
updateSensitivityControl()
```

- [ ] **Step 5: Build**

Run: `just build`
Expected: Build succeeds.

### Task 5: Add `.sensitivityMode()` to `MouseInputRecorderView`

**Files:**
- Modify: `Sources/ShortcutField/MouseInputRecorderView.swift`

- [ ] **Step 1: Add the property and modifier method**

Add to the private properties:
```swift
private var sensitivityModeValue: ScrollSensitivityMode = .stepper
```

Add in `makeNSView`, after setting `fieldBackgroundColor`:
```swift
field.sensitivityMode = sensitivityModeValue
```

Add in `updateNSView`, after setting `fieldBackgroundColor`:
```swift
nsView.sensitivityMode = sensitivityModeValue
```

Add the modifier method in the `Modifiers` extension:
```swift
/// Set how scroll sensitivity is presented in the recorder.
func sensitivityMode(_ mode: ScrollSensitivityMode) -> MouseInputRecorderView {
    var view = self
    view.sensitivityModeValue = mode
    return view
}
```

- [ ] **Step 2: Build**

Run: `just build`
Expected: Build succeeds.

### Task 6: Write tests

**Files:**
- Create: `Tests/ShortcutFieldTests/MouseInputTests.swift`

- [ ] **Step 1: Write model tests**

```swift
import Testing
@testable import ShortcutField

struct MouseInputTests {
    // MARK: - scrollSensitivity

    @Test func scrollSensitivity_defaultsToZero() {
        let input = MouseInput(kind: .scroll(.up), modifiers: [])
        #expect(input.scrollSensitivity == 0.0)
    }

    @Test func scrollSensitivity_clampsAboveOne() {
        let input = MouseInput(kind: .scroll(.up), modifiers: [], scrollSensitivity: 1.5)
        #expect(input.scrollSensitivity == 1.0)
    }

    @Test func scrollSensitivity_clampsBelowZero() {
        let input = MouseInput(kind: .scroll(.up), modifiers: [], scrollSensitivity: -0.5)
        #expect(input.scrollSensitivity == 0.0)
    }

    @Test func scrollSensitivity_preservesValidValue() {
        let input = MouseInput(kind: .scroll(.up), modifiers: [], scrollSensitivity: 0.37)
        #expect(input.scrollSensitivity == 0.37)
    }

    // MARK: - Equatable

    @Test func equatable_differentSensitivity_areNotEqual() {
        let a = MouseInput(kind: .scroll(.up), modifiers: [], scrollSensitivity: 0.0)
        let b = MouseInput(kind: .scroll(.up), modifiers: [], scrollSensitivity: 0.5)
        #expect(a != b)
    }

    @Test func equatable_sameSensitivity_areEqual() {
        let a = MouseInput(kind: .scroll(.up), modifiers: [], scrollSensitivity: 0.75)
        let b = MouseInput(kind: .scroll(.up), modifiers: [], scrollSensitivity: 0.75)
        #expect(a == b)
    }

    @Test func equatable_buttonIgnoresSensitivity_default() {
        // Both use default 0.0, so they are equal
        let a = MouseInput(kind: .button(1), modifiers: [])
        let b = MouseInput(kind: .button(1), modifiers: [])
        #expect(a == b)
    }

    // MARK: - Codable

    @Test func codableRoundtrip_withSensitivity() throws {
        let input = MouseInput(kind: .scroll(.down), modifiers: .shift, scrollSensitivity: 0.6)
        let data = try JSONEncoder().encode(input)
        let decoded = try JSONDecoder().decode(MouseInput.self, from: data)
        #expect(decoded == input)
        #expect(decoded.scrollSensitivity == 0.6)
    }

    @Test func codable_backwardCompat_missingSensitivity() throws {
        // JSON without scrollSensitivity key — should decode with default 0.0
        let json = """
        {"type":"scroll","direction":"up","modifiers":0}
        """
        let data = Data(json.utf8)
        let decoded = try JSONDecoder().decode(MouseInput.self, from: data)
        #expect(decoded.scrollSensitivity == 0.0)
    }

    @Test func codable_clampsOnDecode() throws {
        let json = """
        {"type":"scroll","direction":"up","modifiers":0,"scrollSensitivity":5.0}
        """
        let data = Data(json.utf8)
        let decoded = try JSONDecoder().decode(MouseInput.self, from: data)
        #expect(decoded.scrollSensitivity == 1.0)
    }

    // MARK: - Cooldown formula

    @Test func cooldown_atQuarter_is1000ms() {
        let cooldown = ScrollThrottleState.cooldown(for: 0.25)
        #expect(cooldown == 1.0) // 1.0 second
    }

    @Test func cooldown_atHalf_is667ms() {
        let cooldown = ScrollThrottleState.cooldown(for: 0.5)
        #expect(abs(cooldown - 0.667) < 0.001)
    }

    @Test func cooldown_atThreeQuarters_is333ms() {
        let cooldown = ScrollThrottleState.cooldown(for: 0.75)
        #expect(abs(cooldown - 0.333) < 0.001)
    }

    @Test func cooldown_atOne_isZero() {
        let cooldown = ScrollThrottleState.cooldown(for: 1.0)
        #expect(cooldown == 0.0)
    }

    @Test func cooldown_nearZero_isLarge() {
        let cooldown = ScrollThrottleState.cooldown(for: 0.01)
        #expect(cooldown > 1.3)
    }

    // MARK: - Stepper index mapping

    @Test func stepperIndex_mapsCorrectly() {
        #expect(ScrollSensitivityMode.stepperIndex(for: 0.0) == 0)
        #expect(ScrollSensitivityMode.stepperIndex(for: 0.25) == 1)
        #expect(ScrollSensitivityMode.stepperIndex(for: 0.5) == 2)
        #expect(ScrollSensitivityMode.stepperIndex(for: 0.75) == 3)
        #expect(ScrollSensitivityMode.stepperIndex(for: 1.0) == 4)
    }

    @Test func stepperIndex_roundsToNearest() {
        #expect(ScrollSensitivityMode.stepperIndex(for: 0.1) == 0)
        #expect(ScrollSensitivityMode.stepperIndex(for: 0.3) == 1)
        #expect(ScrollSensitivityMode.stepperIndex(for: 0.6) == 2)
        #expect(ScrollSensitivityMode.stepperIndex(for: 0.8) == 3)
    }
}
```

- [ ] **Step 2: Run tests**

Run: `just test`
Expected: All tests pass including new ones.

### Task 7: Update Example app

**Files:**
- Modify: `Example/ShortcutFieldExample/ContentView.swift`

- [ ] **Step 1: Add sensitivity mode picker to the controls section**

In `WorkbenchTab`, add a state variable:
```swift
@State private var selectedSensitivityMode: ScrollSensitivityMode = .stepper
```

Add a new `GridRow` in `controlsSection` after the Placeholder row:
```swift
GridRow {
    Text("Sensitivity:")
        .frame(width: 100, alignment: .trailing)
    Picker("", selection: $selectedSensitivityMode) {
        Text(".stepper").tag(ScrollSensitivityMode.stepper)
        Text(".continuous").tag(ScrollSensitivityMode.continuous)
        Text(".hidden").tag(ScrollSensitivityMode.hidden)
    }
    .labelsHidden()
    .pickerStyle(.segmented)
    .frame(width: 280)
}
```

Note: `ScrollSensitivityMode` needs `Hashable` conformance for use as a `Picker` tag. Add `: Hashable` to the enum declaration in `ScrollSensitivityMode.swift`.

- [ ] **Step 2: Pass sensitivity mode to the mouse input recorder**

Update `makeMouseInputRecorder` to accept and apply `sensitivityMode`:

```swift
private func makeMouseInputRecorder(_ mouseInput: Binding<MouseInput?>, style: ShortcutRecorderStyle,
                                    size: ControlSize, textColor: NSColor?, bgColor: NSColor?,
                                    sensitivityMode: ScrollSensitivityMode) -> some View
{
    var view = MouseInputRecorderView(mouseInput)
        .placeholder("Record Mouse Input")
        .style(style)
        .sensitivityMode(sensitivityMode)
    if let textColor { view = view.textColor(textColor) }
    if let bgColor { view = view.fieldBackgroundColor(bgColor) }
    return view.controlSize(size)
}
```

Update the call site in the body to pass `sensitivityMode: selectedSensitivityMode`.

- [ ] **Step 3: Build and verify**

Run: `just build`
Expected: Build succeeds.

Run: `just lint`
Expected: 0 violations.

Run: `just test`
Expected: All tests pass.

Ask the user to run `just example` and manually test:
- Record a scroll input, verify stepper appears
- Switch to `.continuous`, verify slider appears
- Switch to `.hidden`, verify no sensitivity control
- Verify fire counter respects sensitivity at different levels
