@testable import LookinCLI
import XCTest

final class SocketInspectorTests: XCTestCase {
    private let range: ClosedRange<UInt16> = 47164 ... 47169

    func testParseListen() {
        let out = "App 123 user 10u IPv4 0x1 0t0 TCP 127.0.0.1:47164 (LISTEN)"
        XCTAssertEqual(SocketInspector.parse(out, range: range)[47164], .listen)
    }

    func testParseEstablished() {
        let out = "App 123 user 11u IPv4 0x1 0t0 TCP 127.0.0.1:47165->127.0.0.1:5000 (ESTABLISHED)"
        XCTAssertEqual(SocketInspector.parse(out, range: range)[47165], .established)
    }

    func testListenOutranksEstablished() {
        let out = """
        App 1 user 10u IPv4 0x1 0t0 TCP 127.0.0.1:47164->127.0.0.1:5000 (ESTABLISHED)
        App 1 user 11u IPv4 0x2 0t0 TCP 127.0.0.1:47164 (LISTEN)
        """
        XCTAssertEqual(SocketInspector.parse(out, range: range)[47164], .listen)
    }

    func testIgnoresPortsOutsideRange() {
        let out = "App 1 user 10u IPv4 0x1 0t0 TCP 127.0.0.1:8080 (LISTEN)"
        XCTAssertTrue(SocketInspector.parse(out, range: range).isEmpty)
    }

    func testIPv6LocalEndpoint() {
        let out = "App 1 user 10u IPv6 0x1 0t0 TCP [::1]:47166 (LISTEN)"
        XCTAssertEqual(SocketInspector.parse(out, range: range)[47166], .listen)
    }

    func testHeaderAndEmptyOutputIgnored() {
        let header = "COMMAND PID USER FD TYPE DEVICE SIZE/OFF NODE NAME"
        XCTAssertTrue(SocketInspector.parse(header, range: range).isEmpty)
        XCTAssertTrue(SocketInspector.parse("", range: range).isEmpty)
    }

    func testEstablishedRemotePortInRangeIsNotCounted() {
        // The remote endpoint port (after `->`) falls in range but must be ignored;
        // only the local endpoint counts.
        let out = "App 1 user 10u IPv4 0x1 0t0 TCP 127.0.0.1:5000->127.0.0.1:47164 (ESTABLISHED)"
        XCTAssertTrue(SocketInspector.parse(out, range: range).isEmpty)
    }
}
