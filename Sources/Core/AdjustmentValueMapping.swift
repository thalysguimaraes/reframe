import Foundation

/// Shared mapping math for UI-facing adjustment controls.
public enum PortraitBlurMapping {
    public static let maximumRadius: Double = 40
    private static let rampExponent: Double = 2

    /// Returns a gently curved blur radius for a user-facing strength in `0...1`.
    public static func radius(for strength: Double) -> Double {
        let clampedStrength = min(max(strength, 0), 1)
        guard clampedStrength > 0 else { return 0 }
        return maximumRadius * pow(clampedStrength, rampExponent)
    }
}

/// Keeps the contrast slider centered on the neutral `1.0` contrast value while
/// still covering the full Core Image range of `0.5...2.0`.
public enum ContrastControlMapping {
    public static let controlRange: ClosedRange<Double> = -1 ... 1
    public static let contrastRange: ClosedRange<Double> = 0.5 ... 2.0

    public static func contrast(for controlValue: Double) -> Double {
        let clampedControl = min(max(controlValue, controlRange.lowerBound), controlRange.upperBound)
        if clampedControl < 0 {
            return 1.0 + 0.5 * clampedControl
        }
        return 1.0 + clampedControl
    }

    public static func controlValue(for contrast: Double) -> Double {
        let clampedContrast = min(max(contrast, contrastRange.lowerBound), contrastRange.upperBound)
        if clampedContrast < 1.0 {
            return (clampedContrast - 1.0) / 0.5
        }
        return clampedContrast - 1.0
    }

    public static func relativePercentage(for contrast: Double) -> Double {
        let clampedContrast = min(max(contrast, contrastRange.lowerBound), contrastRange.upperBound)
        return (clampedContrast - 1.0) * 100.0
    }
}
