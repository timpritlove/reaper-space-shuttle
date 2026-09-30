import Foundation
import SpaceMouseKit

/// Turns raw axis values into −1…1 per axis (ADR-0005): how far the cap is deflected sets how fast the view moves.
public struct AxisShaping: Sendable, Equatable {
    /// Fraction of full deflection ignored around rest.
    public var deadzone = 0.12
    /// Response curve exponent. 3 (with the doubled top speeds) keeps half deflection as fast as exponent 2 did, is
    /// finer below and accelerates harder above (Tim, 2026-10-01: "more acceleration at high values").
    public var exponent = 3.0
    /// An axis only counts while it reaches this fraction of the strongest axis. The cap's crosstalk reaches 151/350
    /// (0.43) on the wrong axis (stagehand findings), so 0.5 suppresses it and still allows deliberate diagonals.
    /// 0 turns the suppression off.
    public var crosstalkRatio = 0.5

    public init() {}

    /// Shaped values in the order x y z rx ry rz.
    public func shaped(_ axes: SpaceMouseAxes, fullScale: Double) -> ShapedAxes {
        let normalized = axes.all.map { max(-1, min(1, Double($0) / fullScale)) }
        let strongest = normalized.map(abs).max() ?? 0
        let values = normalized.map { value -> Double in
            let magnitude = abs(value)
            guard magnitude > deadzone, magnitude >= crosstalkRatio * strongest else { return 0 }
            let t = pow((magnitude - deadzone) / (1 - deadzone), exponent)
            return value < 0 ? -t : t
        }
        return ShapedAxes(values: values)
    }
}

/// −1…1 per axis after dead zone, crosstalk suppression and response curve.
public struct ShapedAxes: Sendable, Equatable {
    public var values: [Double]

    public static let zero = ShapedAxes(values: Array(repeating: 0, count: 6))

    public subscript(axis: AxisMapping.Axis) -> Double {
        switch axis {
        case .x: values[0]
        case .y: values[1]
        case .z: values[2]
        case .rx: values[3]
        case .ry: values[4]
        case .rz: values[5]
        }
    }

    /// The value for a role: the sum of its axes, limited to −1…1, with the mapping's inversion applied.
    public func value(for role: AxisMapping.Role, in mapping: AxisMapping) -> Double {
        let sum = mapping[role].reduce(0) { $0 + self[$1] }
        let value = max(-1, min(1, sum))
        return mapping.inverted[role] == true ? -value : value
    }
}
