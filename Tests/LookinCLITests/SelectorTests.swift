import CoreGraphics
@testable import LookinCLI
import XCTest

final class SelectorTests: XCTestCase {
    func testParseOid() throws {
        guard case let .oid(n) = try Selector.parse("oid:223") else {
            return XCTFail("expected .oid")
        }
        XCTAssertEqual(n, 223)
    }

    func testParsePoint() throws {
        guard case let .point(p) = try Selector.parse("point:32,92") else {
            return XCTFail("expected .point")
        }
        XCTAssertEqual(p.x, 32, accuracy: 0.001)
        XCTAssertEqual(p.y, 92, accuracy: 0.001)
    }

    func testParsePointWithSpaces() throws {
        guard case let .point(p) = try Selector.parse("point:32, 92") else {
            return XCTFail("expected .point")
        }
        XCTAssertEqual(p.y, 92, accuracy: 0.001)
    }

    func testParseAxe() throws {
        guard case let .axe(id) = try Selector.parse("axe:submit-button") else {
            return XCTFail("expected .axe")
        }
        XCTAssertEqual(id, "submit-button")
    }

    func testParseRejectsNoScheme() {
        XCTAssertThrowsError(try Selector.parse("223"))
    }

    func testParseRejectsUnknownScheme() {
        XCTAssertThrowsError(try Selector.parse("foo:bar"))
    }

    func testParseRejectsBadOid() {
        XCTAssertThrowsError(try Selector.parse("oid:notanumber"))
    }

    func testParseRejectsBadPoint() {
        XCTAssertThrowsError(try Selector.parse("point:1"))
        XCTAssertThrowsError(try Selector.parse("point:a,b"))
    }
}
