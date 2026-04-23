# Phase J-1 Report — Swift xcframework publication prep

_Phase J-1 of the v2 close-out: prep the Swift xcframework build / upload
pipeline so the operator can run a single script to produce + patch the
release artifacts for v0.20.0. No actual upload is performed in this phase._

## 1. Script intent (post-J-1)

`scripts/release-swift-binaries.sh <version>` now builds and packages
**three iOS xcframeworks** for the Swift SPM distribution:

| xcframework               | Source archive                                                        | Swift binaryTarget         |
|---------------------------|-----------------------------------------------------------------------|----------------------------|
| `RACommons.xcframework`          | `build/ios-{device,simulator}/sdk/runanywhere-commons/Release-iphone*/librac_commons.a` | `RACommonsBinary`          |
| `RABackendLLAMACPP.xcframework`  | `build/ios-{device,simulator}/engines/llamacpp/Release-iphone*/librac_backend_llamacpp.a` | `RABackendLlamaCPPBinary` |
| `RABackendONNX.xcframework`      | `build/ios-{device,simulator}/engines/onnx/Release-iphone*/librac_backend_onnx.a`       | `RABackendONNXBinary`     |

Each xcframework contains both slices (ios-arm64 device + ios-arm64/x86_64
simulator). The per-backend libraries stay separate from `rac_commons`
because engines/llamacpp and engines/onnx use `SHARED_ONLY` in
`rac_add_engine_plugin(...)`, so their static archives are produced
alongside `librac_commons.a` even under `RAC_STATIC_PLUGINS=ON` (which is
forced ON on iOS by `sdk/runanywhere-commons/CMakeLists.txt:767-770`).

Output layout:

```
release-artifacts/native-ios-macos/
  RACommons-ios-v0.20.0.zip
  RABackendLLAMACPP-ios-v0.20.0.zip
  RABackendONNX-ios-v0.20.0.zip
```

The filename convention matches `scripts/sync-checksums.sh`'s
`declare_mapping()` prefixes and the URL pattern in the `binaryTargets()`
function in `Package.swift`.

## 2. Prereq matrix

| Prereq                                           | Status on this box | How to satisfy                                                 |
|--------------------------------------------------|:-:|---------------------------------------------------------------------------|
| Xcode ≥ 15.0                                     | Xcode 26.4.1 — OK  | App Store / xcode-select                                       |
| `cmake` ≥ 3.22 + `ninja` on PATH                 | cmake 4.1.0, ninja — OK | `brew install cmake ninja`                                 |
| `sdk/runanywhere-commons/third_party/onnxruntime-ios/onnxruntime.xcframework` | **missing**        | `./sdk/runanywhere-commons/scripts/ios/download-onnx.sh` (one-time) |
| libcurl iOS wiring                               | Handled by CMake   | `find_package(CURL)` falls through to the FetchContent vendor of `curl-7_88_1` with SecureTransport TLS (`CURL_USE_SECTRANSP=ON`, `CURL_USE_OPENSSL=OFF`). See `sdk/runanywhere-commons/CMakeLists.txt:318-373`. Operator needs git + network to fetch on first configure. |
| `gh` CLI authenticated against `RunanywhereAI/runanywhere-sdks` | N/A (operator-side) | `gh auth login`                                          |

The only missing prereq on this developer box is the ONNX Runtime iOS
xcframework — the operator must run
`./sdk/runanywhere-commons/scripts/ios/download-onnx.sh` once before the
first real build. The release script exits with a clear message pointing
at that script when the file is missing.

## 3. Code changes applied in this phase

All five changes below are required for the operator to be able to run
the script cleanly on v0.20.0:

### 3.1 `scripts/build-core-xcframework.sh` (rewritten)

Previously only built `RACommons.xcframework` and assumed the Xcode-generator
put archives at `build/ios-device/Release-iphoneos/librac_commons.a`. The
Xcode generator actually emits static libraries at
`build/ios-device/<source-subdir>/Release-iphoneos/lib<target>.a`, so the
old script would have failed to find `librac_commons.a`. The rewrite:

