import Foundation

/// What each control of the SpaceMouse does with the current settings, for the settings window (ADR-0012).
public struct ControlsDescription: Sendable, Equatable {
    public struct Line: Sendable, Equatable, Identifiable {
        public let control: String
        public let function: String
        public var id: String { control }
    }

    public let cap: [Line]
    public let buttons: [Line]

    /// - Parameters:
    ///   - actionName: REAPER's name for an action ID, nil if unknown.
    ///   - ledFeedback: whether the input can flash the LED (native only, ADR-0010).
    public init(settings: NavigationSettings, ledFeedback: Bool, actionName: (Int) -> String?) {
        let mapping = settings.mapping
        cap = AxisMapping.Role.allCases.compactMap { role in
            let axes = mapping[role]
            guard !axes.isEmpty else { return nil }
            return Line(control: Self.names(axes), function: Self.name(role))
        }

        var buttons = [Line(control: "Left button",
                            function: "Autoscroll on/off" + (ledFeedback ? " (LED flashes once for on, twice for off)" : ""))]
        for (role, axes) in mapping.held.sorted(by: { $0.key.rawValue < $1.key.rawValue }) where !axes.isEmpty {
            buttons.append(Line(control: "Right button held + \(Self.names(axes).lowercased())", function: Self.name(role)))
        }
        func action(_ id: Int) -> String {
            guard id > 0 else { return "Nothing" }
            return actionName(id) ?? "Action \(id)"
        }
        buttons.append(Line(control: "Right button click", function: action(settings.rightClickAction)))
        buttons.append(Line(control: "Right button double click", function: action(settings.rightDoubleClickAction)))
        self.buttons = buttons
    }

    static func name(_ role: AxisMapping.Role) -> String {
        switch role {
        case .scroll: "Scroll the timeline"
        case .zoom: "Zoom the timeline"
        case .playhead: "Move the play cursor (not while recording)"
        case .vscroll: "Scroll the track list"
        case .vzoom: "Track height"
        }
    }

    static func name(_ axis: AxisMapping.Axis) -> String {
        switch axis {
        case .x: "Slide left/right"
        case .y: "Slide forward/back"
        case .z: "Push/pull"
        case .rx: "Tilt forward/back"
        case .ry: "Tilt left/right"
        case .rz: "Twist"
        }
    }

    static func names(_ axes: [AxisMapping.Axis]) -> String {
        let names = axes.map(name)
        guard let first = names.first else { return "" }
        return ([first] + names.dropFirst().map { $0.lowercased() }).joined(separator: " or ")
    }
}
