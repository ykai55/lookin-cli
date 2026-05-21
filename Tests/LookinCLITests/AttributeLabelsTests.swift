@testable import LookinCLI
import XCTest

final class AttributeLabelsTests: XCTestCase {
    func testKnownAttrLabels() {
        XCTAssertEqual(AttributeLabels.name(for: "l_f_f"), "Frame")
        XCTAssertEqual(AttributeLabels.name(for: "vl_c_r"), "Corner Radius")
        XCTAssertEqual(AttributeLabels.name(for: "c_c_c"), "Class")
        XCTAssertEqual(AttributeLabels.name(for: "tf_p_p"), "Placeholder")
    }

    func testKnownGroupLabels() {
        XCTAssertEqual(AttributeLabels.groupName(for: "vl"), "View & Layer")
        XCTAssertEqual(AttributeLabels.groupName(for: "l"), "Layout")
        XCTAssertEqual(AttributeLabels.groupName(for: "UIStackView"), "UIStackView")
    }

    func testUnknownReturnsNil() {
        XCTAssertNil(AttributeLabels.name(for: "totally_unknown"))
        XCTAssertNil(AttributeLabels.groupName(for: "zzz"))
    }
}
