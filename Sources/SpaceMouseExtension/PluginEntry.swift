import Foundation
import ReaperBridge
import ReaperKit

/// REAPER calls this on load (with `rec`) and on unload (with `rec == nil`). Returns 1 if the extension loaded.
@_cdecl("ReaperPluginEntry")
public func ReaperPluginEntry(_ instance: UnsafeMutableRawPointer?, _ rec: UnsafeMutablePointer<RBPluginInfo>?) -> Int32 {
    // REAPER loads extensions on its UI thread; without that we cannot touch its API safely (ADR-0002).
    guard pthread_main_np() != 0 else { return 0 }
    nonisolated(unsafe) let rec = rec
    return MainActor.assumeIsolated {
        guard let rec else {
            Extension.shared?.unload()
            Extension.shared = nil
            return 0
        }
        guard let register = rec.pointee.Register, let getFunc = rec.pointee.GetFunc else { return 0 }
        do {
            let api = try ReaperAPI(getFunc: { getFunc($0) })
            let ext = Extension(api: api, register: { name, value in register(name, value) })
            Extension.shared = ext
            ext.load()
            return 1
        } catch {
            // Say why instead of vanishing silently: REAPER unloads a library whose entry returns 0.
            let message = "SpaceMouse extension not loaded: \(error)\n"
            if let show = getFunc("ShowConsoleMsg") {
                unsafeBitCast(show, to: (@convention(c) (UnsafePointer<CChar>?) -> Void).self)(message)
            }
            if let path = ProcessInfo.processInfo.environment["SPACEMOUSE_LOG"] {
                try? message.write(toFile: path, atomically: true, encoding: .utf8)
            }
            return 0
        }
    }
}

@MainActor
final class Extension {
    static var shared: Extension?

    /// Entries in the action list (main section).
    enum Action: String, CaseIterable {
        case toggleNavigation = "SPACEMOUSE_TOGGLE"
        case toggleDiagnostics = "SPACEMOUSE_DIAGNOSTICS"
        case reloadSettings = "SPACEMOUSE_RELOAD"
        case settings = "SPACEMOUSE_SETTINGS"

        var title: String {
            switch self {
            case .toggleNavigation: "SpaceMouse: Toggle navigation"
            case .toggleDiagnostics: "SpaceMouse: Toggle diagnostics in console"
            case .reloadSettings: "SpaceMouse: Reload settings"
            case .settings: "SpaceMouse: Settings…"
            }
        }
    }

    let api: ReaperAPI
    private let register: (String, UnsafeMutableRawPointer?) -> Int32
    private let navigator: Navigator
    private let settingsWindow: SettingsWindowController
    private var commandIDs: [Int32: Action] = [:]

    init(api: ReaperAPI, register: @escaping (String, UnsafeMutableRawPointer?) -> Int32) {
        self.api = api
        self.register = register
        navigator = Navigator(api: api)
        settingsWindow = SettingsWindowController(model: navigator.model)
    }

    func load() {
        for action in Action.allCases {
            let registration = UnsafeMutablePointer<RBCustomAction>.allocate(capacity: 1)
            // REAPER keeps referring to the registration, so it lives as long as the process.
            registration.initialize(to: RBCustomAction(uniqueSectionId: 0, idStr: strdup(action.rawValue),
                                                       name: strdup(action.title), extra: nil))
            let id = register("custom_action", UnsafeMutableRawPointer(registration))
            if id != 0 { commandIDs[id] = action }
        }
        _ = register("hookcommand2", unsafeBitCast(actionHook, to: UnsafeMutableRawPointer.self))
        navigator.start()
    }

    func unload() {
        settingsWindow.close()
        navigator.stop()
        _ = register("-hookcommand2", unsafeBitCast(actionHook, to: UnsafeMutableRawPointer.self))
    }

    fileprivate func handle(_ commandID: Int32) -> Bool {
        guard let action = commandIDs[commandID] else { return false }
        switch action {
        case .toggleNavigation: navigator.toggleEnabled()
        case .toggleDiagnostics: navigator.toggleDiagnostics()
        case .reloadSettings: navigator.reloadSettings()
        case .settings: settingsWindow.show()
        }
        return true
    }
}

/// `hookcommand2`: bool onAction(KbdSectionInfo *sec, int command, int val, int val2, int relmode, HWND hwnd).
private let actionHook: @convention(c) (OpaquePointer?, Int32, Int32, Int32, Int32, UnsafeMutableRawPointer?) -> Bool = {
    _, command, _, _, _, _ in
    guard pthread_main_np() != 0 else { return false }
    return MainActor.assumeIsolated { Extension.shared?.handle(command) ?? false }
}
