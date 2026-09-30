import Foundation

/// A button that is a modifier, a click and a double click (ADR-0005): held while the cap moves an axis that only
/// works with the button held, it is a modifier and counts as no click; released without that, it was a click, and a
/// second click within the double-click interval is a double click.
public struct ModifierButton: Sendable, Equatable {
    public enum Release: Sendable, Equatable {
        case none, click, doubleClick
    }

    public private(set) var isHeld = false
    private var used = false
    private var lastClick: Double?

    public init() {}

    public mutating func press() {
        isHeld = true
        used = false
    }

    /// The held button changed what the cap does in this tick.
    public mutating func noteUsed() {
        if isHeld { used = true }
    }

    /// What the release completes. A double click consumes both clicks, so a third one starts afresh.
    public mutating func release(now: Double, doubleClickInterval: Double) -> Release {
        defer {
            isHeld = false
            used = false
        }
        guard isHeld, !used else {
            lastClick = nil
            return .none
        }
        if let lastClick, now - lastClick <= doubleClickInterval {
            self.lastClick = nil
            return .doubleClick
        }
        lastClick = now
        return .click
    }
}
