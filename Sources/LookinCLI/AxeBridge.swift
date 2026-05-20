import CoreGraphics
import Foundation

public struct AxeElement {
    public let axId: String // AXUniqueId
    public let frame: CGRect // screen-space rect, in points
}

public enum AxeError: Error, CustomStringConvertible {
    case notInstalled
    case commandFailed(Int, String)
    case parseFailed(String)

    public var description: String {
        switch self {
        case .notInstalled:
            "'axe' not found on PATH (needed for axe: selectors). Install cameroncooke/AXe."
        case let .commandFailed(code, msg):
            "axe exited \(code): \(msg)"
        case let .parseFailed(msg):
            "could not parse axe output: \(msg)"
        }
    }
}

public enum AxeBridge {
    /// Locates the `axe` binary on PATH via `/usr/bin/which`.
    public static func axePath() -> String? {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        proc.arguments = ["axe"]
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = Pipe()
        do { try proc.run() } catch { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        proc.waitUntilExit()
        guard proc.terminationStatus == 0 else { return nil }
        let path = String(decoding: data, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return path.isEmpty ? nil : path
    }

    public static var isInstalled: Bool {
        axePath() != nil
    }

    /// Runs `axe describe-ui --udid <udid>` and flattens the result to a list
    /// of (AXUniqueId, screen frame).
    public static func describeUI(udid: String) throws -> [AxeElement] {
        guard let path = axePath() else { throw AxeError.notInstalled }
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: path)
        proc.arguments = ["describe-ui", "--udid", udid]
        let out = Pipe()
        let err = Pipe()
        proc.standardOutput = out
        proc.standardError = err
        try proc.run()
        let data = out.fileHandleForReading.readDataToEndOfFile()
        let errData = err.fileHandleForReading.readDataToEndOfFile()
        proc.waitUntilExit()
        guard proc.terminationStatus == 0 else {
            throw AxeError.commandFailed(Int(proc.terminationStatus),
                                         String(decoding: errData, as: UTF8.self))
        }
        return try parse(data)
    }

    /// Parses axe's accessibility JSON. axe emits either a single root object
    /// or an array of roots; each node has a `frame` { x, y, width, height }
    /// and an `AXUniqueId`, plus `children`.
    static func parse(_ data: Data) throws -> [AxeElement] {
        let json: Any
        do { json = try JSONSerialization.jsonObject(with: data) }
        catch { throw AxeError.parseFailed("\(error)") }

        var result: [AxeElement] = []
        func walk(_ node: [String: Any]) {
            if let axId = node["AXUniqueId"] as? String, !axId.isEmpty,
               let frame = node["frame"] as? [String: Any],
               let x = (frame["x"] as? NSNumber)?.doubleValue,
               let y = (frame["y"] as? NSNumber)?.doubleValue,
               let w = (frame["width"] as? NSNumber)?.doubleValue,
               let h = (frame["height"] as? NSNumber)?.doubleValue
            {
                result.append(AxeElement(
                    axId: axId,
                    frame: CGRect(x: x, y: y, width: w, height: h),
                ))
            }
            if let children = node["children"] as? [[String: Any]] {
                for child in children {
                    walk(child)
                }
            }
        }
        if let root = json as? [String: Any] {
            walk(root)
        } else if let roots = json as? [[String: Any]] {
            for r in roots {
                walk(r)
            }
        } else {
            throw AxeError.parseFailed("unexpected top-level JSON type")
        }
        return result
    }
}
