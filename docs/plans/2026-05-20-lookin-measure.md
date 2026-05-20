# lookin measure Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a `lookin measure <selectorA> <selectorB>` command that reports every pairwise geometric measurement between two UI elements in screen-absolute coordinates, with an optional annotated PNG.

**Architecture:** A new pure `Geometry` module does all CGRect math. A new shared `Hierarchy` model fetches the view tree once, indexes it by oid, builds an oid→parent map, and computes screen-absolute frames by top-down accumulation (`childAbs = parentAbs + child.frame.origin − parent.bounds.origin`). `Selector` resolves `oid:`/`point:`/`axe:` strings to a display item; the `axe:` path shells out to the `axe` CLI (soft dependency). `Measure` wires these together and emits JSON; with `--annotate` it fetches a window screenshot and draws the measurement with CoreGraphics.

**Tech Stack:** Swift 5.9, ArgumentParser, Foundation, CoreGraphics/AppKit (annotation), the existing `LookinTransport` + vendored `LookinCore`.

**Operating constraint:** A live iPhone 17 Pro simulator runs a LookinServer-integrated app. Note that LookinServer is single-client — the Lookin macOS app must be disconnected for the CLI to connect. Pure modules (`Geometry`, `Hierarchy`, `Selector`) are TDD'd with synthetic data; `Measure`/`AxeBridge`/`Annotation` are verified live.

---

## File map

```
Sources/LookinCLI/
├── Geometry.swift            NEW — pure CGRect measurement math + Encodable result types
├── Hierarchy.swift           NEW — fetch + oid index + oid→parent map + absoluteFrame + hitTest
├── Selector.swift            NEW — parse "scheme:value" + resolve to LookinDisplayItem
├── AxeBridge.swift           NEW — run `axe describe-ui`, parse accessibility JSON
├── Annotation.swift          NEW — render annotated PNG via CoreGraphics
├── Session.swift             MODIFIED — add optional simulatorUDID
├── Commands/
│   ├── Attach.swift          MODIFIED — resolve + store booted simulator UDID
│   └── Measure.swift         NEW — the command
└── main.swift                MODIFIED — register Measure subcommand

Tests/LookinCLITests/
├── GeometryTests.swift       NEW
├── HierarchyTests.swift      NEW
└── SelectorTests.swift       NEW
```

---

## Task 1: Geometry.swift — pure measurement math

**Files:**

- Create: `Sources/LookinCLI/Geometry.swift`
- Create: `Tests/LookinCLITests/GeometryTests.swift`

- [ ] **Step 1: Write the failing tests**

`Tests/LookinCLITests/GeometryTests.swift`:

```swift
import XCTest
import CoreGraphics
@testable import LookinCLI

final class GeometryTests: XCTestCase {
    // Two cells stacked vertically, 8pt apart, same x/width.
    let a = CGRect(x: 0, y: 452, width: 402, height: 87)
    let b = CGRect(x: 0, y: 547, width: 402, height: 87)

    func testVerticalGap() {
        let m = Geometry.measure(a: a, b: b, tolerance: 0.5)
        XCTAssertEqual(m.gap.vertical!, 8.0, accuracy: 0.001)
        XCTAssertNil(m.gap.horizontal)
    }

    func testTouchingEdgesGiveZeroGapNotOverlap() {
        let top = CGRect(x: 0, y: 0, width: 100, height: 50)
        let bottom = CGRect(x: 0, y: 50, width: 100, height: 50)
        let m = Geometry.measure(a: top, b: bottom, tolerance: 0.5)
        XCTAssertEqual(m.gap.vertical!, 0.0, accuracy: 0.001)
        XCTAssertNil(m.overlap)
    }

    func testEdges() {
        let m = Geometry.measure(a: a, b: b, tolerance: 0.5)
        XCTAssertEqual(m.edges.leftToLeft, 0, accuracy: 0.001)
        XCTAssertEqual(m.edges.rightToRight, 0, accuracy: 0.001)
        XCTAssertEqual(m.edges.topToTop, 95, accuracy: 0.001)
        XCTAssertEqual(m.edges.bottomToBottom, 95, accuracy: 0.001)
        XCTAssertEqual(m.edges.aMaxYToBMinY!, 8.0, accuracy: 0.001)
        XCTAssertEqual(m.edges.bMaxYToAMinY!, -182.0, accuracy: 0.001)
        XCTAssertNil(m.edges.aMaxXToBMinX)  // overlap on X
    }

    func testAlignment() {
        let m = Geometry.measure(a: a, b: b, tolerance: 0.5)
        XCTAssertTrue(m.alignment.left)
        XCTAssertTrue(m.alignment.right)
        XCTAssertTrue(m.alignment.centerX)
        XCTAssertFalse(m.alignment.top)
        XCTAssertFalse(m.alignment.centerY)
    }

    func testAlignmentTolerance() {
        let x1 = CGRect(x: 0, y: 0, width: 100, height: 10)
        let x2 = CGRect(x: 0.4, y: 50, width: 100, height: 10)  // 0.4pt off
        XCTAssertTrue(Geometry.measure(a: x1, b: x2, tolerance: 0.5).alignment.left)
        XCTAssertFalse(Geometry.measure(a: x1, b: x2, tolerance: 0.3).alignment.left)
    }

    func testOverlap() {
        let r1 = CGRect(x: 0, y: 0, width: 100, height: 100)
        let r2 = CGRect(x: 50, y: 50, width: 100, height: 100)
        let m = Geometry.measure(a: r1, b: r2, tolerance: 0.5)
        XCTAssertNotNil(m.overlap)
        XCTAssertEqual(m.overlap!.area, 2500, accuracy: 0.001)
        XCTAssertNil(m.gap.vertical)
        XCTAssertNil(m.gap.horizontal)
    }

    func testDisjointHasNoOverlap() {
        let m = Geometry.measure(a: a, b: b, tolerance: 0.5)
        XCTAssertNil(m.overlap)
    }

    func testContainment() {
        let outer = CGRect(x: 0, y: 0, width: 200, height: 200)
        let inner = CGRect(x: 50, y: 50, width: 50, height: 50)
        let m = Geometry.measure(a: outer, b: inner, tolerance: 0.5)
        XCTAssertTrue(m.containment.bInsideA)
        XCTAssertFalse(m.containment.aInsideB)
    }

    func testCenter() {
        let m = Geometry.measure(a: a, b: b, tolerance: 0.5)
        XCTAssertEqual(m.center.dx, 0, accuracy: 0.001)
        XCTAssertEqual(m.center.dy, 95, accuracy: 0.001)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter GeometryTests`
