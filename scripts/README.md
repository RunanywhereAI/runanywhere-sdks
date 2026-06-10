# `scripts/` — index

Every shell script in the repo lives in one of these places, organized by scope:

## Repo-root `scripts/` (cross-cutting, grouped by function)

These serve multiple SDKs or the whole repo, so they're grouped by **function**
(per-SDK scripts live under `sdk/<name>/scripts/`, below).

### `build/` — native core builds (cross-cutting → stage into multiple SDKs)
| Script | Purpose |
|---|---|
| `build/build-core-android.sh` | Native build for Android consumers (per-ABI `.so`, staged into kotlin/rn/flutter `jniLibs/`). Stays at root — it serves three SDKs. |

> The Apple xcframework builder and the Web/WASM builder were moved into their
> owning SDKs (`sdk/runanywhere-swift/scripts/build-core-xcframework.sh`,
> `sdk/runanywhere-web/scripts/build-core-wasm.sh`) — see the per-SDK section below.
> `sync-swift-headers.sh` was deleted (unused; the vendored Swift headers are hand-maintained).

### `release/` — version / packaging
| Script | Purpose |
|---|---|
| `release/sync-versions.sh <version>` | Bumps the version string across every manifest (`VERSION`, `VERSIONS`, `Package.swift`, `gradle.properties`, all `package.json`/`pubspec.yaml`). Run before tagging. Cross-cutting — stays at root. |
| `release/validate-artifact.sh <file>...` | Type-aware artifact sanity check (XCFramework / `.so` / `.aar` / `.wasm` / `.tgz`). Called by every `package-sdk.sh`. |

> `sync-checksums.sh` and `release-swift-binaries.sh` moved into
> `sdk/runanywhere-swift/scripts/` (Swift-release-specific) — see below.

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

## Per-SDK `sdk/runanywhere-<lang>/scripts/`

Each client SDK has a `scripts/` folder next to its source. With the single-root CMake layout, the per-SDK build *orchestrators* were removed — native artifacts are produced by the `build-core-*.sh` scripts (Android at `scripts/build/`; Apple and Web each live in their own SDK's `scripts/` folder), and the SDK itself is compiled directly by its native toolchain (Xcode/SwiftPM, Gradle, Vite, Melos, Yarn).

The one canonical per-SDK script is the release packager:

| Name | Purpose |
|---|---|
| `package-sdk.sh` | **Unified release packaging contract.** Consumes *pre-built* natives (from `--natives-from PATH` or canonical `dist/` location) and produces the SDK's distributable artifacts (AAR/JAR, npm `.tgz`, etc.) with `.sha256` sidecars. Same interface across every SDK: `package-sdk.sh [--mode local|ci] [--natives-from PATH]`. |

Per-SDK scripts currently in tree:

```
sdk/runanywhere-swift/scripts/
    package-sdk.sh                     # unified release packaging contract
    build-core-xcframework.sh          # builds the Apple xcframeworks (cmake presets) → Binaries/ (+ stages RN/Flutter iOS)
    release-swift-binaries.sh          # local iOS/macOS release packager (zip + checksums)
    sync-checksums.sh                  # patches the root Package.swift checksum: lines
    create-onnxruntime-xcframework.sh  # one-shot helper for the combined ONNXRuntime xcframework

sdk/runanywhere-kotlin/scripts/
    package-sdk.sh                     # unified contract; Gradle drives the rest

sdk/runanywhere-web/scripts/
    package-sdk.sh                     # unified contract; npm drives the rest
    build-core-wasm.sh                 # builds the WebAssembly artifacts (Emscripten) → packages/llamacpp/wasm

sdk/runanywhere-flutter/scripts/
    package-sdk.sh                     # unified contract; melos + flutter pub drive the rest

sdk/runanywhere-react-native/scripts/
    package-sdk.sh                     # unified contract; yarn workspaces drive the rest
```

For day-to-day iteration, build natives via `scripts/build/build-core-android.sh` (Android), `sdk/runanywhere-swift/scripts/build-core-xcframework.sh` (Apple), or `sdk/runanywhere-web/scripts/build-core-wasm.sh` (Web), then drive the SDK's own toolchain (`swift build`, `./gradlew assembleDebug`, `npm run build:ts`, `flutter pub get`, `yarn typecheck`).

## `sdk/runanywhere-commons/scripts/` (C++ native build helpers)

Most native builds now go through the repo-root `scripts/build/build-core-*.sh`. The files in `sdk/runanywhere-commons/scripts/` are either thin compatibility wrappers (still referenced from `.github/workflows/release.yml` for byte-identical contracts) or one-shot platform-specific helpers (Windows batch script + third-party downloaders).

```
sdk/runanywhere-commons/scripts/
    build-ios.sh                     # COMPAT: forwards to sdk/runanywhere-swift/scripts/build-core-xcframework.sh
    build-android.sh                 # COMPAT: forwards to scripts/build/build-core-android.sh
    build-linux.sh                   # COMPAT: forwards to the linux-release CMake preset
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

The `build-{ios,android,linux}.sh` shims are kept temporarily so `release.yml` and existing docs continue to work — new callers should invoke the repo-root scripts directly. Output convention: native artifacts land under `sdk/runanywhere-swift/Binaries/` (Apple) or each SDK's `jniLibs/` tree (Android); the COMPAT shims additionally stage zips/tars into `sdk/runanywhere-commons/dist/<platform>/` for `release.yml`.

## Test scripts — `sdk/runanywhere-commons/tests/scripts/`

```
run-tests.sh            # per-platform entry
run-tests-{ios,android,linux,web}.sh
run-tests-all.sh
download-test-models.sh
```

## WASM build — `sdk/runanywhere-web/wasm/scripts/`

Emscripten-specific helpers invoked by the repo-root `sdk/runanywhere-web/scripts/build-core-wasm.sh`:

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
- **Scoped to one SDK's build/release/test flow?** → `sdk/runanywhere-<lang>/scripts/`.
- **Native build helper that depends on commons' CMake?** → `sdk/runanywhere-commons/scripts/`.
- **Test runner?** → `sdk/runanywhere-commons/tests/scripts/`.

## CI workflows that call these scripts

- `.github/workflows/pr-build.yml` — calls the repo-root `sdk/runanywhere-swift/scripts/build-core-xcframework.sh` and `scripts/build/build-core-android.sh` for native matrix jobs; calls each SDK's build/gradle/npm tooling for SDK jobs. (Linux/Windows/WASM are exercised via CMake presets directly.)
- `.github/workflows/release.yml` — invokes the legacy `sdk/runanywhere-commons/scripts/build-{ios,android,linux}.sh` shims (which forward to the repo-root scripts), the WASM build via `npm run build:wasm` (→ `wasm/scripts/build.sh`), and `package-sdk.sh` per SDK plus `sync-checksums.sh` after iOS builds land. Migrating release.yml to call the repo-root scripts directly is tracked separately.
- `.github/actions/setup-toolchain/action.yml` — loads `sdk/runanywhere-commons/VERSIONS` into `$GITHUB_ENV` so every script sees the same pinned tool versions.
