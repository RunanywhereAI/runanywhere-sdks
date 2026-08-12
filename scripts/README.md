# `scripts/` — index

Every shell script in the repo lives in one of these places, organized by scope:

## Repo-root `scripts/` (cross-cutting, grouped by function)

These serve multiple SDKs or the whole repo, so they're grouped by **function**
(per-SDK scripts live under `bindings/<name>/scripts/`, below).

### `build/` — native core builds (cross-cutting → stage into multiple SDKs)
| Script | Purpose |
|---|---|
| `build/build-core-android.sh` | Native build for Android consumers (per-ABI `.so`, staged into kotlin/rn/flutter `jniLibs/`). Stays at root — it serves three SDKs. |

> The Apple xcframework builder and the Web/WASM builder were moved into their
> owning SDKs (`bindings/swift/scripts/build-core-xcframework.sh`,
> `bindings/web/scripts/build-core-wasm.sh`) — see the per-SDK section below.
> `sync-swift-headers.sh` was deleted (unused; the vendored Swift headers are hand-maintained).

### `release/` — version / packaging
| Script | Purpose |
|---|---|
| `release/sync-versions.sh <version>` | Bumps the version string across every manifest (`VERSION`, `VERSIONS`, `Package.swift`, `gradle.properties`, all `package.json`/`pubspec.yaml`). Run before tagging. Cross-cutting — stays at root. |
| `release/validate-artifact.sh <file>...` | Type-aware artifact sanity check (XCFramework / `.so` / `.aar` / `.wasm` / `.tgz`). Called by every `package-sdk.sh`. |

> `sync-checksums.sh` and `release-swift-binaries.sh` moved into
> `bindings/swift/scripts/` (Swift-release-specific) — see below.

### `setup/` — dev environment
| Script | Purpose |
|---|---|
| `setup/doctor.sh` | Scans host toolchains and prints what can be built. |
| `setup/setup.sh [target]` | Provisions `local.properties` + deps per platform. |
| `setup/setup-toolchain.sh` | Installs/verifies the pinned IDL codegen toolchain (protoc, swift-protobuf, ts-proto, …). |
| `setup/detect-mode.sh` | Sourced helper: exports `RAC_BUILD_MODE=local\|ci`. |

## Validation command hub — `scripts/validation/`

Organized into `gates/` (CI rule-gates wired into `pr-build.yml`), `commons/`
(C++ commons checks), and `e2e/` (the seven-lane harness, invoked by the local
e2e skills). Output lands under `build/validation/`, not ad hoc root folders.
See `scripts/validation/README.md` for the full per-script table.

## Per-SDK `bindings/<lang>/scripts/`

