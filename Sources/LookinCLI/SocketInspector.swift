import Foundation

/// TCP socket state of a port, as reported by `lsof`.
enum SocketState: String {
    case listen
    case established
}

/// Inspects the host's TCP socket table via `lsof` so `doctor` can tell apart:
/// a port that is *listening* (LookinServer up), one that is only *established*
/// (the single-client connection held by another client, e.g. the Lookin macOS
/// GUI), and one with nothing on it at all.
enum SocketInspector {
    /// The most significant socket state per port in `range`. `listen` outranks
    /// `established`. Ports absent from the result have neither. Returns an empty
    /// map if `lsof` is unavailable.
    static func states(in range: ClosedRange<UInt16>) -> [UInt16: SocketState] {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
        proc.arguments = ["-nP", "-iTCP:\(range.lowerBound)-\(range.upperBound)"]
        let out = Pipe()
        proc.standardOutput = out
        proc.standardError = Pipe()
        do { try proc.run() } catch { return [:] }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        proc.waitUntilExit()
        // lsof exits 1 when no socket matches — expected, the output is just empty.
        return parse(String(decoding: data, as: UTF8.self), range: range)
    }

    /// Parses `lsof -nP -iTCP` output. Connection rows look like:
    ///   `App 123 user 10u IPv4 0x.. 0t0 TCP 127.0.0.1:47164 (LISTEN)`
    ///   `App 123 user 11u IPv4 0x.. 0t0 TCP 127.0.0.1:47164->127.0.0.1:5555 (ESTABLISHED)`
    /// The local endpoint is the NAME token, taken before any `->`.
    static func parse(_ output: String, range: ClosedRange<UInt16>) -> [UInt16: SocketState] {
        var result: [UInt16: SocketState] = [:]
        for line in output.split(separator: "\n") {
            guard let open = line.lastIndex(of: "("),
                  let close = line.lastIndex(of: ")"), open < close else { continue }
            let state: SocketState
            switch line[line.index(after: open) ..< close].uppercased() {
            case "LISTEN": state = .listen
            case "ESTABLISHED": state = .established
            default: continue
            }
            // NAME is the last whitespace-delimited token before "(STATE)".
            guard let name = line[..<open].split(separator: " ").last else { continue }
            let local: Substring = if let arrow = name.range(of: "->") {
                name[..<arrow.lowerBound]
            } else {
                name
            }
            guard let colon = local.lastIndex(of: ":"),
                  let port = UInt16(local[local.index(after: colon)...]),
                  range.contains(port) else { continue }
            if state == .listen || result[port] == nil {
                result[port] = state
            }
        }
        return result
    }
}
