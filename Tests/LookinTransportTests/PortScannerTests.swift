@testable import LookinTransport
import XCTest

final class PortScannerTests: XCTestCase {
    func testSimulatorRangeMatchesUpstream() {
        XCTAssertEqual(PortScanner.Target.simulator.range, 47164 ... 47169)
    }

    func testDeviceRangeMatchesUpstream() {
        XCTAssertEqual(PortScanner.Target.device.range, 47175 ... 47179)
    }

    func testUnreachablePortReturnsFalse() async {
        // Port 1 should be closed on a dev mac.
        let reachable = await PortScanner.isReachable(host: "127.0.0.1", port: 1, timeout: 0.1)
        XCTAssertFalse(reachable)
    }
}
