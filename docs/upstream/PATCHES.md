# Patches Applied to Vendored LookinServer Sources

All files sourced verbatim from commit `985e8afe77aa2f3fab599da4f9882f6e43eed919` (release/1.2.7, MIT),
except for the following targeted patches applied to make the sources compile on macOS.

## Build compatibility patches

1. **`Package.swift`** — Added `.define("SHOULD_COMPILE_LOOKIN_SERVER")` to `cSettings` for the `LookinCore`
   target. All vendored files are guarded by `#ifdef SHOULD_COMPILE_LOOKIN_SERVER`; without this define
   every file compiled as empty translation units and nothing linked.

2. **`Package.swift`** — Added `.linkedFramework("AppKit")` and `.linkedFramework("CoreGraphics")` to
   `linkerSettings` for `LookinCore`. The vendored sources reference `NSImage`/`NSColor` (AppKit types)
   on `TARGET_OS_MAC` paths.

3. **`Image+Lookin.h`** — Added `#import <AppKit/AppKit.h>` inside the `#elif TARGET_OS_MAC` block
   (line inserted before the `@interface NSImage (LookinClient)` declaration). The header extends
   `NSImage` on macOS but omitted the AppKit import, causing a "cannot define category for undefined
   class 'NSImage'" error at compile time.

## Files fetched beyond the original plan list (pulled because they were transitively required)

- `LookinEventHandler.{h,m}` — imported by `LookinDisplayItem.m`
- `Color+Lookin.{h,m}` — imported by `LookinDisplayItem.m`
- `Image+Lookin.{h,m}` — imported by `Color+Lookin.m`
- `LookinTuple.{h,m}` — imported by `LookinEventHandler.m`
- `NSObject+Lookin.{h,m}` — imported by `LookinConnectionAttachment.m` and others
- `NSArray+Lookin.{h,m}` — imported transitively
- `NSString+Lookin.{h,m}` — imported transitively
- `LookinDashboardBlueprint.{h,m}` — imported by `LookinHierarchyInfo.h`
- `LookinAppInfo.{h,m}` — imported by `LookinHierarchyInfo.h`
- `LookinWeakContainer.{h,m}` — imported by `NSObject+Lookin.m`
- `LookinAttrIdentifiers.{h,m}` — imported by `LookinAttribute.h`
- `LookinAttrType.h` — imported by `LookinAttribute.h`
- `LookinCustomDisplayItemInfo.{h,m}` — imported by `LookinDisplayItem.h`
- `LookinCodingValueType.h` — imported by `LookinConnectionAttachment.h`
- `LookinIvarTrace.{h,m}` — originally listed; found at `Src/Base/` instead of `Src/Main/Shared/`

4. **`Sources/LookinCore/include/LookinCore.h`** (umbrella header) — Added relative-path imports
   (`#import "../LookinDefines.h"` etc.) so the module umbrella resolves vendor headers when the
   module is consumed by Swift test targets (the `include/` directory is the `publicHeadersPath`
   root, so relative `..` resolves to `Sources/LookinCore/`). Also added:

   ```objc
   #ifndef SHOULD_COMPILE_LOOKIN_SERVER
   #define SHOULD_COMPILE_LOOKIN_SERVER
   #endif
   ```

   so the vendored types are visible when Swift imports the module (the `cSettings` define applies
   only to the ObjC `.m` compilation, not to the Swift module-import clang invocation).

5. **`Package.swift`** — Added `headerSearchPath("..")` to allow the umbrella's relative imports
   to resolve correctly during ObjC compilation of the vendored `.m` files.

## Test notes (Task 3)

- `LookinCodingValueTypeNumber` (used in the plan's test template) does not exist in the
  vendored enum. Used `LookinCodingValueType(rawValue: 4)` (= `LookinCodingValueTypeLongLong`)
  instead. Documented in `Tests/LookinCoreTests/KeyedArchiverRoundTripTests.swift`.
- No `setClass(_:forClassName:)` registrations were needed; `LookinConnectionAttachment`
  declares `+supportsSecureCoding` returning `YES` and the unarchiver finds it by class lookup.

## encode/decode method status

All `initWithCoder:` and `encodeWithCoder:` method bodies are preserved verbatim.
No UIKit-gating was required on the macOS host because the vendored sources already use
`#if TARGET_OS_IPHONE` / `#elif TARGET_OS_MAC` guards throughout. `NSKeyedUnarchiver` can
decode these types on macOS without constructing any live UIView — it deserializes into
the same Objective-C classes using their existing `initWithCoder:` implementations.
