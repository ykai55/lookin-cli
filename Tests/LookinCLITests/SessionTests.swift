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
}
