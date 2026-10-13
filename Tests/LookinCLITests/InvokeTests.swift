import XCTest
@testable import LookinCLI

final class InvokeTests: XCTestCase {
    func testGetterChainPreservesOrder() throws {
        let command = try Invoke.parse([
            "--oid", "1918", "--selector", "component",
            "--selector", "preventNativeDismiss",
        ])
        XCTAssertEqual(command.oid, 1918)
        XCTAssertEqual(command.selector, ["component", "preventNativeDismiss"])
    }

    func testInvalidInvocationsAreRejectedBeforeConnecting() {
        for arguments in [
            ["--oid", "0", "--selector", "description"],
            ["--oid", "1918"],
            ["--oid", "1918", "--selector", "setHidden:"],
            ["--oid", "1918", "--selector", ""],
            ["--oid", "1918", "--selector", "a b"],
        ] {
            XCTAssertThrowsError(try Invoke.parse(arguments), "\(arguments)")
        }
    }
}
