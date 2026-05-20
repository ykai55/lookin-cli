import Foundation

public struct Session: Codable, Equatable {
    public enum Target: String, Codable { case simulator, device }

    public var host: String
    public var port: UInt16
    public var target: Target
    public var serverVersion: Int
    public var capturedAt: Date
    /// UDID of the booted simulator the app runs on. Optional: older session
    /// files decode with this as nil. Used by `measure`'s axe: selector path.
    public var simulatorUDID: String?

    public static let defaultPath: URL = {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent(".lookin-cli/session.json")
    }()

    public static func load(from url: URL = defaultPath) throws -> Session? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(Session.self, from: data)
    }

    public func save(to url: URL = defaultPath) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true,
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(self)
        try data.write(to: url, options: .atomic)
    }
}
