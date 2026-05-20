import Foundation
import LookinCore
import Network

public final class PeertalkTransport: LookinTransport {
    private let connection: NWConnection
    private let queue = DispatchQueue(label: "lookin.peertalk")
    /// Start at a high tag to avoid collision with server-push streaming frame tags
    /// (the server continuously sends type=203 frames with tags 1, 3, etc.).
    private var nextTag: UInt32 = 100
    // Key: (type, tag) — match response frames by request type AND tag to avoid collisions
    // with server-push streaming frames (e.g. type=203 async updates).
    private var pending: [PendingKey: CheckedContinuation<Frame, Error>] = [:]
    // For streaming responses: accumulate frames keyed by (type, tag).
    private var streaming: [PendingKey: StreamingSlot] = [:]
    private var rxBuffer = Data()
    private var didStart = false
    private var startContinuation: CheckedContinuation<Void, Error>?

    public init(host: String, port: UInt16) {
        let endpoint = NWEndpoint.hostPort(
            host: NWEndpoint.Host(host),
            port: NWEndpoint.Port(rawValue: port)!,
        )
        connection = NWConnection(to: endpoint, using: .tcp)
    }

    public func start() async throws {
        guard !didStart else { return }
        didStart = true
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { cont in
                self.startContinuation = cont
                connection.stateUpdateHandler = { [weak self] state in
                    guard let self else { return }
                    switch state {
                    case .ready:
                        startContinuation?.resume()
                        startContinuation = nil
                        scheduleReceive()
                    case let .failed(err):
                        startContinuation?.resume(throwing: err)
                        startContinuation = nil
                        failAllPending(LookinTransportError.io("\(err)"))
                    case .cancelled:
                        startContinuation?.resume(throwing: LookinTransportError.notConnected)
                        startContinuation = nil
                        failAllPending(LookinTransportError.notConnected)
                    default: break
                    }
                }
                connection.start(queue: queue)
            }
        } onCancel: {
            connection.cancel()
        }
    }

    public func send(
        type: UInt32,
        payload: LookinConnectionAttachment,
    ) async throws -> LookinConnectionAttachment {
        if !didStart { try await start() }

        let tag: UInt32 = queue.sync { defer { nextTag += 1 }; return nextTag }
        let body = encode(payload)
        let outFrame = Frame(type: type, tag: tag, payload: body)
        let key = PendingKey(type: type, tag: tag)

        let response: Frame = try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { cont in
                queue.async {
                    self.pending[key] = cont
                    self.connection.send(content: outFrame.encode(), completion: .contentProcessed { err in
                        if let err {
                            if let cont = self.pending.removeValue(forKey: key) {
                                cont.resume(throwing: LookinTransportError.io("\(err)"))
                            }
                        }
                    })
                }
            }
        } onCancel: {
            queue.async {
                if let cont = self.pending.removeValue(forKey: key) {
                    cont.resume(throwing: CancellationError())
                }
            }
        }

        return try unarchive(response.payload)
    }

    public func sendStreaming(
        type: UInt32,
        payload: LookinConnectionAttachment,
        expectedTotal: Int,
    ) async throws -> [LookinConnectionAttachment] {
        if !didStart { try await start() }

        let tag: UInt32 = queue.sync { defer { nextTag += 1 }; return nextTag }
        let body = encode(payload)
        let outFrame = Frame(type: type, tag: tag, payload: body)
        let key = PendingKey(type: type, tag: tag)

        let frames: [Frame] = try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { cont in
                queue.async {
                    self.streaming[key] = StreamingSlot(expectedTotal: expectedTotal, continuation: cont)
                    self.connection.send(content: outFrame.encode(), completion: .contentProcessed { err in
                        if let err {
                            if let slot = self.streaming.removeValue(forKey: key) {
                                slot.continuation.resume(throwing: LookinTransportError.io("\(err)"))
                            }
                        }
                    })
                }
            }
        } onCancel: {
            queue.async {
                if let slot = self.streaming.removeValue(forKey: key) {
                    slot.continuation.resume(throwing: CancellationError())
                }
            }
        }

        return try frames.map { try unarchive($0.payload) }
    }

    public func close() async {
        connection.cancel()
    }

    // MARK: - Private

    private func encode(_ payload: LookinConnectionAttachment) -> Data {
        let archiver = NSKeyedArchiver(requiringSecureCoding: true)
        archiver.encode(payload, forKey: NSKeyedArchiveRootObjectKey)
        return archiver.encodedData
    }

    private func scheduleReceive() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            if let data, !data.isEmpty {
                queue.async {
                    self.rxBuffer.append(data)
                    self.drainBuffer()
                }
            }
            if isComplete || error != nil {
                failAllPending(LookinTransportError.io(error.map { "\($0)" } ?? "EOF"))
                return
            }
            scheduleReceive()
        }
    }

    private func drainBuffer() {
        while true {
            do {
                guard let result = try Frame.decode(from: rxBuffer) else { return }
                rxBuffer.removeSubrange(0 ..< result.consumed)
                let key = PendingKey(type: result.frame.type, tag: result.frame.tag)

                // Check one-shot pending first.
                if let cont = pending.removeValue(forKey: key) {
                    cont.resume(returning: result.frame)
                    continue
                }

                // Check streaming slots next.
                if var slot = streaming[key] {
                    slot.frames.append(result.frame)
                    if slot.frames.count >= slot.expectedTotal {
                        streaming.removeValue(forKey: key)
                        slot.continuation.resume(returning: slot.frames)
                    } else {
                        streaming[key] = slot
                    }
                    continue
                }

                // Server-push frames (e.g. streaming type=203 async updates) without a matching
                // pending entry are silently discarded.
            } catch {
                failAllPending(LookinTransportError.decodeFailed("\(error)"))
                rxBuffer.removeAll()
                return
            }
        }
    }

    private func failAllPending(_ error: Error) {
        let singleConts = pending
        pending.removeAll()
        for (_, cont) in singleConts {
            cont.resume(throwing: error)
        }

        let streamingSlots = streaming
        streaming.removeAll()
        for (_, slot) in streamingSlots {
            slot.continuation.resume(throwing: error)
        }
    }

    private func unarchive(_ data: Data) throws -> LookinConnectionAttachment {
        // LookinServer always responds with LookinConnectionResponseAttachment (a subclass).
        // Its initWithCoder: calls decodeObjectForKey: for `data` and `error` without
        // specifying expected classes, incompatible with requiresSecureCoding = true.
        // We trust the LookinServer wire and decode without secure coding.
        let unarchiver = try NSKeyedUnarchiver(forReadingFrom: data)
        unarchiver.requiresSecureCoding = false
        guard let obj = unarchiver.decodeObject(forKey: NSKeyedArchiveRootObjectKey) as? LookinConnectionAttachment else {
            throw LookinTransportError.decodeFailed("not a LookinConnectionAttachment")
        }
        return obj
    }
}

// MARK: - Supporting types

/// Identifies an in-flight request by both its request type and tag so that
/// server-push frames (which share tags with client requests) cannot accidentally
/// resolve the wrong continuation.
private struct PendingKey: Hashable {
    let type: UInt32
    let tag: UInt32
}

/// Accumulates streaming response frames for a single request.
private struct StreamingSlot {
    let expectedTotal: Int
    var frames: [Frame] = []
    let continuation: CheckedContinuation<[Frame], Error>
}
