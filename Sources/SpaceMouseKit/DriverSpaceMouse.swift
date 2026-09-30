import Foundation

/// The SpaceMouse through 3Dconnexion's own driver (3DxWare), via its classic client API
/// (`3DconnexionClient.framework`, loaded at runtime; ADR-0003).
///
/// Two ways to register (`Registration`):
/// - `application` (default): signature '****' with the process name, takeover mode — the way apps like Blender do it;
///   the driver itself delivers data only while this app is frontmost.
/// - `manual`: signature '++++', activated with '3dac' while REAPER is active and deactivated with '3ddc' otherwise
///   (made for background clients; measured in stagehand's findings, "Routing").
/// Registration waits until REAPER has finished launching: the helper crashed on a registration made while REAPER
/// was loading its extensions (2026-10-01, docs/feasibility.md).
@MainActor
public final class DriverSpaceMouse: SpaceMouseInput {
    public enum Registration: String, Sendable {
        case application = "app"
        case manual
    }

    public let name = "3DxWare driver"
    /// Not yet measured whether the driver repeats unchanged states; assume it does not (ADR-0003).
    public let streamsWhileDeflected = false

    nonisolated static let frameworkPath = "/Library/Frameworks/3DconnexionClient.framework/3DconnexionClient"
    nonisolated static let wildcardSignature: UInt32 = 0x2A2A_2A2A      // '****' kConnexionClientWildcard
    nonisolated static let manualSignature: UInt32 = 0x2B2B_2B2B        // '++++' kConnexionClientManual
    nonisolated static let modeTakeOver: UInt16 = 1                      // kConnexionClientModeTakeOver
    nonisolated static let maskAll: UInt32 = 0x3FFF                      // kConnexionMaskAll
    nonisolated static let maskAllButtons: UInt32 = 0xFFFF_FFFF          // kConnexionMaskAllButtons
    nonisolated static let messageDeviceState: UInt32 = 0x3364_5352      // '3dSR'
    nonisolated static let controlActivate: UInt32 = 0x3364_6163         // '3dac'
    nonisolated static let controlDeactivate: UInt32 = 0x3364_6463       // '3ddc'
    /// Seconds after `start` before registering, so REAPER has finished launching.
    nonisolated static let registrationDelay = 2.0

    /// The one instance the C callbacks talk to; the client API has no context pointer.
    fileprivate static var current: DriverSpaceMouse?

    private let registration: Registration
    private var api: ConnexionAPI?
    private var clientID: UInt16 = 0
    private var onEvent: (@MainActor (SpaceMouseEvent) -> Void)?
    private var active = false
    private var clientActive = false

    public init(registration: Registration = .application) {
        self.registration = registration
    }

    /// Whether the vendor framework is installed at all.
    public static var isInstalled: Bool { FileManager.default.fileExists(atPath: frameworkPath) }

    public func start(onEvent: @escaping @MainActor (SpaceMouseEvent) -> Void) {
        self.onEvent = onEvent
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.registrationDelay) { [weak self] in
            guard let self, self.onEvent != nil else { return }
            self.register()
        }
    }

    private func register() {
        guard api == nil, let onEvent else { return }
        guard Self.current == nil else {
            onEvent(.failed("another driver client is already running in this process"))
            return
        }
        let api: ConnexionAPI
        do {
            api = try ConnexionAPI.load(path: Self.frameworkPath)
        } catch {
            onEvent(.failed("\(error)"))
            return
        }
        self.api = api
        Self.current = self
        let handlers = api.setHandlers(messageHandler, addedHandler, removedHandler, false)
        guard handlers == 0 else {
            self.api = nil
            Self.current = nil
            onEvent(.failed("SetConnexionHandlers returned \(handlers) — is the 3Dconnexion helper running?"))
            return
        }
        switch registration {
        case .application:
            // Pascal string with the executable name, as the driver matches the frontmost app by it.
            let processName = Array(ProcessInfo.processInfo.processName.utf8.prefix(63))
            var pascal = [UInt8(processName.count)] + processName
            clientID = pascal.withUnsafeMutableBufferPointer {
                api.register(Self.wildcardSignature, $0.baseAddress, Self.modeTakeOver, Self.maskAll)
            }
        case .manual:
            clientID = api.register(Self.manualSignature, nil, Self.modeTakeOver, Self.maskAll)
        }
        guard clientID != 0 else {
            api.cleanup()
            self.api = nil
            Self.current = nil
            onEvent(.failed("RegisterConnexionClient returned no client ID"))
            return
        }
        api.setButtonMask(clientID, Self.maskAllButtons)
        onEvent(.connected("\(name) (\(registration.rawValue)), client \(clientID)"))
        updateManualActivation()
    }

    public func setActive(_ active: Bool) {
        self.active = active
        updateManualActivation()
    }

    /// Only the manual registration is switched by hand; the application registration follows the frontmost app.
    private func updateManualActivation() {
        guard registration == .manual, clientID != 0, active != clientActive else { return }
        clientActive = active
        control(active ? Self.controlActivate : Self.controlDeactivate)
    }

    public func stop() {
        guard let api else { return }
        onEvent = nil
        if clientID != 0 {
            if clientActive { control(Self.controlDeactivate) }
            api.unregister(clientID)
            clientID = 0
        }
        api.cleanup()
        self.api = nil
        if Self.current === self { Self.current = nil }
    }

    private func control(_ message: UInt32) {
        guard let api else { return }
        var result: Int32 = 0
        let status = api.control(clientID, message, 0, &result)
        if status != 0 { onEvent?(.failed("ConnexionClientControl \(fourCC(message)) returned \(status)")) }
    }

    fileprivate func received(_ state: ConnexionDeviceState) {
        // The framework filters on the client ID itself; this guards against a second client in the process.
        guard state.client == Int(clientID) || state.client == 0 else { return }
        switch state.command {
        case ConnexionDeviceState.handleAxis: onEvent?(.axes(state.axes))
        case ConnexionDeviceState.handleButtons: onEvent?(.buttons(state.buttons))
        default: break
        }
    }

    fileprivate func deviceAdded(_ productID: UInt32) {
        onEvent?(.connected(String(format: "%@, device 0x%04X", name, productID)))
    }

    fileprivate func deviceRemoved(_ productID: UInt32) {
        onEvent?(.disconnected)
    }
}

