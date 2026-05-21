# lookin-cli

Tools like AXe, idb, and XcodeBuildMCP answer "what is interactable and where" by querying the iOS accessibility tree. That tree omits non-accessible decorative views, hides Auto Layout constraints, and exposes none of the render-time visual properties — `cornerRadius`, `shadow`, `font`, `transform`, custom view ivars. `lookin-cli` fills this gap by talking directly to LookinServer's peertalk wire protocol, extracting the real `UIView`/`CALayer` view tree including offscreen and decorative views, live frame data, and runtime attributes. Designed for Coding Agents (Claude Code, Cursor) that need to compare a running iOS app against a Figma design with structural precision.

## Status

Demo. Hybrid Route B (zero app change required). macOS only. Simulator-first; real-device path is supported via `iproxy` (see below).

## Requirements

- macOS 13+
- Swift 6.2 toolchain (pinned via `.swift-version`; the package manifest targets tools 5.9+)
- An iOS app embedding LookinServer (e.g., via CocoaPods or SPM), running on a booted Simulator

Tested against an iPhone 17 Pro simulator running a LookinServer-integrated app on port 47164.

## Build

```bash
swift build -c release
cp .build/release/lookin /usr/local/bin/   # optional
```

## Quickstart (simulator)

Run these in order. Each command prints JSON to stdout.

```bash
# 1. Sanity check — per-port LookinServer diagnostics
lookin doctor --pretty
# {"reachable":true,"reason":"ok","port":47164,"serverVersion":7,"probeMs":118,"ports":[...]}

# 2. Discover and save a session
lookin attach --pretty
# {"host":"127.0.0.1","port":47164,"target":"simulator","serverVersion":7,...}

# 3. Dump the full view hierarchy (3 levels deep)
lookin tree --depth 3 --pretty
# {"serverVersion":7,"windowCount":1,"roots":[{"oid":4325478400,"class":"UIWindow",...}]}

# 4. Find views by class name
lookin find UIButton --by class --limit 5 --pretty
# {"query":"UIButton","by":"class","matchCount":3,"results":[...]}

# 5. Inspect all attributes of a specific view
lookin attributes --oid 4325478400 --pretty
# {"oid":4325478400,"class":"UIWindow","attributeCount":42,"attributes":[...]}

# 6. Save a PNG snapshot of a view (no --pretty; writes file, prints path to stderr)
lookin screenshot --view 4325478400 --out /tmp/x.png
```

`--pretty` enables indented JSON output. Omit it for compact one-line JSON suitable for agent pipelines.

## Real-device path

For physical devices, forward the LookinServer port over USB before running any command:

```bash
iproxy 47175 47175   # run in a separate terminal, keep it alive
```

Then pass `--device` to any command:

```bash
lookin doctor --device --pretty
lookin attach --device --pretty
lookin tree --device --depth 2 --pretty
```

The device port scanner probes the range 47175–47179. Ensure the device is connected via USB and trusted, and that the app is running in Debug configuration.

## Convention: Figma node join key

If you set `view.accessibilityIdentifier = "figma:<nodeId>"` (or `"figma:<fileKey>:<nodeId>"`), the `figmaRef` field in `tree` and `find` output becomes a deterministic join key against the `node_id` values returned by `get_metadata` from the Figma MCP. Example:

```
// In Swift, somewhere during view setup:
myView.accessibilityIdentifier = "figma:1:234"
```

`lookin tree` output will then include `"figmaRef": "1:234"` on that node, which maps directly to Figma's node identifier. Without this convention, agents fall back to fuzzy class+label matching, which is slower and less reliable. This is the highest-leverage convention to ship when integrating the two tools.

## JSON output schema

Full shape is specified in §9 of the design doc (`docs/specs/2026-05-19-lookin-cli-design.md`). Key paths:

**`lookin tree` / `lookin find`**

```
roots[].{
  oid        UInt     -- stable object identity within this session
  class      String   -- UIView/CALayer subclass name
  axId       String?  -- accessibilityIdentifier (via LookinServer specialTrace)
  figmaRef   String?  -- set when axId starts with "figma:", stripped prefix
  frame      {x, y, width, height}
  alpha      Double
  hidden     Bool
  children   [...]
}
```

**`lookin attributes`**

