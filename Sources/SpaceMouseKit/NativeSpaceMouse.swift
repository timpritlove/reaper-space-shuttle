import Foundation
import IOKit.hid

/// The SpaceMouse Compact read directly over HID, without the 3Dconnexion driver (ADR-0003). Ported from Spacer's
/// `SpaceMouseHID`, which follows stagehand's rules: match vendor and product ID exactly, open seized (a shared open
/// turns the cap into scroll events), write nothing to the device, keep the report buffer alive until the device's
/// cancel handler ran. Fails with `kIOReturnExclusiveAccess` while the 3Dconnexion helper holds the device.
@MainActor
public final class NativeSpaceMouse: SpaceMouseInput {
    public let name = "native HID"
    /// The device sends a report pair about every 16 ms while the cap is deflected (stagehand findings).
    public let streamsWhileDeflected = true

    private let reader = HIDReader()

    public init() {}

    public func start(onEvent: @escaping @MainActor (SpaceMouseEvent) -> Void) {
        reader.start { event in onMain { onEvent(event) } }
    }

    /// The device stays seized while REAPER is in the background; the navigator ignores its data then.
    public func setActive(_ active: Bool) {}

    public func stop() { reader.stop() }
}

/// Owns the HID manager and device on a private serial queue.
private final class HIDReader: @unchecked Sendable {
    static let vendorID = 0x256F
    static let productID = 0xC635

    private let queue = DispatchQueue(label: "reaper-spacemouse.hid", qos: .userInteractive)
    private var onEvent: (@Sendable (SpaceMouseEvent) -> Void)?

    // Only touched on `queue`.
    private var manager: IOHIDManager?
    private var device: IOHIDDevice?
    private var registryID: UInt64?
    private var reports: ReportBuffer?

    func start(onEvent: @escaping @Sendable (SpaceMouseEvent) -> Void) {
        queue.async {
            self.onEvent = onEvent
            self.startOnQueue()
        }
    }

    func stop() {
        queue.sync {
            closeDevice()
            if let manager {
                IOHIDManagerCancel(manager)
                self.manager = nil
            }
        }
    }

    private func startOnQueue() {
        guard manager == nil else { return }
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        let matching: [String: Any] = [
            kIOHIDVendorIDKey: Self.vendorID,
            kIOHIDProductIDKey: Self.productID,
            kIOHIDPrimaryUsagePageKey: kHIDPage_GenericDesktop,
            kIOHIDPrimaryUsageKey: kHIDUsage_GD_MultiAxisController,
        ]
        IOHIDManagerSetDeviceMatching(manager, matching as CFDictionary)
        let context = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterDeviceMatchingCallback(manager, { context, _, _, device in
            guard let context else { return }
            Unmanaged<HIDReader>.fromOpaque(context).takeUnretainedValue().deviceAppeared(device)
        }, context)
        IOHIDManagerRegisterDeviceRemovalCallback(manager, { context, _, _, device in
            guard let context else { return }
            Unmanaged<HIDReader>.fromOpaque(context).takeUnretainedValue().deviceVanished(device)
        }, context)
        IOHIDManagerSetDispatchQueue(manager, queue)
        IOHIDManagerActivate(manager)
        self.manager = manager
    }

    private func deviceAppeared(_ managed: IOHIDDevice) {
        guard device == nil else { return }
        // Do not configure the manager's own device object; open a separate one by registry ID.
        let service = IOHIDDeviceGetService(managed)
        var id: UInt64 = 0
        guard IORegistryEntryGetRegistryEntryID(service, &id) == KERN_SUCCESS else { return }
        let own = IOServiceGetMatchingService(kIOMainPortDefault, IORegistryEntryIDMatching(id))
        guard own != 0, let device = IOHIDDeviceCreate(kCFAllocatorDefault, own) else {
            if own != 0 { IOObjectRelease(own) }
            onEvent?(.failed("device not reachable"))
            return
        }
        IOObjectRelease(own)

        let size = max((IOHIDDeviceGetProperty(device, kIOHIDMaxInputReportSizeKey as CFString) as? Int) ?? 64, 64)
        let reports = ReportBuffer(size: size, onEvent: onEvent ?? { _ in })
        IOHIDDeviceRegisterInputReportCallback(device, reports.buffer, size, { context, result, _, _, _, report, length in
            guard result == kIOReturnSuccess, let context else { return }
            Unmanaged<ReportBuffer>.fromOpaque(context).takeUnretainedValue()
                .ingest(UnsafeBufferPointer(start: report, count: length))
        }, Unmanaged.passUnretained(reports).toOpaque())
        IOHIDDeviceSetDispatchQueue(device, queue)

        let result = IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeSeizeDevice))
        guard result == kIOReturnSuccess else {
            IOHIDDeviceSetCancelHandler(device) { withExtendedLifetime((device, reports)) {} }
            IOHIDDeviceCancel(device)
            onEvent?(.failed(Self.describe(result)))
            return
        }
        IOHIDDeviceActivate(device)
        self.device = device
        self.reports = reports
        self.registryID = id
        onEvent?(.connected("native HID, SpaceMouse Compact"))
    }

    private func deviceVanished(_ managed: IOHIDDevice) {
        var id: UInt64 = 0
        IORegistryEntryGetRegistryEntryID(IOHIDDeviceGetService(managed), &id)
        guard id == registryID else { return }
        closeDevice()
        onEvent?(.disconnected)
    }

    private func closeDevice() {
        guard let device, let reports else { return }
        IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeNone))
        IOHIDDeviceSetCancelHandler(device) { withExtendedLifetime((device, reports)) {} }
        IOHIDDeviceCancel(device)
        self.device = nil
        self.reports = nil
        self.registryID = nil
    }

    private static func describe(_ result: IOReturn) -> String {
        switch result {
        case kIOReturnExclusiveAccess: "device busy — is the 3Dconnexion helper (or stagehand, Spacer) holding it?"
        case kIOReturnNotPermitted: "access denied (Input Monitoring?)"
        default: String(format: "open failed (0x%08X)", UInt32(bitPattern: result))
        }
    }
}

/// Owns the report buffer and decodes reports on the HID queue.
private final class ReportBuffer: @unchecked Sendable {
    let buffer: UnsafeMutablePointer<UInt8>
    private let onEvent: @Sendable (SpaceMouseEvent) -> Void
    private var pending = SpaceMouseAxes.zero
    private var buttons: SpaceMouseButtons = []

    init(size: Int, onEvent: @escaping @Sendable (SpaceMouseEvent) -> Void) {
        buffer = .allocate(capacity: size)
        self.onEvent = onEvent
    }

    deinit { buffer.deallocate() }

    func ingest(_ bytes: UnsafeBufferPointer<UInt8>) {
        if let now = SpaceMouseReport.buttons(bytes) {
            if now != buttons {
                buttons = now
                onEvent(.buttons(now))
            }
        } else if SpaceMouseReport.take(bytes, into: &pending), bytes[0] == SpaceMouseReport.rotationReportID {
            // Reports 1 and 2 come as a pair; only a complete pair counts.
            onEvent(.axes(pending))
        }
    }
}
