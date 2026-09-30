import Foundation

/// What an input tells its owner. Always delivered on the main thread.
public enum SpaceMouseEvent: Sendable, Equatable {
    case connected(String)
    case disconnected
    case failed(String)
    case axes(SpaceMouseAxes)
    case buttons(SpaceMouseButtons)
}

/// A source of SpaceMouse data (ADR-0003): the 3DxWare driver's client API or the device over HID.
@MainActor
public protocol SpaceMouseInput: AnyObject {
    /// Human-readable name for logs.
    var name: String { get }
    /// Whether the input keeps sending axis reports while the cap is held still. Only then may silence be read as
    /// "released" (watchdog).
    var streamsWhileDeflected: Bool { get }
    func start(onEvent: @escaping @MainActor (SpaceMouseEvent) -> Void)
    /// Called when REAPER becomes the active app or stops being it.
    func setActive(_ active: Bool)
    func stop()
}

/// Runs `body` on the main actor: directly if already on the main thread, otherwise asynchronously.
func onMain(_ body: @escaping @MainActor @Sendable () -> Void) {
    if pthread_main_np() != 0 {
        MainActor.assumeIsolated(body)
    } else {
        DispatchQueue.main.async(execute: body)
    }
}
