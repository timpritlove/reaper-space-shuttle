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
            let message = "Space Shuttle extension not loaded: \(error)\n"
            if let show = getFunc("ShowConsoleMsg") {
                unsafeBitCast(show, to: (@convention(c) (UnsafePointer<CChar>?) -> Void).self)(message)
            }
            if let path = ProcessInfo.processInfo.environment["SPACESHUTTLE_LOG"] {
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
        case toggleNavigation = "SPACESHUTTLE_TOGGLE"
        case toggleDiagnostics = "SPACESHUTTLE_DIAGNOSTICS"
        case reloadSettings = "SPACESHUTTLE_RELOAD"
        case settings = "SPACESHUTTLE_SETTINGS"

        var title: String {
            switch self {
            case .toggleNavigation: "Space Shuttle: Toggle navigation"
            case .toggleDiagnostics: "Space Shuttle: Toggle diagnostics in console"
            case .reloadSettings: "Space Shuttle: Reload settings"
            case .settings: "Space Shuttle: Settings…"
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
        if let predecessor = Self.predecessor() {
            navigator.hold(because: Self.retire(predecessor))
        } else {
            navigator.start()
        }
    }

    /// The extension's file before the rename to Space Shuttle (ADR-0013). If REAPER loaded it too, both would read
    /// the SpaceMouse and move the view twice.
    static let predecessorFile = "reaper_spacemouse.dylib"

    /// The predecessor next to this library, if there is one.
    private static func predecessor() -> URL? {
        var info = Dl_info()
        guard dladdr(#dsohandle, &info) != 0, let path = info.dli_fname else { return nil }
        let url = URL(fileURLWithPath: String(cString: path)).deletingLastPathComponent()
            .appendingPathComponent(predecessorFile)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    /// Moves the predecessor to the Trash (REAPER keeps its loaded copy until it quits) and says what happened.
    private static func retire(_ predecessor: URL) -> String {
        do {
            try FileManager.default.trashItem(at: predecessor, resultingItemURL: nil)
            return "moved the old \(predecessorFile) to the Trash; Space Shuttle takes over after REAPER restarts"
        } catch {
            return "found the old \(predecessor.path); delete it and restart REAPER (\(error.localizedDescription))"
        }
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
