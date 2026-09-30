import Foundation

/// A visible time range of the arrange view, in seconds.
public struct TimeRange: Sendable, Equatable {
    public var start: Double
    public var end: Double

    public init(start: Double, end: Double) {
        self.start = start
        self.end = end
    }

    public var width: Double { end - start }

    public func contains(_ time: Double) -> Bool { time >= start && time <= end }
}

/// Rate control of the arrange view (ADR-0004): scroll and zoom are velocities, integrated over elapsed time.
public enum ArrangeMotion {
    /// The view after `deltaTime` seconds.
    ///
    /// - Parameters:
    ///   - scroll: −1…1; +1 moves the view `scrollSpeed` widths per second towards later times.
    ///   - zoom: −1…1; +1 zooms in by a factor of e^`zoomSpeed` per second.
    ///   - anchor: the time that stays in place while zooming.
    /// Scrolling is measured in widths so it feels the same at every zoom level; zoom is exponential for the same
    /// reason.
    public static func step(_ view: TimeRange, scroll: Double, zoom: Double, anchor: Double,
                            scrollSpeed: Double, zoomSpeed: Double, deltaTime: Double) -> TimeRange {
        let width = view.width
        guard width > 0, deltaTime > 0 else { return view }
        let rate = zoom * zoomSpeed
        let newWidth = width * exp(-rate * deltaTime)
        let fraction = (anchor - view.start) / width
        var start = anchor - fraction * newWidth
        // Scrolling runs in widths per second while the width changes: integrate w₀·e^(−rate·t) over the step, so the
        // result does not depend on the tick rate.
        let widthSeconds = abs(rate) < 1e-9 ? width * deltaTime : (width - newWidth) / rate
        start += scroll * scrollSpeed * widthSeconds
        return TimeRange(start: start, end: start + newWidth)
    }

    /// The zoom anchor for the current view.
    public static func anchor(_ choice: NavigationSettings.ZoomAnchor, view: TimeRange,
                              editCursor: Double, playPosition: Double?) -> Double {
        let center = (view.start + view.end) / 2
        switch choice {
        case .center:
            return center
        case .editCursor:
            return view.contains(editCursor) ? editCursor : center
        case .playPosition:
            if let playPosition, view.contains(playPosition) { return playPosition }
            return center
        case .automatic:
            if let playPosition, view.contains(playPosition) { return playPosition }
            return view.contains(editCursor) ? editCursor : center
        }
    }

    /// Whether REAPER's view differs from the one we set by more than `pixels` at `pixelsPerSecond` — then something
    /// else moved it (the user, REAPER clamping at the project start or maximum zoom) and we adopt REAPER's view.
    /// Smaller differences are REAPER rounding to pixels; we keep our own fractional view so slow motion adds up.
    public static func diverged(_ reaper: TimeRange, from ours: TimeRange, pixelsPerSecond: Double,
                                pixels: Double = 1.5) -> Bool {
        guard pixelsPerSecond > 0 else { return true }
        let tolerance = pixels / pixelsPerSecond
        return abs(reaper.start - ours.start) > tolerance || abs(reaper.end - ours.end) > tolerance
    }
}

/// Turns a rate (steps per second) into whole steps for APIs that only move in steps (vertical scroll and zoom).
public struct StepAccumulator: Sendable, Equatable {
    private var remainder = 0.0

    public init() {}

    /// Whole steps due after `deltaTime` at `rate` steps per second; the fraction carries over.
    public mutating func steps(rate: Double, deltaTime: Double) -> Int {
        guard rate != 0 else {
            remainder = 0
            return 0
        }
        if remainder != 0, (remainder < 0) != (rate < 0) { remainder = 0 }
        remainder += rate * deltaTime
        let whole = remainder.rounded(.towardZero)
        remainder -= whole
        return Int(whole)
    }

    public mutating func reset() { remainder = 0 }
}
