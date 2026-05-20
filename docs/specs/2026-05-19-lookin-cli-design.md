# lookin-cli — Design Doc

**Date:** 2026-05-19
**Status:** Implemented
**Owner:** shoujiaxin@gmail.com

## 1. Problem

Coding Agents (Claude Code, Cursor) building iOS UI today cannot reliably compare a running app against a Figma design. Screenshot-only comparison is slow and imprecise. The existing AI-friendly iOS tooling (`AXe`, `idb`, XcodeBuildMCP) only surfaces the accessibility tree from FBSimulator — that tree omits non-accessible decorative views, hides Auto Layout constraints, and exposes none of the render-time visual properties (`cornerRadius`, `shadow`, `font`, `transform`, custom view ivars). Real device is also out of scope for those tools.

The host app already integrates **LookinServer** (QMUI's debug runtime, MIT). LookinServer holds exactly the data the agent needs — real `UIView`/`CALayer` frames, Auto Layout, runtime attributes, custom debug info — but its only consumer today is the Lookin macOS GUI client. We need a CLI that turns this runtime into an agent-friendly data source.

## 2. Non-goals

- Replacing AXe / idb / XcodeBuildMCP for sim lifecycle, HID, screenshots of full screens, or "what's interactable here" queries. We delegate to them.
- Wrapping the CLI as an MCP server (deferred to a follow-up).
- Modifying upstream LookinServer in the demo phase (Hybrid path: zero app change for B; route A revisits this later).
- Cross-platform CLI hosts. macOS only.

## 3. Architectural strategy — Hybrid (B now, A later)

Two coexisting transports behind a single `LookinTransport` protocol:

- **Route B — `PeertalkTransport` (demo, zero app change).** Swift implementation of LookinServer's existing wire protocol. Talks directly to unmodified `LookinServer` in the running app via local TCP loopback (simulator) or `iproxy`-forwarded TCP (real device).
- **Route A — `HTTPTransport` (future, requires app fork).** A `LKS_HTTPServer` is added inside a fork of LookinServer; reuses `LookinHierarchyInfo` / `LKS_AttrGroupsMaker` and serves JSON over loopback. CLI becomes a thin HTTP client.

The CLI does **not** ship Route A in the demo. The protocol abstraction exists so we can drop in `HTTPTransport` without touching command code.

```
+---------+    LookinCommand     +-----------+   LookinTransport    +---------------------------+
|   CLI   |--------------------->|  Session  |--------------------->| PeertalkTransport (demo)  |
+---------+                      +-----------+                      | HTTPTransport (future)    |
                                                                    +---------------------------+
                                                                                |
                                                                                v
                                                                       LookinServer in iOS app
```

## 4. Transport (Route B) — technical detail

### 4.1 Peertalk framing

LookinServer uses a vendored peertalk. Frame header is 16 bytes big-endian: `{ uint32 version=1, uint32 type, uint32 tag, uint32 payloadSize }`, followed by `payloadSize` bytes. This is trivial to implement in pure Swift over `NWConnection` — about 100 LOC. We do **not** vendor the peertalk ObjC code.

### 4.2 Payload — `NSKeyedArchiver` compatibility

Payload is an `NSKeyedArchiver`-encoded `LookinConnectionAttachment { LookinCodingValueType dataType; id data }`, where `data` is a graph of `LookinHierarchyInfo` → `LookinDisplayItem` → `LookinAttributesGroup` → `LookinAttribute` → `LookinAttributeValue*` etc., plus `LookinObject`, `LookinAutoLayoutConstraint`, `LookinIvarTrace`, `LookinStaticAsyncUpdateTasksPackage`.

We vendor the header + implementation files from `LookinServer/Src/Main/Shared/` for these types **as Objective-C sources inside an SPM target**:

- `LookinConnectionAttachment.{h,m}`
- `LookinDisplayItem.{h,m}`
- `LookinHierarchyInfo.{h,m}`
- `LookinObject.{h,m}`
- `LookinAttribute.{h,m}` + `LookinAttributesGroup.{h,m}` + `LookinAttributesSection.{h,m}`
- `LookinAutoLayoutConstraint.{h,m}`
- `LookinIvarTrace.{h,m}`
- `LookinDefines.h` (request type enum, port ranges, version constant)
- A few supporting value types as needed (`LookinColor`, `LookinShadow`, `LookinTransform3D`, etc.)

These compile in macOS Foundation; they don't touch UIKit/CALayer directly on the macOS side because we only **decode** them, never **construct from a live view**. (Spot-check at implementation time: a few may transitively import `UIKit`. For those we either: (a) gate their UIKit-only methods with `#if TARGET_OS_IOS`, or (b) provide thin macOS stubs. Decided per file when we hit them.)

Rationale: NSKeyedUnarchiver requires real class objects with the right `+supportsSecureCoding`, `initWithCoder:`, and ivar layout. Reimplementing in Swift is harder than vendoring 8-10 small ObjC files.

### 4.3 Connection

- **Simulator:** scan loopback ports 47164–47169.
- **Device:** assume user has run `iproxy <local-port> 47175 <UDID>` (or `pymobiledevice3 usbmux forward`). CLI does `--port` override.
- **Handshake:** send `LookinRequestTypePing (200)` with `LookinClientVersion=7`. Validate server version returned. Single retry on cold start (app may not have hit `applicationDidBecomeActive` yet).

### 4.4 Versioning

Pin `LookinClientVersion=7`. On mismatch (`-600` / `-601` errors), surface a clear message and exit non-zero. Cite the upstream commit hash we vendored at build time.

## 5. CLI surface — primitives only (demo scope)

All commands emit JSON to stdout unless `--pretty` is set. Exit non-zero on transport error.

### `lookin attach [--simulator | --device <udid>] [--port N]`

Resolve a working port, ping the server, persist `{ host, port, serverVersion, target, pid }` to `~/.lookin-cli/session.json`. Idempotent.

### `lookin tree [--root <axId>] [--depth N] [--include-hidden]`

Compact view tree. One node = `{ oid, axId?, class, hostVC?, frame: [x,y,w,h], alpha, isHidden, childCount, children?: [...] }`. No heavy attributes here — keep the response small so agents can fit it in context.

### `lookin attributes <oid | axId>`

Heavy per-view attributes for a single view: every `LookinAttributesGroup` flattened into `{ groupTitle, sectionTitle, key, valueType, value }`. Includes: backgroundColor, tintColor, cornerRadius, borderWidth/Color, shadow, font, textColor, alignment, contentMode, transform, clipsToBounds, custom attributes (the `@LookinCustomDebugInfo*` hooks).

### `lookin find <query> [--by class|label|axId] [--limit N]`

Substring/prefix match. Returns shallow node list (no children).

### `lookin screenshot [--view <oid>] [--out <path>]`

Server-side rendered PNG of a specific view (`LookinRequestTypeFetchImageViewImage = 208`) or the full window. **For full-screen sim screenshots, the CLI's docs explicitly point at `axe screenshot` / `simctl io … screenshot`** — Lookin's screenshot path is meant for "just this view, including offscreen siblings."

### `lookin doctor`

Diagnostic: shows resolved port, ping latency, server version, OS, sim UDID. Used in CI / debugging.

## 6. Out-of-scope for demo (documented, not built)

- `lookin diff --figma <fileKey>:<nodeId> --view <axId>` — runs `get_metadata` + `get_variable_defs` via the agent-side Figma MCP, compares against `lookin attributes`, emits a structured diff. The agent can already do this manually with the primitives.
- `lookin verify <spec.yml>` — declarative invariants.
- MCP server wrapper (`lookin-mcp`).
- `LKS_HTTPServer` (Route A).
- Real-device automatic port forwarding (we shell out to `iproxy` for now; later candidate for built-in via `pymobiledevice3`).

## 7. Highest-leverage convention (recommendation, not enforced)

Encourage app code to set `view.accessibilityIdentifier = "figma:<fileKey>:<nodeId>"` (or just `"figma:<nodeId>"` if `fileKey` is implicit). When present, the CLI surfaces it as `figmaRef` on the tree node, giving Figma↔runtime a deterministic join key. When absent, joining falls back to class+label heuristics (lossy). This is the single highest-ROI convention to ship alongside the CLI.

## 8. Project structure

```
lookin-cli/
├── Package.swift
├── Sources/
│   ├── LookinCLI/              # ArgumentParser entry, command structs
│   │   ├── Commands/{Attach,Tree,Attributes,Find,Screenshot,Doctor}.swift
│   │   ├── Session.swift
│   │   └── JSONEncoding.swift  # LookinDisplayItem -> public JSON
│   ├── LookinTransport/         # Swift, transport protocol + peertalk client
│   │   ├── LookinTransport.swift
│   │   ├── PeertalkTransport.swift
│   │   └── Frame.swift
│   └── LookinCore/              # vendored ObjC sources from LookinServer
│       ├── include/             # module map + umbrella header
│       ├── LookinDisplayItem.{h,m}
│       ├── LookinHierarchyInfo.{h,m}
│       ├── ... (see §4.2)
│       └── module.modulemap
├── Tests/
│   └── LookinCLITests/
└── docs/specs/2026-05-19-lookin-cli-design.md (this file)
```

Build: `swift build -c release`. Run: `.build/release/lookin tree`. Distribution (post-demo): `mint`/`brew`.

## 9. Public JSON schema (stable surface)

Designed for agent consumption: predictable keys, no nested optionals when avoidable, frame as `[x, y, w, h]` arrays so a model can pattern-match without parsing objects.

```jsonc
// `lookin tree`
{
  "root": {
    "oid": "0x7f9a2b001230",      // stable per-attach
    "class": "UIWindow",
    "frame": [0, 0, 393, 852],
    "alpha": 1.0,
    "isHidden": false,
    "childCount": 1,
    "children": [
      {
        "oid": "0x7f9a2b002340",
        "axId": "loginScreen",
        "figmaRef": "9:2",        // present iff axId starts with "figma:"
        "class": "LoginViewController.View",
        "hostVC": "LoginViewController",
        "frame": [0, 0, 393, 852],
        "alpha": 1.0, "isHidden": false,
        "childCount": 4,
        "children": [ ... ]
      }
    ]
  },
  "target":  { "kind": "simulator", "udid": "...", "name": "iPhone 15 Pro" },
  "captured": "2026-05-19T10:11:12Z",
  "serverVersion": 7
}

// `lookin attributes <oid>`
{
  "oid": "0x7f9a2b002340",
  "class": "PrimaryButton",
  "groups": [
    { "title": "Background", "section": "Color",
      "key": "backgroundColor", "type": "color",
      "value": { "hex": "#0A84FF", "rgba": [10,132,255,255] } },
    { "title": "Border", "section": "Corner",
      "key": "cornerRadius", "type": "number", "value": 12 },
    { "title": "Text", "section": "Font",
      "key": "font", "type": "font",
      "value": { "family": ".SFUI-Semibold", "size": 17 } },
    // ...
    { "title": "Custom", "section": "ViewModel",
      "key": "state", "type": "string", "value": "loading" }
  ],
  "constraints": [ /* LookinAutoLayoutConstraint flattened */ ]
}
```

## 10. Demo acceptance criteria

The demo is "done" when, against a fresh iOS app embedding upstream LookinServer 1.x in the iPhone 15 Pro simulator, all of the following succeed:

1. `lookin attach --simulator` — exits 0, writes session file, prints resolved port + server version.
2. `lookin tree --depth 3` — emits JSON, root is a `UIWindow`, includes at least the app's root view controller's view, frame numbers match the simulator screen size.
3. `lookin attributes <oid>` — for a button OID picked from the tree, returns ≥5 attribute groups including `backgroundColor`, `cornerRadius`, and `font` if present.
4. `lookin find UILabel --limit 5` — returns ≥1 label with stable OIDs that can be passed back to `attributes`.
5. `lookin screenshot --view <oid> --out /tmp/x.png` — writes a non-empty PNG.
6. `lookin doctor` — exits 0 and prints latency under 500ms on warm runs.

Out-of-scope: `diff`, `verify`, MCP, real-device USB.

## 11. Risk register

| Risk                                                                                  | Likelihood                    | Mitigation                                                                                                           |
| ------------------------------------------------------------------------------------- | ----------------------------- | -------------------------------------------------------------------------------------------------------------------- |
| Vendored ObjC files transitively import `UIKit` and break on macOS                    | Med                           | Stub UIKit-only methods with `#if TARGET_OS_IOS`. Pin upstream commit, audit at build time.                          |
| Lookin protocol version bumps and breaks `LookinClientVersion=7`                      | Low (Lookin not super active) | Pin a known-good upstream commit; CI test against that commit. Surface a clear `version mismatch` error.             |
| `NSKeyedUnarchiver` rejects archive due to missing class                              | Med                           | Catch and report class name. Iteratively add missing classes to vendored set.                                        |
| Real-device path is hard without `iproxy`                                             | High                          | Demo punts to simulator only. Document the `iproxy` recipe explicitly.                                               |
| Lookin sample app sometimes binds to a different port than we expect                  | Low                           | Port scan range, not single port. `--port` override.                                                                 |
| Server-side `LookinRequestTypeHierarchyDetails (203)` streams in packages and is slow | Med                           | `tree` uses the lighter `Hierarchy (202)` request first; `attributes` triggers `203` only for the requested subtree. |

## 12. Open questions (resolve during implementation)

- Which Lookin upstream commit do we pin? (Pick latest tagged release on impl day.)
- Do we ship a tiny "hello LookinServer" iOS sample under `Examples/` to enable CI? (Probably yes, smallest possible.)
- `--json` vs `--pretty` default? Default = compact JSON, `--pretty` for humans.

## 13. Future work (post-demo)

1. `lookin diff` — leverages `figma-mcp` + `lookin attributes`. Diff rules: bbox tolerance, color ΔE, font equality.
2. `lookin verify <spec.yml>` — declarative invariants for CI.
3. MCP server wrapper exposing `lookin_*` tools; either standalone or contributed to XcodeBuildMCP.
4. Route A: add `LKS_HTTPServer` upstream PR or maintain a small fork. Swap `PeertalkTransport` for `HTTPTransport`.
5. Built-in `iproxy`-less device path via `pymobiledevice3`'s usbmux library, possibly via a thin Swift wrapper.
