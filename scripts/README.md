# `scripts/` — index

Every shell script in the repo lives in one of these places, organized by scope:

## Repo-root `scripts/` (cross-cutting)

| Script | Purpose |
|---|---|
| `detect-mode.sh` | Sources `$CI` / `$GITHUB_ACTIONS` to export `RAC_BUILD_MODE=local\|ci`. Other scripts `source` it to share the same detection. |
| `sync-versions.sh <version>` | Bumps the version string in every manifest across the monorepo (`VERSION`, `VERSIONS`, `Package.swift`, `gradle.properties`, all `package.json`, all `pubspec.yaml`). Run locally before tagging a release. |
| `sync-checksums.sh <zip_dir>` | Reads SHA-256 of freshly-built XCFramework zips and updates the `checksum: "..."` lines in root `Package.swift`. Run in the release workflow after native iOS/macOS builds produce the zips. |
| `validate-artifact.sh <file>...` | Type-aware sanity check for each artifact extension (XCFramework Info.plist + slices, `.so` ELF magic, `.aar` classes.jar + jni, `.wasm` magic bytes, `.tgz` package.json). Same script runs locally and in CI. |

## Per-SDK `sdk/runanywhere-<lang>/scripts/`

Each client SDK has a `scripts/` folder next to its source with scripts scoped to that SDK. Two canonical names to know:

| Name | Purpose |
|---|---|
| `build-<lang>.sh` | **Developer pipeline orchestrator.** Full build from source — rebuilds C++ (runanywhere-commons), copies natives into place, then builds the SDK. For day-to-day iteration. |
| `package-sdk.sh` | **Unified release packaging contract.** Consumes *pre-built* natives (from `--natives-from PATH` or canonical `dist/` location) and produces the SDK's distributable artifacts (AAR/JAR, npm `.tgz`, etc.) with `.sha256` sidecars. Same interface across every SDK: `package-sdk.sh [--mode local|ci] [--natives-from PATH]`. |

Per-SDK scripts currently in tree:

```
sdk/runanywhere-swift/scripts/
    build-swift.sh                   # --setup | --build-commons | --set-local | --set-remote
    package-sdk.sh                   # unified contract
    create-onnxruntime-xcframework.sh  # one-shot helper for building the combined ONNXRuntime xcframework

sdk/runanywhere-kotlin/scripts/
    build-kotlin.sh                  # full pipeline
    build-sdk.sh                     # thin wrapper over build-kotlin.sh
    package-sdk.sh                   # unified contract

sdk/runanywhere-web/scripts/
    build-web.sh                     # WASM + TypeScript build
    package-sdk.sh                   # unified contract

sdk/runanywhere-flutter/scripts/
    build-flutter.sh                 # developer pipeline
    package-sdk.sh                   # unified contract

sdk/runanywhere-react-native/scripts/
    build-react-native.sh            # developer pipeline
    package-sdk.sh                   # unified contract
```

## `sdk/runanywhere-commons/scripts/` (C++ native build)

Native library build scripts for commons + each backend. Stay here because they use relative paths to commons' `CMakeLists.txt` and `third_party/`.

```
sdk/runanywhere-commons/scripts/
    build-ios.sh                     # iOS + macOS XCFrameworks
    build-android.sh                 # per-ABI .so via NDK
    build-linux.sh                   # Linux x86_64 .so / static .a
    build-windows.bat                # Windows MSVC .lib/.dll
    build-server.sh                  # OpenAI-compatible HTTP server (optional target)
    load-versions.sh                 # sources VERSIONS file into $ENV; sourced by all build-*.sh

    ios/download-onnx.sh             # ONNX Runtime for iOS
    ios/download-sherpa-onnx.sh      # Sherpa-ONNX for iOS
    android/download-sherpa-onnx.sh  # Sherpa-ONNX for Android (all ABIs)
    linux/download-sherpa-onnx.sh    # Sherpa-ONNX for Linux
    macos/download-onnx.sh           # ONNX Runtime for macOS
    macos/download-sherpa-onnx.sh    # Sherpa-ONNX for macOS
    windows/download-sherpa-onnx.bat # Sherpa-ONNX for Windows
```

Output convention: all scripts write to `sdk/runanywhere-commons/dist/<platform>/...` (canonical).

## Test scripts — `sdk/runanywhere-commons/tests/scripts/`

```
run-tests.sh            # per-platform entry
run-tests-{ios,android,linux,web}.sh
run-tests-all.sh
download-test-models.sh
```

## WASM build — `sdk/runanywhere-web/wasm/scripts/`

Emscripten-specific helpers invoked by the top-level `build-web.sh`:

```
build.sh                # WASM compile orchestrator
build-sherpa-onnx.sh    # Sherpa-ONNX WASM module
setup-emsdk.sh          # installs Emscripten toolchain
```

## Why scripts aren't all in one folder

The build scripts use `SCRIPT_DIR/..` relative paths to find their project's `CMakeLists.txt`, `VERSIONS` file, and `third_party/` folder. Moving them would require rewriting those paths and breaks the "script is scoped to the project it builds" convention that every platform's build system follows.

**Rule of thumb when adding a new script:**
- **Cross-cutting utility that operates on multiple SDKs or the whole repo?** → `scripts/` at repo root.
- **Scoped to one SDK's build/release/test flow?** → `sdk/runanywhere-<lang>/scripts/`.
- **Native build helper that depends on commons' CMake?** → `sdk/runanywhere-commons/scripts/`.
- **Test runner?** → `sdk/runanywhere-commons/tests/scripts/`.

## CI workflows that call these scripts

- `.github/workflows/pr-build.yml` — calls `build-{ios,android,linux,web}.sh` and `build-windows.bat` for native matrix jobs; calls each SDK's build/gradle/npm tooling for SDK jobs.
- `.github/workflows/release.yml` — same native matrix, plus invokes `package-sdk.sh` per SDK and `sync-checksums.sh` after iOS builds land.
- `.github/actions/setup-toolchain/action.yml` — loads `sdk/runanywhere-commons/VERSIONS` into `$GITHUB_ENV` so every script sees the same pinned tool versions.