private func fourCC(_ value: UInt32) -> String {
    let bytes = [24, 16, 8, 0].map { UInt8((value >> UInt32($0)) & 0xFF) }
    return "'" + String(decoding: bytes, as: UTF8.self) + "'"
}

// MARK: - C callbacks (no context pointer; SetConnexionHandlers(…, useSeparateThread: false))

private let messageHandler: ConnexionAPI.MessageHandler = { _, type, argument in
    guard type == DriverSpaceMouse.messageDeviceState, let argument,
          let state = ConnexionDeviceState(UnsafeRawBufferPointer(start: argument, count: ConnexionDeviceState.size))
    else { return }
    onMain { DriverSpaceMouse.current?.received(state) }
}

private let addedHandler: ConnexionAPI.DeviceHandler = { productID in
    onMain { DriverSpaceMouse.current?.deviceAdded(productID) }
}

private let removedHandler: ConnexionAPI.DeviceHandler = { productID in
    onMain { DriverSpaceMouse.current?.deviceRemoved(productID) }
}

/// The functions of `ConnexionClientAPI.h` we use, resolved with `dlopen`/`dlsym` so the extension loads without
/// the framework (ported from stagehand's `spacemouse-probe`).
struct ConnexionAPI {
    typealias MessageHandler = @convention(c) (UInt32, UInt32, UnsafeMutableRawPointer?) -> Void
    typealias DeviceHandler = @convention(c) (UInt32) -> Void

    let setHandlers: @convention(c) (MessageHandler?, DeviceHandler?, DeviceHandler?, Bool) -> Int16
    let register: @convention(c) (UInt32, UnsafePointer<UInt8>?, UInt16, UInt32) -> UInt16
    let unregister: @convention(c) (UInt16) -> Void
    let cleanup: @convention(c) () -> Void
    let setButtonMask: @convention(c) (UInt16, UInt32) -> Void
    let control: @convention(c) (UInt16, UInt32, Int32, UnsafeMutablePointer<Int32>?) -> Int16

    struct LoadError: Error, CustomStringConvertible {
        let description: String
    }

    static func load(path: String) throws -> ConnexionAPI {
        guard let handle = dlopen(path, RTLD_NOW) else {
            throw LoadError(description: "3Dconnexion framework not loadable: \(String(cString: dlerror()))")
        }
        func symbol<T>(_ name: String, as type: T.Type) throws -> T {
            guard let address = dlsym(handle, name) else { throw LoadError(description: "missing symbol \(name)") }
            return unsafeBitCast(address, to: T.self)
        }
        return try ConnexionAPI(
            setHandlers: symbol("SetConnexionHandlers", as: (@convention(c) (MessageHandler?, DeviceHandler?, DeviceHandler?, Bool) -> Int16).self),
            register: symbol("RegisterConnexionClient", as: (@convention(c) (UInt32, UnsafePointer<UInt8>?, UInt16, UInt32) -> UInt16).self),
            unregister: symbol("UnregisterConnexionClient", as: (@convention(c) (UInt16) -> Void).self),
            cleanup: symbol("CleanupConnexionHandlers", as: (@convention(c) () -> Void).self),
            setButtonMask: symbol("SetConnexionClientButtonMask", as: (@convention(c) (UInt16, UInt32) -> Void).self),
            control: symbol("ConnexionClientControl", as: (@convention(c) (UInt16, UInt32, Int32, UnsafeMutablePointer<Int32>?) -> Int16).self)
        )
    }
}
