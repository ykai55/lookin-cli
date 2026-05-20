---
name: lookin-cli
description: Use when you need the real UIView/CALayer view hierarchy, exact layout geometry, spacing/alignment measurements, or runtime visual properties (cornerRadius, shadow, font, transform, custom ivars) of a running iOS app — e.g. verifying an implementation matches a Figma design. Drives the `lookin` CLI, which talks to LookinServer over its peertalk wire protocol.
---

# lookin-cli: Inspect a Running iOS App's UI Layout

`lookin` is a macOS CLI that reads a running iOS app's **real view tree** — every
`UIView`/`CALayer`, including offscreen and decorative views — plus live frame
data and runtime render attributes. It talks directly to LookinServer, so it sees
what the accessibility tree cannot.

## When to use this skill

Use `lookin` when the task needs the **visual / structural** truth of the UI:

- Compare a built screen against a Figma design — spacing, alignment, sizing.
- Measure the gap, edge deltas, or center offset between two elements.
- Read render-time properties: `cornerRadius`, `shadow`, `font`, `backgroundColor`,
  `transform`, alpha, and custom view ivars.
- Dump the full view hierarchy with absolute frames, including non-accessible
  decorative views the a11y tree omits.

## When NOT to use it

- **Interaction/automation** (tap, type, swipe, navigate) → use AXe or XcodeBuildMCP.
- **Build/run/launch the app** → use XcodeBuildMCP.
- **What is interactable and where** (accessibility tree only) → AXe `describe-ui`.

`lookin` is read-only inspection. It pairs with the above tools; it does not replace them.

## Prerequisites

