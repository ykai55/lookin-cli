# lookin measure — Design Doc

**Date:** 2026-05-20
**Status:** Implemented
**Owner:** shoujiaxin@gmail.com
**Builds on:** `2026-05-19-lookin-cli-design.md` (the lookin-cli demo)

## 1. Problem

A Coding Agent comparing a running iOS app against a Figma design repeatedly needs one specific fact: _the geometric relationship between two UI elements_ — the gap between two stacked cards, whether two labels are left-aligned, whether a button overflows its container. Today the agent must call `lookin tree`/`find`, read two frames, and do the arithmetic itself — and that arithmetic is wrong whenever the two elements live in different parent coordinate spaces, because `LookinDisplayItem.frame` is parent-relative.

`lookin measure` makes this a single deterministic call: pick two elements, get every pairwise geometric measurement in a common (screen-absolute) coordinate space, optionally rendered as an annotated screenshot.

## 2. Non-goals

- Measuring against Figma directly. `measure` operates entirely on the running app. The Figma side is a future `lookin diff`.
- Three-or-more-element measurement. Exactly two endpoints.
- Handling ancestor `CGAffineTransform` / `CATransform3D`. LookinServer does not serialize transforms onto `LookinDisplayItem` (confirmed in the vendored `LookinDisplayItem.h`), so we cannot detect or correct for them. Documented as a limitation.
- A measurement UI inside the Lookin macOS app. This is a CLI command.

## 3. Command surface

```
lookin measure <selectorA> <selectorB> [options]

  <selectorA> <selectorB>   Two element selectors (see §4).

  --annotate <path>         Also render an annotated PNG to <path>.
  --tolerance <pt>          Alignment tolerance in points (default: 0.5).
  --pretty                  Pretty-print JSON.
```

Exit non-zero if either selector resolves to nothing, or on transport error. JSON report to stdout on success.

## 4. Selectors

A selector is a `scheme:value` string. Three schemes, all resolving to a single `LookinDisplayItem`:

| Scheme  | Example             | Resolution                                                                                                                                                                                                                                       |
| ------- | ------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `oid`   | `oid:223`           | Direct lookup in the fetched hierarchy by `LookinObject.oid`.                                                                                                                                                                                    |
| `point` | `point:32,92`       | Screen-coordinate hit-test: the deepest display item whose **absolute frame** contains the point. Ties broken by smallest area. Hidden / `alpha==0` items are skipped unless `--include-hidden` is later added (out of scope now: skip them).    |
| `axe`   | `axe:button-submit` | Soft dependency. Shell out to `axe describe-ui --udid <udid>`, parse the JSON accessibility tree, find the element whose `AXUniqueId` equals the value, take the center of its `frame` (screen rect), then hit-test our hierarchy at that point. |

**axe soft dependency:** `axe:` is the only path that needs the `axe` binary. If `axe` is not on `PATH`, only the `axe:` path errors (`axe not found on PATH; install cameroncooke/AXe or use oid:/point:`). `oid:` and `point:` never touch axe. The simulator UDID for `axe` comes from the saved session (`Session` is extended to record the booted simulator UDID at `attach` time — see §8).

A selector that resolves to nothing produces: `error: selector '<raw>' matched no element`.

## 5. Coordinate model — the core logic

`LookinDisplayItem.frame` is in the **superview's `bounds` coordinate system**. To compare two arbitrary items they must be lifted into one absolute (screen) space.

### 5.1 Absolute frame

Build, from the fetched hierarchy, an `oid → parent` map by walking `subitems` from each root (do **not** rely on the `superItem` weak ref surviving unarchive). Then compute absolute origins **top-down** in one pass from each root:

```
absoluteOrigin(root)  = root.frame.origin                       // normally (0,0)
absoluteOrigin(child) = absoluteOrigin(parent)
                      + child.frame.origin
                      - parent.bounds.origin                    // scroll-view contentOffset
```

The absolute frame keeps the item's own `frame.size`; only the origin is recomputed.

Subtracting `parent.bounds.origin` is what makes measurement correct across scroll views: a cell at `frame.y = 452` inside a `UICollectionView` scrolled by `bounds.origin.y = 200` is at screen `y = parentAbsoluteY + 452 - 200`.

### 5.2 Limitation

If any ancestor has a non-identity transform, the accumulated frame is wrong and we cannot know it (transform not serialized). The report includes `"coordinateModel": "frame-accumulation"` and the README documents this. Acceptable: the overwhelmingly common case (auto-layout / stack views / scroll views) is transform-free.

## 6. Measurements

Given absolute frames `A` and `B` (`CGRect`, screen space), all measurements are pure functions in `Geometry.swift`.

### 6.1 Gap

The signed empty distance between the two facing edges, on whichever axis the rects do **not** overlap:

