# lookin-cli Demo Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship a Swift macOS CLI that connects to an unmodified LookinServer in a running iOS app and exposes `attach`/`tree`/`attributes`/`find`/`screenshot`/`doctor` primitives as JSON, satisfying the §10 acceptance criteria in the design doc.

**Architecture:** Hybrid route B. Three SPM targets: `LookinCLI` (executable, ArgumentParser), `LookinTransport` (Swift, reimplements peertalk's 16-byte BE framing over `NWConnection`), `LookinCore` (Objective-C, vendored MIT-licensed sources from `LookinServer/Src/Main/Shared/` so `NSKeyedUnarchiver` can decode the wire payload natively). Connection is local TCP loopback on simulator port range 47164–47169; real-device USB forwarding is documented but not built-in.

**Tech Stack:** Swift 5.9+, ArgumentParser, Foundation `NWConnection`, vendored Objective-C from `QMUI/LookinServer` (MIT), XCTest.

**Operating constraint:** This session has no running iOS simulator with a LookinServer-integrated app. All implementation is verified via unit tests + `swift build` succeeding; final end-to-end validation against a live app is a documented manual smoke test the user runs after handoff.

---

## File map

```
lookin-cli/
├── Package.swift
├── README.md
├── Sources/
│   ├── LookinCLI/
│   │   ├── main.swift                       # @main entry (Lookin command group)
│   │   ├── Commands/
│   │   │   ├── Attach.swift
│   │   │   ├── Tree.swift
│   │   │   ├── Attributes.swift
│   │   │   ├── Find.swift
│   │   │   ├── Screenshot.swift
│   │   │   └── Doctor.swift
│   │   ├── Session.swift                    # ~/.lookin-cli/session.json
│   │   ├── JSONOutput.swift                 # LookinDisplayItem → public JSON
│   │   └── OutputFormat.swift               # --pretty handling
│   ├── LookinTransport/
│   │   ├── LookinTransport.swift            # protocol + LookinRequest/LookinResponse
│   │   ├── Frame.swift                      # 16-byte BE header encode/decode
│   │   ├── PeertalkTransport.swift          # NWConnection-based client
│   │   └── PortScanner.swift                # try 47164…47169 in turn
│   └── LookinCore/
│       ├── include/
│       │   ├── LookinCore.h                 # umbrella
│       │   └── module.modulemap
│       ├── LookinDefines.h                  # vendored verbatim
│       ├── LookinConnectionAttachment.{h,m}
│       ├── LookinHierarchyInfo.{h,m}
│       ├── LookinDisplayItem.{h,m}
│       ├── LookinObject.{h,m}
│       ├── LookinAttribute.{h,m}
│       ├── LookinAttributesGroup.{h,m}
│       ├── LookinAttributesSection.{h,m}
│       ├── LookinAutoLayoutConstraint.{h,m}
│       ├── LookinIvarTrace.{h,m}
│       └── ...supporting value types as discovered
└── Tests/
    ├── LookinTransportTests/
    │   ├── FrameTests.swift
    │   └── PortScannerTests.swift
    ├── LookinCoreTests/
    │   └── KeyedArchiverRoundTripTests.swift
    └── LookinCLITests/
        ├── JSONOutputTests.swift
        └── SessionTests.swift
```

---

## Task 1: Bootstrap Swift package

**Files:**

- Create: `Package.swift`
- Create: `.gitignore`
- Create: `Sources/LookinCLI/main.swift`
- Create: `Sources/LookinTransport/Placeholder.swift`
- Create: `Sources/LookinCore/include/LookinCore.h`
- Create: `Sources/LookinCore/include/module.modulemap`
- Create: `Sources/LookinCore/Placeholder.m`
- Create: `Tests/LookinCLITests/SmokeTest.swift`

- [ ] **Step 1:** Write `Package.swift` declaring three targets and ArgumentParser dependency.

```swift
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "lookin-cli",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "lookin", targets: ["LookinCLI"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.3.0"),
    ],
    targets: [
        .executableTarget(
            name: "LookinCLI",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                "LookinTransport",
            ]
        ),
        .target(
            name: "LookinTransport",
            dependencies: ["LookinCore"]
        ),
        .target(
            name: "LookinCore",
            publicHeadersPath: "include",
            cSettings: [
                .headerSearchPath("."),
                .define("LOOKIN_CLI_HOST", to: "1"),
            ]
        ),
        .testTarget(name: "LookinTransportTests", dependencies: ["LookinTransport"]),
        .testTarget(name: "LookinCoreTests", dependencies: ["LookinCore"]),
        .testTarget(name: "LookinCLITests", dependencies: ["LookinCLI"]),
    ]
)
```

- [ ] **Step 2:** Write `.gitignore`:

```
.build/
.swiftpm/
*.xcodeproj
DerivedData/
.DS_Store
*.sw?
```

- [ ] **Step 3:** Write a stub `Sources/LookinCLI/main.swift` so the package builds:

```swift
import ArgumentParser

@main
struct Lookin: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "lookin",
        abstract: "Query a running iOS app's view hierarchy via LookinServer.",
        subcommands: [],
        defaultSubcommand: nil
    )
}
```

- [ ] **Step 4:** Write placeholder sources so all three targets have at least one file:

`Sources/LookinTransport/Placeholder.swift`:

```swift
// Placeholder until real transport lands in Task 4.
internal enum LookinTransportModule {}
```

`Sources/LookinCore/include/LookinCore.h`:

```objc
#import <Foundation/Foundation.h>
// Umbrella header; real vendored headers added in Task 2.
```

`Sources/LookinCore/include/module.modulemap`:

```
module LookinCore {
    umbrella header "LookinCore.h"
    export *
}
```

`Sources/LookinCore/Placeholder.m`:

```objc
#import "LookinCore.h"
// Placeholder until real vendored sources land in Task 2.
```

- [ ] **Step 5:** Write a smoke test that proves the build works:

`Tests/LookinCLITests/SmokeTest.swift`:

```swift
import XCTest

final class SmokeTest: XCTestCase {
    func testPackageBuilds() {
        XCTAssertTrue(true)
    }
}
```

- [ ] **Step 6:** Verify build + test.

Run: `swift build && swift test`
Expected: both succeed; test count = 1.

- [ ] **Step 7:** Commit.

```bash
git add Package.swift .gitignore Sources Tests
git commit -m "feat: bootstrap SPM package with three targets"
```

---

## Task 2: Vendor LookinServer Objective-C sources

**Goal:** Pull in the minimum set of `Src/Main/Shared/` headers and implementations from LookinServer so `NSKeyedUnarchiver` can natively decode the wire payload on macOS. The set is determined empirically: start with the headers we know we need, then iterate until the round-trip test (Task 3) passes against a captured archive.

**Files:**

- Modify: `Sources/LookinCore/include/LookinCore.h`
- Create: `Sources/LookinCore/LookinDefines.h`
- Create: `Sources/LookinCore/Lookin{ConnectionAttachment, HierarchyInfo, DisplayItem, Object, Attribute, AttributesGroup, AttributesSection, AutoLayoutConstraint, IvarTrace}.{h,m}` (vendored)
- Create: `docs/upstream/PINNED_COMMIT.md`

- [ ] **Step 1:** Pick a pinned LookinServer upstream commit. Use `gh api repos/QMUI/LookinServer/commits` to fetch the latest commit on `master`; record its SHA + date in `docs/upstream/PINNED_COMMIT.md` along with the license string ("MIT").

- [ ] **Step 2:** Fetch the raw source files into `Sources/LookinCore/` (verbatim — do **not** edit). Files to fetch (paths relative to the upstream repo):
  - `Src/Main/Shared/LookinDefines.h`
  - `Src/Main/Shared/LookinConnectionAttachment.{h,m}`
  - `Src/Main/Shared/LookinHierarchyInfo.{h,m}`
  - `Src/Main/Shared/LookinDisplayItem.{h,m}`
  - `Src/Main/Shared/LookinObject.{h,m}`
  - `Src/Main/Shared/LookinAttribute.{h,m}`
  - `Src/Main/Shared/LookinAttributesGroup.{h,m}`
  - `Src/Main/Shared/LookinAttributesSection.{h,m}`
  - `Src/Main/Shared/LookinAutoLayoutConstraint.{h,m}`
  - `Src/Main/Shared/LookinIvarTrace.{h,m}`

Use `gh api repos/QMUI/LookinServer/contents/<path>?ref=<sha>` (the response's `download_url` field gives a raw URL) or `curl https://raw.githubusercontent.com/QMUI/LookinServer/<sha>/<path>`. Save each to `Sources/LookinCore/<filename>`.

- [ ] **Step 3:** Update the umbrella header to re-export the vendored public headers:

```objc
#import <Foundation/Foundation.h>
#import "LookinDefines.h"
#import "LookinConnectionAttachment.h"
#import "LookinHierarchyInfo.h"
#import "LookinDisplayItem.h"
#import "LookinObject.h"
#import "LookinAttribute.h"
#import "LookinAttributesGroup.h"
#import "LookinAttributesSection.h"
#import "LookinAutoLayoutConstraint.h"
#import "LookinIvarTrace.h"
```

- [ ] **Step 4:** Delete the placeholder `Sources/LookinCore/Placeholder.m`.

- [ ] **Step 5:** First build attempt:

```bash
swift build
```

This will likely fail with `UIKit/UIKit.h` not found or undeclared selectors on `UIColor`/`UIImage`/`UIView`. For each error:

- If a method/section is UIKit-only and only used by `init` from a live UIView, wrap it with `#if TARGET_OS_IOS` / `#endif`.
- If a type is referenced in encode/decode paths (e.g. `UIColor` in `+decodeObject…`), add a minimal macOS shim: `#if !TARGET_OS_IOS\n@class UIColor;\n#endif` in the relevant header — the decoded value is a class-by-name lookup, the macOS host doesn't need to materialize a real UIColor instance.
- For complete UIKit-dependent constructors that can't decode without UIKit, gate the whole method with `#if TARGET_OS_IOS`.

**Do not** change the encode/decode logic itself — `initWithCoder:` and `encodeWithCoder:` must remain identical to upstream so the archive shape matches.

Iterate `swift build` until it succeeds. Record every gated file in `docs/upstream/PATCHES.md` with a one-line reason.

- [ ] **Step 6:** Commit (separately, since this is a large vendored drop):

```bash
git add Sources/LookinCore docs/upstream/
git commit -m "feat: vendor LookinServer ObjC sources (MIT) at <sha>"
```

---

## Task 3: NSKeyedArchiver round-trip smoke test

**Goal:** Prove that the vendored types can decode a `LookinConnectionAttachment` archive on macOS. Use a synthesized archive (created in-process with the same vendored types) — full round-trip ensures both sides work and the wire envelope is correct.

**Files:**

- Create: `Tests/LookinCoreTests/KeyedArchiverRoundTripTests.swift`

- [ ] **Step 1:** Write the test:

```swift
import XCTest
import LookinCore

final class KeyedArchiverRoundTripTests: XCTestCase {
    func testEmptyAttachmentRoundTrip() throws {
        let original = LookinConnectionAttachment()
        original.dataType = LookinCodingValueTypeNumber
        original.data = NSNumber(value: 42)

        let archiver = NSKeyedArchiver(requiringSecureCoding: true)
        archiver.encode(original, forKey: NSKeyedArchiveRootObjectKey)
        let data = archiver.encodedData

        let unarchiver = try NSKeyedUnarchiver(forReadingFrom: data)
        unarchiver.requiresSecureCoding = true
        let decoded = unarchiver.decodeObject(
            of: LookinConnectionAttachment.self,
            forKey: NSKeyedArchiveRootObjectKey
        )
        XCTAssertNotNil(decoded)
        XCTAssertEqual(decoded?.dataType, LookinCodingValueTypeNumber)
        XCTAssertEqual(decoded?.data as? NSNumber, 42)
    }
}
```

- [ ] **Step 2:** Run:

```bash
swift test --filter LookinCoreTests
```

Expected: PASS. If it fails with "class not registered for secure coding" or "couldn't decode", add the missing class names to the unarchiver's allowed classes set (`unarchiver.setClass(LookinX.self, forClassName: "LookinX")`) until it passes — record additions in `docs/upstream/PATCHES.md`.

- [ ] **Step 3:** Commit.

```bash
git add Tests/LookinCoreTests/KeyedArchiverRoundTripTests.swift docs/upstream/
git commit -m "test: NSKeyedArchiver round-trip for vendored LookinCore types"
```

---

## Task 4: Peertalk frame encode/decode in Swift

**Goal:** Reimplement peertalk's 16-byte big-endian frame header — the only wire-level piece — in pure Swift.

**Files:**

- Create: `Sources/LookinTransport/Frame.swift`
- Create: `Tests/LookinTransportTests/FrameTests.swift`
- Delete: `Sources/LookinTransport/Placeholder.swift`

- [ ] **Step 1:** Write `Frame.swift`:

```swift
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
        let type    = buffer.readBE(at: 4)
        let tag     = buffer.readBE(at: 8)
        let size    = buffer.readBE(at: 12)
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
        withUnsafeBytes(of: &be) { append(contentsOf: $0) }
    }
    func readBE(at offset: Int) -> UInt32 {
        self.subdata(in: offset ..< offset + 4)
            .withUnsafeBytes { $0.load(as: UInt32.self) }
            .bigEndian
    }
}
```

- [ ] **Step 2:** Write tests:

```swift
import XCTest
@testable import LookinTransport

final class FrameTests: XCTestCase {
    func testEncodeProducesExpectedLayout() {
        let payload = Data([0xAA, 0xBB, 0xCC])
        let frame = Frame(type: 200, tag: 7, payload: payload)
        let bytes = [UInt8](frame.encode())
        XCTAssertEqual(bytes.count, 16 + 3)
        XCTAssertEqual(bytes[0..<4],  [0, 0, 0, 1])     // version
        XCTAssertEqual(bytes[4..<8],  [0, 0, 0, 200])   // type
        XCTAssertEqual(bytes[8..<12], [0, 0, 0, 7])     // tag
        XCTAssertEqual(bytes[12..<16],[0, 0, 0, 3])     // payload size
        XCTAssertEqual(bytes[16..<19],[0xAA, 0xBB, 0xCC])
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
        bytes.append(contentsOf: [0, 0, 0, 9])    // version 9
        bytes.append(contentsOf: [0, 0, 0, 0])
        bytes.append(contentsOf: [0, 0, 0, 0])
        bytes.append(contentsOf: [0, 0, 0, 0])
        XCTAssertThrowsError(try Frame.decode(from: bytes))
    }
}
```

- [ ] **Step 3:** Delete `Sources/LookinTransport/Placeholder.swift`.

- [ ] **Step 4:** Run:

```bash
swift test --filter LookinTransportTests
```

Expected: all 4 tests pass.

- [ ] **Step 5:** Commit.

```bash
git add Sources/LookinTransport/Frame.swift Tests/LookinTransportTests/FrameTests.swift
git rm Sources/LookinTransport/Placeholder.swift
git commit -m "feat: peertalk 16-byte BE frame codec"
```

---

## Task 5: Transport protocol abstraction

**Files:**

- Create: `Sources/LookinTransport/LookinTransport.swift`

- [ ] **Step 1:** Write:

```swift
import Foundation
import LookinCore

/// Abstracts how the CLI talks to a running LookinServer.
/// Today: `PeertalkTransport` (route B). Tomorrow: `HTTPTransport` (route A).
public protocol LookinTransport: AnyObject {
    /// Sends a request, awaits the matching tagged response.
    func send(
        type: UInt32,
        payload: LookinConnectionAttachment
    ) async throws -> LookinConnectionAttachment

    /// Tear down the underlying connection.
    func close() async
}

public enum LookinTransportError: Error, CustomStringConvertible {
    case notConnected
    case decodeFailed(String)
    case serverError(code: Int, message: String)
    case versionMismatch(client: Int, server: Int)
    case io(String)

    public var description: String {
        switch self {
        case .notConnected:                       return "Not connected to LookinServer."
        case .decodeFailed(let msg):              return "Decode failed: \(msg)"
        case .serverError(let code, let msg):     return "Server error \(code): \(msg)"
        case .versionMismatch(let c, let s):      return "Version mismatch (client=\(c), server=\(s))."
        case .io(let msg):                        return "I/O error: \(msg)"
        }
    }
}
```

- [ ] **Step 2:** Build + test (no new tests; just `swift build`).

```bash
swift build
```

Expected: succeeds.

- [ ] **Step 3:** Commit.

```bash
git add Sources/LookinTransport/LookinTransport.swift
git commit -m "feat: LookinTransport protocol and error types"
```

---

## Task 6: PeertalkTransport — NWConnection client

**Files:**

- Create: `Sources/LookinTransport/PeertalkTransport.swift`

- [ ] **Step 1:** Write the transport. It manages a single `NWConnection`, multiplexes by `tag`, and (de)serializes payloads via `NSKeyedArchiver/Unarchiver`.

```swift
import Foundation
import Network
import LookinCore

public final class PeertalkTransport: LookinTransport {
    private let connection: NWConnection
    private let queue = DispatchQueue(label: "lookin.peertalk")
    private var nextTag: UInt32 = 1
    private var pending: [UInt32: CheckedContinuation<Frame, Error>] = [:]
    private var rxBuffer = Data()
    private var didStart = false
    private var startContinuation: CheckedContinuation<Void, Error>?

    public init(host: String, port: UInt16) {
        let endpoint = NWEndpoint.hostPort(
            host: NWEndpoint.Host(host),
            port: NWEndpoint.Port(rawValue: port)!
        )
        self.connection = NWConnection(to: endpoint, using: .tcp)
    }

    public func start() async throws {
        guard !didStart else { return }
        didStart = true
        try await withCheckedThrowingContinuation { cont in
            self.startContinuation = cont
            connection.stateUpdateHandler = { [weak self] state in
                guard let self else { return }
                switch state {
                case .ready:
                    self.startContinuation?.resume()
                    self.startContinuation = nil
                    self.scheduleReceive()
                case .failed(let err):
                    self.startContinuation?.resume(throwing: err)
                    self.startContinuation = nil
                    self.failAllPending(LookinTransportError.io("\(err)"))
                case .cancelled:
                    self.failAllPending(LookinTransportError.notConnected)
                default: break
                }
            }
            connection.start(queue: queue)
        }
    }

    public func send(
        type: UInt32,
        payload: LookinConnectionAttachment
    ) async throws -> LookinConnectionAttachment {
        if !didStart { try await start() }

        let tag: UInt32 = queue.sync { defer { nextTag += 1 }; return nextTag }
        let archiver = NSKeyedArchiver(requiringSecureCoding: true)
        archiver.encode(payload, forKey: NSKeyedArchiveRootObjectKey)
        let body = archiver.encodedData
        let frame = Frame(type: type, tag: tag, payload: body)

        let response: Frame = try await withCheckedThrowingContinuation { cont in
            queue.async {
                self.pending[tag] = cont
                self.connection.send(content: frame.encode(), completion: .contentProcessed { err in
                    if let err {
                        if let cont = self.pending.removeValue(forKey: tag) {
                            cont.resume(throwing: LookinTransportError.io("\(err)"))
                        }
                    }
                })
            }
        }

        return try unarchive(response.payload)
    }

    public func close() async {
        connection.cancel()
    }

    // MARK: - Private

    private func scheduleReceive() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            if let data, !data.isEmpty {
                self.queue.async {
                    self.rxBuffer.append(data)
                    self.drainBuffer()
                }
            }
            if isComplete || error != nil {
                self.failAllPending(LookinTransportError.io(error.map { "\($0)" } ?? "EOF"))
                return
            }
            self.scheduleReceive()
        }
    }

    private func drainBuffer() {
        while true {
            do {
                guard let result = try Frame.decode(from: rxBuffer) else { return }
                rxBuffer.removeSubrange(0 ..< result.consumed)
                if let cont = pending.removeValue(forKey: result.frame.tag) {
                    cont.resume(returning: result.frame)
                }
                // Server-push frames without pending continuations are ignored for now.
            } catch {
                failAllPending(LookinTransportError.decodeFailed("\(error)"))
                rxBuffer.removeAll()
                return
            }
        }
    }

    private func failAllPending(_ error: Error) {
        let conts = pending
        pending.removeAll()
        for (_, cont) in conts { cont.resume(throwing: error) }
    }

    private func unarchive(_ data: Data) throws -> LookinConnectionAttachment {
        let unarchiver = try NSKeyedUnarchiver(forReadingFrom: data)
        unarchiver.requiresSecureCoding = true
        guard let obj = unarchiver.decodeObject(
            of: LookinConnectionAttachment.self,
            forKey: NSKeyedArchiveRootObjectKey
        ) else {
            throw LookinTransportError.decodeFailed("not a LookinConnectionAttachment")
        }
        return obj
    }
}
```

- [ ] **Step 2:** Build:

```bash
swift build
```

Expected: succeeds. (No new tests here — exercising NWConnection requires a real server. Task 11+ test against a mock by swapping the protocol.)

- [ ] **Step 3:** Commit.

```bash
git add Sources/LookinTransport/PeertalkTransport.swift
git commit -m "feat: peertalk NWConnection transport"
```

---

## Task 7: PortScanner

**Files:**

- Create: `Sources/LookinTransport/PortScanner.swift`
- Create: `Tests/LookinTransportTests/PortScannerTests.swift`

- [ ] **Step 1:** Write the scanner. It opens a quick TCP connect to each port in a range and returns the first responsive one.

```swift
import Foundation
import Network

public struct PortScanner {
    public enum Target {
        case simulator       // 47164...47169
        case device          // 47175...47179, but normally already forwarded via iproxy

        public var range: ClosedRange<UInt16> {
            switch self {
            case .simulator: return 47164 ... 47169
            case .device:    return 47175 ... 47179
            }
        }
    }

    public static func firstResponsivePort(
        host: String = "127.0.0.1",
        target: Target,
        timeout: TimeInterval = 0.25
    ) async -> UInt16? {
        for port in target.range {
            if await isReachable(host: host, port: port, timeout: timeout) { return port }
        }
        return nil
    }

    public static func isReachable(host: String, port: UInt16, timeout: TimeInterval) async -> Bool {
        let endpoint = NWEndpoint.hostPort(
            host: NWEndpoint.Host(host),
            port: NWEndpoint.Port(rawValue: port)!
        )
        let connection = NWConnection(to: endpoint, using: .tcp)
        return await withCheckedContinuation { cont in
            let queue = DispatchQueue(label: "lookin.portscan.\(port)")
            var resumed = false
            connection.stateUpdateHandler = { state in
                guard !resumed else { return }
                switch state {
                case .ready:
                    resumed = true
                    connection.cancel()
                    cont.resume(returning: true)
                case .failed, .cancelled:
                    resumed = true
                    cont.resume(returning: false)
                default: break
                }
            }
            connection.start(queue: queue)
            queue.asyncAfter(deadline: .now() + timeout) {
                guard !resumed else { return }
                resumed = true
                connection.cancel()
                cont.resume(returning: false)
            }
        }
    }
}
```

- [ ] **Step 2:** Write a port-scanner test that confirms the range matches Lookin's constants:

```swift
import XCTest
@testable import LookinTransport

final class PortScannerTests: XCTestCase {
    func testSimulatorRangeMatchesUpstream() {
        XCTAssertEqual(PortScanner.Target.simulator.range, 47164 ... 47169)
    }

    func testDeviceRangeMatchesUpstream() {
        XCTAssertEqual(PortScanner.Target.device.range, 47175 ... 47179)
    }

    func testUnreachablePortReturnsFalse() async {
        // Port 1 should be closed on a dev mac.
        let reachable = await PortScanner.isReachable(host: "127.0.0.1", port: 1, timeout: 0.1)
        XCTAssertFalse(reachable)
    }
}
```

- [ ] **Step 3:** Run:

```bash
swift test --filter LookinTransportTests
```

Expected: 7 tests pass total (4 from Frame + 3 here).

- [ ] **Step 4:** Commit.

```bash
git add Sources/LookinTransport/PortScanner.swift Tests/LookinTransportTests/PortScannerTests.swift
git commit -m "feat: port scanner for LookinServer's loopback range"
```

---

## Task 8: Session model

**Files:**

- Create: `Sources/LookinCLI/Session.swift`
- Create: `Tests/LookinCLITests/SessionTests.swift`

- [ ] **Step 1:** Write:

```swift
import Foundation

public struct Session: Codable, Equatable {
    public enum Target: String, Codable { case simulator, device }

    public var host: String
    public var port: UInt16
    public var target: Target
    public var serverVersion: Int
    public var capturedAt: Date

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
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(self)
        try data.write(to: url, options: .atomic)
    }
}
```

- [ ] **Step 2:** Test:

```swift
import XCTest
@testable import LookinCLI

final class SessionTests: XCTestCase {
    func testRoundTrip() throws {
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("session-\(UUID()).json")
        defer { try? FileManager.default.removeItem(at: tmp) }

        let original = Session(
            host: "127.0.0.1",
            port: 47164,
            target: .simulator,
            serverVersion: 7,
            capturedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        try original.save(to: tmp)

        let loaded = try Session.load(from: tmp)
        XCTAssertEqual(loaded, original)
    }

    func testLoadReturnsNilWhenMissing() throws {
        let url = URL(fileURLWithPath: "/tmp/lookin-cli-does-not-exist-\(UUID()).json")
        XCTAssertNil(try Session.load(from: url))
    }
}
```

- [ ] **Step 3:** Run + commit.

```bash
swift test --filter LookinCLITests
git add Sources/LookinCLI/Session.swift Tests/LookinCLITests/SessionTests.swift
git commit -m "feat: Session persistence in ~/.lookin-cli/session.json"
```

---

## Task 9: ArgumentParser command tree skeleton

**Files:**

- Modify: `Sources/LookinCLI/main.swift`
- Create: `Sources/LookinCLI/Commands/Attach.swift` (stub)
- Create: `Sources/LookinCLI/Commands/Tree.swift` (stub)
- Create: `Sources/LookinCLI/Commands/Attributes.swift` (stub)
- Create: `Sources/LookinCLI/Commands/Find.swift` (stub)
- Create: `Sources/LookinCLI/Commands/Screenshot.swift` (stub)
- Create: `Sources/LookinCLI/Commands/Doctor.swift` (stub)
- Create: `Sources/LookinCLI/OutputFormat.swift`

- [ ] **Step 1:** Write `OutputFormat.swift`:

```swift
import Foundation
import ArgumentParser

public struct OutputOptions: ParsableArguments {
    @Flag(name: .long, help: "Pretty-print JSON output.")
    public var pretty: Bool = false

    public init() {}

    public func encoder() -> JSONEncoder {
        let enc = JSONEncoder()
        enc.outputFormatting = pretty ? [.prettyPrinted, .sortedKeys] : [.sortedKeys]
        enc.dateEncodingStrategy = .iso8601
        return enc
    }
}

public func emit<T: Encodable>(_ value: T, options: OutputOptions) throws {
    let data = try options.encoder().encode(value)
    FileHandle.standardOutput.write(data)
    FileHandle.standardOutput.write(Data([0x0A]))  // trailing newline
}
```

- [ ] **Step 2:** Write each command as a stub that prints `not yet implemented` to stderr and exits 1 (we'll fill them in subsequent tasks):

```swift
// Sources/LookinCLI/Commands/Attach.swift
import ArgumentParser
struct Attach: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "attach",
        abstract: "Discover and connect to a LookinServer."
    )
    func run() throws {
        FileHandle.standardError.write(Data("attach: not yet implemented\n".utf8))
        throw ExitCode.failure
    }
}
```

Replicate for `Tree`, `Attributes`, `Find`, `Screenshot`, `Doctor` with their own abstracts.

- [ ] **Step 3:** Wire them into `main.swift`:

```swift
import ArgumentParser

@main
struct Lookin: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "lookin",
        abstract: "Query a running iOS app's view hierarchy via LookinServer.",
        version: "0.1.0",
        subcommands: [Attach.self, Tree.self, Attributes.self, Find.self, Screenshot.self, Doctor.self]
    )
}
```

- [ ] **Step 4:** Verify the help text:

```bash
swift run lookin --help
```

Expected: lists the 6 subcommands.

- [ ] **Step 5:** Commit.

```bash
git add Sources/LookinCLI
git commit -m "feat: ArgumentParser subcommand skeleton"
```

---

## Task 10: `lookin doctor`

**Files:**

- Modify: `Sources/LookinCLI/Commands/Doctor.swift`

- [ ] **Step 1:** Implement. Doctor scans ports, attempts a ping, prints a single-line JSON status. It does **not** write the session file (that's `attach`'s job).

```swift
import Foundation
import ArgumentParser
import LookinTransport
import LookinCore

struct Doctor: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "doctor",
        abstract: "Probe simulator/device for a reachable LookinServer; print diagnostics."
    )

    @OptionGroup var output: OutputOptions

    @Flag(name: .long, help: "Probe the device USB port range instead of the simulator range.")
    var device: Bool = false

    func run() throws {
        let target: PortScanner.Target = device ? .device : .simulator
        let start = Date()
        let result = try runAsync { try await Doctor.probe(target: target) }
        let elapsed = Date().timeIntervalSince(start) * 1000

        struct Report: Encodable {
            let target: String
            let host: String
            let port: UInt16?
            let reachable: Bool
            let serverVersion: Int?
            let probeMs: Int
            let hint: String?
        }
        let report = Report(
            target: device ? "device" : "simulator",
            host: "127.0.0.1",
            port: result.port,
            reachable: result.port != nil,
            serverVersion: result.serverVersion,
            probeMs: Int(elapsed),
            hint: result.port == nil
                ? (device
                    ? "No port reachable. Did you run `iproxy 47175 47175`?"
                    : "No port reachable. Is the simulator app running in Debug?")
                : nil
        )
        try emit(report, options: output)
    }

    private static func probe(target: PortScanner.Target) async throws -> (port: UInt16?, serverVersion: Int?) {
        guard let port = await PortScanner.firstResponsivePort(target: target) else {
            return (nil, nil)
        }
        let transport = PeertalkTransport(host: "127.0.0.1", port: port)
        defer { Task { await transport.close() } }
        let ping = LookinConnectionAttachment()
        ping.dataType = LookinCodingValueTypeNumber
        ping.data = NSNumber(value: LookinClientVersion)
        do {
            let response = try await transport.send(type: UInt32(LookinRequestTypePing), payload: ping)
            let serverVersion = (response.data as? NSNumber)?.intValue
            return (port, serverVersion)
        } catch {
            return (port, nil)
        }
    }
}

// MARK: - Async bridge

func runAsync<T>(_ body: @escaping () async throws -> T) throws -> T {
    let group = DispatchGroup()
    var result: Result<T, Error>!
    group.enter()
    Task {
        do { result = .success(try await body()) }
        catch { result = .failure(error) }
        group.leave()
    }
    group.wait()
    return try result.get()
}
```

- [ ] **Step 2:** Build + manual smoke (no live server expected; should report `reachable=false`):

```bash
swift build
.build/debug/lookin doctor --pretty
```

Expected output (since no app running):

```json
{
  "host" : "127.0.0.1",
  "hint" : "No port reachable. Is the simulator app running in Debug?",
  "port" : null,
  "probeMs" : <number>,
  "reachable" : false,
  "serverVersion" : null,
  "target" : "simulator"
}
```

- [ ] **Step 3:** Commit.

```bash
git add Sources/LookinCLI/Commands/Doctor.swift
git commit -m "feat: lookin doctor"
```

---

## Task 11: `lookin attach`

**Files:**

- Modify: `Sources/LookinCLI/Commands/Attach.swift`

- [ ] **Step 1:** Implement attach. Resolves port, ping handshake, writes session file.

```swift
import Foundation
import ArgumentParser
import LookinTransport
import LookinCore

struct Attach: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "attach",
        abstract: "Discover a LookinServer, save session to ~/.lookin-cli/session.json."
    )

    @OptionGroup var output: OutputOptions

    @Flag(name: .long, help: "Attach to a real device (default: simulator).")
    var device: Bool = false

    @Option(name: .long, help: "Override port (skip scan).")
    var port: UInt16?

    func run() throws {
        let target: PortScanner.Target = device ? .device : .simulator
        let session = try runAsync { try await Attach.attach(target: target, explicitPort: port) }
        try session.save()
        try emit(session, options: output)
    }

    private static func attach(target: PortScanner.Target, explicitPort: UInt16?) async throws -> Session {
        let resolved: UInt16
        if let explicitPort {
            resolved = explicitPort
        } else if let scanned = await PortScanner.firstResponsivePort(target: target) {
            resolved = scanned
        } else {
            throw LookinTransportError.notConnected
        }
        let transport = PeertalkTransport(host: "127.0.0.1", port: resolved)
        defer { Task { await transport.close() } }
        let payload = LookinConnectionAttachment()
        payload.dataType = LookinCodingValueTypeNumber
        payload.data = NSNumber(value: LookinClientVersion)
        let response = try await transport.send(type: UInt32(LookinRequestTypePing), payload: payload)
        let serverVersion = (response.data as? NSNumber)?.intValue ?? 0
        if serverVersion == 0 {
            throw LookinTransportError.decodeFailed("ping returned no version")
        }
        return Session(
            host: "127.0.0.1",
            port: resolved,
            target: target == .device ? .device : .simulator,
            serverVersion: serverVersion,
            capturedAt: Date()
        )
    }
}
```

- [ ] **Step 2:** Build:

```bash
swift build
```

Expected: succeeds. (Manual `lookin attach` against no live server will exit non-zero — that's expected.)

- [ ] **Step 3:** Commit.

```bash
git add Sources/LookinCLI/Commands/Attach.swift
git commit -m "feat: lookin attach"
```

---

## Task 12: `lookin tree`

**Files:**

- Create: `Sources/LookinCLI/JSONOutput.swift`
- Modify: `Sources/LookinCLI/Commands/Tree.swift`
- Create: `Tests/LookinCLITests/JSONOutputTests.swift`

- [ ] **Step 1:** Write `JSONOutput.swift`. Maps `LookinDisplayItem` → a stable public JSON shape per spec §9.

```swift
import Foundation
import LookinCore
import CoreGraphics

struct PublicNode: Encodable {
    let oid: String
    let axId: String?
    let figmaRef: String?
    let `class`: String
    let hostVC: String?
    let frame: [CGFloat]
    let alpha: CGFloat
    let isHidden: Bool
    let childCount: Int
    let children: [PublicNode]?
}

enum JSONOutput {
    static func encode(_ item: LookinDisplayItem, includeChildren: Bool, maxDepth: Int) -> PublicNode {
        let axId = item.viewObject?.specialTrace ?? nil  // populated only when the view has an accessibilityIdentifier
        let figmaRef = axId.flatMap { id -> String? in
            guard id.hasPrefix("figma:") else { return nil }
            return String(id.dropFirst("figma:".count))
        }
        let frame = item.frame
        let children: [PublicNode]?
        if includeChildren && maxDepth > 0 {
            children = (item.subitems ?? []).map {
                encode($0, includeChildren: true, maxDepth: maxDepth - 1)
            }
        } else {
            children = nil
        }
        return PublicNode(
            oid: String(format: "0x%llx", UInt64(bitPattern: Int64(item.viewObject?.address ?? 0))),
            axId: axId,
            figmaRef: figmaRef,
            class: item.viewObject?.rawClassName ?? "<unknown>",
            hostVC: item.hostViewControllerObject?.rawClassName,
            frame: [frame.origin.x, frame.origin.y, frame.size.width, frame.size.height],
            alpha: CGFloat(item.alpha),
            isHidden: item.isHidden,
            childCount: item.subitems?.count ?? 0,
            children: children
        )
    }
}
```

> **Implementation note:** the actual property names on `LookinDisplayItem` / `LookinObject` may differ from what's listed above (specifically `address`, `specialTrace`, `rawClassName`). After Task 2 lands, audit `Sources/LookinCore/LookinDisplayItem.h` + `LookinObject.h` and adjust the property accesses here to match the vendored headers. Keep the public JSON shape stable.

- [ ] **Step 2:** Implement `Tree.swift`:

```swift
import Foundation
import ArgumentParser
import LookinTransport
import LookinCore

struct Tree: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "tree",
        abstract: "Print the running view hierarchy as JSON."
    )

    @OptionGroup var output: OutputOptions

    @Option(name: .long, help: "Maximum tree depth.")
    var depth: Int = 8

    @Flag(name: .long, help: "Include views with isHidden == true.")
    var includeHidden: Bool = false

    func run() throws {
        guard let session = try Session.load() else {
            FileHandle.standardError.write(Data("No session. Run `lookin attach` first.\n".utf8))
            throw ExitCode.failure
        }
        let result = try runAsync { try await Tree.fetchTree(session: session) }
        let pruned = includeHidden ? result : Tree.pruneHidden(result)
        let node = JSONOutput.encode(pruned, includeChildren: true, maxDepth: depth)

        struct Envelope<N: Encodable>: Encodable {
            let root: N
            let target: SessionView
            let captured: Date
            let serverVersion: Int
        }
        struct SessionView: Encodable { let kind: String; let host: String; let port: UInt16 }

        let env = Envelope(
            root: node,
            target: SessionView(kind: session.target.rawValue, host: session.host, port: session.port),
            captured: Date(),
            serverVersion: session.serverVersion
        )
        try emit(env, options: output)
    }

    private static func fetchTree(session: Session) async throws -> LookinDisplayItem {
        let transport = PeertalkTransport(host: session.host, port: session.port)
        defer { Task { await transport.close() } }
        let req = LookinConnectionAttachment()
        req.dataType = LookinCodingValueTypeNumber
        req.data = NSNumber(value: 0)  // requests the full hierarchy
        let response = try await transport.send(type: UInt32(LookinRequestTypeHierarchy), payload: req)
        guard let info = response.data as? LookinHierarchyInfo,
              let root = info.displayItems?.first else {
            throw LookinTransportError.decodeFailed("hierarchy response missing root")
        }
        return root
    }

    private static func pruneHidden(_ item: LookinDisplayItem) -> LookinDisplayItem {
        item.subitems = (item.subitems ?? []).filter { !$0.isHidden }.map(pruneHidden)
        return item
    }
}
```

> **Implementation note:** `LookinHierarchyInfo.displayItems` returns a flat array (per upstream); depending on the schema, you may need to rebuild the parent/child links from `superItem` references. Audit `LookinHierarchyInfo.h` during Task 2 and adjust.

- [ ] **Step 3:** Write a JSONOutput test against a synthesized `LookinDisplayItem`:

```swift
import XCTest
import LookinCore
@testable import LookinCLI

final class JSONOutputTests: XCTestCase {
    func testFlatNodeEncoding() throws {
        let item = LookinDisplayItem()
        item.frame = CGRect(x: 0, y: 0, width: 100, height: 50)
        item.alpha = 0.5
        item.isHidden = false
        let obj = LookinObject()
        obj.rawClassName = "UIButton"
        item.viewObject = obj
        let node = JSONOutput.encode(item, includeChildren: false, maxDepth: 0)
        XCTAssertEqual(node.class, "UIButton")
        XCTAssertEqual(node.frame, [0, 0, 100, 50])
        XCTAssertEqual(node.alpha, 0.5)
        XCTAssertFalse(node.isHidden)
        XCTAssertNil(node.children)
    }
}
```

- [ ] **Step 4:** Build + test.

```bash
swift build
swift test --filter LookinCLITests
```

Expected: build succeeds; new test passes (+ existing pass).

- [ ] **Step 5:** Commit.

```bash
git add Sources/LookinCLI/JSONOutput.swift Sources/LookinCLI/Commands/Tree.swift Tests/LookinCLITests/JSONOutputTests.swift
git commit -m "feat: lookin tree with stable JSON schema"
```

---

## Task 13: `lookin attributes`

**Files:**

- Modify: `Sources/LookinCLI/Commands/Attributes.swift`
- Extend: `Sources/LookinCLI/JSONOutput.swift` (add `attributes` encoder)

- [ ] **Step 1:** Extend `JSONOutput.swift` with an attribute-flattening encoder:

```swift
struct PublicAttribute: Encodable {
    let group: String
    let section: String
    let key: String
    let type: String
    let value: AnyEncodable
}

struct AnyEncodable: Encodable {
    let encode: (Encoder) throws -> Void
    init<T: Encodable>(_ value: T) { self.encode = { try value.encode(to: $0) } }
    init(string: String) { self.init(string) }
    init(double: Double) { self.init(double) }
    init(bool: Bool) { self.init(bool) }
    init(null: Bool) { self.encode = { var c = $0.singleValueContainer(); try c.encodeNil() } }
    func encode(to encoder: Encoder) throws { try self.encode(encoder) }
}

extension JSONOutput {
    static func attributes(of item: LookinDisplayItem) -> [PublicAttribute] {
        let groups: [LookinAttributesGroup] = (item.attributesGroupList ?? []) + (item.customAttrGroupList ?? [])
        return groups.flatMap { group -> [PublicAttribute] in
            (group.attrSections ?? []).flatMap { section -> [PublicAttribute] in
                (section.attributes ?? []).map { attr -> PublicAttribute in
                    PublicAttribute(
                        group: group.userInfo?["title"] as? String ?? "",
                        section: section.identifier ?? "",
                        key: attr.identifier ?? "",
                        type: String(describing: attr.attrType),
                        value: encodeAttributeValue(attr)
                    )
                }
            }
        }
    }

    private static func encodeAttributeValue(_ attr: LookinAttribute) -> AnyEncodable {
        // Per LookinAttribute.h: value is a typed object based on attrType.
        // Cover the common cases; fall back to string description for others.
        if let str = attr.value as? String     { return AnyEncodable(string: str) }
        if let num = attr.value as? NSNumber   { return AnyEncodable(double: num.doubleValue) }
        // Other typed values (LookinColor, LookinShadow, ...) → string description.
        return AnyEncodable(string: "\(attr.value ?? "<nil>")")
    }
}
```

> **Implementation note:** the exact property names (`attributesGroupList`, `customAttrGroupList`, `attrSections`, `attributes`, `attrType`, `userInfo`) are based on upstream conventions; audit and correct against the vendored headers after Task 2.

- [ ] **Step 2:** Implement `Attributes.swift`:

```swift
import Foundation
import ArgumentParser
import LookinTransport
import LookinCore

struct Attributes: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "attributes",
        abstract: "Print all attribute groups for a single view, identified by --oid or --ax-id."
    )

    @OptionGroup var output: OutputOptions

    @Option(name: .long, help: "OID (hex string) returned by `lookin tree`.")
    var oid: String?

    @Option(name: .customLong("ax-id"), help: "accessibilityIdentifier.")
    var axId: String?

    func run() throws {
        guard let session = try Session.load() else {
            FileHandle.standardError.write(Data("No session. Run `lookin attach` first.\n".utf8))
            throw ExitCode.failure
        }
        guard oid != nil || axId != nil else {
            FileHandle.standardError.write(Data("Need --oid or --ax-id.\n".utf8))
            throw ExitCode.validationFailure
        }

        let result = try runAsync { try await Attributes.fetch(session: session, oid: oid, axId: axId) }

        struct Envelope: Encodable {
            let oid: String
            let `class`: String
            let attributes: [PublicAttribute]
        }
        let env = Envelope(
            oid: result.oid,
            class: result.className,
            attributes: result.attributes
        )
        try emit(env, options: output)
    }

    private static func fetch(session: Session, oid: String?, axId: String?) async throws
        -> (oid: String, className: String, attributes: [PublicAttribute])
    {
        let transport = PeertalkTransport(host: session.host, port: session.port)
        defer { Task { await transport.close() } }

        // Step 1: fetch full hierarchy (cheap request 202) to resolve OID/axId → DisplayItem.
        let lite = LookinConnectionAttachment()
        lite.dataType = LookinCodingValueTypeNumber
        lite.data = NSNumber(value: 0)
        let liteResp = try await transport.send(type: UInt32(LookinRequestTypeHierarchy), payload: lite)
        guard let info = liteResp.data as? LookinHierarchyInfo else {
            throw LookinTransportError.decodeFailed("no hierarchy")
        }
        let allItems = (info.displayItems ?? [])
        guard let target = allItems.first(where: { item in
            if let oid {
                let asHex = String(format: "0x%llx", UInt64(bitPattern: Int64(item.viewObject?.address ?? 0)))
                return asHex == oid
            }
            if let axId { return item.viewObject?.specialTrace == axId }
            return false
        }) else {
            throw LookinTransportError.decodeFailed("OID/axId not found in hierarchy")
        }

        // Step 2: fetch details (request 203) just for this OID. Upstream supports a "tasks" payload
        // listing which OIDs need detail packages. Audit LookinStaticAsyncUpdateTasksPackage.h
        // during Task 2 for the exact payload shape and adjust.
        // For the demo, we fall back to using the attributesGroupList already attached to `target`
        // from the hierarchy response if details aren't critical.

        let attrs = JSONOutput.attributes(of: target)
        let className = target.viewObject?.rawClassName ?? "<unknown>"
        let hex = String(format: "0x%llx", UInt64(bitPattern: Int64(target.viewObject?.address ?? 0)))
        return (hex, className, attrs)
    }
}
```

- [ ] **Step 2:** Build:

```bash
swift build
```

Expected: succeeds.

- [ ] **Step 3:** Commit.

```bash
git add Sources/LookinCLI/Commands/Attributes.swift Sources/LookinCLI/JSONOutput.swift
git commit -m "feat: lookin attributes"
```

---

## Task 14: `lookin find`

**Files:**

- Modify: `Sources/LookinCLI/Commands/Find.swift`

- [ ] **Step 1:** Implement client-side filter on a `tree` fetch:

```swift
import Foundation
import ArgumentParser
import LookinTransport
import LookinCore

struct Find: ParsableCommand {
    enum By: String, ExpressibleByArgument { case `class`, label, axId }

    static let configuration = CommandConfiguration(
        commandName: "find",
        abstract: "Find views by substring match on class, label, or accessibilityIdentifier."
    )

    @OptionGroup var output: OutputOptions

    @Argument(help: "Substring to match.") var query: String
    @Option(name: .long) var by: By = .class
    @Option(name: .long) var limit: Int = 20

    func run() throws {
        guard let session = try Session.load() else {
            FileHandle.standardError.write(Data("No session. Run `lookin attach` first.\n".utf8))
            throw ExitCode.failure
        }
        let matches = try runAsync { try await Find.search(session: session, query: query, by: by, limit: limit) }
        let nodes = matches.map { JSONOutput.encode($0, includeChildren: false, maxDepth: 0) }
        struct Envelope: Encodable { let count: Int; let matches: [PublicNode] }
        try emit(Envelope(count: nodes.count, matches: nodes), options: output)
    }

    private static func search(session: Session, query: String, by: By, limit: Int) async throws -> [LookinDisplayItem] {
        let transport = PeertalkTransport(host: session.host, port: session.port)
        defer { Task { await transport.close() } }
        let req = LookinConnectionAttachment()
        req.dataType = LookinCodingValueTypeNumber
        req.data = NSNumber(value: 0)
        let resp = try await transport.send(type: UInt32(LookinRequestTypeHierarchy), payload: req)
        guard let info = resp.data as? LookinHierarchyInfo else {
            throw LookinTransportError.decodeFailed("no hierarchy")
        }
        let items = info.displayItems ?? []
        let needle = query.lowercased()
        let filtered = items.filter { item in
            switch by {
            case .class:
                return (item.viewObject?.rawClassName ?? "").lowercased().contains(needle)
            case .label:
                return (item.viewObject?.displayTitle ?? "").lowercased().contains(needle)
            case .axId:
                return (item.viewObject?.specialTrace ?? "").lowercased().contains(needle)
            }
        }
        return Array(filtered.prefix(limit))
    }
}
```

- [ ] **Step 2:** Build + commit.

```bash
swift build
git add Sources/LookinCLI/Commands/Find.swift
git commit -m "feat: lookin find"
```

---

## Task 15: `lookin screenshot`

**Files:**

- Modify: `Sources/LookinCLI/Commands/Screenshot.swift`

- [ ] **Step 1:** Implement. Uses `LookinRequestTypeFetchImageViewImage = 208`. (Upstream uses 208 specifically for `UIImageView`-backed fetches; for general per-view rendering use the snapshot embedded in `LookinDisplayItem.soloScreenshot`, which is populated by request 203 details.)

```swift
import Foundation
import ArgumentParser
import LookinTransport
import LookinCore

struct Screenshot: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "screenshot",
        abstract: "Save a PNG of a single view (uses Lookin's rendered snapshot)."
    )

    @OptionGroup var output: OutputOptions

    @Option(name: .long, help: "OID of the view to capture.") var view: String?
    @Option(name: .long, help: "Output PNG path.") var out: String = "lookin-screenshot.png"

    func run() throws {
        guard let session = try Session.load() else {
            FileHandle.standardError.write(Data("No session. Run `lookin attach` first.\n".utf8))
            throw ExitCode.failure
        }
        guard let view else {
            FileHandle.standardError.write(Data("Need --view <oid>.\n".utf8))
            throw ExitCode.validationFailure
        }
        let png = try runAsync { try await Screenshot.fetch(session: session, oid: view) }
        try png.write(to: URL(fileURLWithPath: out))

        struct Result: Encodable { let path: String; let bytes: Int }
        try emit(Result(path: out, bytes: png.count), options: output)
    }

    private static func fetch(session: Session, oid: String) async throws -> Data {
        let transport = PeertalkTransport(host: session.host, port: session.port)
        defer { Task { await transport.close() } }
        let req = LookinConnectionAttachment()
        req.dataType = LookinCodingValueTypeNumber
        // Upstream passes a layer/view memory address as the payload number.
        let addr = UInt64(oid.dropFirst(2), radix: 16) ?? 0  // "0x...." → UInt64
        req.data = NSNumber(value: addr)
        let resp = try await transport.send(type: UInt32(LookinRequestTypeFetchImageViewImage), payload: req)
        guard let img = resp.data as? Data else {
            throw LookinTransportError.decodeFailed("screenshot response was not Data")
        }
        return img
    }
}
```

> **Implementation note:** confirm the exact payload shape for request 208 against upstream's `LKS_*RequestHandler.m`. The above is the simplest plausible shape (raw OID as `NSNumber`). If upstream wraps it in a struct, adjust.

- [ ] **Step 2:** Build + commit.

```bash
swift build
git add Sources/LookinCLI/Commands/Screenshot.swift
git commit -m "feat: lookin screenshot"
```

---

## Task 16: README and smoke-test docs

**Files:**

- Create: `README.md`

- [ ] **Step 1:** Write a focused README covering:
  - 90-second elevator: what it does, where it fits between AXe and Figma MCP.
  - Build/install: `swift build -c release && cp .build/release/lookin /usr/local/bin/`.
  - Quickstart against simulator (attach → tree → attributes).
  - Real-device path: `iproxy 47175 47175` recipe, then `lookin attach --device`.
  - Accessibility-identifier convention (`figma:<nodeId>`).
  - Known limitations: macOS only; demo route B only; no MCP yet; no diff yet.
  - Pointer to design doc and plan.

- [ ] **Step 2:** Commit.

```bash
git add README.md
git commit -m "docs: README with quickstart and limitations"
```

---

## Self-Review

After all tasks land, verify against the spec:

1. **§5 commands implemented?** attach (Task 11), tree (Task 12), attributes (Task 13), find (Task 14), screenshot (Task 15), doctor (Task 10) — yes.
2. **§9 JSON schema stable?** Yes — `PublicNode` / `PublicAttribute` in `JSONOutput.swift`.
3. **§10 acceptance criteria executable?** Yes — README covers the manual smoke test against a real LookinServer-integrated sim app.
4. **Vendor-source freedom guarded?** Pinned commit recorded in `docs/upstream/PINNED_COMMIT.md`, every patch logged in `docs/upstream/PATCHES.md`.
5. **Future evolution (route A) compatible?** Yes — `LookinTransport` protocol means a `HTTPTransport` can drop in without touching command code.

Known follow-ups (deferred per spec §12 / §13):

- `lookin diff` against Figma MCP
- `lookin verify <spec.yml>`
- MCP server wrapper
- Built-in usbmux forwarding via `pymobiledevice3`
