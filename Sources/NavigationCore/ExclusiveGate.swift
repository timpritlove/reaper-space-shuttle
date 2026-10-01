import Foundation

/// Lets only one of two movements act at a time (ADR-0014, Tim 2026-10-01: while scrolling, the twist must not count,
/// and the other way round). The one that starts first wins until it comes back to rest; if both start in the same
/// tick, the stronger one wins.
public struct ExclusiveGate: Sendable, Equatable {
    enum Owner: Sendable, Equatable {
        case none, first, second
    }

    private(set) var owner = Owner.none

    public init() {}

    /// Both values with the one that does not own the gate set to 0.
    public mutating func filter(_ first: Double, _ second: Double) -> (first: Double, second: Double) {
        switch owner {
        case .first where first == 0, .second where second == 0, .none:
            owner = if first == 0 && second == 0 { .none } else if abs(first) >= abs(second) { .first } else { .second }
        default:
            break
        }
        switch owner {
        case .none: return (0, 0)
        case .first: return (first, 0)
        case .second: return (0, second)
        }
    }
}
