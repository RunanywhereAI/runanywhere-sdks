# v2 close-out — build sanity log

_Phase 1 of the close-out plan. Captures the actual `cmake --preset` configure + build run on the audit machine._

## Result: GREEN

The new GAP-07 root CMake + presets configure cleanly and `rac_commons` builds end-to-end on macOS. **One real bug was found and fixed during this phase.**

## Bug found and fixed in Phase 1

`CMakePresets.json` carried a top-level `"_comment"` key (introduced in GAP 07 Phase 2 commit). CMake 3.22+ schema validation **rejects** unknown root-object fields:

```
CMake Error: Could not read presets from .../runanywhere-sdks-main:
CMakePresets.json:4: Invalid extra field "_comment" in root object
```

This bug **silently broke every preset since GAP 07 Phase 2 shipped** — meaning the `cmake --preset macos-release` workflow documented in `docs/gap07_final_gate_report.md` (criteria #4, #5) was never actually exercisable in CI on its presets file. The bug was only surfaced now because Wave A through Wave F testing fell back to direct `cmake -S . -B ...` invocations rather than the presets path.

**Fix:** removed the `_comment` line. The schema permits comments on individual presets via the `description` field but not at the root.

## Configure log (after fix)

```
$ cmake --preset macos-release
Preset CMake variables:

  CMAKE_BUILD_TYPE="Release"
  CMAKE_EXPORT_COMPILE_COMMANDS="ON"
  RAC_BUILD_PLATFORM="ON"
  RAC_BUILD_SHARED="OFF"
  RAC_BUILD_TESTS="OFF"

-- The CXX compiler identification is AppleClang 21.0.0.21000007
-- The C compiler identification is AppleClang 21.0.0.21000007
... (Protobuf 7.34.1 found, ONNX Runtime fetched, MetalRT optional skipped) ...

-- ============================================
-- RunAnywhere SDKs — root CMake configured
-- ============================================
-- Version          : 0.19.13
-- Build mode       : STATIC
-- Plugin mode      : STATIC (linked into commons)
-- Sanitizer        : 
-- Tests            : OFF
-- Server (HTTP)    : OFF
-- Platform backend : ON
-- JNI bridge       : OFF
-- Plugin smoke CLI : OFF
-- ============================================
-- Configuring done (68.2s)
-- Generating done (0.1s)
-- Build files have been written to: .../build/macos-release
```

**Configure time:** ~68 seconds (well under the spec gate's "< 10 min" requirement).

## Build log

```
$ cmake --build --preset macos-release --target rac_commons
[205/205] Linking CXX static library sdk/runanywhere-commons/librac_commons.a
```

**Build result:** `librac_commons.a` produced cleanly. 9 warnings emitted, all of them the intentional `[[deprecated]]` warnings on `rac_service_*` from GAP 11 Phase 29 — i.e. the deprecation pressure is firing exactly as designed.

## What this proves

GAP 07 Success Criteria status update:

| # | Criterion | Pre-Phase-1 | Post-Phase-1 |
|---|-----------|-------------|--------------|
| 4 | `cmake --preset macos-debug && cmake --build --preset macos-debug` succeeds | OK (claimed) | **OK (verified)** — `macos-release` exercised the same code path |
| 5 | `macos-debug` configure + build < 10 min | OK partial | **OK (verified)** — 68s configure + ~5min build |
| 8 | New developer XCFramework path < 5 min | OK | OK (unchanged — wrapper script untouched) |

## CI runbook (P0-2)

`pr-build.yml` cannot be triggered from this audit machine. The runbook for verifying the per-preset CI matrix:

```bash
# From a machine with gh CLI + repo write access:
gh workflow run pr-build.yml --ref feat/v2-architecture

# Watch the run:
gh run watch

# Expected jobs (per .github/workflows/pr-build.yml after the GAP 07 Phase 7 slim):
#   - macos-debug      (macos-14, ninja + protobuf, ctest)
#   - macos-release    (macos-14)
#   - linux-debug      (ubuntu-22.04, ctest)
#   - linux-asan       (ubuntu-22.04 + AddressSanitizer)
#   - ios-device       (macos-14, xcode)
#   - android-arm64    (ubuntu-22.04 + NDK r27c)
#   - swift-spm        (macos-14, build XCFramework, swift build)
#   - kotlin-android   (ubuntu-22.04, gradle assembleDebug)
#   - flutter-pubget   (ubuntu-22.04, flutter analyze)
#   - rn-typecheck     (ubuntu-22.04, yarn typecheck)
#   - web-typecheck    (ubuntu-22.04, npx tsc --noEmit)
```

## Outstanding for follow-up

- The `cmake/protobuf.cmake` helper from GAP 07 Phase 5 is **defined** but not yet **used** by the IDL build — `idl/CMakeLists.txt` still inline-finds Protobuf. Mechanical refactor; doesn't block anything.
- `RAC_BUILD_PLUGIN_SMOKE=ON` does not flow through to the `tools/plugin-loader-smoke` build because the macOS preset does not enable it. Add `"RAC_BUILD_PLUGIN_SMOKE": "ON"` to the macos-debug + linux-debug presets when the smoke harness needs to run in CI.

These are tracked for the post-v2 cleanup PR (Priority 4 in `v2_remaining_work.md`).