Expected: FAIL — `Geometry` is not defined.

- [ ] **Step 3: Write the implementation**

`Sources/LookinCLI/Geometry.swift`:

```swift
import Foundation
import CoreGraphics

// MARK: - Encodable result types

public struct GeometryResult: Encodable {
    public let gap: Gap
    public let edges: Edges
    public let center: Center
    public let alignment: Alignment
    public let overlap: Overlap?
    public let containment: Containment
}

public struct Gap: Encodable {
    public let vertical: Double?
    public let horizontal: Double?
}

public struct Edges: Encodable {
    public let leftToLeft: Double
    public let rightToRight: Double
    public let topToTop: Double
    public let bottomToBottom: Double
    public let aMaxXToBMinX: Double?
    public let aMaxYToBMinY: Double?
    public let bMaxXToAMinX: Double?
    public let bMaxYToAMinY: Double?
}

public struct Center: Encodable {
    public let dx: Double
    public let dy: Double
}

public struct Alignment: Encodable {
    public let left: Bool
    public let right: Bool
    public let top: Bool
    public let bottom: Bool
    public let centerX: Bool
    public let centerY: Bool
}

public struct Overlap: Encodable {
    public let rect: [Double]   // [x, y, w, h]
    public let area: Double
}

public struct Containment: Encodable {
    public let aInsideB: Bool
    public let bInsideA: Bool
}

// MARK: - Pure measurement

public enum Geometry {
    /// True iff the two rects' projections onto the X axis overlap.
    static func overlapsX(_ a: CGRect, _ b: CGRect) -> Bool {
        a.minX < b.maxX && b.minX < a.maxX
    }
    /// True iff the two rects' projections onto the Y axis overlap.
    static func overlapsY(_ a: CGRect, _ b: CGRect) -> Bool {
        a.minY < b.maxY && b.minY < a.maxY
    }

    public static func measure(a: CGRect, b: CGRect, tolerance: Double) -> GeometryResult {
        let tol = CGFloat(tolerance)

        // Gap: empty distance on the axis where the rects do NOT overlap.
        let vGap: Double? = overlapsY(a, b)
            ? nil
            : Double(max(a.minY, b.minY) - min(a.maxY, b.maxY))
        let hGap: Double? = overlapsX(a, b)
            ? nil
            : Double(max(a.minX, b.minX) - min(a.maxX, b.maxX))

        // Facing-edge deltas are only defined on the non-overlapping axis.
        let aMaxXToBMinX: Double? = overlapsX(a, b) ? nil : Double(b.minX - a.maxX)
        let bMaxXToAMinX: Double? = overlapsX(a, b) ? nil : Double(a.minX - b.maxX)
        let aMaxYToBMinY: Double? = overlapsY(a, b) ? nil : Double(b.minY - a.maxY)
        let bMaxYToAMinY: Double? = overlapsY(a, b) ? nil : Double(a.minY - b.maxY)

        let edges = Edges(
            leftToLeft: Double(b.minX - a.minX),
            rightToRight: Double(b.maxX - a.maxX),
            topToTop: Double(b.minY - a.minY),
            bottomToBottom: Double(b.maxY - a.maxY),
            aMaxXToBMinX: aMaxXToBMinX,
            aMaxYToBMinY: aMaxYToBMinY,
            bMaxXToAMinX: bMaxXToAMinX,
            bMaxYToAMinY: bMaxYToAMinY
        )

        let center = Center(dx: Double(b.midX - a.midX), dy: Double(b.midY - a.midY))

        let alignment = Alignment(
            left:    abs(b.minX - a.minX) <= tol,
            right:   abs(b.maxX - a.maxX) <= tol,
            top:     abs(b.minY - a.minY) <= tol,
            bottom:  abs(b.maxY - a.maxY) <= tol,
            centerX: abs(b.midX - a.midX) <= tol,
            centerY: abs(b.midY - a.midY) <= tol
        )

        let intersection = a.intersection(b)
        let overlap: Overlap? = (intersection.isNull || intersection.isEmpty)
            ? nil
            : Overlap(
                rect: [Double(intersection.minX), Double(intersection.minY),
                       Double(intersection.width), Double(intersection.height)],
                area: Double(intersection.width * intersection.height)
              )

        let containment = Containment(
            aInsideB: b.contains(a),
            bInsideA: a.contains(b)
        )

        return GeometryResult(
            gap: Gap(vertical: vGap, horizontal: hGap),
            edges: edges,
            center: center,
            alignment: alignment,
            overlap: overlap,
            containment: containment
        )
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter GeometryTests`
Expected: PASS — all 9 tests.

- [ ] **Step 5: Commit**

```bash
git add Sources/LookinCLI/Geometry.swift Tests/LookinCLITests/GeometryTests.swift
git -c user.email='shoujiaxin@gmail.com' -c user.name='Jiaxin Shou' commit -m "feat: pure CGRect measurement geometry"
```

---

## Task 2: Session.simulatorUDID + Attach populates it

**Files:**

- Modify: `Sources/LookinCLI/Session.swift`
- Modify: `Sources/LookinCLI/Commands/Attach.swift`

- [ ] **Step 1: Add the field to Session**

In `Sources/LookinCLI/Session.swift`, add a property after `capturedAt`:

```swift
    public var capturedAt: Date
    /// UDID of the booted simulator the app runs on. Optional: older session
    /// files decode with this as nil. Used by `measure`'s axe: selector path.
    public var simulatorUDID: String?
```

Because the property is optional, `JSONDecoder` tolerates its absence in older `session.json` files — no custom `init(from:)` needed.

- [ ] **Step 2: Add a booted-simulator UDID resolver to Attach**

In `Sources/LookinCLI/Commands/Attach.swift`, add this private static helper at the end of the `Attach` struct (before the closing brace):