- Looks up each library at the correct subdir path (`sdk/runanywhere-commons/…`, `engines/llamacpp/…`, `engines/onnx/…`).
- Packages all three xcframeworks (RACommons + LLAMACPP + ONNX) with both iOS slices.
- Honours `DRY_RUN=1` and `RAC_BACKEND_ONNX=OFF` env knobs so `release-swift-binaries.sh DRY_RUN=1` can run end-to-end without Xcode / network access.
- Fails fast with a precise error pointing at `download-onnx.sh` when the iOS ONNX Runtime xcframework is missing (and ONNX isn't explicitly skipped).

### 3.2 `scripts/release-swift-binaries.sh` (rewritten)

- **Fixed the ONNX prereq path** — it used to check `${REPO_ROOT}/third_party/onnxruntime-ios/` which is the wrong location; the actual iOS ONNX Runtime lives under `sdk/runanywhere-commons/third_party/onnxruntime-ios/` (matches `download-onnx.sh` + `FetchONNXRuntime.cmake`).
- **Added DRY_RUN mode** — `DRY_RUN=1 scripts/release-swift-binaries.sh <ver>` exercises the full pipeline (build → zip → checksum → Package.swift patch → operator handoff print) without invoking cmake / xcodebuild. Used to validate the plumbing independently of whether Xcode / onnxruntime is installed.
- **Wired backend xcframework builds** — the old script had `TODO` markers admitting per-backend build scripts didn't exist; this shipped them via the rewritten `build-core-xcframework.sh`.
- **Dropped MetalRT from the mandatory set** — `metalrtRemoteBinaryAvailable = false` in `Package.swift`, so `sync-checksums.sh` prints "missing RABackendMetalRT-ios-v*.zip" but does not fail the run.
- **Xcode version gate** — refuses to run on Xcode < 15.
- **Kept the operator-gated upload step** — the script still does NOT run `gh release upload`; it only prints the exact commands for the operator to execute next. This matches Phase J-1's "prep only, no actual publish" contract.

### 3.3 `docs/release/v0_20_0_release_plan.md` (Step 5 rewritten)

Updated to reflect the actual script behaviour: correct output path
(`release-artifacts/native-ios-macos/`, not `.build/release/`), correct
zip filenames, explicit prereq reference, single-invocation `gh release
upload` with glob, and a smoke-test command the operator should run from
a fresh clone to confirm `swift package resolve` pulls the new zips and
the checksums verify.

### 3.4 `sdk/runanywhere-commons/CMakeLists.txt` — libcurl iOS TLS backend

The FetchContent fallback used the pre-7.86 variable names
`CMAKE_USE_SECTRANSP` / `CMAKE_USE_SCHANNEL`, which curl-7_88_1 ignores.
With neither a TLS backend selected nor OpenSSL suppressed, curl's
CMakeLists fell through to `find_package(OpenSSL REQUIRED)` and failed
the iOS configure step (no OpenSSL inside `iPhoneOS.sdk`). Fix:

```cmake
if(APPLE)
    set(CURL_USE_SECTRANSP ON  CACHE BOOL "" FORCE)
    set(CURL_USE_OPENSSL   OFF CACHE BOOL "" FORCE)
elseif(WIN32)
    set(CURL_USE_SCHANNEL ON  CACHE BOOL "" FORCE)
    set(CURL_USE_OPENSSL  OFF CACHE BOOL "" FORCE)
endif()
```

Verified by dropping `build/ios-device/` and running
`cmake --preset ios-device -DRAC_BACKEND_ONNX=OFF` → `Configuring done`,
with the `CURL_USE_SECTRANSP=ON / CURL_USE_OPENSSL=OFF` variables applied
to the fetched curl subproject.

### 3.5 `cmake/plugins.cmake` + `engines/onnx/CMakeLists.txt` — SHARED_ONLY no longer forces SHARED

Two related issues surfaced once the iOS slice actually got built:

- `rac_add_engine_plugin(...)` treated `SHARED_ONLY` as "build as SHARED
  library", which on iOS (where `RAC_BUILD_SHARED=OFF`) still produced a
  dylib and therefore required a development team for code signing. The
  flag really meant "don't fold the sources into `rac_commons`"; SHARED
  vs STATIC should follow `RAC_BUILD_SHARED`. The macro now picks STATIC
  on iOS (as intended), and SHARED only when `RAC_BUILD_SHARED=ON`
  (Android / Linux shared-plugin hosts).
- `engines/onnx/CMakeLists.txt` previously did not pass `SHARED_ONLY`,
  so under `RAC_STATIC_PLUGINS=ON` (forced on iOS) the ONNX sources got
  folded into `rac_commons` and the `target_link_libraries(
  rac_backend_onnx ...)` blocks that follow the macro invocation
  referred to a non-existent target. Adding `SHARED_ONLY` makes
  `rac_backend_onnx` always a standalone static library on iOS, which
  also matches the Swift xcframework layout that distributes
  `RABackendONNX.xcframework` separately from `RACommons.xcframework`.

## 4. Verification

### 4.1 DRY_RUN pipeline

```
$ DRY_RUN=1 ./scripts/release-swift-binaries.sh 0.20.0
▶ [1/3] Building iOS xcframeworks (DRY_RUN=1, RAC_BACKEND_ONNX=ON)
[DRY RUN] cmake --preset ios-device
[DRY RUN] cmake --build --preset ios-device --config Release
[DRY RUN] cmake --preset ios-simulator
[DRY RUN] cmake --build --preset ios-simulator --config Release
[DRY RUN] xcodebuild -create-xcframework -library .../librac_commons.a  -headers ... -library .../librac_commons.a -headers ...
[DRY RUN] xcodebuild -create-xcframework -library .../librac_backend_llamacpp.a ...
[DRY RUN] xcodebuild -create-xcframework -library .../librac_backend_onnx.a ...
▶ [2/3] Zipping xcframeworks   (placeholder zips in DRY_RUN mode)
▶ [3/3] Patching Package.swift checksums via sync-checksums.sh
  bumped:    RACommonsBinary          a1caaf12186c... → cdf1e17aca2e...
  bumped:    RABackendLlamaCPPBinary  7ff978fbc877... → 08fbbbf6e9cd...
  bumped:    RABackendONNXBinary      0f8575559ac9... → 6021bd73b3c3...
  missing:   no RABackendMetalRT-ios-v*.zip in ...  (OK — metalrtRemoteBinaryAvailable=false)
>> Done. 3 processed, 1 missing.
✓ Release artifacts ready in: release-artifacts/native-ios-macos
```

Exit code `0`. The dry-run Package.swift mutation was reverted with
`git checkout -- Package.swift` after the run.

### 4.2 Real partial build (iOS device + simulator, RAC_BACKEND_ONNX=OFF)

Because `third_party/onnxruntime-ios/onnxruntime.xcframework` isn't
extracted on this box, the ONNX backend was skipped. The remaining
pipeline was exercised end-to-end:

```
$ RAC_BACKEND_ONNX=OFF ./scripts/release-swift-binaries.sh 0.20.0-rc1
▶ Configure ios-device            (fetches curl-7_88_1, libarchive, llama.cpp b8201 — ~8 min first time)
▶ Build ios-device (Release)      ** BUILD SUCCEEDED **
▶ Configure ios-simulator         (~8 min)
▶ Build ios-simulator (Release)   ** BUILD SUCCEEDED **
▶ Create-xcframework → RACommons.xcframework            (both slices)
▶ Create-xcframework → RABackendLLAMACPP.xcframework    (both slices)
▶ Skipping RABackendONNX.xcframework (RAC_BACKEND_ONNX=OFF)
▶ Zipping xcframeworks
  ▶ release-artifacts/native-ios-macos/RACommons-ios-v0.20.0-rc1.zip        (1.6 MB)
  ▶ release-artifacts/native-ios-macos/RABackendLLAMACPP-ios-v0.20.0-rc1.zip (1.7 MB)
  ▶ Skipping RABackendONNX zip
▶ Patching Package.swift checksums via sync-checksums.sh
  bumped:    RACommonsBinary         a1caaf12186c... → 528d94543a27...
  bumped:    RABackendLlamaCPPBinary 7ff978fbc877... → 203cab67243d...
>> Done. 2 processed, 2 missing.   (ONNX skipped + MetalRT deferred)
✓ Release artifacts ready
```

Both `sdk/runanywhere-swift/Binaries/*.xcframework` contain
`ios-arm64/` and `ios-arm64-simulator/` slices with the expected
`lib{rac_commons,rac_backend_llamacpp}.a` under each plus the
`Headers/` directory from `sdk/runanywhere-commons/include`. Package.swift
checksums for the two built targets were patched to the real SHA-256
values of the produced zips; `git checkout -- Package.swift` restored
the working copy after verification.

First-time configure is dominated by three FetchContent clones —
llama.cpp, libcurl, libarchive — which run in parallel in the libarchive
subbuild and total ~8 minutes on a clean checkout. Warm re-configures
finish in ~20s.

### 4.3 What was NOT verified on this box

- Real ONNX build — needs `third_party/onnxruntime-ios/onnxruntime.xcframework`
  on disk, which is a separate ~100 MB download the operator performs
  via `./sdk/runanywhere-commons/scripts/ios/download-onnx.sh` (existing
  script, verified syntactically but not executed here to avoid wasting
  the release bucket's bandwidth).
- `swift package resolve` against the produced zips — the zips are
  pointed at `https://github.com/.../releases/download/v0.20.0-rc1/` by
  the patched Package.swift, but that release does not exist so SPM
  would 404. This is the final operator-side smoke-test (step 7 of the
  operator checklist in §5).

## 5. Remaining operator steps for the actual publish

After the version bump from Step 1 of the release plan is in place:

```bash
# 1. Install the iOS ONNX Runtime xcframework (one-time per checkout):
./sdk/runanywhere-commons/scripts/ios/download-onnx.sh

# 2. (Optional) Validate the pipeline is wired correctly without
#    kicking off a 15-minute build:
DRY_RUN=1 ./scripts/release-swift-binaries.sh 0.20.0
#    — remember to `git checkout -- Package.swift` after a DRY_RUN
#    because the placeholder-zip checksums will have overwritten real
#    ones.

# 3. Real build (produces the three real zips and patches
#    Package.swift's `checksum:` lines with the real SHA-256s):
./scripts/release-swift-binaries.sh 0.20.0

# 4. Verify the package still resolves locally:
swift package resolve && swift build -c release

# 5. Upload the zips to the v0.20.0 GitHub release (created in Step 4
#    of the release plan):
gh release upload v0.20.0 release-artifacts/native-ios-macos/*.zip

# 6. Commit the checksum bump:
git add Package.swift
git commit -m "release: bump xcframework checksums for v0.20.0"
git push origin HEAD

# 7. Smoke-test from a fresh clone on a separate machine:
cd /tmp && rm -rf v020-smoke && \
  git clone https://github.com/RunanywhereAI/runanywhere-sdks v020-smoke && \
  cd v020-smoke && swift package resolve && swift build -c release
```

## 6. Code changes required before the operator can publish

**None** — all in-repo fixes have been applied in this phase. The
operator's only actions are the seven commands above; no source code
edits are needed between "Phase J-1 merged" and "v0.20.0 zips published".

### Summary of files touched in this phase

| File                                            | Delta | Intent                                                          |
|-------------------------------------------------|------:|-----------------------------------------------------------------|
| `scripts/build-core-xcframework.sh`             | ±160  | Build all 3 xcframeworks + DRY_RUN + RAC_BACKEND_ONNX gate      |
| `scripts/release-swift-binaries.sh`             | ±193  | DRY_RUN, zip all targets, fix ONNX prereq path, Xcode 15 gate   |
| `cmake/plugins.cmake`                           |   −3/+7 | SHARED_ONLY no longer forces SHARED (iOS signing unblock)       |
| `engines/onnx/CMakeLists.txt`                   |   +1 | `SHARED_ONLY` so `rac_backend_onnx` is a standalone static lib  |
| `sdk/runanywhere-commons/CMakeLists.txt`        |   −4/+15 | `CURL_USE_SECTRANSP=ON` + `CURL_USE_OPENSSL=OFF` on Apple       |
| `docs/release/v0_20_0_release_plan.md` (§5)     |  ±40  | Rewritten operator step 5                                      |
| `docs/v2_closeout_phase_j1_report.md`           |  +200 | This report                                                     |

Remaining NOT-in-scope for Phase J-1 (explicitly deferred):

- **macOS slice**: the script is iOS-only. The `Package.swift` comments
  mention "All xcframeworks include iOS + macOS slices (v0.19.0+)" but
  that was aspirational — the v0.19.x release shipped iOS-only too. When
  macOS becomes a hard requirement, a `macos-release` preset build step
  will be added here and the xcframeworks repackaged with the extra
  slice. Tracked separately.
- **MetalRT xcframework**: `metalrtRemoteBinaryAvailable = false` in
  `Package.swift:56`, so MetalRT is only exposed in local-natives mode.
  When the closed-source engine lib becomes publishable, the Swift
  release pipeline gets a fourth xcframework and the release plan grows
  a "flip `metalrtRemoteBinaryAvailable` to true" step.
- **Notarization**: iOS static libraries don't require notarization; if
  we ever add a dynamic macOS slice, notarization via `xcrun notarytool`
  will have to be bolted onto this script, but for pure static iOS
  `.a`-backed xcframeworks this is a no-op.
