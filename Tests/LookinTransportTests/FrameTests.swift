@testable import LookinTransport
import XCTest

final class FrameTests: XCTestCase {
    func testEncodeProducesExpectedLayout() {
        let payload = Data([0xAA, 0xBB, 0xCC])
        let frame = Frame(type: 200, tag: 7, payload: payload)
        let bytes = [UInt8](frame.encode())
        XCTAssertEqual(bytes.count, 16 + 3)
        XCTAssertEqual(bytes[0 ..< 4], [0, 0, 0, 1]) // version
        XCTAssertEqual(bytes[4 ..< 8], [0, 0, 0, 200]) // type
        XCTAssertEqual(bytes[8 ..< 12], [0, 0, 0, 7]) // tag
        XCTAssertEqual(bytes[12 ..< 16], [0, 0, 0, 3]) // payload size
        XCTAssertEqual(bytes[16 ..< 19], [0xAA, 0xBB, 0xCC])
    }

    func testEncodeDecodeRoundTrip() throws {
        let frame = Frame(type: 203, tag: 42, payload: Data(repeating: 0x5A, count: 64))
        let bytes = frame.encode()
        let result = try Frame.decode(from: bytes)
        XCTAssertEqual(result?.frame, frame)
        XCTAssertEqual(result?.consumed, bytes.count)
    }

    func testDecodeReturnsNilOnPartialBuffer() throws {
        let frame = Frame(type: 200, tag: 1, payload: Data([0x01, 0x02]))
        let bytes = frame.encode()
        XCTAssertNil(try Frame.decode(from: bytes.prefix(8)))
        XCTAssertNil(try Frame.decode(from: bytes.prefix(17)))
    }

    func testDecodeRejectsUnknownVersion() {
        var bytes = Data()
        bytes.append(contentsOf: [0, 0, 0, 9]) // version 9
        bytes.append(contentsOf: [0, 0, 0, 0])
        bytes.append(contentsOf: [0, 0, 0, 0])
        bytes.append(contentsOf: [0, 0, 0, 0])
        XCTAssertThrowsError(try Frame.decode(from: bytes))
    }
}