Each client SDK has a `scripts/` folder next to its source. With the single-root CMake layout, the per-SDK build *orchestrators* were removed — native artifacts are produced by the `build-core-*.sh` scripts (Android at `scripts/build/`; Apple and Web each live in their own SDK's `scripts/` folder), and the SDK itself is compiled directly by its native toolchain (Xcode/SwiftPM, Gradle, Vite, Melos, Yarn).

The one canonical per-SDK script is the release packager:

| Name | Purpose |
|---|---|
| `package-sdk.sh` | **Unified release packaging contract.** Consumes *pre-built* natives (from `--natives-from PATH` or canonical `dist/` location) and produces the SDK's distributable artifacts (AAR/JAR, npm `.tgz`, etc.) with `.sha256` sidecars. Same interface across every SDK: `package-sdk.sh [--mode local|ci] [--natives-from PATH]`. |

Per-SDK scripts currently in tree:

```
bindings/swift/scripts/
    package-sdk.sh                     # unified release packaging contract
    build-core-xcframework.sh          # builds the Apple xcframeworks (cmake presets) → Binaries/ (+ stages RN/Flutter iOS)
    release-swift-binaries.sh          # local iOS/macOS release packager (zip + checksums)
    sync-checksums.sh                  # patches the root Package.swift checksum: lines

bindings/kotlin/scripts/
    package-sdk.sh                     # unified contract; Gradle drives the rest

bindings/web/scripts/
    package-sdk.sh                     # unified contract; npm drives the rest
    build-core-wasm.sh                 # builds the WebAssembly artifacts (Emscripten) → packages/llamacpp/wasm

bindings/flutter/scripts/
    package-sdk.sh                     # unified contract; melos + flutter pub drive the rest

bindings/react-native/scripts/
    package-sdk.sh                     # unified contract; yarn workspaces drive the rest
```

For day-to-day iteration, build natives via `scripts/build/build-core-android.sh` (Android), `bindings/swift/scripts/build-core-xcframework.sh` (Apple), or `bindings/web/scripts/build-core-wasm.sh` (Web), then drive the SDK's own toolchain (`RUNANYWHERE_USE_LOCAL_NATIVES=1 swift build`, `./gradlew assembleDebug`, `npm run build:ts`, `flutter pub get`, `yarn typecheck`).

## `core/scripts/` (C++ native build helpers)

Day-to-day native builds use the platform core builders. The release entry
points in `core/scripts/` call those builders and add the
strict, deterministic archive staging consumed by `release.yml`; the remaining
files are platform-specific helpers.

```
core/scripts/
    build-ios.sh                     # canonical Apple release build + versioned XCFramework archives
    build-android.sh                 # canonical per-ABI Android release build + public archive
    build-linux.sh                   # canonical Linux release build + versioned tarball
    build-windows.bat                # Windows MSVC .lib/.dll (no root-level equivalent yet)
    lint-cpp.sh                      # clang-format gate; --fix for in-place edits
    load-versions.sh                 # sources VERSIONS file into $ENV; sourced by every build helper

    ios/download-onnx.sh             # ONNX Runtime for iOS
    ios/download-sherpa-onnx.sh      # Sherpa-ONNX for iOS
    android/download-sherpa-onnx.sh  # Sherpa-ONNX for Android (all ABIs)
    linux/download-sherpa-onnx.sh    # Sherpa-ONNX for Linux
    macos/download-onnx.sh           # ONNX Runtime for macOS
    macos/download-sherpa-onnx.sh    # Sherpa-ONNX for macOS
    windows/download-sherpa-onnx.bat # Sherpa-ONNX for Windows
```

Use the core builders for local iteration and these three release entry points
when producing publishable archives. Native artifacts land under
`bindings/swift/Binaries/` (Apple) or each SDK's `jniLibs/` tree
(Android); release archives and checksums land under
`core/dist/`.

## Test scripts — `core/tests/scripts/`

```
run-tests.sh            # per-platform entry
run-tests-{ios,android,linux,web}.sh
run-tests-all.sh
download-test-models.sh
```

## WASM build — `bindings/web/wasm/scripts/`

Emscripten-specific helpers invoked by the repo-root `bindings/web/scripts/build-core-wasm.sh`:

```
build.sh                # WASM compile orchestrator
build-sherpa-onnx.sh    # Sherpa-ONNX WASM module
setup-emsdk.sh          # installs Emscripten toolchain
```

## Why scripts live where they do

Root `scripts/` holds **cross-cutting** automation, grouped by function
(`build/`, `release/`, `setup/`, `validation/`). Each script derives the repo
root from its own location (`$(dirname …)/../..`, or `/../../..` for the nested
`validation/` subfolders), so paths resolve the same whether invoked directly or
via `./run`. Per-SDK and commons helpers stay next to the project they build, so
they can reference that project's `CMakeLists.txt` / `VERSIONS` / `third_party/`
relatively.

**Rule of thumb when adding a new script:**
- **Cross-cutting utility for multiple SDKs or the whole repo?** → `scripts/<build|release|setup|validation>/` at repo root.
- **Scoped to one SDK's build/release/test flow?** → `bindings/<lang>/scripts/`.
- **Native build helper that depends on commons' CMake?** → `core/scripts/`.
- **Test runner?** → `core/tests/scripts/`.

## CI workflows that call these scripts

- `.github/workflows/pr-build.yml` — calls the repo-root `bindings/swift/scripts/build-core-xcframework.sh` and `scripts/build/build-core-android.sh` for native matrix jobs; calls each SDK's build/gradle/npm tooling for SDK jobs. (Linux/Windows/WASM are exercised via CMake presets directly.)
- `.github/workflows/release.yml` — invokes the canonical `core/scripts/build-{ios,android,linux}.sh` release packagers, the WASM build via `npm run build:wasm` (→ `wasm/scripts/build.sh`), and `package-sdk.sh` per SDK plus `sync-checksums.sh` after iOS builds land.
- `.github/actions/setup-toolchain/action.yml` — loads `core/VERSIONS` into `$GITHUB_ENV` so every script sees the same pinned tool versions.