```
attributes[].{
  group      String   -- LookinServer attribute group short code (e.g. "vl", "l")
  groupName  String?  -- decoded group label (e.g. "View & Layer"); null if unknown
  section    String   -- LookinServer attribute section identifier
  identifier String   -- LookinServer internal short code (e.g. "l_f_f", "c_c_c")
  name       String?  -- decoded human-readable label (e.g. "Corner Radius"); null if unknown
  attrType   Int      -- raw LookinAttrType enum value
  value      String | Number | Bool | {x,y,w,h} | {r,g,b,a} | null
}
```

All commands accept `--pretty` for human-readable output.

## lookin doctor

`doctor` probes the whole LookinServer port range concurrently and reports a
per-port diagnosis. The top-level `reason` field classifies the outcome:

| `reason`                      | Meaning                                                                                                                                                                                           |
| ----------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `ok`                          | A LookinServer answered the ping; `port` / `serverVersion` are set.                                                                                                                               |
| `no_listener`                 | Nothing is listening. LookinServer not linked, app not in Debug, or the app is not foreground-active yet — a system modal (e.g. the ATT prompt) delays the listener until the app becomes active. |
| `port_in_use_by_other_client` | A port is held by another client. LookinServer is single-client — the Lookin macOS app or another `lookin-cli` is connected. Detected when the socket is `established` rather than `listen`.      |
| `scan_timed_out`              | The scan exceeded its budget; the simulator/device may be unresponsive.                                                                                                                           |

The `ports[]` array carries per-port detail: `tcp` (`open`/`closed`), `socket`
(`listen`/`established`/`none`, from `lsof`), and `ping` (`ok`/`failed`/`skipped`).

## lookin measure

Reports the geometric relationship between two UI elements — gap, edge deltas, center offset, alignment, overlap, containment, and per-element box model — in a single screen-absolute coordinate space. This is the deterministic answer to "how far apart are these two views" that an agent would otherwise have to compute (incorrectly, across mismatched parent coordinate spaces) from raw `tree` output.

```bash
lookin measure <selectorA> <selectorB> [--tolerance <pt>] [--annotate <path>] [--pretty]
```

Each selector picks one element, in one of three forms:

| Selector           | Example             | Resolves by                                                                                                                                           |
| ------------------ | ------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------- |
| `oid:<n>`          | `oid:223`           | Object id from `tree` / `find` output.                                                                                                                |
| `point:<x>,<y>`    | `point:210,330`     | Screen-coordinate hit-test; the deepest (smallest) view containing the point.                                                                         |
| `axe:<AXUniqueId>` | `axe:submit-button` | Shells out to the `axe` CLI (`axe describe-ui`), finds the accessibility element, hit-tests its center. Soft dependency — only this form needs `axe`. |

Example — measure the gap between two list rows:

```bash
$ lookin measure point:210,330 point:210,440 --pretty
{
  "a": { "selector": "point:210,330", "oid": 312, "class": "...CGDrawingLayer",
         "absoluteFrame": [40, 289.33, 328.33, 42.33],
         "parent": { "oid": 305, "class": "_UICollectionViewListCellContentView" },
         "boxModel": { "top": 0, "left": 0, "right": 0, "bottom": 0 } },
  "b": { "selector": "point:210,440", "oid": 348, "class": "...CGDrawingLayer",
         "absoluteFrame": [40, 405.33, 328.33, 42.33], ... },
  "gap": { "vertical": 73.67 },
  "edges": { "leftToLeft": 0, "rightToRight": 0, "topToTop": 116,
             "bottomToBottom": 116, "aMaxYToBMinY": 73.67, "bMaxYToAMinY": -158.33 },
  "center": { "dx": 0, "dy": 116 },
  "alignment": { "left": true, "right": true, "centerX": true,
                 "top": false, "bottom": false, "centerY": false },
  "overlap": null,
  "containment": { "aInsideB": false, "bInsideA": false },
  "commonAncestor": { "oid": 41, "class": "SwiftUI.UpdateCoalescingCollectionView" },
  "coordinateModel": "frame-accumulation"
}
```

`--tolerance` (default `0.5`) is the points-of-slack for the `alignment` flags. `--annotate <path>` additionally writes a PNG with both elements outlined and the measured gap drawn as a labelled connector (see limitations below).

Absolute frames are computed by accumulating `frame.origin` down the view tree and subtracting each ancestor's `bounds.origin`, so the measurement is correct even when the two elements live under different scroll views.

## Known limitations

- **macOS only.** The Swift CLI uses Foundation's `NSKeyedUnarchiver` to decode LookinServer's `NSKeyedArchiver` wire format. This requires the same Objective-C runtime that encoded the data.

