import Foundation

/// Rate control of the play cursor (ADR-0014): deflection is a velocity in view widths per second, like scrolling, so
/// it feels the same at every zoom level.
///
/// While playing, REAPER's play position runs on by itself and may report a seek only a little later (audio buffers).
/// The motion therefore keeps its own position, advanced by the play rate, and adopts REAPER's only when the two
/// differ by more than `tolerance` — then something else moved it (loop, the user, project end).
public struct PlayheadMotion: Sendable, Equatable {
    /// Seconds REAPER's position may differ from ours before we adopt it.
    public static let tolerance = 0.2

    private var ours: Double?

    public init() {}

    /// The new position after `deltaTime`.
    ///
    /// - Parameters:
    ///   - reaper: REAPER's current position (play position while the transport runs or pauses, else the edit cursor).
    ///   - playRate: how fast the position runs by itself, 0 while stopped or paused.
    ///   - value: −1…1; +1 moves `speed` view widths per second towards later times.
    public mutating func step(reaper: Double, playRate: Double, value: Double, speed: Double, viewWidth: Double,
                              deltaTime: Double) -> Double {
        var base = reaper
        if let ours {
            let expected = ours + playRate * deltaTime
            if abs(expected - reaper) <= Self.tolerance { base = expected }
        }
        let position = max(0, base + value * speed * viewWidth * deltaTime)
        ours = position
        return position
    }

    public mutating func reset() { ours = nil }
}
