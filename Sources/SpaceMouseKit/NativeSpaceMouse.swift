import Foundation
import IOKit.hid

/// The SpaceMouse Compact read directly over HID, without the 3Dconnexion driver (ADR-0003). Ported from Spacer's
/// `SpaceMouseHID`, which follows stagehand's rules: match vendor and product ID exactly, open seized (a shared open
/// turns the cap into scroll events), keep the report buffer alive until the device's cancel handler ran. Writes only
/// the LED's output report (ADR-0010). Holds the device only while `setActive(true)`, so another program's native
/// input can have it in between (`SeizeClaim`). Fails with `kIOReturnExclusiveAccess` while the 3Dconnexion helper holds
/// the device.
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

    /// Seizes the device while active and lets go of it otherwise (`SeizeClaim`).
    public func setActive(_ active: Bool) { reader.setActive(active) }

    public func setLED(_ on: Bool) { reader.setLED(on) }

    public func stop() { reader.stop() }
}

/// Owns the HID manager and device on a private serial queue.
private final class HIDReader: @unchecked Sendable {
    static let vendorID = 0x256F
    static let productID = 0xC635
    /// Output report 4, one bit: the LED (`04 01` on, `04 00` off; measured in stagehand, 2026-09-26).
    static let ledReportID: UInt8 = 4

    private let queue = DispatchQueue(label: "space-shuttle.hid", qos: .userInteractive)
    private var onEvent: (@Sendable (SpaceMouseEvent) -> Void)?

    // Only touched on `queue`.
    private var manager: IOHIDManager?
    private var claim = SeizeClaim()
    /// The manager's device object while the SpaceMouse is connected, open or not.
    private var present: IOHIDDevice?
    /// Our own device object, only while open.
    private var device: IOHIDDevice?
    private var reports: ReportBuffer?
    private var ledFailed = false

    func start(onEvent: @escaping @Sendable (SpaceMouseEvent) -> Void) {
        queue.async {
            self.onEvent = onEvent
            self.startOnQueue()
        }
    }

    func setActive(_ active: Bool) {
        queue.async { self.perform(self.claim.want(active)) }
    }

    func stop() {
        queue.sync {
            closeDevice()
            present = nil
            claim = SeizeClaim()
            if let manager {
                IOHIDManagerCancel(manager)
                self.manager = nil
            }
        }
    }

    /// On the HID queue, so the USB transfer never blocks REAPER's main thread. A failure is reported once per device.
    func setLED(_ on: Bool) {
        queue.async {
            guard let device = self.device else { return }
            var report: [UInt8] = [Self.ledReportID, on ? 1 : 0]
            let result = IOHIDDeviceSetReport(device, kIOHIDReportTypeOutput, CFIndex(Self.ledReportID), &report, report.count)
            guard result != kIOReturnSuccess, !self.ledFailed else { return }
            self.ledFailed = true
            self.onEvent?(.failed(String(format: "LED not switched (0x%08X)", UInt32(bitPattern: result))))
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
        guard present == nil else { return }
        present = managed
        perform(claim.deviceAppeared())
    }

    private func deviceVanished(_ managed: IOHIDDevice) {
        guard let present, Self.registryID(of: managed) == Self.registryID(of: present) else { return }
        closeDevice()
        self.present = nil
        claim.deviceVanished()
        onEvent?(.disconnected)
    }

    private func perform(_ action: SeizeClaim.Action) {
        switch action {
        case .none: break
        case .open: openDevice()
        case .close:
            closeDevice()
            claim.closed()
        }
    }

    private func openDevice() {
        guard device == nil, let present else { return }
        // Do not configure the manager's own device object; open a separate one by registry ID.
        guard let id = Self.registryID(of: present) else { return openFailed(kIOReturnNotFound, "device not reachable") }
        let own = IOServiceGetMatchingService(kIOMainPortDefault, IORegistryEntryIDMatching(id))
        guard own != 0, let device = IOHIDDeviceCreate(kCFAllocatorDefault, own) else {
            if own != 0 { IOObjectRelease(own) }
            return openFailed(kIOReturnNotFound, "device not reachable")
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
            return openFailed(result, Self.describe(result))
        }
        IOHIDDeviceActivate(device)
        self.device = device
        self.reports = reports
        ledFailed = false
        claim.opened()
        onEvent?(.connected("native HID, SpaceMouse Compact"))
    }

    /// Busy (another program still holds the device) is retried for a while; everything else is reported at once.
    private func openFailed(_ result: IOReturn, _ reason: String) {
        switch claim.openFailed(busy: result == kIOReturnExclusiveAccess) {
        case .retry(let seconds, let generation):
            queue.asyncAfter(deadline: .now() + seconds) { self.perform(self.claim.retry(generation: generation)) }
        case .giveUp:
            onEvent?(.failed(reason))
        }
    }

    private func closeDevice() {
        guard let device, let reports else { return }
        IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeNone))
        IOHIDDeviceSetCancelHandler(device) { withExtendedLifetime((device, reports)) {} }
        IOHIDDeviceCancel(device)
        self.device = nil
        self.reports = nil
    }

    private static func registryID(of device: IOHIDDevice) -> UInt64? {
        var id: UInt64 = 0
        return IORegistryEntryGetRegistryEntryID(IOHIDDeviceGetService(device), &id) == KERN_SUCCESS ? id : nil
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
