import Foundation

/// The speed slider (ADR-0012): a position from -1 (slowest) through 0 (normal, speed 1) to +1 (fastest),
/// logarithmic, so both halves span the same factor.
public enum SpeedScale {
    /// Speed at either end of the slider: ÷4 … ×4.
    public static let span = 4.0
    /// Positions this close to the middle count as the middle, so "normal" is easy to hit.
    public static let snap = 0.04

    public static func speed(at position: Double) -> Double {
        pow(span, clamped(position))
    }

    public static func position(for speed: Double) -> Double {
        guard speed > 0 else { return -1 }
        return clamped(log(speed) / log(span))
    }

    /// The position as the slider should keep it: snapped to the middle when close to it.
    public static func snapped(_ position: Double) -> Double {
        abs(position) < snap ? 0 : clamped(position)
    }

    private static func clamped(_ position: Double) -> Double { min(max(position, -1), 1) }
}
