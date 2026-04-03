import Foundation
@testable import ShortcutField
import Testing

struct MouseInputTests {
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

    @Test func button_sensitivityClampedToZero() {
        let input = MouseInput(kind: .button(1), modifiers: [], scrollSensitivity: 0.5)
        #expect(input.scrollSensitivity == 0.0)
    }

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

    @Test func equatable_buttonsWithDifferentSensitivityArguments_areEqual() {
        let a = MouseInput(kind: .button(1), modifiers: [], scrollSensitivity: 0.5)
        let b = MouseInput(kind: .button(1), modifiers: [], scrollSensitivity: 1.0)
        #expect(a == b)
    }

    @Test func codableRoundtrip_withSensitivity() throws {
        let input = MouseInput(kind: .scroll(.down), modifiers: .shift, scrollSensitivity: 0.6)
        let data = try JSONEncoder().encode(input)
        let decoded = try JSONDecoder().decode(MouseInput.self, from: data)
        #expect(decoded == input)
        #expect(decoded.scrollSensitivity == 0.6)
    }

    @Test func codable_backwardCompat_missingSensitivity() throws {
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

    @Test func codable_buttonDecodesWithZeroSensitivity() throws {
        let json = """
        {"type":"button","buttonNumber":1,"modifiers":0,"scrollSensitivity":0.5}
        """
        let data = Data(json.utf8)
        let decoded = try JSONDecoder().decode(MouseInput.self, from: data)
        #expect(decoded.scrollSensitivity == 0.0)
    }

    @Test func cooldownSeconds_atQuarter_isOneSecond() {
        #expect(ScrollThrottleState.cooldownSeconds(for: 0.25) == 1.0)
    }

    @Test func cooldownSeconds_atHalf() {
        #expect(abs(ScrollThrottleState.cooldownSeconds(for: 0.5) - 0.667) < 0.001)
    }

    @Test func cooldownSeconds_atThreeQuarters() {
        #expect(abs(ScrollThrottleState.cooldownSeconds(for: 0.75) - 0.333) < 0.001)
    }

    @Test func cooldownSeconds_atOne_isZero() {
        #expect(ScrollThrottleState.cooldownSeconds(for: 1.0) == 0.0)
    }

    @Test func cooldownSeconds_nearZero_isLarge() {
        #expect(ScrollThrottleState.cooldownSeconds(for: 0.01) > 1.3)
    }

    @Test func discreteIndex_mapsCorrectly() {
        #expect(ScrollSensitivityMode.discreteIndex(for: 0.0) == 0)
        #expect(ScrollSensitivityMode.discreteIndex(for: 0.25) == 1)
        #expect(ScrollSensitivityMode.discreteIndex(for: 0.5) == 2)
        #expect(ScrollSensitivityMode.discreteIndex(for: 0.75) == 3)
        #expect(ScrollSensitivityMode.discreteIndex(for: 1.0) == 4)
    }

    @Test func discreteIndex_roundsToNearest() {
        #expect(ScrollSensitivityMode.discreteIndex(for: 0.1) == 0)
        #expect(ScrollSensitivityMode.discreteIndex(for: 0.3) == 1)
        #expect(ScrollSensitivityMode.discreteIndex(for: 0.6) == 2)
        #expect(ScrollSensitivityMode.discreteIndex(for: 0.8) == 3)
    }

    @MainActor
    @Test func evaluate_maxSensitivity_alwaysFires() {
        let state = ScrollThrottleState()
        state.sensitivity = 1.0
        let t0 = ContinuousClock.now
        let d1 = ScrollThrottleState.evaluate(state: state, now: t0)
        #expect(d1.shouldFire == true)
        #expect(d1.rearmAfter == nil)

        let d2 = ScrollThrottleState.evaluate(state: state, now: t0)
        #expect(d2.shouldFire == true)
    }

    @MainActor
    @Test func evaluate_fireOnce_suppressesAfterFirstFire() {
        let state = ScrollThrottleState()
        state.sensitivity = 0.0
        let t0 = ContinuousClock.now
        let d1 = ScrollThrottleState.evaluate(state: state, now: t0)
        #expect(d1.shouldFire == true)
        #expect(d1.rearmAfter == .milliseconds(350))

        let t1 = t0.advanced(by: .milliseconds(100))
        let d2 = ScrollThrottleState.evaluate(state: state, now: t1)
        #expect(d2.shouldFire == false)
        #expect(d2.rearmAfter == .milliseconds(350))
    }

    @MainActor
    @Test func evaluate_fireOnce_refiresAfterReset() {
        let state = ScrollThrottleState()
        state.sensitivity = 0.0
        _ = ScrollThrottleState.evaluate(state: state, now: ContinuousClock.now)
        state.reset()
        let d = ScrollThrottleState.evaluate(state: state, now: ContinuousClock.now)
        #expect(d.shouldFire == true)
    }

    @MainActor
    @Test func evaluate_cooldown_blocksWithinInterval() {
        let state = ScrollThrottleState()
        state.sensitivity = 0.5
        let t0 = ContinuousClock.now
        let d1 = ScrollThrottleState.evaluate(state: state, now: t0)
        #expect(d1.shouldFire == true)

        let t1 = t0.advanced(by: .milliseconds(500))
        let d2 = ScrollThrottleState.evaluate(state: state, now: t1)
        #expect(d2.shouldFire == false)
    }

    @MainActor
    @Test func evaluate_cooldown_firesAfterInterval() {
        let state = ScrollThrottleState()
        state.sensitivity = 0.5
        let t0 = ContinuousClock.now
        _ = ScrollThrottleState.evaluate(state: state, now: t0)
        let t1 = t0.advanced(by: .milliseconds(800))
        let d = ScrollThrottleState.evaluate(state: state, now: t1)
        #expect(d.shouldFire == true)
    }

    @MainActor
    @Test func evaluate_cooldown_firesFirstEventUnconditionally() {
        let state = ScrollThrottleState()
        state.sensitivity = 0.5
        let d = ScrollThrottleState.evaluate(state: state, now: ContinuousClock.now)
        #expect(d.shouldFire == true)
        #expect(d.rearmAfter == nil)
    }
}
