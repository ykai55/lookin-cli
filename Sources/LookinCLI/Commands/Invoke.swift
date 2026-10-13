import ArgumentParser
import Foundation
import LookinCore
import LookinTransport

struct Invoke: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "invoke",
        abstract: "Invoke a zero-argument Objective-C method. Repeat --selector to follow returned objects. Methods may have side effects.",
    )

    @OptionGroup var output: OutputOptions

    @Option(name: .long, help: "Lookin object ID, not a memory address.")
    var oid: UInt

    @Option(name: .long, help: "Zero-argument selector; repeat to chain through returned objects.")
    var selector: [String] = []

    mutating func validate() throws {
        guard oid > 0, !selector.isEmpty else {
            throw ValidationError("Provide a positive --oid and at least one --selector.")
        }
        for name in selector {
            guard !name.isEmpty, !name.contains(":"),
                  name.rangeOfCharacter(from: .whitespacesAndNewlines) == nil else {
                throw ValidationError("Only zero-argument selectors are supported: \(name)")
            }
        }
    }

    struct ObjectInfo: Encodable {
        let oid: UInt
        let address: String?
        let className: String?
    }

    struct Result: Encodable {
        let oid: UInt
        let selector: String
        let description: String?
        let object: ObjectInfo?
    }

    func run() throws {
        let session = try loadSession()
        let results: [Result] = try runAsync {
            let transport = PeertalkTransport(host: session.host, port: session.port)
            defer { Task { await transport.close() } }

            let ping = LookinConnectionAttachment()
            ping.dataType = LookinCodingValueType(rawValue: 4)!
            ping.data = NSNumber(value: LOOKIN_CLIENT_VERSION)
            let handshake = try await withRequestTimeout(seconds: 8) {
                try await transport.send(type: UInt32(LookinRequestTypePing), payload: ping)
            }
            if let error = (handshake as? LookinConnectionResponseAttachment)?.error {
                throw error
            }

            var target = oid
            var results: [Result] = []
            for (index, name) in selector.enumerated() {
                let request = LookinConnectionAttachment()
                request.dataType = LookinCodingValueType(rawValue: 0)!
                request.data = ["oid": NSNumber(value: target), "text": name] as NSDictionary
                let response = try await withRequestTimeout(seconds: 15) {
                    try await transport.send(type: UInt32(LookinRequestTypeInvokeMethod), payload: request)
                }
                if let error = (response as? LookinConnectionResponseAttachment)?.error {
                    throw error
                }
                guard let data = response.data as? [String: Any] else {
                    throw ValidationError("Unexpected response for \(name).")
                }
                let object = data["object"] as? LookinObject
                results.append(Result(
                    oid: target,
                    selector: name,
                    description: data["description"] as? String,
                    object: object.map { ObjectInfo(oid: $0.oid, address: $0.memoryAddress, className: $0.rawClassName()) },
                ))
                if index + 1 < selector.count {
                    guard let object, object.oid > 0 else {
                        throw ValidationError("\(name) returned no object; cannot continue the selector chain.")
                    }
                    target = object.oid
                }
            }
            return results
        }
        try emit(results, options: output)
        exitSuccess()
    }
}