- `vertical`: if `A` and `B` do not overlap on Y — `gap = max(A.minY,B.minY) - min(A.maxY,B.maxY)`. Positive = a real gap; negative would mean overlap (then it's `null`, see overlap).
- `horizontal`: same on X.
- If the rects overlap on an axis, that axis's gap is `null`.
- If they overlap on **both** axes, both gaps are `null` and `overlap` is non-null.

### 6.2 Edges (signed, B relative to A)

`leftToLeft = B.minX - A.minX`, `rightToRight = B.maxX - A.maxX`, `topToTop = B.minY - A.minY`, `bottomToBottom = B.maxY - A.maxY`, plus the facing-edge deltas `aMaxXToBMinX`, `aMaxYToBMinY`, `bMaxXToAMinX`, `bMaxYToAMinY`.

### 6.3 Center

`dx = B.midX - A.midX`, `dy = B.midY - A.midY`.

### 6.4 Alignment (bool, within `--tolerance`)

`left, right, top, bottom, centerX, centerY` — each true iff the corresponding edge/center delta is `<= tolerance` in absolute value.

### 6.5 Overlap

`null` if the rects are disjoint; otherwise `{ rect: [x,y,w,h], area: <pt²> }` for the intersection.

### 6.6 Containment

`aInsideB`, `bInsideA` — true iff one absolute frame fully contains the other.

### 6.7 Box model (per element)

The element's inset within its **direct parent's** bounds rectangle: `{ top, left, right, bottom }` where `top = item.frame.minY - parent.bounds.minY`, `left = item.frame.minX - parent.bounds.minX`, `right = parent.bounds.maxX - item.frame.maxX`, `bottom = parent.bounds.maxY - item.frame.maxY`. `null` if the element is a root window. This is the devtools-style "distance to each parent edge".

## 7. JSON output schema

```jsonc
{
  "a": {
    "selector": "oid:204",
    "oid": 204,
    "class": "ContentCardCell",
    "absoluteFrame": [0, 452, 402, 87], // [x, y, w, h] in screen points
    "parent": { "oid": 47, "class": "UICollectionView" },
    "boxModel": { "top": 452, "left": 0, "right": 0, "bottom": 335 },
  },
  "b": {
    "selector": "oid:218",
    "oid": 218,
    "class": "ContentCardCell",
    "absoluteFrame": [0, 547, 402, 87],
    "parent": { "oid": 47, "class": "UICollectionView" },
    "boxModel": { "top": 547, "left": 0, "right": 0, "bottom": 240 },
  },
  "gap": { "vertical": 8.0, "horizontal": null },
  "edges": {
    "leftToLeft": 0,
    "rightToRight": 0,
    "topToTop": 95,
    "bottomToBottom": 95,
    "aMaxYToBMinY": 8.0,
    "bMaxYToAMinY": -182.0,
    "aMaxXToBMinX": null,
    "bMaxXToAMinX": null,
  },
  "center": { "dx": 0.0, "dy": 95.0 },
  "alignment": {
    "left": true,
    "right": true,
    "centerX": true,
    "top": false,
    "bottom": false,
    "centerY": false,
  },
  "overlap": null,
  "containment": { "aInsideB": false, "bInsideA": false },
  "commonAncestor": { "oid": 47, "class": "UICollectionView" },
  "coordinateModel": "frame-accumulation",
  "annotated": "/tmp/measure.png", // present only with --annotate
}
```

`aMaxXToBMinX` is `null` when the rects overlap on X (the facing edges don't exist on that axis); same logic per facing-edge field.

## 8. Annotation (`--annotate <path>`)

1. Fetch a full-window screenshot. Reuse the existing screenshot path: request `LookinRequestTypeHierarchyDetails (203)` streaming for the key window's root layer `groupScreenshot` — the same code `lookin screenshot` already uses for container layers. The screenshot is at device-pixel scale; record the scale factor (`screenshotPixelWidth / windowPointWidth`) to map points → pixels.
2. Draw with CoreGraphics on macOS (`NSImage` → `NSBitmapImageRep` / `CGContext`):
   - Both element rects: 2px outline (A in one hue, B in another).
   - The gap: a line spanning the empty space on the measured axis, capped with ticks, plus a rounded "pill" label showing the gap value (mirrors the reference image — a number in a filled rounded rect).
   - Alignment guides: for each true alignment flag, a dashed line through the shared edge/center.
3. Write PNG to `<path>`. Put the path in the JSON `annotated` field.

Annotation is **opt-in**; without `--annotate` no screenshot is fetched (one network request total, not two).

## 9. Session change

`Session` (`Session.swift`) gains an optional `simulatorUDID: String?`. `attach` resolves the booted simulator's UDID (via `xcrun simctl list devices booted` — first booted device, or the one whose app owns the resolved port if that's cheaply determinable; first-booted is acceptable for the demo) and stores it. `measure`'s `axe:` path reads it to pass `--udid` to `axe`. If absent, the `axe:` path errors asking the user to re-`attach`.

## 10. Architecture & files

A new shared `Hierarchy` model is introduced (approved approach): fetch once, index by oid, expose parent lookup and absolute-frame computation. `measure` builds on it. Existing commands (`tree`, `find`, `attributes`, `screenshot`) are **not** migrated in this change — that is optional later cleanup, out of scope here.

```
Sources/LookinCLI/
├── Hierarchy.swift          NEW — fetch hierarchy (request 202), oid index,
│                                  oid→parent map, absoluteFrame(oid), hitTest(point)
├── Geometry.swift           NEW — pure CGRect math: gap, edges, center, alignment,
│                                  overlap, containment, boxModel. No I/O.
├── Selector.swift           NEW — parse "scheme:value"; resolve oid/point/axe → oid
├── AxeBridge.swift          NEW — run `axe describe-ui --udid <udid>`, parse JSON,
│                                  find element by AXUniqueId → screen rect
├── Annotation.swift         NEW — render annotated PNG via CoreGraphics
├── Commands/Measure.swift   NEW — wire selectors → Hierarchy → Geometry → JSON/annotate
└── Session.swift            MODIFIED — add optional simulatorUDID
```

Data flow:

```
Measure → Hierarchy.fetch (one request 202)
        → Selector.resolve(A), Selector.resolve(B)   // axe path may shell out
        → Hierarchy.absoluteFrame(A), .absoluteFrame(B)
        → Geometry.measure(A, B, tolerance)          // pure
        → emit JSON
        → if --annotate: fetch window screenshot, Annotation.render, write PNG
```

## 11. Error handling

| Condition                                    | Behavior                                                                                                                     |
| -------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------- |
| No session                                   | `error: no session. Run \`lookin attach\` first.` exit 1                                                                     |
| Selector unparseable (`foo:bar` / no scheme) | `error: bad selector '<raw>': expected oid:/point:/axe:` exit 1                                                              |
| Selector resolves to nothing                 | `error: selector '<raw>' matched no element` exit 1                                                                          |
| `axe:` used but `axe` not on PATH            | `error: 'axe' not found on PATH (needed for axe: selectors)` exit 1                                                          |
| `axe:` used but session has no UDID          | `error: session has no simulator UDID; re-run \`lookin attach\`` exit 1                                                      |
| Both selectors resolve to the same element   | `error: both selectors resolved to the same element (oid <n>)` exit 1                                                        |
| `--annotate` set but screenshot fetch fails  | Emit the JSON anyway (measurement succeeded); print `warning: annotation failed: <reason>` to stderr; omit `annotated` field |

## 12. Testing

**`Geometry.swift` — pure, exhaustively unit-tested (the bulk of test value):**

- gap: vertical-only, horizontal-only, both-null-on-overlap, touching edges (gap 0)
- edges: signed deltas correct; facing-edge fields `null` on overlapping axis
- alignment: exactly at tolerance, just inside, just outside
- overlap: disjoint → null; partial → correct intersection rect+area; containment case
- containment: aInsideB, bInsideA, neither
- boxModel: simple parent, scroll-view parent with non-zero `bounds.origin`

**`Hierarchy.swift` — absolute frame accumulation:**

- Synthetic 3-level tree, middle node is a scroll view with `bounds.origin = (0,200)`; assert a leaf's absolute frame accounts for the contentOffset.
- `hitTest`: nested rects, point in overlap region returns the deepest/smallest.

**`Selector.swift`:** parsing valid/invalid forms; `oid:`/`point:` resolution against a synthetic `Hierarchy`. (`axe:` resolution is covered by live verification, not unit tests — it shells out.)

**Live verification (against the running iPhone 17 Pro sim):**

- `lookin measure oid:204 oid:218` → `gap.vertical == 8.0` (matches the hand-computed value from the earlier session).
- `lookin measure point:200,490 point:200,580` → resolves two cells, same gap.
- `lookin measure oid:204 oid:218 --annotate /tmp/m.png` → PNG written, non-empty, `file` reports PNG.

## 13. Acceptance criteria

1. `lookin measure oid:<cellA> oid:<cellB>` emits valid JSON with the §7 shape; `gap.vertical` matches the manual calculation within 0.5pt.
2. `point:` selector resolves the same cells as their `oid:` and yields an identical gap.
3. `axe:` selector path: with `axe` installed, resolves an element and produces a measurement; with `axe` absent, only the `axe:` path errors with the §11 message.
4. `alignment.left/right/centerX` are `true` for two cells that share x and width.
5. `--annotate` writes a non-empty PNG showing both rects and the gap label.
6. `Geometry` + `Hierarchy` + `Selector` unit tests all pass.

## 14. Future work

- `lookin diff` — feed one side from Figma MCP `get_metadata`, the other from `measure`/`attributes`.
- Migrate `tree`/`find`/`attributes`/`screenshot` onto the shared `Hierarchy` model.
- Transform-aware coordinates if a future LookinServer serializes transforms.
- `measure` accepting an element and a parent edge ("distance from button to safe-area").
