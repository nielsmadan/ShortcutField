import Foundation

/// Controls how the sensitivity slider is presented in `ContinuousShortcutRecorderView`.
public enum SensitivityMode: Sendable, Hashable {
    /// User adjusts sensitivity via a slider that snaps to 5 discrete tick marks (default).
    /// Maps to values: 0.0, 0.25, 0.5, 0.75, 1.0.
    case discrete
    /// User adjusts sensitivity via a continuous 0.0-1.0 slider.
    case continuous

    static let discreteValues: [Double] = [0.0, 0.25, 0.5, 0.75, 1.0]

    /// The value this mode stores: the nearest tick in `.discrete`, the clamped
    /// value in `.continuous`.
    func snap(_ sensitivity: Double) -> Double {
        switch self {
        case .discrete: Self.discreteValues[Self.discreteIndex(for: sensitivity)]
        case .continuous: sensitivity.clampedToUnitInterval
        }
    }

    /// Returns the discrete tick-mark index (0-4) closest to the given sensitivity value.
    static func discreteIndex(for sensitivity: Double) -> Int {
        let clamped = sensitivity.clampedToUnitInterval
        var bestIndex = 0
        var bestDist = Double.greatestFiniteMagnitude
        for (i, val) in discreteValues.enumerated() {
            let dist = abs(val - clamped)
            if dist < bestDist {
                bestDist = dist
                bestIndex = i
            }
        }
        return bestIndex
    }
}

/// Where the sensitivity control appears relative to the recorder field.
public enum SensitivityPosition: Sendable, Hashable {
    /// Control appears below the field (default).
    case below
    /// Control appears to the left of the field.
    case left
    /// Control appears to the right of the field.
    case right
}
