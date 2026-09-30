import Testing
@testable import SpaceMouseKit

struct SpaceMouseReportTests {
    @Test func translationThenRotationFillsAllAxes() {
        var axes = SpaceMouseAxes.zero
        // x = 350, y = -2, z = 151 (little endian int16), as in stagehand's captures.
        let translation: [UInt8] = [0x01, 0x5E, 0x01, 0xFE, 0xFF, 0x97, 0x00]
        let rotation: [UInt8] = [0x02, 0x00, 0x00, 0x01, 0x00, 0xA2, 0xFE]
        #expect(translation.withUnsafeBufferPointer { SpaceMouseReport.take($0, into: &axes) })
        #expect(rotation.withUnsafeBufferPointer { SpaceMouseReport.take($0, into: &axes) })
        #expect(axes == SpaceMouseAxes(x: 350, y: -2, z: 151, rx: 0, ry: 1, rz: -350))
    }

    @Test func buttonReport() {
        let both: [UInt8] = [0x03, 0x03, 0x00]
        #expect(both.withUnsafeBufferPointer { SpaceMouseReport.buttons($0) } == [.left, .right])
        let axisReport: [UInt8] = [0x01, 0, 0, 0, 0, 0, 0]
        #expect(axisReport.withUnsafeBufferPointer { SpaceMouseReport.buttons($0) } == nil)
    }

    @Test func otherReportsAreRejected() {
        var axes = SpaceMouseAxes.zero
        let led: [UInt8] = [0x04, 0x01, 0, 0, 0, 0, 0]
        #expect(!led.withUnsafeBufferPointer { SpaceMouseReport.take($0, into: &axes) })
        #expect(axes == .zero)
    }
}

struct ConnexionDeviceStateTests {
    /// Builds a 48-byte `ConnexionDeviceState` (pack 2) the way the driver sends it.
    private func state(client: UInt16, command: UInt16, axes: [Int16], buttons: UInt32) -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: 48)
        func put16(_ value: UInt16, at offset: Int) {
            bytes[offset] = UInt8(value & 0xFF)
            bytes[offset + 1] = UInt8(value >> 8)
        }
        put16(0x6D33, at: 0)
        put16(client, at: 2)
        put16(command, at: 4)
        for (index, value) in axes.enumerated() { put16(UInt16(bitPattern: value), at: 30 + 2 * index) }
        put16(UInt16(buttons & 0xFFFF), at: 44)
        put16(UInt16(buttons >> 16), at: 46)
        return bytes
    }

    @Test func decodesAxisState() throws {
        let bytes = state(client: 4098, command: 3, axes: [-260, 522, 0, 1, -1, 100], buttons: 0)
        let decoded = try #require(bytes.withUnsafeBytes { ConnexionDeviceState($0) })
        #expect(decoded.client == 4098)
        #expect(decoded.command == ConnexionDeviceState.handleAxis)
        #expect(decoded.axes == SpaceMouseAxes(x: -260, y: 522, z: 0, rx: 1, ry: -1, rz: 100))
    }

    @Test func decodesButtonState() throws {
        let bytes = state(client: 1, command: 2, axes: [0, 0, 0, 0, 0, 0], buttons: 0x3)
        let decoded = try #require(bytes.withUnsafeBytes { ConnexionDeviceState($0) })
        #expect(decoded.command == ConnexionDeviceState.handleButtons)
        #expect(decoded.buttons == [.left, .right])
    }

    @Test func rejectsShortBuffers() {
        let bytes = [UInt8](repeating: 0, count: 47)
        #expect(bytes.withUnsafeBytes { ConnexionDeviceState($0) } == nil)
    }
}
