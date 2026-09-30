import Foundation

/// Deflection of the SpaceMouse cap, as the input reports it. Native HID: raw device units, about ±350 per axis.
/// Axis signs, seen from the user with the cable at the back (stagehand, docs/spacemouse-findings.md):
/// slide right x+, slide forward y−, push down z+, tilt forward rx−, tilt right ry−,
/// twist clockwise seen from above rz+.
public struct SpaceMouseAxes: Sendable, Equatable, CustomStringConvertible {
    public var x = 0, y = 0, z = 0
    public var rx = 0, ry = 0, rz = 0

    public init(x: Int = 0, y: Int = 0, z: Int = 0, rx: Int = 0, ry: Int = 0, rz: Int = 0) {
        self.x = x; self.y = y; self.z = z
        self.rx = rx; self.ry = ry; self.rz = rz
    }

    public static let zero = SpaceMouseAxes()
    /// Logical maximum of every axis in the HID report descriptor of the SpaceMouse Compact.
    public static let deviceFullScale = 350

    public var all: [Int] { [x, y, z, rx, ry, rz] }
    public var isZero: Bool { self == .zero }

    public var description: String { "x \(x) y \(y) z \(z) rx \(rx) ry \(ry) rz \(rz)" }
}

/// Buttons as a bitmap: bit 0 = left (button 1), bit 1 = right (button 2) on the SpaceMouse Compact.
public struct SpaceMouseButtons: OptionSet, Sendable, Hashable {
    public let rawValue: UInt32
    public init(rawValue: UInt32) { self.rawValue = rawValue }
    public static let left = SpaceMouseButtons(rawValue: 0x01)
    public static let right = SpaceMouseButtons(rawValue: 0x02)
}

/// Decodes the input reports of the SpaceMouse Compact (USB 256F:C635). Ported from stagehand's
/// `SpaceMouseReport` via Spacer. The report buffer includes the report ID as byte 0.
public enum SpaceMouseReport {
    public static let translationReportID: UInt8 = 1
    public static let rotationReportID: UInt8 = 2
    public static let buttonReportID: UInt8 = 3

    /// Buttons held according to report 3; nil for other reports.
    public static func buttons(_ bytes: UnsafeBufferPointer<UInt8>) -> SpaceMouseButtons? {
        guard bytes.count >= 2, bytes[0] == buttonReportID else { return nil }
        return SpaceMouseButtons(rawValue: UInt32(bytes[1] & 0x03))
    }

    /// Report 1 sets x y z, report 2 sets rx ry rz, each as three int16 little endian.
    /// Returns false for any other report.
    public static func take(_ bytes: UnsafeBufferPointer<UInt8>, into axes: inout SpaceMouseAxes) -> Bool {
        guard bytes.count >= 7,
              bytes[0] == translationReportID || bytes[0] == rotationReportID else { return false }
        func value(_ at: Int) -> Int {
            Int(Int16(bitPattern: UInt16(bytes[at]) | UInt16(bytes[at + 1]) << 8))
        }
        if bytes[0] == translationReportID {
            axes.x = value(1); axes.y = value(3); axes.z = value(5)
        } else {
            axes.rx = value(1); axes.ry = value(3); axes.rz = value(5)
        }
        return true
    }
}

/// `ConnexionDeviceState` of the 3DxWare client API (ConnexionClient.h, `#pragma pack(2)`, 48 bytes), as delivered
/// with the message `kConnexionMsgDeviceState` ('3dSR').
public struct ConnexionDeviceState: Sendable, Equatable {
    public static let size = 48
    public static let handleButtons = 2
    public static let handleAxis = 3

    public var client: Int
    public var command: Int
    public var axes: SpaceMouseAxes
    public var buttons: SpaceMouseButtons
    /// Uptime timestamp of the message (`clock_get_uptime` units).
    public var time: UInt64

    public init?(_ bytes: UnsafeRawBufferPointer) {
        guard bytes.count >= Self.size else { return nil }
        func u16(_ offset: Int) -> UInt16 { UInt16(bytes[offset]) | UInt16(bytes[offset + 1]) << 8 }
        func i16(_ offset: Int) -> Int { Int(Int16(bitPattern: u16(offset))) }
        func u32(_ offset: Int) -> UInt32 { UInt32(u16(offset)) | UInt32(u16(offset + 2)) << 16 }
        client = Int(u16(2))
        command = Int(u16(4))
        time = UInt64(u32(12)) | UInt64(u32(16)) << 32
        axes = SpaceMouseAxes(x: i16(30), y: i16(32), z: i16(34), rx: i16(36), ry: i16(38), rz: i16(40))
        buttons = SpaceMouseButtons(rawValue: u32(44))
    }
}
