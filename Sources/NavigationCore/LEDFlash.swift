import Foundation

/// A short LED pattern that confirms the autoscroll button (ADR-0010): the LED, normally lit, goes dark once when
/// autoscroll is switched on and twice when it is switched off, and always ends lit.
public enum LEDFlash {
    public struct Step: Sendable, Equatable {
        /// Seconds after the start of the pattern.
        public let delay: Double
        public let on: Bool
    }

    /// Seconds the LED stays dark, and lit between two flashes.
    public static let defaultPhase = 0.15

    /// One flash per `count`: dark, then lit again after `phase`.
    public static func steps(count: Int, phase: Double = defaultPhase) -> [Step] {
        (0..<max(count, 0)).flatMap { flash in
            let start = Double(flash) * 2 * phase
            return [Step(delay: start, on: false), Step(delay: start + phase, on: true)]
        }
    }

    /// The pattern for autoscroll switched on (one flash) or off (two flashes).
    public static func autoscroll(on: Bool, phase: Double = defaultPhase) -> [Step] {
        steps(count: on ? 1 : 2, phase: phase)
    }
}
