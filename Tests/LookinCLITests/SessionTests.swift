@testable import LookinCLI
import XCTest

final class SessionTests: XCTestCase {
    func testRoundTrip() throws {
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("session-\(UUID()).json")
        defer { try? FileManager.default.removeItem(at: tmp) }

        let original = Session(
            host: "127.0.0.1",
            port: 47164,
            target: .simulator,
            serverVersion: 7,
            capturedAt: Date(timeIntervalSince1970: 1_700_000_000),
        )
        try original.save(to: tmp)

        let loaded = try Session.load(from: tmp)
        XCTAssertEqual(loaded, original)
    }

    func testLoadReturnsNilWhenMissing() throws {
        let url = URL(fileURLWithPath: "/tmp/lookin-cli-does-not-exist-\(UUID()).json")
        XCTAssertNil(try Session.load(from: url))
    }

    func testUSBSessionRoundTripPreservesDeviceIdentity() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("session-\(UUID()).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let original = Session(host: "usbmuxd", port: 47175, target: .device,
                               serverVersion: 7, capturedAt: Date(timeIntervalSince1970: 1_700_000_000),
                               deviceUDID: "phone-a")
        try original.save(to: url)
        XCTAssertEqual(try Session.load(from: url), original)
    }

    func testLegacyForwardedSessionStillDecodesWithoutDeviceUDID() throws {
        let data = Data(#"{"host":"127.0.0.1","port":47175,"target":"device","serverVersion":7,"capturedAt":"2023-11-14T22:13:20Z"}"#.utf8)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let session = try decoder.decode(Session.self, from: data)
        XCTAssertNil(session.deviceUDID)
        XCTAssertEqual(session.host, "127.0.0.1")
    }

    func testDeviceSelectionFlags() throws {
        XCTAssertThrowsError(try Attach.parse(["--udid", "phone-a"]))
        XCTAssertThrowsError(try Doctor.parse(["--udid", "phone-a"]))
        XCTAssertEqual(try Attach.parse(["--device", "--udid", "phone-a"]).udid, "phone-a")
        XCTAssertEqual(try Doctor.parse(["--device", "--udid", "phone-a"]).udid, "phone-a")
    }
}
