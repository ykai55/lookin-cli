import Foundation
import XCTest
@testable import LookinTransport

final class USBMuxTests: XCTestCase {
    func testConnectWireFormatUsesLittleEndianHeaderAndNetworkOrderPort() throws {
        let data = try USBMux.encode(USBMux.connectMessage(deviceID: 42, port: 47175))
        XCTAssertEqual(Array(data[4 ..< 16]), [1, 0, 0, 0, 8, 0, 0, 0, 1, 0, 0, 0])
        XCTAssertEqual(try USBMux.bodyLength(Data(data.prefix(16))), data.count - 16)
        let plist = try XCTUnwrap(PropertyListSerialization.propertyList(from: Data(data.dropFirst(16)), format: nil) as? [String: Any])
        XCTAssertEqual(plist["MessageType"] as? String, "Connect")
        XCTAssertEqual(plist["DeviceID"] as? Int, 42)
        XCTAssertEqual(plist["PortNumber"] as? Int, 18360) // 0xB847 in network order on macOS
    }

    func testDiscoveryExcludesNetworkDevicesAndSelectsStableUDID() throws {
        let devices = try USBMux.parseDevices(["DeviceList": [
            ["DeviceID": 1, "Properties": ["ConnectionType": "Network", "SerialNumber": "wifi"]],
            ["DeviceID": 2, "Properties": ["ConnectionType": "USB", "SerialNumber": "phone-a"]],
            ["DeviceID": 3, "Properties": ["ConnectionType": "USB", "SerialNumber": "phone-b"]],
        ]])
        XCTAssertEqual(devices.map(\.udid), ["phone-a", "phone-b"])
        XCTAssertEqual(try USBMux.select(devices, udid: "phone-b").id, 3)
        XCTAssertThrowsError(try USBMux.select(devices, udid: nil))
        XCTAssertThrowsError(try USBMux.select(devices, udid: "wifi"))
        XCTAssertThrowsError(try USBMux.select([], udid: nil))
        XCTAssertEqual(try USBMux.select([devices[0]], udid: nil), devices[0])
    }

    func testRejectsMalformedOrOversizedHeaders() throws {
        XCTAssertThrowsError(try USBMux.bodyLength(Data([0])))
        let valid = try USBMux.encode(["MessageType": "ListDevices"]).prefix(16)
        for offset in [4, 8, 12] {
            var header = Data(valid)
            header[offset] = 0
            XCTAssertThrowsError(try USBMux.bodyLength(header))
        }
        var oversized = Data(valid)
        oversized.replaceSubrange(0 ..< 4, with: [0, 0, 0, 0])
        XCTAssertThrowsError(try USBMux.bodyLength(oversized))
        oversized.replaceSubrange(0 ..< 4, with: [255, 255, 255, 127])
        XCTAssertThrowsError(try USBMux.bodyLength(oversized))
    }
}
