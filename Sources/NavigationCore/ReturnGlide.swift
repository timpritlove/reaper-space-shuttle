import Foundation

/// Glides the view back to the play position before autoscroll takes over again (ADR-0006): speeding up until half
/// the distance, then slowing down, with the most acceleration the remaining distance allows ("bang-bang").
///
/// Distances are measured in view widths, so the glide looks the same at every zoom level; the duration grows only
/// with the logarithm of the distance, so a far jump does not take forever. The glide runs in the target's frame: when
/// the play position moves on, the view moves with it, and only the remaining offset is eased.
public struct ReturnGlide: Sendable, Equatable {
    /// Remaining offset (in widths) below which the glide counts as arrived.
    public static let arrivalTolerance = 0.002

    private var acceleration: Double
    /// Current speed relative to the target, widths per second, signed.
    private var speed = 0.0
    private var previousTarget: Double?

    /// - Parameter distance: offset from the view's start to the target start, in widths.
    public init(distance: Double) {
        acceleration = Self.acceleration(for: distance)
    }

    /// Seconds a glide over `distance` widths takes: 0.4 s up to 1.8 s.
    public static func duration(for distance: Double) -> Double {
        min(max(0.4 + 0.3 * log2(1 + abs(distance)), 0.4), 1.8)
    }

    /// Bang-bang over distance d in time T needs a = 4d/T².
    static func acceleration(for distance: Double) -> Double {
        let time = duration(for: distance)
        return max(4 * abs(distance) / (time * time), 1)
    }

    /// The view after `deltaTime`, heading for a view that starts at `targetStart`, and whether it arrived.
    public mutating func step(_ view: TimeRange, targetStart: Double, deltaTime: Double) -> (view: TimeRange, arrived: Bool) {
        let width = view.width
        guard width > 0 else { return (view, true) }
        var start = view.start
        if let previousTarget {
            let carry = targetStart - previousTarget
            if abs(carry) > width {
                // The play position jumped (loop, seek): start a new glide from here.
                speed = 0
                acceleration = Self.acceleration(for: (targetStart - start) / width)
            } else {
                start += carry
            }
        }
        previousTarget = targetStart

        let remaining = (targetStart - start) / width
        guard abs(remaining) > Self.arrivalTolerance else {
            return (TimeRange(start: targetStart, end: targetStart + width), true)
        }
        let direction: Double = remaining < 0 ? -1 : 1
        var magnitude = speed * direction > 0 ? abs(speed) : 0
        magnitude = min(magnitude + acceleration * deltaTime, (2 * acceleration * abs(remaining)).squareRoot())
        let move = magnitude * deltaTime
        guard move < abs(remaining) else {
            return (TimeRange(start: targetStart, end: targetStart + width), true)
        }
        speed = direction * magnitude
        start += direction * move * width
        return (TimeRange(start: start, end: start + width), false)
    }
}
