import CoreGraphics
@testable import LookinCLI
import LookinCore
import XCTest

final class HierarchyTests: XCTestCase {
    /// Build a synthetic 3-level tree:
    ///   root window (0,0,400,800)
    ///     scrollView frame (0,100,400,500), bounds.origin (0,200)  [scrolled 200pt]
    ///       cell frame (0,452,400,87)
    private func makeTree() -> LookinHierarchyInfo {
        func obj(_ oid: UInt, _ cls: String) -> LookinObject {
            let o = LookinObject()
            o.oid = oid
            // rawClassName() returns classChainList.firstObject
            o.classChainList = [cls]
            return o
        }
        let cell = LookinDisplayItem()
        cell.frame = CGRect(x: 0, y: 452, width: 400, height: 87)
        cell.bounds = CGRect(x: 0, y: 0, width: 400, height: 87)
        cell.alpha = 1
        cell.viewObject = obj(3, "Cell")

        let scroll = LookinDisplayItem()
        scroll.frame = CGRect(x: 0, y: 100, width: 400, height: 500)
        scroll.bounds = CGRect(x: 0, y: 200, width: 400, height: 500)
        scroll.alpha = 1
        scroll.viewObject = obj(2, "UIScrollView")
        scroll.subitems = [cell]

        let window = LookinDisplayItem()
        window.frame = CGRect(x: 0, y: 0, width: 400, height: 800)
        window.bounds = CGRect(x: 0, y: 0, width: 400, height: 800)
        window.alpha = 1
        window.viewObject = obj(1, "UIWindow")
        window.subitems = [scroll]

        let info = LookinHierarchyInfo()
        info.displayItems = [window]
        return info
    }

    func testIndexAndLookup() {
        let h = Hierarchy(info: makeTree())
        XCTAssertNotNil(h.item(oid: 3))
        XCTAssertEqual(h.parent(oid: 3)?.viewObject?.oid, 2)
        XCTAssertEqual(h.parent(oid: 2)?.viewObject?.oid, 1)
        XCTAssertNil(h.parent(oid: 1))
    }

    func testAbsoluteFrameAccountsForScrollOffset() throws {
        let h = Hierarchy(info: makeTree())
        // window abs origin (0,0).
        // scroll abs = (0,0) + (0,100) - window.bounds.origin(0,0) = (0,100)
        // cell  abs = (0,100) + (0,452) - scroll.bounds.origin(0,200) = (0,352)
        let cellAbs = h.absoluteFrame(oid: 3)
        XCTAssertNotNil(cellAbs)
        XCTAssertEqual(try XCTUnwrap(cellAbs?.origin.x), 0, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(cellAbs?.origin.y), 352, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(cellAbs?.size.width), 400, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(cellAbs?.size.height), 87, accuracy: 0.001)
    }

    func testHitTestReturnsDeepest() {
        let h = Hierarchy(info: makeTree())
        // point (10,360) is inside the cell's absolute frame (0,352,400,87).
        let hit = h.hitTest(point: CGPoint(x: 10, y: 360))
        XCTAssertEqual(hit?.viewObject?.oid, 3)
    }

    func testCommonAncestor() {
        let h = Hierarchy(info: makeTree())
        XCTAssertEqual(h.commonAncestorOid(3, 2), 2)
        XCTAssertEqual(h.commonAncestorOid(3, 3), 3)
    }
}
