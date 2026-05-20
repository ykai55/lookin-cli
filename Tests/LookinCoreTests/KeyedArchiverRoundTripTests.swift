import LookinCore
import XCTest

/// Verifies that LookinConnectionAttachment (and the full graph of vendored types it
/// depends on) can survive an NSKeyedArchiver → NSKeyedUnarchiver round-trip on macOS.
/// The archive is synthesised in-process so no live iOS device is required.
final class KeyedArchiverRoundTripTests: XCTestCase {
    /// Note: The plan specified LookinCodingValueTypeNumber, which does not exist in the
    /// vendored enum (LookinCodingValueType). We use LookinCodingValueTypeLongLong, the
    /// closest numeric variant, which round-trips an NSNumber cleanly.
    func testEmptyAttachmentRoundTrip() throws {
        // LookinCodingValueTypeLongLong = 4 (6th value in the enum, 0-indexed).
        // The plan used LookinCodingValueTypeNumber which doesn't exist in the vendored enum;
        // LookinCodingValueTypeLongLong is the correct numeric variant.
        let numericType = try XCTUnwrap(LookinCodingValueType(rawValue: 4)) // LookinCodingValueTypeLongLong

        let original = LookinConnectionAttachment()
        original.dataType = numericType
        original.data = NSNumber(value: 42)

        let archiver = NSKeyedArchiver(requiringSecureCoding: true)
        archiver.encode(original, forKey: NSKeyedArchiveRootObjectKey)
        let data = archiver.encodedData

        let unarchiver = try NSKeyedUnarchiver(forReadingFrom: data)
        unarchiver.requiresSecureCoding = true
        let decoded = unarchiver.decodeObject(
            of: LookinConnectionAttachment.self,
            forKey: NSKeyedArchiveRootObjectKey,
        )
        XCTAssertNotNil(decoded)
        XCTAssertEqual(decoded?.dataType, numericType)
        XCTAssertEqual(decoded?.data as? NSNumber, 42)
    }
}
