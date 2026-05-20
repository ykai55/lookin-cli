import Foundation

/// Peertalk wire frame. Header is 16 bytes big-endian:
/// `{ uint32 version; uint32 type; uint32 tag; uint32 payloadSize }`
/// followed by `payloadSize` bytes of payload.
public struct Frame: Equatable {
    public static let headerSize = 16
    public static let protocolVersion: UInt32 = 1

    public let version: UInt32
    public let type: UInt32
    public let tag: UInt32
    public let payload: Data

    public init(type: UInt32, tag: UInt32, payload: Data, version: UInt32 = Frame.protocolVersion) {
        self.version = version
        self.type = type
        self.tag = tag
        self.payload = payload
    }

    public func encode() -> Data {
        var out = Data(capacity: Frame.headerSize + payload.count)
        out.appendBE(version)
        out.appendBE(type)
        out.appendBE(tag)
        out.appendBE(UInt32(payload.count))
        out.append(payload)
        return out
    }

    /// Decode a frame from a buffer. Returns `nil` if `buffer` doesn't yet
    /// contain a full frame. Throws on malformed data.
    public static func decode(from buffer: Data) throws -> (frame: Frame, consumed: Int)? {
        guard buffer.count >= headerSize else { return nil }
        let version = buffer.readBE(at: 0)
        let type = buffer.readBE(at: 4)
        let tag = buffer.readBE(at: 8)
        let size = buffer.readBE(at: 12)
        guard version == Frame.protocolVersion else {
            throw FrameError.unsupportedVersion(version)
        }
        let total = headerSize + Int(size)
        guard buffer.count >= total else { return nil }
        let payload = buffer.subdata(in: headerSize ..< total)
        let frame = Frame(type: type, tag: tag, payload: payload, version: version)
        return (frame, total)
    }
}

public enum FrameError: Error, Equatable {
    case unsupportedVersion(UInt32)
}

private extension Data {
    mutating func appendBE(_ value: UInt32) {
        var be = value.bigEndian
        Swift.withUnsafeBytes(of: &be) { append(contentsOf: $0) }
    }

    func readBE(at offset: Int) -> UInt32 {
        subdata(in: offset ..< offset + 4)
            .withUnsafeBytes { $0.load(as: UInt32.self) }
            .bigEndian
    }
}
