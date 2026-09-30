import Foundation

/// Keeps the track list still while the view moves horizontally (ADR-0005, Tim 2026-10-01: "mostly one only wants to
/// move horizontally without shifting vertically"). The direction that dominates when a movement starts wins:
/// a movement that starts horizontal (scroll or zoom) blocks vertical scrolling until the horizontal part ends; one that
/// starts with vertical dominating scrolls vertically (horizontal still works).
public struct VerticalGate: Sendable, Equatable {
    enum Mode: Sendable, Equatable {
        case idle, horizontal, vertical
    }

    private(set) var mode = Mode.idle

    public init() {}

    /// The vertical value to use. `horizontal` is the strongest horizontal role value (scroll, zoom), `vertical` the
    /// vertical scroll value, both after shaping.
    public mutating func filter(horizontal: Double, vertical: Double) -> Double {
        let h = abs(horizontal), v = abs(vertical)
        switch mode {
        case .idle:
            if v > 0, v > h {
                mode = .vertical
                return vertical
            }
            if h > 0 { mode = .horizontal }
            return 0
        case .horizontal:
            guard h == 0 else { return 0 }
            mode = v > 0 ? .vertical : .idle
            return vertical
        case .vertical:
            if v == 0 { mode = h > 0 ? .horizontal : .idle }
            return vertical
        }
    }
}