```swift
    /// Returns the UDID of the first booted simulator, or nil if none / xcrun fails.
    /// For the demo we take the first booted device; if multiple simulators are
    /// booted this may not be the one hosting the app — documented in README.
    static func bootedSimulatorUDID() -> String? {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        proc.arguments = ["simctl", "list", "devices", "booted", "-j"]
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = Pipe()
        do { try proc.run() } catch { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        proc.waitUntilExit()
        guard proc.terminationStatus == 0,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let devices = json["devices"] as? [String: Any] else { return nil }
        for (_, runtimeDevices) in devices {
            guard let list = runtimeDevices as? [[String: Any]] else { continue }
            for device in list {
                if (device["state"] as? String) == "Booted",
                   let udid = device["udid"] as? String {
                    return udid
                }
            }
        }
        return nil
    }
```

- [ ] **Step 3: Store the UDID when building the Session**

In `Attach.swift`, find where the `Session(...)` value is constructed. Add the `simulatorUDID` argument:

```swift
        let session = Session(
            host: "127.0.0.1",
            port: port,
            target: device ? .device : .simulator,
            serverVersion: serverVersion,
            capturedAt: Date(),
            simulatorUDID: device ? nil : Attach.bootedSimulatorUDID()
        )
```

(Only resolve a UDID for the simulator target; a real device has none.)

- [ ] **Step 4: Build and run the existing Session test**

