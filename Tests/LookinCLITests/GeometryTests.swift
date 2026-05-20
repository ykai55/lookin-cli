import CoreGraphics
@testable import LookinCLI
import XCTest

final class GeometryTests: XCTestCase {
    // Two cells stacked vertically, 8pt apart, same x/width.
    let a = CGRect(x: 0, y: 452, width: 402, height: 87)
    let b = CGRect(x: 0, y: 547, width: 402, height: 87)

    func testVerticalGap() throws {
        let m = Geometry.measure(a: a, b: b, tolerance: 0.5)
        XCTAssertEqual(try XCTUnwrap(m.gap.vertical), 8.0, accuracy: 0.001)
        XCTAssertNil(m.gap.horizontal)
    }

    func testTouchingEdgesGiveZeroGapNotOverlap() throws {
        let top = CGRect(x: 0, y: 0, width: 100, height: 50)
        let bottom = CGRect(x: 0, y: 50, width: 100, height: 50)
        let m = Geometry.measure(a: top, b: bottom, tolerance: 0.5)
        XCTAssertEqual(try XCTUnwrap(m.gap.vertical), 0.0, accuracy: 0.001)
        XCTAssertNil(m.overlap)
    }

    func testEdges() throws {
        let m = Geometry.measure(a: a, b: b, tolerance: 0.5)
        XCTAssertEqual(m.edges.leftToLeft, 0, accuracy: 0.001)
        XCTAssertEqual(m.edges.rightToRight, 0, accuracy: 0.001)
        XCTAssertEqual(m.edges.topToTop, 95, accuracy: 0.001)
        XCTAssertEqual(m.edges.bottomToBottom, 95, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(m.edges.aMaxYToBMinY), 8.0, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(m.edges.bMaxYToAMinY), -182.0, accuracy: 0.001)
        XCTAssertNil(m.edges.aMaxXToBMinX) // overlap on X
    }

    func testAlignment() {
        let m = Geometry.measure(a: a, b: b, tolerance: 0.5)
        XCTAssertTrue(m.alignment.left)
        XCTAssertTrue(m.alignment.right)
        XCTAssertTrue(m.alignment.centerX)
        XCTAssertFalse(m.alignment.top)
        XCTAssertFalse(m.alignment.centerY)
    }

    func testAlignmentTolerance() {
        let x1 = CGRect(x: 0, y: 0, width: 100, height: 10)
        let x2 = CGRect(x: 0.4, y: 50, width: 100, height: 10) // 0.4pt off
        XCTAssertTrue(Geometry.measure(a: x1, b: x2, tolerance: 0.5).alignment.left)
        XCTAssertFalse(Geometry.measure(a: x1, b: x2, tolerance: 0.3).alignment.left)
    }

    func testOverlap() throws {
        let r1 = CGRect(x: 0, y: 0, width: 100, height: 100)
        let r2 = CGRect(x: 50, y: 50, width: 100, height: 100)
        let m = Geometry.measure(a: r1, b: r2, tolerance: 0.5)
        XCTAssertNotNil(m.overlap)
        XCTAssertEqual(try XCTUnwrap(m.overlap?.area), 2500, accuracy: 0.001)
        XCTAssertNil(m.gap.vertical)
        XCTAssertNil(m.gap.horizontal)
    }

    func testDisjointHasNoOverlap() {
        let m = Geometry.measure(a: a, b: b, tolerance: 0.5)
        XCTAssertNil(m.overlap)
    }

    func testContainment() {
        let outer = CGRect(x: 0, y: 0, width: 200, height: 200)
        let inner = CGRect(x: 50, y: 50, width: 50, height: 50)
        let m = Geometry.measure(a: outer, b: inner, tolerance: 0.5)
        XCTAssertTrue(m.containment.bInsideA)
        XCTAssertFalse(m.containment.aInsideB)
    }

    func testCenter() {
        let m = Geometry.measure(a: a, b: b, tolerance: 0.5)
        XCTAssertEqual(m.center.dx, 0, accuracy: 0.001)
        XCTAssertEqual(m.center.dy, 95, accuracy: 0.001)
    }
}
