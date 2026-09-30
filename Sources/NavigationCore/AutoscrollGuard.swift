import Foundation

/// REAPER's two autoscroll options ("auto-view-scroll during playback" and "while recording").
public struct AutoscrollState: Sendable, Equatable {
    public var playback: Bool
    public var recording: Bool

    public init(playback: Bool, recording: Bool) {
        self.playback = playback
        self.recording = recording
    }

    public static let off = AutoscrollState(playback: false, recording: false)
    public static let on = AutoscrollState(playback: true, recording: true)

    public var any: Bool { playback || recording }

    func union(_ other: AutoscrollState) -> AutoscrollState {
        AutoscrollState(playback: playback || other.playback, recording: recording || other.recording)
    }
}

/// Keeps autoscroll out of the way while the SpaceMouse moves the view horizontally, and brings it back after a
/// rest (ADR-0006): holding → (rest for `grace`) → returning (the caller glides to the play position) → restored.
/// Pure state machine: the caller reads REAPER's state, passes it in, and applies what comes back.
public struct AutoscrollGuard: Sendable, Equatable {
    /// Options we switched off and will switch on again.
    public private(set) var suspended = AutoscrollState.off
    /// True while the caller should glide the view back to the play position.
    public private(set) var isReturning = false
    private var restoreAt: Double?
    private var moving = false

    public init() {}

    /// Whether the guard is holding autoscroll off, waiting to restore it or returning.
    public var isHolding: Bool { moving || suspended.any }

    /// Called every tick. `needsReturn`: the play position is running and the view is not (yet) back at it — while
    /// idle "not visible", while returning "glide not arrived". Returns the state to set, or nil to leave REAPER alone.
    public mutating func update(now: Double, moving: Bool, current: AutoscrollState, grace: Double,
                                needsReturn: Bool = false) -> AutoscrollState? {
        self.moving = moving
        if moving {
            restoreAt = nil
            isReturning = false
            guard current.any else { return nil }
            // Also catches an option switched on by hand while moving: it is held off and restored with the rest.
            suspended = suspended.union(current)
            return .off
        }
        guard suspended.any else { return nil }
        if isReturning {
            return needsReturn ? nil : restore(current)
        }
        let deadline = restoreAt ?? now + grace
        restoreAt = deadline
        guard now >= deadline else { return nil }
        if needsReturn {
            isReturning = true
            return nil
        }
        return restore(current)
    }

    private mutating func restore(_ current: AutoscrollState) -> AutoscrollState? {
        let target = current.union(suspended)
        suspended = .off
        restoreAt = nil
        isReturning = false
        return target == current ? nil : target
    }

    /// The left button (ADR-0006): both options together, on if both are off, otherwise off. While the guard holds
    /// autoscroll (moving, resting or returning), the button changes what comes back instead of switching now.
    public mutating func toggle(current: AutoscrollState) -> AutoscrollState? {
        if isHolding {
            suspended = suspended.any ? .off : .on
            if !suspended.any {
                restoreAt = nil
                isReturning = false
            }
            return nil
        }
        return current.any ? .off : .on
    }

    /// Everything we switched off, switched on again right now (unload, input lost, REAPER in the background).
    public mutating func release(current: AutoscrollState) -> AutoscrollState? {
        defer { moving = false }
        guard suspended.any else {
            restoreAt = nil
            isReturning = false
            return nil
        }
        return restore(current)
    }
}