Run: `swift build && swift test --filter SessionTests`
Expected: PASS — `SessionTests.testRoundTrip` still passes (the new optional field round-trips as nil since the test constructs `Session` without it; if the test's `Session(...)` initializer call now fails to compile because of the new parameter, update the test to pass `simulatorUDID: nil`).

- [ ] **Step 5: Commit**

```bash
git add Sources/LookinCLI/Session.swift Sources/LookinCLI/Commands/Attach.swift Tests/LookinCLITests/SessionTests.swift
git -c user.email='shoujiaxin@gmail.com' -c user.name='Jiaxin Shou' commit -m "feat: record booted simulator UDID in session"
```

---

## Task 3: Hierarchy.swift — shared fetch + index + absolute frames

**Files:**

- Create: `Sources/LookinCLI/Hierarchy.swift`
- Create: `Tests/LookinCLITests/HierarchyTests.swift`

**Known API facts (from the existing codebase — use these exactly):**

- `LookinHierarchyInfo.displayItems` → `[LookinDisplayItem]?` (the root windows; each has nested `subitems`).
- `LookinHierarchyInfo.serverVersion` → `Int32`.
- `LookinDisplayItem.frame` / `.bounds` → `CGRect`; `.subitems` → `[LookinDisplayItem]?`; `.isHidden` → `Bool`; `.alpha` → `Float`.
- `LookinDisplayItem.viewObject` / `.layerObject` → `LookinObject?`.
- `LookinObject.oid` → `UInt`; `.rawClassName()` → `String`.
- A display item's public oid is `(viewObject ?? layerObject)?.oid` — same rule as `PublicNode`.
- `Tree.fetchHierarchy(session:)` already exists (`static`, internal) and returns `LookinHierarchyInfo`.

- [ ] **Step 1: Write the failing tests**

`Tests/LookinCLITests/HierarchyTests.swift`:

```swift
import XCTest
import CoreGraphics
import LookinCore
@testable import LookinCLI

final class HierarchyTests: XCTestCase {
    // Build a synthetic 3-level tree:
    //   root window (0,0,400,800)
    //     scrollView frame (0,100,400,500), bounds.origin (0,200)  [scrolled 200pt]
    //       cell frame (0,452,400,87)
    private func makeTree() -> LookinHierarchyInfo {
        func obj(_ oid: UInt, _ cls: String) -> LookinObject {
            let o = LookinObject()
            o.oid = oid
            o.setValue(cls, forKey: "rawClassNameValue")  // see note below
            return o
        }
        let cell = LookinDisplayItem()
        cell.frame = CGRect(x: 0, y: 452, width: 400, height: 87)
        cell.bounds = CGRect(x: 0, y: 0, width: 400, height: 87)
        cell.viewObject = obj(3, "Cell")

        let scroll = LookinDisplayItem()
        scroll.frame = CGRect(x: 0, y: 100, width: 400, height: 500)
        scroll.bounds = CGRect(x: 0, y: 200, width: 400, height: 500)
        scroll.viewObject = obj(2, "UIScrollView")
        scroll.subitems = [cell]

        let window = LookinDisplayItem()
        window.frame = CGRect(x: 0, y: 0, width: 400, height: 800)
        window.bounds = CGRect(x: 0, y: 0, width: 400, height: 800)
        window.viewObject = obj(1, "UIWindow")
        window.subitems = [scroll]

        let info = LookinHierarchyInfo()
        info.displayItems = [window]
        return info
    }

    func testIndexAndLookup() {
        let h = Hierarchy(info: makeTree())
        XCTAssertNotNil(h.item(oid: 3))
        XCTAssertEqual(h.parent(oid: 3)?.viewObject?.oid, 2)
        XCTAssertEqual(h.parent(oid: 2)?.viewObject?.oid, 1)
        XCTAssertNil(h.parent(oid: 1))
    }

    func testAbsoluteFrameAccountsForScrollOffset() {
        let h = Hierarchy(info: makeTree())
        // window abs origin (0,0).
        // scroll abs = (0,0) + (0,100) - window.bounds.origin(0,0) = (0,100)
        // cell  abs = (0,100) + (0,452) - scroll.bounds.origin(0,200) = (0,352)
        let cellAbs = h.absoluteFrame(oid: 3)
        XCTAssertNotNil(cellAbs)
        XCTAssertEqual(cellAbs!.origin.x, 0, accuracy: 0.001)
        XCTAssertEqual(cellAbs!.origin.y, 352, accuracy: 0.001)
        XCTAssertEqual(cellAbs!.size.width, 400, accuracy: 0.001)
        XCTAssertEqual(cellAbs!.size.height, 87, accuracy: 0.001)
    }

    func testHitTestReturnsDeepest() {
        let h = Hierarchy(info: makeTree())
        // point (10,360) is inside the cell's absolute frame (0,352,400,87).
        let hit = h.hitTest(point: CGPoint(x: 10, y: 360))
        XCTAssertEqual(hit?.viewObject?.oid, 3)
    }

    func testCommonAncestor() {
        let h = Hierarchy(info: makeTree())
        XCTAssertEqual(h.commonAncestorOid(3, 2), 2)
        XCTAssertEqual(h.commonAncestorOid(3, 3), 3)
    }
}
```

> **Note for the implementer:** `LookinObject.rawClassName()` is a _method_, and `rawClassName` may be backed by a private ivar/property. The test above uses a placeholder `setValue(_:forKey:)` — before writing the implementation, open `Sources/LookinCore/LookinObject.h` / `.m` and find the actual writable property that `rawClassName()` returns (likely a `classChainList` or a backing `NSString`). Adjust the `obj(_:_:)` helper so the synthetic objects carry a class name, OR drop class-name assertions from the tests if no writable hook exists (the Hierarchy logic does not depend on class names — only `commonAncestor`/`absoluteFrame`/`hitTest` do, and those use oids and frames). Keep the oid/frame/parent assertions; those are the load-bearing ones.

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter HierarchyTests`
Expected: FAIL — `Hierarchy` is not defined.

- [ ] **Step 3: Write the implementation**

`Sources/LookinCLI/Hierarchy.swift`:

```swift
import Foundation
import CoreGraphics
import LookinCore

/// Fetches the view hierarchy once and provides oid lookup, parent lookup,
/// and screen-absolute frame computation. Shared substrate for `measure`
/// (and a candidate for migrating tree/find/attributes onto later).
public final class Hierarchy {
    public let roots: [LookinDisplayItem]
    public let serverVersion: Int

    private var itemByOid: [UInt: LookinDisplayItem] = [:]
    private var parentByOid: [UInt: UInt] = [:]
    private var absoluteOriginByOid: [UInt: CGPoint] = [:]

    public init(info: LookinHierarchyInfo) {
        roots = info.displayItems ?? []
        serverVersion = Int(info.serverVersion)
        index()
    }

    /// Fetches and indexes the hierarchy from a live LookinServer.
    public static func fetch(session: Session) async throws -> Hierarchy {
        let info = try await Tree.fetchHierarchy(session: session)
        return Hierarchy(info: info)
    }

    /// The public oid of an item: the view's oid, or the layer's if view-less.
    public static func oid(of item: LookinDisplayItem) -> UInt? {
        if let v = item.viewObject { return v.oid }
        if let l = item.layerObject { return l.oid }
        return nil
    }

    public static func className(of item: LookinDisplayItem) -> String {
        (item.viewObject ?? item.layerObject)?.rawClassName() ?? "(unknown)"
    }

    private func index() {
        func visit(_ item: LookinDisplayItem, parentOid: UInt?, parentAbs: CGPoint, parentBoundsOrigin: CGPoint) {
            guard let id = Hierarchy.oid(of: item) else { return }
            itemByOid[id] = item
            let absOrigin: CGPoint
            if parentOid != nil {
                absOrigin = CGPoint(
                    x: parentAbs.x + item.frame.origin.x - parentBoundsOrigin.x,
                    y: parentAbs.y + item.frame.origin.y - parentBoundsOrigin.y
                )
            } else {
                absOrigin = item.frame.origin
            }
            if let parentOid { parentByOid[id] = parentOid }
            absoluteOriginByOid[id] = absOrigin
            for child in item.subitems ?? [] {
                visit(child, parentOid: id, parentAbs: absOrigin, parentBoundsOrigin: item.bounds.origin)
            }
        }
        for root in roots {
            visit(root, parentOid: nil, parentAbs: .zero, parentBoundsOrigin: .zero)
        }
    }

    public func item(oid: UInt) -> LookinDisplayItem? { itemByOid[oid] }

    public func parent(oid: UInt) -> LookinDisplayItem? {
        guard let pid = parentByOid[oid] else { return nil }
        return itemByOid[pid]
    }

    public func absoluteFrame(oid: UInt) -> CGRect? {
        guard let item = itemByOid[oid], let origin = absoluteOriginByOid[oid] else { return nil }
        return CGRect(origin: origin, size: item.frame.size)
    }

    /// Deepest (smallest-area) item whose absolute frame contains `point`.
    /// Hidden / fully transparent items are skipped unless `includeHidden`.
    public func hitTest(point: CGPoint, includeHidden: Bool = false) -> LookinDisplayItem? {
        var best: (item: LookinDisplayItem, area: CGFloat)?
        for (id, item) in itemByOid {
            if !includeHidden && (item.isHidden || item.alpha <= 0.01) { continue }
            guard let frame = absoluteFrame(oid: id), frame.contains(point) else { continue }
            let area = frame.width * frame.height
            if best == nil || area < best!.area {
                best = (item, area)
            }
        }
        return best?.item
    }

    /// Lowest oid that is an ancestor of (or equal to) both `a` and `b`.
    public func commonAncestorOid(_ a: UInt, _ b: UInt) -> UInt? {
        var ancestorsOfA: Set<UInt> = []
        var cur: UInt? = a
        while let c = cur {
            ancestorsOfA.insert(c)
            cur = parentByOid[c]
        }
        cur = b
        while let c = cur {
            if ancestorsOfA.contains(c) { return c }
            cur = parentByOid[c]
        }
        return nil
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter HierarchyTests`
Expected: PASS (after reconciling the synthetic-object class-name helper per the Step 1 note).

- [ ] **Step 5: Commit**

```bash
git add Sources/LookinCLI/Hierarchy.swift Tests/LookinCLITests/HierarchyTests.swift
git -c user.email='shoujiaxin@gmail.com' -c user.name='Jiaxin Shou' commit -m "feat: shared Hierarchy model with absolute-frame accumulation"
```

---

## Task 4: AxeBridge.swift — shell out to the axe CLI

**Files:**

- Create: `Sources/LookinCLI/AxeBridge.swift`

There is no unit test for this task — it shells out to an external binary. It is covered by live verification in Task 8.

- [ ] **Step 1: Write the implementation**

`Sources/LookinCLI/AxeBridge.swift`:

```swift
import Foundation
import CoreGraphics

public struct AxeElement {
    public let axId: String      // AXUniqueId
    public let frame: CGRect     // screen-space rect, in points
}

public enum AxeError: Error, CustomStringConvertible {
    case notInstalled
    case commandFailed(Int, String)
    case parseFailed(String)

    public var description: String {
        switch self {
        case .notInstalled:
            return "'axe' not found on PATH (needed for axe: selectors). Install cameroncooke/AXe."
        case .commandFailed(let code, let msg):
            return "axe exited \(code): \(msg)"
        case .parseFailed(let msg):
            return "could not parse axe output: \(msg)"
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

    public static var isInstalled: Bool { axePath() != nil }

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
               let h = (frame["height"] as? NSNumber)?.doubleValue {
                result.append(AxeElement(
                    axId: axId,
                    frame: CGRect(x: x, y: y, width: w, height: h)
                ))
            }
            if let children = node["children"] as? [[String: Any]] {
                for child in children { walk(child) }
            }
        }
        if let root = json as? [String: Any] {
            walk(root)
        } else if let roots = json as? [[String: Any]] {
            for r in roots { walk(r) }
        } else {
            throw AxeError.parseFailed("unexpected top-level JSON type")
        }
        return result
    }
}
```

> **Implementer note:** the exact JSON key names (`AXUniqueId`, `frame`, `frame.x/y/width/height`, `children`) come from prior research on AXe ≥ 1.7. Before relying on it, run `axe describe-ui --udid <the booted sim UDID>` once and confirm the keys. If axe uses `AXFrame` as a string or different child key, adjust `parse`. The rest of the design does not depend on these exact names.

- [ ] **Step 2: Build**

Run: `swift build`
Expected: succeeds.

- [ ] **Step 3: Commit**

```bash
git add Sources/LookinCLI/AxeBridge.swift
git -c user.email='shoujiaxin@gmail.com' -c user.name='Jiaxin Shou' commit -m "feat: AxeBridge — shell out to axe describe-ui"
```

---

## Task 5: Selector.swift — parse and resolve element selectors

**Files:**

- Create: `Sources/LookinCLI/Selector.swift`
- Create: `Tests/LookinCLITests/SelectorTests.swift`

- [ ] **Step 1: Write the failing tests**

`Tests/LookinCLITests/SelectorTests.swift`:

```swift
import XCTest
import CoreGraphics
@testable import LookinCLI

final class SelectorTests: XCTestCase {
    func testParseOid() throws {
        guard case .oid(let n) = try Selector.parse("oid:223") else {
            return XCTFail("expected .oid")
        }
        XCTAssertEqual(n, 223)
    }

    func testParsePoint() throws {
        guard case .point(let p) = try Selector.parse("point:32,92") else {
            return XCTFail("expected .point")
        }
        XCTAssertEqual(p.x, 32, accuracy: 0.001)
        XCTAssertEqual(p.y, 92, accuracy: 0.001)
    }

    func testParsePointWithSpaces() throws {
        guard case .point(let p) = try Selector.parse("point:32, 92") else {
            return XCTFail("expected .point")
        }
        XCTAssertEqual(p.y, 92, accuracy: 0.001)
    }

    func testParseAxe() throws {
        guard case .axe(let id) = try Selector.parse("axe:submit-button") else {
            return XCTFail("expected .axe")
        }
        XCTAssertEqual(id, "submit-button")
    }

    func testParseRejectsNoScheme() {
        XCTAssertThrowsError(try Selector.parse("223"))
    }

    func testParseRejectsUnknownScheme() {
        XCTAssertThrowsError(try Selector.parse("foo:bar"))
    }

    func testParseRejectsBadOid() {
        XCTAssertThrowsError(try Selector.parse("oid:notanumber"))
    }

    func testParseRejectsBadPoint() {
        XCTAssertThrowsError(try Selector.parse("point:1"))
        XCTAssertThrowsError(try Selector.parse("point:a,b"))
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter SelectorTests`
Expected: FAIL — `Selector` not defined.

- [ ] **Step 3: Write the implementation**

`Sources/LookinCLI/Selector.swift`:

```swift
import Foundation
import CoreGraphics
import LookinCore

public enum Selector: Equatable {
    case oid(UInt)
    case point(CGPoint)
    case axe(String)

    public static func parse(_ raw: String) throws -> Selector {
        guard let colon = raw.firstIndex(of: ":") else {
            throw SelectorError.badFormat(raw)
        }
        let scheme = String(raw[..<colon])
        let value = String(raw[raw.index(after: colon)...])
        switch scheme {
        case "oid":
            guard let n = UInt(value) else { throw SelectorError.badValue(raw) }
            return .oid(n)
        case "point":
            let parts = value.split(separator: ",")
            guard parts.count == 2,
                  let x = Double(parts[0].trimmingCharacters(in: .whitespaces)),
                  let y = Double(parts[1].trimmingCharacters(in: .whitespaces))
            else { throw SelectorError.badValue(raw) }
            return .point(CGPoint(x: x, y: y))
        case "axe":
            guard !value.isEmpty else { throw SelectorError.badValue(raw) }
            return .axe(value)
        default:
            throw SelectorError.badFormat(raw)
        }
    }
}

public enum SelectorError: Error, CustomStringConvertible {
    case badFormat(String)
    case badValue(String)
    case noMatch(String)
    case axeNotInstalled
    case noSimulatorUDID

    public var description: String {
        switch self {
        case .badFormat(let r):
            return "bad selector '\(r)': expected oid:<n>, point:<x>,<y>, or axe:<id>"
        case .badValue(let r):
            return "bad selector value '\(r)'"
        case .noMatch(let r):
            return "selector '\(r)' matched no element"
        case .axeNotInstalled:
            return "'axe' not found on PATH (needed for axe: selectors)"
        case .noSimulatorUDID:
            return "session has no simulator UDID; re-run `lookin attach`"
        }
    }
}

public struct ResolvedElement {
    public let raw: String                 // the original selector string
    public let item: LookinDisplayItem
    public let oid: UInt
}

/// Resolves a parsed selector to a concrete display item within `hierarchy`.
/// The axe: path shells out to the axe CLI (soft dependency).
public func resolveSelector(
    raw: String,
    selector: Selector,
    hierarchy: Hierarchy,
    session: Session
) throws -> ResolvedElement {
    switch selector {
    case .oid(let n):
        guard let item = hierarchy.item(oid: n) else {
            throw SelectorError.noMatch(raw)
        }
        return ResolvedElement(raw: raw, item: item, oid: n)

    case .point(let p):
        guard let item = hierarchy.hitTest(point: p),
              let oid = Hierarchy.oid(of: item) else {
            throw SelectorError.noMatch(raw)
        }
        return ResolvedElement(raw: raw, item: item, oid: oid)

    case .axe(let axId):
        guard AxeBridge.isInstalled else { throw SelectorError.axeNotInstalled }
        guard let udid = session.simulatorUDID else { throw SelectorError.noSimulatorUDID }
        let elements = try AxeBridge.describeUI(udid: udid)
        guard let el = elements.first(where: { $0.axId == axId }) else {
            throw SelectorError.noMatch(raw)
        }
        let center = CGPoint(x: el.frame.midX, y: el.frame.midY)
        guard let item = hierarchy.hitTest(point: center),
              let oid = Hierarchy.oid(of: item) else {
            throw SelectorError.noMatch("\(raw) (no view at \(center))")
        }
        return ResolvedElement(raw: raw, item: item, oid: oid)
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter SelectorTests`
Expected: PASS — all 8 tests.

- [ ] **Step 5: Commit**

```bash
git add Sources/LookinCLI/Selector.swift Tests/LookinCLITests/SelectorTests.swift
git -c user.email='shoujiaxin@gmail.com' -c user.name='Jiaxin Shou' commit -m "feat: element selectors (oid/point/axe) with resolution"
```

---

## Task 6: Annotation.swift — render the annotated PNG

**Files:**

- Create: `Sources/LookinCLI/Annotation.swift`

No unit test — image rendering is verified visually in Task 8. **Expect to iterate on this once against a real screenshot.**

- [ ] **Step 1: Write the implementation**

`Sources/LookinCLI/Annotation.swift`:

```swift
import Foundation
import CoreGraphics
import AppKit

public enum AnnotationError: Error, CustomStringConvertible {
    case badImage
    case contextFailed
    case encodeFailed

    public var description: String {
        switch self {
        case .badImage:      return "could not decode window screenshot"
        case .contextFailed: return "could not create drawing context"
        case .encodeFailed:  return "could not encode annotated PNG"
        }
    }
}

public enum Annotation {
    /// Draws element outlines + the measured gap onto a window screenshot.
    /// - pngData: full-window screenshot (device-pixel resolution).
    /// - windowPointWidth: the window's width in points (to derive the scale).
    /// - a / b: the two elements' absolute frames, in points.
    public static func render(
        pngData: Data,
        windowPointWidth: CGFloat,
        a: CGRect,
        b: CGRect,
        result: GeometryResult,
        to path: String
    ) throws {
        guard let rep = NSBitmapImageRep(data: pngData) else { throw AnnotationError.badImage }
        let pixelW = CGFloat(rep.pixelsWide)
        let pixelH = CGFloat(rep.pixelsHigh)
        let scale = pixelW / windowPointWidth

        let canvas = NSImage(size: NSSize(width: pixelW, height: pixelH))
        canvas.addRepresentation(rep)

        let outRep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: rep.pixelsWide, pixelsHigh: rep.pixelsHigh,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        )!
        guard let ctx = NSGraphicsContext(bitmapImageRep: outRep) else {
            throw AnnotationError.contextFailed
        }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = ctx

        // Base screenshot.
        rep.draw(in: NSRect(x: 0, y: 0, width: pixelW, height: pixelH))

        // Point-space (top-left origin) -> pixel-space (bottom-left origin).
        func px(_ r: CGRect) -> NSRect {
            NSRect(x: r.minX * scale,
                   y: pixelH - (r.maxY * scale),
                   width: r.width * scale,
                   height: r.height * scale)
        }

        let blue = NSColor(calibratedRed: 0.04, green: 0.52, blue: 1.0, alpha: 1)
        let orange = NSColor(calibratedRed: 0.95, green: 0.55, blue: 0.05, alpha: 1)

        let pa = px(a), pb = px(b)
        blue.setStroke()
        let pathA = NSBezierPath(rect: pa); pathA.lineWidth = 2 * scale; pathA.stroke()
        orange.setStroke()
        let pathB = NSBezierPath(rect: pb); pathB.lineWidth = 2 * scale; pathB.stroke()

        // Gap connector + label.
        if let v = result.gap.vertical {
            drawGapLabel(value: v, axis: .vertical, a: pa, b: pb,
                         pixelH: pixelH, scale: scale, color: orange)
        } else if let h = result.gap.horizontal {
            drawGapLabel(value: h, axis: .horizontal, a: pa, b: pb,
                         pixelH: pixelH, scale: scale, color: orange)
        }

        NSGraphicsContext.restoreGraphicsState()

        guard let png = outRep.representation(using: .png, properties: [:]) else {
            throw AnnotationError.encodeFailed
        }
        try png.write(to: URL(fileURLWithPath: path))
    }

    private enum Axis { case vertical, horizontal }

    /// Draws a connector line across the empty gap with a filled "pill" label,
    /// mirroring the reference annotation style.
    private static func drawGapLabel(
        value: Double, axis: Axis, a: NSRect, b: NSRect,
        pixelH: CGFloat, scale: CGFloat, color: NSColor
    ) {
        color.setStroke()
        color.setFill()
        let line = NSBezierPath()
        line.lineWidth = max(1, 1.5 * scale)

        let label = String(format: value == value.rounded() ? "%.0f" : "%.1f", value)
        let font = NSFont.boldSystemFont(ofSize: 13 * scale)
        let textAttrs: [NSAttributedString.Key: Any] = [
            .font: font, .foregroundColor: NSColor.white
        ]
        let textSize = (label as NSString).size(withAttributes: textAttrs)
        let padX = 10 * scale, padY = 5 * scale
        let pillW = textSize.width + padX * 2
        let pillH = textSize.height + padY * 2

        let pillCenter: NSPoint
        switch axis {
        case .vertical:
            // a is one rect, b the other; the gap is between min(maxY) and max(minY)
            // in pixel space (remember pixel Y is flipped).
            let topRectBottom = min(a.minY, b.minY)
            let bottomRectTop = max(a.maxY, b.maxY)
            let midX = (a.midX + b.midX) / 2
            line.move(to: NSPoint(x: midX, y: topRectBottom))
            line.line(to: NSPoint(x: midX, y: bottomRectTop))
            line.stroke()
            pillCenter = NSPoint(x: midX, y: (topRectBottom + bottomRectTop) / 2)
        case .horizontal:
            let leftRectRight = min(a.maxX, b.maxX)
            let rightRectLeft = max(a.minX, b.minX)
            let midY = (a.midY + b.midY) / 2
            line.move(to: NSPoint(x: leftRectRight, y: midY))
            line.line(to: NSPoint(x: rightRectLeft, y: midY))
            line.stroke()
            pillCenter = NSPoint(x: (leftRectRight + rightRectLeft) / 2, y: midY)
        }

        let pill = NSRect(
            x: pillCenter.x - pillW / 2, y: pillCenter.y - pillH / 2,
            width: pillW, height: pillH
        )
        let pillPath = NSBezierPath(roundedRect: pill, xRadius: pillH / 2, yRadius: pillH / 2)
        pillPath.fill()
        (label as NSString).draw(
            at: NSPoint(x: pill.minX + padX, y: pill.minY + padY),
            withAttributes: textAttrs
        )
    }
}
```

- [ ] **Step 2: Build**

Run: `swift build`
Expected: succeeds.

- [ ] **Step 3: Commit**

```bash
git add Sources/LookinCLI/Annotation.swift
git -c user.email='shoujiaxin@gmail.com' -c user.name='Jiaxin Shou' commit -m "feat: Annotation — render measured gap onto a screenshot"
```

---

## Task 7: Measure.swift — the command

**Files:**

- Create: `Sources/LookinCLI/Commands/Measure.swift`
- Modify: `Sources/LookinCLI/main.swift`

**Known API facts:**

- `Screenshot.fetchScreenshot(session:viewOid:)` exists (`static`, returns `Data?` — a PNG) and works for container/window OIDs via request 203. Reuse it for the window screenshot.
- `loadSession()`, `runAsync(_:)`, `emit(_:options:)`, `exitSuccess()`, `OutputOptions` all exist in `OutputFormat.swift`.
- `Hierarchy.className(of:)` returns the class name string.

- [ ] **Step 1: Write the implementation**

`Sources/LookinCLI/Commands/Measure.swift`:

```swift
import Foundation
import CoreGraphics
import ArgumentParser
import LookinCore

struct Measure: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "measure",
        abstract: "Measure the geometric relationship between two UI elements."
    )

    @OptionGroup var output: OutputOptions

    @Argument(help: "First element selector: oid:<n> | point:<x>,<y> | axe:<id>")
    var selectorA: String

    @Argument(help: "Second element selector: oid:<n> | point:<x>,<y> | axe:<id>")
    var selectorB: String

    @Option(name: .long, help: "Alignment tolerance in points (default: 0.5).")
    var tolerance: Double = 0.5

    @Option(name: .long, help: "Also write an annotated PNG to this path.")
    var annotate: String?

    // MARK: Encodable report

    struct ElementReport: Encodable {
        let selector: String
        let oid: UInt
        let `class`: String
        let absoluteFrame: [Double]
        let parent: ParentRef?
        let boxModel: BoxModel?
    }
    struct ParentRef: Encodable { let oid: UInt; let `class`: String }
    struct BoxModel: Encodable {
        let top: Double; let left: Double; let right: Double; let bottom: Double
    }
    struct Report: Encodable {
        let a: ElementReport
        let b: ElementReport
        let gap: Gap
        let edges: Edges
        let center: Center
        let alignment: Alignment
        let overlap: Overlap?
        let containment: Containment
        let commonAncestor: ParentRef?
        let coordinateModel: String
        var annotated: String?
    }

    func run() throws {
        let session = try loadSession()

        let selA = try Selector.parse(selectorA)
        let selB = try Selector.parse(selectorB)

        let report = try runAsync { () -> Report in
            let hierarchy = try await Hierarchy.fetch(session: session)
            let a = try resolveSelector(raw: selectorA, selector: selA,
                                        hierarchy: hierarchy, session: session)
            let b = try resolveSelector(raw: selectorB, selector: selB,
                                        hierarchy: hierarchy, session: session)
            if a.oid == b.oid {
                throw MeasureError.sameElement(a.oid)
            }
            guard let frameA = hierarchy.absoluteFrame(oid: a.oid),
                  let frameB = hierarchy.absoluteFrame(oid: b.oid) else {
                throw MeasureError.noAbsoluteFrame
            }

            let geo = Geometry.measure(a: frameA, b: frameB, tolerance: tolerance)

            var rep = Report(
                a: Measure.elementReport(a, hierarchy: hierarchy),
                b: Measure.elementReport(b, hierarchy: hierarchy),
                gap: geo.gap, edges: geo.edges, center: geo.center,
                alignment: geo.alignment, overlap: geo.overlap,
                containment: geo.containment,
                commonAncestor: Measure.commonAncestorRef(a.oid, b.oid, hierarchy: hierarchy),
                coordinateModel: "frame-accumulation",
                annotated: nil
            )

            if let annotatePath = annotate {
                do {
                    try await Measure.annotate(
                        session: session, hierarchy: hierarchy,
                        frameA: frameA, frameB: frameB, result: geo, to: annotatePath
                    )
                    rep.annotated = annotatePath
                } catch {
                    FileHandle.standardError.write(
                        Data("warning: annotation failed: \(error)\n".utf8))
                }
            }
            return rep
        }

        try emit(report, options: output)
        exitSuccess()
    }

    // MARK: Helpers

    private static func elementReport(
        _ el: ResolvedElement, hierarchy: Hierarchy
    ) -> ElementReport {
        let absFrame = hierarchy.absoluteFrame(oid: el.oid) ?? .zero
        let parentItem = hierarchy.parent(oid: el.oid)
        let parentRef: ParentRef? = parentItem.flatMap { p in
            Hierarchy.oid(of: p).map {
                ParentRef(oid: $0, class: Hierarchy.className(of: p))
            }
        }
        var box: BoxModel?
        if let p = parentItem {
            let f = el.item.frame
            let pb = p.bounds
            box = BoxModel(
                top: Double(f.minY - pb.minY),
                left: Double(f.minX - pb.minX),
                right: Double(pb.maxX - f.maxX),
                bottom: Double(pb.maxY - f.maxY)
            )
        }
        return ElementReport(
            selector: el.raw,
            oid: el.oid,
            class: Hierarchy.className(of: el.item),
            absoluteFrame: [Double(absFrame.minX), Double(absFrame.minY),
                            Double(absFrame.width), Double(absFrame.height)],
            parent: parentRef,
            boxModel: box
        )
    }

    private static func commonAncestorRef(
        _ a: UInt, _ b: UInt, hierarchy: Hierarchy
    ) -> ParentRef? {
        guard let oid = hierarchy.commonAncestorOid(a, b),
              let item = hierarchy.item(oid: oid) else { return nil }
        return ParentRef(oid: oid, class: Hierarchy.className(of: item))
    }

    /// Fetches a window screenshot and renders the annotation.
    private static func annotate(
        session: Session, hierarchy: Hierarchy,
        frameA: CGRect, frameB: CGRect, result: GeometryResult, to path: String
    ) async throws {
        // Use the first root window as the screenshot subject.
        guard let window = hierarchy.roots.first,
              let windowOid = Hierarchy.oid(of: window) else {
            throw MeasureError.noWindow
        }
        guard let png = try await Screenshot.fetchScreenshot(
            session: session, viewOid: windowOid
        ) else {
            throw MeasureError.screenshotFailed
        }
        try Annotation.render(
            pngData: png,
            windowPointWidth: window.frame.width,
            a: frameA, b: frameB, result: result, to: path
        )
    }
}

enum MeasureError: Error, CustomStringConvertible {
    case sameElement(UInt)
    case noAbsoluteFrame
    case noWindow
    case screenshotFailed

    var description: String {
        switch self {
        case .sameElement(let n):
            return "both selectors resolved to the same element (oid \(n))"
        case .noAbsoluteFrame:
            return "could not compute absolute frame for an element"
        case .noWindow:
            return "no root window in hierarchy"
        case .screenshotFailed:
            return "window screenshot fetch returned no data"
        }
    }
}
```

- [ ] **Step 2: Register the subcommand**

In `Sources/LookinCLI/main.swift`, add `Measure.self` to the `subcommands` array of the root `Lookin` command. The line currently lists `Attach, Tree, Attributes, Find, Screenshot, Doctor`; add `Measure`:

```swift
        subcommands: [Attach.self, Tree.self, Attributes.self, Find.self,
                      Screenshot.self, Doctor.self, Measure.self]
```

- [ ] **Step 3: Build**

Run: `swift build`
Expected: succeeds. If `Screenshot.fetchScreenshot` has a different signature than `static func fetchScreenshot(session:viewOid:) async throws -> Data?`, open `Sources/LookinCLI/Commands/Screenshot.swift` and adjust the call in `Measure.annotate` to match.

- [ ] **Step 4: Verify help**

Run: `swift run lookin measure --help`
Expected: shows the two selector arguments, `--tolerance`, `--annotate`, `--pretty`.

- [ ] **Step 5: Commit**

```bash
git add Sources/LookinCLI/Commands/Measure.swift Sources/LookinCLI/main.swift
git -c user.email='shoujiaxin@gmail.com' -c user.name='Jiaxin Shou' commit -m "feat: lookin measure command"
```

---

## Task 8: README + live verification

**Files:**

- Modify: `README.md`

- [ ] **Step 1: Live-verify against the running simulator**

Ensure the Lookin macOS app is disconnected (LookinServer is single-client). Then run, in order:

```bash
swift build -c release
.build/release/lookin attach
.build/release/lookin find ScheduledCardCell --by class --limit 5
```

Pick two adjacent cell OIDs from the `find` output (call them `<A>` and `<B>`). Then:

```bash
.build/release/lookin measure oid:<A> oid:<B> --pretty
```

Confirm against the §13 acceptance criteria of the spec:

1. JSON has the schema from spec §7.
2. `gap.vertical` equals the hand-computed value (for the known cells it is `8.0`).
3. `alignment.left`, `alignment.right`, `alignment.centerX` are `true`.

Then verify the `point:` path resolves the same cells (use a coordinate inside each cell — read each cell's `absoluteFrame` from the JSON above and pick its center):

```bash
.build/release/lookin measure point:<ax>,<ay> point:<bx>,<by> --pretty
```

Confirm the gap matches the `oid:` result.

Then the annotation:

```bash
.build/release/lookin measure oid:<A> oid:<B> --annotate /tmp/measure.png
file /tmp/measure.png        # must report: PNG image data
```

Then the axe path (if `axe` is installed):

```bash
which axe && .build/release/lookin measure axe:<someAxId> oid:<B> --pretty
```

If any command fails, fix the implementation, rebuild, re-run. Record the actual `measure oid:<A> oid:<B>` JSON output — it goes in the README.

- [ ] **Step 2: Update the README**

Add a `## lookin measure` section to `README.md`, placed after the existing command documentation. Include:

- One sentence: measures gap / alignment / overlap / containment / box model between two elements in screen-absolute coordinates.
- The selector syntax table (`oid:` / `point:` / `axe:`).
- The verified `measure oid:<A> oid:<B> --pretty` command and its real JSON output captured in Step 1.
- The `--annotate` and `--tolerance` options.
- Add to the existing **Known limitations** list:
  - `measure` cannot correct for ancestor `CGAffineTransform` / `CATransform3D` — LookinServer does not serialize transforms; measurement assumes a transform-free ancestor chain.
  - The `axe:` selector needs the `axe` CLI on PATH and works on Simulator only.
  - If multiple simulators are booted, `attach` records the first booted UDID, which may not host the app under test.

- [ ] **Step 3: Commit**

```bash
git add README.md
git -c user.email='shoujiaxin@gmail.com' -c user.name='Jiaxin Shou' commit -m "docs: document lookin measure"
```

---

## Self-Review

Run after all tasks land, against the spec (`2026-05-20-lookin-measure-design.md`):

1. **§3 command surface** — Task 7 (`measure`, two selector args, `--annotate`, `--tolerance`, `--pretty`). ✓
2. **§4 selectors** — Task 5 (`Selector.parse` + `resolveSelector`), axe path in Task 4. ✓
3. **§5 coordinate model** — Task 3 (`Hierarchy` absolute-frame accumulation with `bounds.origin`). ✓
4. **§6 measurements** — Task 1 (`Geometry.measure`: gap, edges, center, alignment, overlap, containment); box model in Task 7 (`elementReport`). ✓
5. **§7 JSON schema** — Task 7 (`Report` struct). ✓
6. **§8 annotation** — Task 6 (`Annotation.render`) + Task 7 (`Measure.annotate`). ✓
7. **§9 session change** — Task 2 (`Session.simulatorUDID` + `Attach`). ✓
8. **§10 architecture / files** — all new files created; existing commands not migrated. ✓
9. **§11 error handling** — `SelectorError`, `MeasureError`, `AxeError`, annotation-failure-is-non-fatal in Task 7. ✓
10. **§12 testing** — `GeometryTests`, `HierarchyTests`, `SelectorTests`; live verification in Task 8. ✓
11. **§13 acceptance** — exercised in Task 8 Step 1. ✓

Known deferred items (spec §14): `lookin diff`, migrating other commands onto `Hierarchy`, transform-aware coordinates.
