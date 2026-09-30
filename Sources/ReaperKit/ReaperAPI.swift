import ReaperBridge

/// Opaque REAPER handles. `nil` as project means "the active project".
public typealias ReaProject = OpaquePointer
public typealias KbdSectionInfo = OpaquePointer

public enum ReaperAPIError: Error, CustomStringConvertible {
    case missingFunction(String)

    public var description: String {
        switch self {
        case .missingFunction(let name): "REAPER API function \(name) not found"
        }
    }
}

/// Typed access to the REAPER API functions we use, resolved by name via `GetFunc`.
///
/// REAPER's API must only be called on its UI thread (ADR-0002); the type is main-actor isolated to enforce that.
/// Signatures follow `reaper_plugin_functions.h`.
@MainActor
public final class ReaperAPI {
    let _ShowConsoleMsg: @convention(c) (UnsafePointer<CChar>?) -> Void
    let _GetAppVersion: @convention(c) () -> UnsafePointer<CChar>?
    let _GetSet_ArrangeView2: @convention(c) (ReaProject?, Bool, Int32, Int32, UnsafeMutablePointer<Double>?, UnsafeMutablePointer<Double>?) -> Void
    let _GetHZoomLevel: @convention(c) () -> Double
    let _GetCursorPosition: @convention(c) () -> Double
    let _GetPlayPosition: @convention(c) () -> Double
    let _GetPlayState: @convention(c) () -> Int32
    let _GetToggleCommandState: @convention(c) (Int32) -> Int32
    let _Main_OnCommand: @convention(c) (Int32, Int32) -> Void
    let _CSurf_OnScroll: @convention(c) (Int32, Int32) -> Void
    let _CSurf_OnZoom: @convention(c) (Int32, Int32) -> Void
    let _GetExtState: @convention(c) (UnsafePointer<CChar>?, UnsafePointer<CChar>?) -> UnsafePointer<CChar>?
    let _SetExtState: @convention(c) (UnsafePointer<CChar>?, UnsafePointer<CChar>?, UnsafePointer<CChar>?, Bool) -> Void
    let _kbd_getTextFromCmd: @convention(c) (UInt32, KbdSectionInfo?) -> UnsafePointer<CChar>?
    let _SectionFromUniqueID: @convention(c) (Int32) -> KbdSectionInfo?
    let _kbd_enumerateActions: @convention(c) (KbdSectionInfo?, Int32, UnsafeMutablePointer<UnsafePointer<CChar>?>?) -> Int32

    public init(getFunc: (String) -> UnsafeMutableRawPointer?) throws {
        func load<T>(_ name: String) throws -> T {
            guard let pointer = getFunc(name) else { throw ReaperAPIError.missingFunction(name) }
            return unsafeBitCast(pointer, to: T.self)
        }
        _ShowConsoleMsg = try load("ShowConsoleMsg")
        _GetAppVersion = try load("GetAppVersion")
        _GetSet_ArrangeView2 = try load("GetSet_ArrangeView2")
        _GetHZoomLevel = try load("GetHZoomLevel")
        _GetCursorPosition = try load("GetCursorPosition")
        _GetPlayPosition = try load("GetPlayPosition")
        _GetPlayState = try load("GetPlayState")
        _GetToggleCommandState = try load("GetToggleCommandState")
        _Main_OnCommand = try load("Main_OnCommand")
        _CSurf_OnScroll = try load("CSurf_OnScroll")
        _CSurf_OnZoom = try load("CSurf_OnZoom")
        _GetExtState = try load("GetExtState")
        _SetExtState = try load("SetExtState")
        _kbd_getTextFromCmd = try load("kbd_getTextFromCmd")
        _SectionFromUniqueID = try load("SectionFromUniqueID")
        _kbd_enumerateActions = try load("kbd_enumerateActions")
    }

    // MARK: - General

    public func showConsoleMessage(_ message: String) { _ShowConsoleMsg(message) }
    public var appVersion: String { _GetAppVersion().map { String(cString: $0) } ?? "" }

    // MARK: - Arrange view

    /// The visible time range of the arrange view in seconds.
    public func arrangeView() -> (start: Double, end: Double) {
        var start = 0.0, end = 0.0
        _GetSet_ArrangeView2(nil, false, 0, 0, &start, &end)
        return (start, end)
    }

    public func setArrangeView(start: Double, end: Double) {
        var start = start, end = end
        _GetSet_ArrangeView2(nil, true, 0, 0, &start, &end)
    }

    /// Horizontal zoom in pixels per second.
    public var horizontalZoom: Double { _GetHZoomLevel() }

    /// Scrolls the track list (`y`) or the time line (`x`) by REAPER's own steps.
    public func scroll(x: Int, y: Int) { _CSurf_OnScroll(Int32(x), Int32(y)) }
    /// Zooms by REAPER's own steps; `y` changes the track height.
    public func zoom(x: Int, y: Int) { _CSurf_OnZoom(Int32(x), Int32(y)) }

    // MARK: - Transport

    public var editCursor: Double { _GetCursorPosition() }
    public var playPosition: Double { _GetPlayPosition() }
    /// Bits: 1 = playing, 2 = paused, 4 = recording.
    public var playState: Int { Int(_GetPlayState()) }

    // MARK: - Actions

    /// 1 = on, 0 = off, -1 = not a toggle or unknown.
    public func toggleState(_ command: Int) -> Int { Int(_GetToggleCommandState(Int32(command))) }
    public func run(_ command: Int) { _Main_OnCommand(Int32(command), 0) }
    /// The action's name in the main section, or nil if there is no such action.
    public func actionName(_ command: Int) -> String? {
        // The section must be given; nil finds nothing (seen with REAPER 7.81).
        guard let main = _SectionFromUniqueID(0), let text = _kbd_getTextFromCmd(UInt32(command), main) else { return nil }
        let name = String(cString: text)
        return name.isEmpty ? nil : name
    }

    /// Every action of the main section as (command ID, name).
    public func mainActions() -> [(command: Int, name: String)] {
        guard let main = _SectionFromUniqueID(0) else { return [] }
        var result: [(command: Int, name: String)] = []
        var index: Int32 = 0
        while true {
            var name: UnsafePointer<CChar>?
            let command = _kbd_enumerateActions(main, index, &name)
            guard command != 0 else { break }
            result.append((Int(command), name.map { String(cString: $0) } ?? ""))
            index += 1
        }
        return result
    }

    // MARK: - Extension state

    public func extState(section: String, key: String) -> String? {
        guard let value = _GetExtState(section, key) else { return nil }
        let text = String(cString: value)
        return text.isEmpty ? nil : text
    }

    public func setExtState(section: String, key: String, value: String, persist: Bool = true) {
        _SetExtState(section, key, value, persist)
    }
}