- **Demo Route B.** Relies on LookinServer's existing peertalk-based wire protocol without modifying the app. Pinned to upstream commit `985e8afe` on `release/1.2.7` — see `docs/upstream/PINNED_COMMIT.md`.

- **SwiftUI screens.** lookin's differentiator — the real `UIView`/`CALayer` tree with render-time properties (`cornerRadius`, `shadow`, `transform`, ivars) — is strongest on **UIKit-heavy** screens. SwiftUI renders `Text` / `Button` / shapes into anonymous `CGDrawingLayer` / `_UIGraphicsView` nodes: no text content, no control identity, and `cornerRadius` lives in a drawn path rather than `layer.cornerRadius`. On SwiftUI-heavy screens lookin's geometry largely overlaps an accessibility tree (`axe describe-ui`), and the differentiating attributes do not surface. Folding the a11y tree into `tree` output is planned follow-on work.

- **Attribute identifiers.** `lookin attributes` decodes LookinServer's internal short codes (`c_c_c`, `l_f_f`, …) into `name` / `groupName` labels via a static table, keeping the raw codes alongside for reference. User-custom attributes outside the known set fall back to `name: null`.

- **Screenshot reliability.** `lookin screenshot` works reliably for `UIImageView` (request 208) and for container views/layers (request 203 streaming). Bare `UILabel` and some leaf views may return empty data — LookinServer does not always materialize a solo snapshot for those nodes.

- **`axId` field.** Currently surfaces LookinServer's `displayTitle` via `specialTrace`, not the raw `accessibilityIdentifier` directly. If `displayTitle` already starts with `figma:`, `figmaRef` resolves correctly. A future pass will separate them.

- **No `lookin diff` yet.** The CLI exposes primitives only. A Figma MCP-backed diff command is planned as follow-on work.

- **No MCP wrapper yet.** Call the binary directly from your agent. Wrapping as an MCP server is deferred.

- **`measure` ignores ancestor transforms.** Absolute frames are computed by `frame.origin` accumulation. LookinServer does not serialize `CGAffineTransform` / `CATransform3D`, so a non-identity transform on any ancestor silently skews the result. The JSON reports `"coordinateModel": "frame-accumulation"` as a reminder. The common auto-layout / stack-view / scroll-view case is transform-free.

- **`measure --annotate` base image.** On a simulator the background is captured with `xcrun simctl io screenshot` (full pixel fidelity). On a real device it falls back to LookinServer's `groupScreenshot`, which cannot rasterize some SwiftUI-hosted windows (`renderInContext` yields blank) — for those the annotation draws on a blank canvas. The overlay geometry (outlines + gap connector + value pill) is accurate either way.

- **`axe:` selector coordinate space.** The `axe:` path hit-tests axe's accessibility-frame center against LookinServer's hierarchy. If axe's coordinate space differs from LookinServer's window space (e.g. the app's window size ≠ the device screen size), the hit-test may resolve to a coarser ancestor. `oid:` and `point:` are exact.

## Architecture

Three SPM targets: `LookinCLI` (ArgumentParser entrypoint, six commands), `LookinTransport` (Swift reimplementation of peertalk's 16-byte big-endian frame codec over `NWConnection`, port scanner, streaming support), and `LookinCore` (vendored Objective-C from `QMUI/LookinServer` — `LookinConnectionAttachment`, `LookinDisplayItem`, `LookinHierarchyInfo`, and related types — so `NSKeyedUnarchiver` can decode the wire payload natively). All commands flow `LookinCLI → Session → PeertalkTransport → live LookinServer in app → JSON to stdout`. A future `HTTPTransport` (Route A — adds a small HTTP/JSON sidecar inside a forked LookinServer) can drop in behind the same `LookinTransport` protocol without changes to command code.

## References

- Design doc (CLI): `docs/specs/2026-05-19-lookin-cli-design.md`
- Design doc (measure): `docs/specs/2026-05-20-lookin-measure-design.md`
- Implementation plan (CLI): `docs/plans/2026-05-19-lookin-cli-demo.md`
- Implementation plan (measure): `docs/plans/2026-05-20-lookin-measure.md`
- Upstream LookinServer: https://github.com/QMUI/LookinServer (MIT)
- Pinned commit: `docs/upstream/PINNED_COMMIT.md`
- Vendoring patches: `docs/upstream/PATCHES.md`

## License

MIT — see [`LICENSE`](LICENSE).

`Sources/LookinCore/` vendors source from [LookinServer](https://github.com/QMUI/LookinServer)
(© QMUI Team, MIT). Those files keep their original license headers.
