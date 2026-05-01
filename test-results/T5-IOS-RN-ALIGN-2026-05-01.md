# T5 iOS React Native E2E — Alignment 2026-05-01

**Simulator:** iPhone 17 Pro Max (UDID `B5B271E5-C633-4F94-A5C1-DCC5073E236A`, iOS 26.1)
**Commit:** 79975ae0 — "feat(align): execute ALIGNMENT_PLAN M1-M8 across 5 SDKs"
**Example project:** `/Users/sanchitmonga/development/ODLM/MONOREPOOO/runanywhere-sdks3/runanywhere-sdks-main/examples/react-native/RunAnywhereAI/`

## Build: FAIL
- `pod install` — PASS (94 dependencies, 93 pods installed).
- `xcodebuild -workspace ios/RunAnywhereAI.xcworkspace -scheme RunAnywhereAI -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' -configuration Debug build` — **BUILD FAILED** with 2 compile errors.

### Error detail (M1.2 regression)
```
/sdk/runanywhere-react-native/packages/core/ios/URLSessionHttpTransport.mm:181:5:
  error: use of undeclared identifier 'clock_get_time'
/sdk/runanywhere-react-native/packages/core/ios/URLSessionHttpTransport.mm:193:5:
  error: use of undeclared identifier 'clock_get_time'
** BUILD FAILED **
```

### Root cause
`URLSessionHttpTransport.mm` uses `host_get_clock_service(...)`, `clock_get_time(...)`, and `mach_port_deallocate(...)` in `elapsedMsSince()` and `monotonicNs()` helpers (lines 177–197), but the file does **not** include the required Mach kernel headers:

```objc
#import <Foundation/Foundation.h>

#include <atomic>
#include <cstdint>
#include <cstdlib>
...
```

Missing: `#include <mach/clock.h>` and `#include <mach/mach.h>`.

The Flutter variant at `sdk/runanywhere-flutter/packages/runanywhere/ios/Classes/URLSessionHttpTransport.mm` has the correct imports at line 26-27 — that file compiles cleanly and Flutter iOS T6 PASSES. The RN copy under `sdk/runanywhere-react-native/packages/core/ios/URLSessionHttpTransport.mm` was created / updated in M1.2 when stub-mode `#ifdef` guards were deleted, but the copy did not carry over the `<mach/*>` includes.

### Fix (not applied — outside task scope)
Add to `sdk/runanywhere-react-native/packages/core/ios/URLSessionHttpTransport.mm` after line 23:
```objc
#include <mach/clock.h>
#include <mach/mach.h>
```

## Launch (no crash): N/A (not launched — no binary)

## Milestone verification
- **M1.2 (RN iOS xcframework rebuild + stub-mode deletion):** **FAIL.** The podspec correctly sets `RAC_HAS_HTTP_TRANSPORT=1` (visible in the clang invocation: `-DRAC_HAS_HTTP_TRANSPORT=1`), and the stub-mode `#ifdef` was indeed removed — but the real-mode code path now references Mach APIs without declaring the headers. Net effect: Android RN works, iOS RN does not compile.
- **M5 (Nitro spec 10-field progress, `SyncHttpDownload` gone):** UNVERIFIED AT RUNTIME. Cannot run the app. Source-level grep confirms `SyncHttpDownload` is absent from `packages/core/ios/`; Nitro spec regeneration needed for confidence.
- **M6 (SHA-256 infra):** UNVERIFIED AT RUNTIME. Source compiles up to the M1.2 block; no evidence of M6-specific errors in the build log.
- **M8 (`RADownloadProgress` proto):** UNVERIFIED AT RUNTIME.
- **Anti-regression (no libcurl, no stub-mode, no `RAC_ERROR_INTERNAL`):** UNVERIFIED. Blocked.

## Overall: FAIL
Per task constraint ("If pod install fails on RN, document and continue to Swift + Flutter") — pod install actually succeeded, but xcodebuild fails on M1.2 iOS transport. This is the first known regression of the 79975ae0 alignment commit on iOS RN. Both T4 (Swift) and T6 (Flutter) PASS on iOS.

**Recommended immediate action:** add the two missing `<mach/*>` `#include` directives to `sdk/runanywhere-react-native/packages/core/ios/URLSessionHttpTransport.mm` and rebuild. This is a 2-line diff that should mirror the Flutter variant line-for-line.
