import Foundation

/// Everything the user can tune. Read from REAPER's extension state (section `spacemouse`, file
/// `reaper-extstate.ini`); a missing or unreadable key keeps the default.
public struct NavigationSettings: Sendable, Equatable {
    public enum InputChoice: String, Sendable {
        /// 3DxWare driver if its framework is installed, otherwise native HID (ADR-0003).
        case automatic = "auto"
        case driver
        case native
    }

    public enum ZoomAnchor: String, Sendable {
        /// Play position while playing and visible, else the edit cursor if visible, else the middle of the view.
        case automatic = "auto"
        case center
        case editCursor = "edit"
        case playPosition = "play"
    }

    public var input = InputChoice.automatic
    /// How to register with the 3DxWare driver: `app` (as the frontmost application) or `manual` (ADR-0003).
    public var driverRegistration = "app"
    /// Value of a fully deflected axis; the driver scales its values, so this may need tuning there.
    public var fullScale = 350.0
    public var shaping = AxisShaping()
    /// Overall speed factor for every movement (Tim, 2026-10-01): 1 is the baseline, which feels like the 3DxWare
    /// speed slider in its middle position; experienced users may want more.
    public var speed = 1.0
    /// View widths per second at full deflection.
    public var scrollSpeed = 3.0
    /// Natural-log zoom rate per second at full deflection: 3 means ×e³ ≈ 20 per second.
    public var zoomSpeed = 3.0
    /// REAPER track-list steps per second at full deflection (Tim, 2026-10-01: 20 was far too slow, 200 still too slow).
    public var verticalScrollSteps = 500.0
    /// REAPER track-height steps per second at full deflection.
    public var verticalZoomSteps = 80.0
    public var zoomAnchor = ZoomAnchor.automatic
    /// Ticks per second while moving (60 = every device report, 30 = every second one).
    public var tickRate = 60.0
    /// Seconds of rest before a suspended autoscroll comes back (ADR-0006).
    public var autoscrollGrace = 1.5
    /// Where the play position ends up in the view after gliding back to it: 0 = left edge, 0.5 = middle (ADR-0006).
    public var returnPosition = 0.5
    /// Action run by a click of the right button (released without being used as a modifier); 0 = none.
    public var rightClickAction = 0
    /// Action run by a double click of the right button; 40295 = "View: Zoom out project" (Tim, 2026-10-01).
    public var rightDoubleClickAction = 40295
    public var mapping = AxisMapping()
    public var diagnostics = false

    public init() {}

    /// Top speeds with the overall factor applied.
    public var effectiveScrollSpeed: Double { scrollSpeed * speed }
    public var effectiveZoomSpeed: Double { zoomSpeed * speed }
    public var effectiveVerticalScrollSteps: Double { verticalScrollSteps * speed }
    public var effectiveVerticalZoomSteps: Double { verticalZoomSteps * speed }

    /// Reads every known key through `lookup`; unknown values keep the default.
    public init(lookup: (String) -> String?) {
        func number(_ key: String) -> Double? { lookup(key).flatMap { Double($0.trimmingCharacters(in: .whitespaces)) } }
        func flag(_ key: String) -> Bool? { number(key).map { $0 != 0 } }

        if let value = lookup("input").flatMap(InputChoice.init(rawValue:)) { input = value }
        if let value = lookup("driver_registration"), ["app", "manual"].contains(value) { driverRegistration = value }
        if let value = number("full_scale"), value > 0 { fullScale = value }
        if let value = number("deadzone"), (0..<1).contains(value) { shaping.deadzone = value }
        if let value = number("exponent"), value > 0 { shaping.exponent = value }
        if let value = number("crosstalk"), (0...1).contains(value) { shaping.crosstalkRatio = value }
        if let value = number("speed"), (0.1...10).contains(value) { speed = value }
        if let value = number("scroll_speed"), value >= 0 { scrollSpeed = value }
        if let value = number("zoom_speed"), value >= 0 { zoomSpeed = value }
        if let value = number("vscroll_steps"), value >= 0 { verticalScrollSteps = value }
        if let value = number("vzoom_steps"), value >= 0 { verticalZoomSteps = value }
        if let value = lookup("zoom_anchor").flatMap(ZoomAnchor.init(rawValue:)) { zoomAnchor = value }
        if let value = number("tick_rate"), (1...240).contains(value) { tickRate = value }
        if let value = number("autoscroll_grace"), value >= 0 { autoscrollGrace = value }
        if let value = number("return_position"), (0...1).contains(value) { returnPosition = value }
        if let value = number("right_click_action") { rightClickAction = Int(value) }
        if let value = number("right_double_click_action") { rightDoubleClickAction = Int(value) }
        for axis in AxisMapping.Role.allCases {
            if let value = lookup("\(axis.rawValue)_axis").flatMap(AxisMapping.axes(from:)) {
                mapping[axis] = value
            }
            if let value = lookup("\(axis.rawValue)_axis_held").flatMap(AxisMapping.axes(from:)) {
                mapping.held[axis] = value
            }
            if let value = flag("\(axis.rawValue)_invert") { mapping.inverted[axis] = value }
        }
        if let value = flag("diagnostics") { diagnostics = value }
    }
}

/// Which cap movements drive which view movement (ADR-0005). A role may take several axes; their values add up.
public struct AxisMapping: Sendable, Equatable {
    public enum Axis: String, Sendable, CaseIterable {
        case x, y, z, rx, ry, rz
    }

    public enum Role: String, Sendable, CaseIterable {
        case scroll, zoom, vscroll, vzoom
    }

    /// Slide right or twist clockwise → later, push down → zoom in, slide forward → up the track list. Track height is
    /// off: REAPER only changes it in coarse steps, which does not fit the stepless rest (Tim, 2026-10-01).
    public var axes: [Role: [Axis]] = [.scroll: [.x, .rz], .zoom: [.z], .vscroll: [.y], .vzoom: []]
    /// While the right button is held, these roles take these axes, and the axes leave every other role:
    /// right button + twist = track height (Tim, 2026-10-01).
    public var held: [Role: [Axis]] = [.vzoom: [.rz]]
    public var inverted: [Role: Bool] = [:]

    /// The mapping in effect while the right button is held.
    public var whileHeld: AxisMapping {
        var mapping = self
        let taken = Set(held.values.flatMap { $0 })
        for role in Role.allCases {
            mapping[role] = held[role] ?? self[role].filter { !taken.contains($0) }
        }
        return mapping
    }

    public init() {}

    public subscript(role: Role) -> [Axis] {
        get { axes[role] ?? [] }
        set { axes[role] = newValue }
    }

    /// Parses a setting like `x`, `x,rz` or `none`; nil if any part is unknown.
    public static func axes(from text: String) -> [Axis]? {
        let parts = text.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
        if parts == ["none"] { return [] }
        let axes = parts.compactMap(Axis.init(rawValue:))
        return axes.count == parts.count && !axes.isEmpty ? axes : nil
    }
}