- **macOS only** (decodes LookinServer's `NSKeyedArchiver` payload natively).
- The target iOS app must **embed LookinServer** (CocoaPods or SPM) and be running
  on a booted Simulator (or a USB-connected device).
- The `lookin` binary is on `PATH`. If not, build it once:

  ```bash
  swift build -c release            # run from the lookin-cli repo
  cp .build/release/lookin /usr/local/bin/
  ```

  Without installing, substitute `swift run lookin` for `lookin` below.

## Core workflow

Run in order. Every command prints JSON to stdout; add `--pretty` for indented JSON,
omit it for compact one-line JSON (better for piping into `jq`).

```bash
# 1. Sanity check — confirm LookinServer is reachable.
lookin doctor --pretty

# 2. Discover and cache a session (~/.lookin-cli/session.json).
lookin attach --pretty

# 3. Dump the view hierarchy. Constrain depth for large screens.
lookin tree --depth 4 --pretty

# 4. Narrow down to the elements you care about.
lookin find ContentCardCell --by class --limit 5 --pretty

# 5. Inspect one element's render attributes.
lookin attributes --oid 4325478400 --pretty

# 6. Measure two elements (the headline command — see below).
lookin measure oid:312 oid:348 --pretty
```

If a command reports the server is unreachable, re-run `lookin attach` — LookinServer
is single-client and re-listens after every connection closes.

## Command reference

| Command      | Purpose                                                         | Key options                                           |
| ------------ | --------------------------------------------------------------- | ----------------------------------------------------- |
| `doctor`     | Probe for a reachable LookinServer; print diagnostics.          | `--device`, `--pretty`                                |
| `attach`     | Discover server, cache session to `~/.lookin-cli/session.json`. | `--device`, `--pretty`                                |
| `tree`       | Print the full view hierarchy as JSON.                          | `--depth <n>` (default unlimited), `--pretty`         |
| `find`       | Find views by substring on class / label / ax-id.               | `--by class\|label\|ax-id`, `--limit <n>`, `--pretty` |
| `attributes` | Print all attribute groups for one view.                        | `--oid <n>` or `--ax-id <s>`, `--pretty`              |
| `screenshot` | Save a PNG of a view/layer.                                     | `--view <oid>`, `-o/--out <path>`                     |
| `measure`    | Geometric relationship between two elements.                    | `--tolerance <pt>`, `--annotate <path>`, `--pretty`   |

Pass `--device` to `doctor`/`attach` for a USB-connected real device. First forward
the port in a separate, long-lived terminal: `iproxy 47175 47175`.

## `lookin measure` — the design-comparison command

`measure` is the deterministic answer to "how far apart / how aligned are these two
views". It computes both elements' frames in **one screen-absolute coordinate
space** (accumulating `frame.origin` down the tree, subtracting each ancestor's
`bounds.origin`), so the result is correct even across different scroll views — a
calculation that is easy to get wrong from raw `tree` output.

```bash
lookin measure <selectorA> <selectorB> [--tolerance <pt>] [--annotate <path>] [--pretty]
```

Each selector picks exactly one element:

| Selector           | Example             | Resolves by                                                       |
| ------------------ | ------------------- | ----------------------------------------------------------------- |
| `oid:<n>`          | `oid:312`           | Object id from `tree` / `find` output (exact).                    |
| `point:<x>,<y>`    | `point:210,330`     | Screen-coordinate hit-test; deepest view containing the point.    |
| `axe:<AXUniqueId>` | `axe:submit-button` | Shells out to the `axe` CLI, hit-tests the a11y element's center. |

Output (`--pretty`) reports `gap`, `edges`, `center`, `alignment` flags, `overlap`,
`containment`, per-element `boxModel`, and the `commonAncestor`:

```bash
$ lookin measure point:210,330 point:210,440 --pretty
{
  "a": { "oid": 312, "absoluteFrame": [40, 289.33, 328.33, 42.33], ... },
  "b": { "oid": 348, "absoluteFrame": [40, 405.33, 328.33, 42.33], ... },
  "gap": { "vertical": 73.67 },
  "edges": { "leftToLeft": 0, "rightToRight": 0, "topToTop": 116, ... },
  "alignment": { "left": true, "right": true, "centerX": true, "top": false, ... },
  "coordinateModel": "frame-accumulation"
}
```

- `--tolerance` (default `0.5` pt) is the slack for the boolean `alignment` flags.
- `--annotate <path>` also writes a PNG with both elements outlined and the gap
  drawn as a labelled dimension line — useful as visual proof in a report.

## Figma join key (highest-leverage convention)

When the app sets `view.accessibilityIdentifier = "figma:<nodeId>"` (or
`"figma:<fileKey>:<nodeId>"`), `tree` and `find` output gains a `figmaRef` field
that maps **deterministically** to the `node_id` values from the Figma MCP's
`get_metadata`. This turns design-vs-implementation comparison from fuzzy
class+label matching into an exact join. Recommend adding this convention to any
app that will be compared against Figma.

## Output schema notes

`tree` / `find` nodes:

```
roots[].{ oid, class, axId?, figmaRef?, frame{x,y,width,height}, alpha, hidden, children[] }
```

- `oid` is a **stable object id within one session** — pass it to `attributes`,
  `screenshot`, and `measure` as `oid:<n>`.
- `attributes` values use LookinServer's internal short identifiers
  (`c_c_c`, `l_f_f`, …) — match on `attrType` / `group` / `section`, not the code.

## Troubleshooting

- **`reachable: false`** — the app isn't running, isn't in Debug, or doesn't embed
  LookinServer. For a real device, confirm `iproxy 47175 47175` is still alive.
- **Connection flakiness right after another command** — LookinServer is
  single-client and re-listens after each close. Retry once; `measure` already
  retries internally.
- **`measure` looks skewed** — LookinServer does not serialize transforms; a
  non-identity `CGAffineTransform`/`CATransform3D` on any ancestor silently skews
  frame accumulation. The JSON flags this via `"coordinateModel": "frame-accumulation"`.
  The common auto-layout / stack-view / scroll-view case is transform-free.
- **`screenshot` returns empty data** — bare `UILabel` and some leaf views don't
  materialize a solo snapshot. Screenshot a container view/layer instead.
