# Top-level infra — v1/v2 cleanup audit

> Analysis date: 2026-04-18. v2 = `cmake --preset */release` + SwiftPM (`frontends/swift`) +
> Gradle (`frontends/kotlin`) + pub (`frontends/dart`) + npm (`frontends/ts`, `frontends/web`).

---

## Summary

| Bucket | Count | Notable LOC |
|---|---|---|
| DELETE-NOW | 4 | ~6,750 (EXTERNAL dir + root yarn.lock + package-lock stub + comments/) |
| DELETE-AFTER-V1-REMOVAL | 9 | ~2,500 (pr-build.yml 597, release.yml 561, auto-tag.yml 153, root build.gradle.kts 357, root Package.swift 390, sync-versions.sh 152, sync-checksums.sh 126, jitpack.yml 31, validate-artifact.sh 139) |
| REPLACE-WITH-V2 | 5 | root Package.swift → frontends/swift/Package.swift; root build.gradle.kts + settings.gradle.kts + gradlew* + gradle.properties → frontends/kotlin/build.gradle.kts + settings.gradle.kts; CLAUDE.md and AGENTS.md get v2 rewrites |
| KEEP | 6 | LICENSE, SECURITY.md, CODE_OF_CONDUCT.md, secret-scan.yml, .github/actions/setup-toolchain, detect-mode.sh |
| INSPECT | 3 | Playground/, lefthook.yml, README.md |

**Top 5 highest-impact deletions (by artifact mass and confusion reduction):**
1. `EXTERNAL/` — 8 vendored repos with zero build system connection (~tens of thousands of LOC, see below)
2. `.github/workflows/pr-build.yml` (597 LOC) — entire path-filter matrix points at `sdk/` v1 paths
3. `.github/workflows/release.yml` (561 LOC) — builds v1 XCFrameworks, runs `sync-checksums.sh` against v1 `Package.swift`
4. Root `Package.swift` (390 LOC) — downloads v1 XCFrameworks from GitHub Releases; `sync-checksums.sh` only updates this file
5. Root `build.gradle.kts` (357 LOC) — wires v1 KMP SDK + v1 Android example + IntelliJ plugin; hardcodes NDK `27.0.12077973` at line 62

---

## DELETE-NOW

| Path | Reason | LOC/Size |
|---|---|---|
| `EXTERNAL/` | MASTER_PLAN calls it "reference graveyard." 8 vendored repos (FluidAudio, Local-Diffusion, local-dream, mlx-audio, stable-diffusion.cpp, ToolNeuron, WhisperKit, cl_stub). No `include()` in any CMakeLists.txt, no `dependencies {}` block pointing here. Zero build system connection. | Large (multiple repos) |
| `comments/` | 4 markdown files of raw PR review comments (PR_400, 409, 461, 478). Scratch notes only. | 4 files |
| `package-lock.json` | 6-line stub (`"packages": {}`). The real lock file for the React Native SDK is `sdk/runanywhere-react-native/package-lock.json`. | 6 lines |
| `yarn.lock` | 6,750 lines. Root-level yarn workspace lock for the v1 React Native SDK (`sdk/runanywhere-react-native/packages/*`). v2 React Native frontend lives at `frontends/ts/` with its own `package.json`. | 6,750 lines |

---

## DELETE-AFTER-V1-REMOVAL

| Path | Reason | LOC |
|---|---|---|
| `.github/workflows/pr-build.yml` | All 15 jobs and the `detect` path-filter matrix reference v1 SDK paths (`sdk/runanywhere-commons/**`, `sdk/runanywhere-swift/**`, `sdk/runanywhere-kotlin/**`, `sdk/runanywhere-flutter/**`, `sdk/runanywhere-react-native/**`). The setup-toolchain action is called for v1 platforms (`ios`, `android`, `web`, `sdk-only`). No v2 path is mentioned. | 597 |
| `.github/workflows/release.yml` | Builds v1 native artifacts via `sdk/runanywhere-commons/scripts/build-{ios,android,linux,windows}.sh`. Runs `scripts/sync-checksums.sh` to update v1 `Package.swift` checksums. Validates v1 SDK packages (Kotlin AAR, Web npm tarballs from `sdk/runanywhere-web`). Publishes a GitHub Release of v1 XCFramework zips. | 561 |
| `.github/workflows/auto-tag.yml` | Reads `PROJECT_VERSION` from `sdk/runanywhere-commons/VERSIONS` and calls `scripts/sync-versions.sh` — both are v1 version-management infrastructure. v2 version lives in root `CMakeLists.txt` project version `2.0.0`. | 153 |
| `scripts/sync-versions.sh` | Bumps version in `sdk/runanywhere-commons/VERSION`, `sdk/runanywhere-commons/VERSIONS`, root `Package.swift`, `sdk/runanywhere-kotlin/gradle.properties`, all `sdk/runanywhere-web/packages/*/package.json`, all `sdk/runanywhere-react-native/packages/*/package.json`, all `sdk/runanywhere-flutter/packages/*/pubspec.yaml`. Every target path is a v1 SDK path. | 152 |
| `scripts/sync-checksums.sh` | Updates `checksum: "..."` lines in root `Package.swift` (v1) for `RACommons`, `RABackendLLAMACPP`, `RABackendONNX`, `RABackendMetalRT` binary targets. v2 Swift package (`frontends/swift/Package.swift`) uses a `.binaryTarget` pointing at the CMake-built `RunAnywhereCore.xcframework` — no remote URL, no checksum line. | 126 |
| `scripts/validate-artifact.sh` | Validates v1 artifact shapes: XCFramework `.zip` (Info.plist + arch slices), `.so` ELF, `.aar` (classes.jar + JNI), `.wasm`, `.tgz` npm, `.jar`. All artifact types correspond to v1 release output. v2 CI uses `ctest` gates and sanitizer runs — no separate artifact validation step. | 139 |
| `jitpack.yml` | Ships v1 Kotlin SDK to JitPack. Points at `sdk/runanywhere-kotlin/gradlew`. Downloads pre-built JNI libs from GitHub Releases (`downloadJniLibs -Prunanywhere.useLocalNatives=false`). v2 Kotlin frontend distributes via Maven Central or direct AAR from `frontends/kotlin/build.gradle.kts` — no JitPack mechanism. | 31 |
| Root `build.gradle.kts` | 357-line root Gradle script. Includes `sdk/runanywhere-kotlin` (v1 KMP), `examples/android/RunAnywhereAI` (v1 example), `examples/intellij-plugin-demo/plugin` (v1 example). Hardcodes NDK `27.0.12077973` at line 62. Calls `build-kotlin.sh` at line 125. v2 Kotlin adapter is self-contained at `frontends/kotlin/build.gradle.kts`. | 357 |
| Root `settings.gradle.kts` | Includes `:runanywhere-kotlin` → `sdk/runanywhere-kotlin`, `:runanywhere-core-llamacpp` → `sdk/runanywhere-kotlin/modules/runanywhere-core-llamacpp`, `:runanywhere-core-onnx` → `sdk/runanywhere-kotlin/modules/runanywhere-core-onnx`. All v1 module paths. v2 uses `frontends/kotlin/settings.gradle.kts` (`rootProject.name = "runanywhere-v2-kotlin"`). | 42 |

---

## REPLACE-WITH-V2

| Before | After | What changes |
|---|---|---|
| `Package.swift` (root, 390 LOC) | `frontends/swift/Package.swift` | v1: downloads v1 XCFrameworks from GitHub Releases, wraps `sdk/runanywhere-swift/Sources/`. v2: references `RunAnywhereCore.xcframework` from local CMake build, name is `RunAnywhereV2`, uses `swift-protobuf`. Root `Package.swift` is the SPM entry point for external v1 consumers; once v1 goes away external consumers point at `frontends/swift/Package.swift` instead. |
| Root `build.gradle.kts` + `settings.gradle.kts` + `gradle.properties` + `gradlew` + `gradlew.bat` + `gradle/` | `frontends/kotlin/build.gradle.kts` + `frontends/kotlin/settings.gradle.kts` | v1 root Gradle wraps the KMP SDK + example apps + IntelliJ plugin. v2 Kotlin is standalone (`gradle --no-daemon build` in `frontends/kotlin/`). Root Gradle files have no v2 targets. After v1 deletion the root Gradle wrapper becomes dead weight unless v2 adopts it for a future top-level build orchestration task. |
| `CLAUDE.md` | Rewritten `CLAUDE.md` | Current file describes v1 SDK commands: `./scripts/sdk.sh`, CocoaPods `pod install`, `fix_pods_sandbox.sh`, `npm run build:wasm --setup`, `swift build` in `sdk/runanywhere-swift/`. All iOS guidance assumes `sdk/runanywhere-swift/`. All Kotlin guidance assumes `sdk/runanywhere-kotlin/`. v2 entry points are `cmake --preset *`, `swift build` in `frontends/swift/`, `gradle` in `frontends/kotlin/`. |
| `AGENTS.md` | Rewritten `AGENTS.md` | v1-specific: build table references `sdk/runanywhere-commons/`, `sdk/runanywhere-kotlin/`, `sdk/runanywhere-web/`. Quick-start for `Playground/linux-voice-assistant` references v1 commons build path. v2 entry point is `cmake --preset linux-debug` from repo root. |
| `CONTRIBUTING.md` | Rewritten `CONTRIBUTING.md` | Setup flow references `sdk/runanywhere-kotlin/scripts/sdk.sh android`, CocoaPods, `fix_pods_sandbox.sh`. v2 developer flow is `cmake --preset`, `swift build`, `gradle build` — no CocoaPods, no per-SDK setup scripts. |

---

## KEEP

| Path | Reason |
|---|---|
| `LICENSE` | Repository license. Unaffected by v1/v2 split. |
| `SECURITY.md` | Security disclosure policy. Repo-level, not SDK-level. |
| `CODE_OF_CONDUCT.md` | Community standards. Repo-level. |
| `.github/workflows/secret-scan.yml` | Gitleaks incremental diff scan on every PR and push to main. Scans the repo regardless of whether v1 or v2 code is staged. No paths in the scan are SDK-specific. |
| `.github/actions/setup-toolchain/action.yml` | Loads VERSIONS into `$GITHUB_ENV` and installs per-platform toolchain. Currently reads `sdk/runanywhere-commons/VERSIONS` for v1 tool pins. v2-core.yml does not use this action (it calls `brew install cmake ninja protobuf` directly), but the action itself is a reusable pattern that v2 CI can adopt once v2 has its own VERSIONS file. The action will need the VERSIONS path updated, not deleted. |
| `scripts/detect-mode.sh` | 36-line utility that sets `RAC_BUILD_MODE=ci|local` by inspecting `$CI` / `$GITHUB_ACTIONS`. Pure environment detection. Already pattern-matched to what v2 CMake presets would use for local vs. CI distinctions. No SDK paths. |

---

## INSPECT

| Path | Reason |
|---|---|
| `Playground/` | Contains 6 subdirectories: `android-use-agent`, `linux-voice-assistant`, `on-device-browser-agent`, `openclaw-hybrid-assistant`, `swift-starter-app`, `YapRun`. `linux-voice-assistant` links against v1 commons (`sdk/runanywhere-commons`) and is the only one documented in `AGENTS.md`. The others are unknown-status experiments. `swift-starter-app` is an Xcode project (`LocalAIPlayground`). None are wired into root build. Determine per-subdir whether each becomes a v2 example (→ `examples/`) or is scrapped. |
| `lefthook.yml` | File contains only the default `lefthook.yml` example template comments. No actual hooks are configured. The pre-commit hook configuration that runs Android lint and iOS SwiftLint is in `.pre-commit-config.yaml` (not audited here — not listed in the task). `lefthook.yml` as it stands is a placeholder. Inspect whether the team actually uses Lefthook or only `pre-commit`. |
| `README.md` | 413-line file. Describes v1 SDK installation (`pod install`, `swift package add`, `gradlew`, `npm install @runanywhere/core`). All examples point at v1 SDK paths and APIs. Needs a v2 rewrite but the exact content depends on which v1 install paths are still live during the migration window. |

---

## GitHub Actions workflows

| Workflow | LOC | Verdict | Notes |
|---|---|---|---|
| `pr-build.yml` | 597 | DELETE-AFTER-V1-REMOVAL | 15 jobs. Every `paths-filter` entry targets `sdk/runanywhere-{commons,swift,kotlin,flutter,react-native}/**`. Every native build step calls `sdk/runanywhere-commons/scripts/build-{ios,android,linux,windows}.sh`. Every SDK job runs from `sdk/runanywhere-kotlin`, `sdk/runanywhere-web`, etc. Zero v2 path coverage. |
| `release.yml` | 561 | DELETE-AFTER-V1-REMOVAL | Builds v1 XCFrameworks. Calls `scripts/sync-checksums.sh` against root `Package.swift`. Produces v1 Kotlin AARs and Web npm tarballs. Creates GitHub Releases of v1 artifacts. v2 release is `cmake --preset */release` → `xcodebuild -create-xcframework` → tag; no GitHub Release of zips needed once SwiftPM uses local path. |
| `auto-tag.yml` | 153 | DELETE-AFTER-V1-REMOVAL | Reads `PROJECT_VERSION` from `sdk/runanywhere-commons/VERSIONS` and calls `sync-versions.sh`. Both files are v1 infrastructure. v2 version is in root `CMakeLists.txt project(...VERSION 2.0.0...)`. |
| `secret-scan.yml` | 78 | KEEP | No SDK-path dependencies. Incremental gitleaks scan on PR diff. Applies to v2 code equally. |
| `v2-core.yml` | 194 | KEEP — this is the v2 CI | Path triggers on `core/**`, `engines/**`, `solutions/**`, `frontends/**`, `idl/**`, `cmake/**`, `tools/**`, `CMakeLists.txt`, `CMakePresets.json`, `vcpkg.json`. Jobs: `cpp-macos` (ASan+UBSan via `cmake --preset macos-debug`), `cpp-linux`, `proto-codegen-swift` (drift check), `swift-frontend` (SwiftPM in `frontends/swift`), `kotlin-frontend` (Gradle in `frontends/kotlin`), `dart-frontend`, `ts-frontend`. This workflow replaces `pr-build.yml` + `release.yml` for all v2 paths. |

**Post-v1-removal state:** only `secret-scan.yml` and `v2-core.yml` remain. A new `v2-release.yml` would be needed for tagging and publishing v2 artifacts (not yet written).

---

## Root Package.swift + gradle config

**Root `Package.swift`** (390 LOC, `sdk/runanywhere-swift/` paths throughout):
- Purpose: SPM entry point for external v1 consumers (`github.com/RunanywhereAI/runanywhere-sdks`).
- Wraps v1 binary targets: `RACommonsBinary`, `RABackendLlamaCPPBinary`, `RABackendONNXBinary`, `ONNXRuntimeiOSBinary`, `ONNXRuntimemacOSBinary`.
- `scripts/sync-checksums.sh` and the `release.yml` publish job exist solely to keep this file's checksums up to date.
- **After v1 removal:** delete root `Package.swift`. External consumers are pointed at `frontends/swift/Package.swift` (name `RunAnywhereV2`, no remote binary targets during dev, binary target added once v2 XCFramework is published).
- `frontends/swift/Package.swift` is already the v2 replacement. It declares `RunAnywhereV2`, depends on `swift-protobuf`, and points at `build/ios-static/RunAnywhereCore.xcframework` via local `.binaryTarget`.

**Root Gradle cluster** (`build.gradle.kts` + `settings.gradle.kts` + `gradle.properties` + `gradlew` + `gradlew.bat` + `gradle/`):
- `settings.gradle.kts` includes only v1 modules: `:runanywhere-kotlin` → `sdk/runanywhere-kotlin`, two backend modules under that tree, and two v1 example `includeBuild`s.
- `build.gradle.kts` hardcodes NDK `27.0.12077973` (one of the 5 locations MASTER_PLAN cites), delegates native tasks to `build-kotlin.sh`, wires Android example app and IntelliJ plugin demo.
- `gradle.properties` has `runanywhere.useLocalNatives=false` and `runanywhere.testLocal=false` — these flags are v1 KMP SDK feature flags.
- `frontends/kotlin/build.gradle.kts` + `frontends/kotlin/settings.gradle.kts` are the v2 replacements. They are self-contained (Wire plugin, `kotlinx-coroutines`, no NDK dependency).
- **After v1 removal:** the entire root Gradle cluster (`build.gradle.kts`, `settings.gradle.kts`, `gradle.properties`, `gradlew`, `gradlew.bat`, `gradle/`) becomes dead weight. The v2 Kotlin build lives entirely inside `frontends/kotlin/`.
- Note: `frontends/kotlin/` does not yet have its own `gradlew` wrapper. Before deleting the root `gradlew`, verify `frontends/kotlin/` has `gradle wrapper` committed or the v2-core.yml job uses a system Gradle (`gradle --no-daemon build`).

---

## EXTERNAL/

**Verdict: DELETE-NOW.**

MASTER_PLAN explicitly calls this the "reference graveyard." Confirmed by inspection:

- 8 subdirectories: `cl_stub`, `FluidAudio`, `Local-Diffusion`, `local-dream`, `mlx-audio`, `stable-diffusion.cpp`, `ToolNeuron`, `WhisperKit`.
- No `add_subdirectory(EXTERNAL/...)` in any `CMakeLists.txt` in the repo root or `sdk/`.
- No `implementation(...)` or `dependencies {}` block referencing these paths in any `build.gradle.kts`.
- No `import` or `path:` in any `pubspec.yaml` or `package.json` pointing here.
- The v2 reference implementations from RCLI and FastVoice cited throughout MASTER_PLAN live at `EXTERNAL/` conceptually but the plan explicitly says to port their algorithms into `core/`, not link to this directory.
- `EXTERNAL/WhisperKit` and `EXTERNAL/FluidAudio` overlap with Swift package dependencies declared in root `Package.swift` via SPM URLs — they are not the authoritative source for those libraries.

---

## scripts/ — cross-SDK

| Script | LOC | Verdict | Reason |
|---|---|---|---|
| `scripts/detect-mode.sh` | 36 | KEEP | Pure CI-vs-local environment detection. No v1 SDK paths. Sourced by v1 build scripts but the logic is generic (`$CI`, `$GITHUB_ACTIONS`). v2 CMake presets can source this for the same purpose. |
| `scripts/sync-versions.sh` | 152 | DELETE-AFTER-V1-REMOVAL | Every target it writes is a v1 path: `sdk/runanywhere-commons/VERSIONS`, root `Package.swift`, `sdk/runanywhere-kotlin/gradle.properties`, `sdk/runanywhere-web/packages/*/package.json`, `sdk/runanywhere-react-native/packages/*/package.json`, `sdk/runanywhere-flutter/packages/*/pubspec.yaml`. v2 version is managed in root `CMakeLists.txt` and in each frontend's own manifest (`frontends/kotlin/build.gradle.kts` `v2Version`, `frontends/swift/Package.swift` has no standalone version line). |
| `scripts/sync-checksums.sh` | 126 | DELETE-AFTER-V1-REMOVAL | Exclusively updates `checksum: "..."` lines in root `Package.swift` for v1 binary targets (`RACommons`, `RABackendLLAMACPP`, `RABackendONNX`, `RABackendMetalRT`, ONNX Runtime). `frontends/swift/Package.swift` uses a local `.binaryTarget(path:)` during development; no remote checksums to update. Called only from `release.yml` publish job, which is also DELETE-AFTER-V1-REMOVAL. |
| `scripts/validate-artifact.sh` | 139 | DELETE-AFTER-V1-REMOVAL | Validates v1 artifact shapes: XCFramework zip Info.plist, `.so` ELF, `.aar` classes.jar, `.wasm` magic bytes, `.tgz` npm pack, `.jar` MANIFEST.MF. These artifact types are produced by `release.yml`. v2 CI validation is handled by CMake `ctest` and sanitizer gates in `v2-core.yml` — no standalone artifact validation script is planned in MASTER_PLAN. |
| `scripts/README.md` | ~30 | DELETE-AFTER-V1-REMOVAL (update) | Documents the 4 cross-SDK scripts above plus per-SDK `build-<lang>.sh` and `sdk.sh` scripts. All per-SDK scripts are in `sdk/runanywhere-<lang>/scripts/` (v1 paths). After v1 deletion this index becomes stale. |

---

## CLAUDE.md / AGENTS.md / CONTRIBUTING.md — guidance docs

All three files are written entirely against v1 architecture. The specific v1-only sections that will need rewriting:

**`CLAUDE.md`** (the largest, contains the v1 KMP architecture section that runs ~300 lines):
- `## Common Development Commands` — all commands target v1 SDK paths (`sdk/runanywhere-kotlin/`, `sdk/runanywhere-swift/`, `sdk/runanywhere-web/`, `sdk/runanywhere-android/`). v2 commands are `cmake --preset`, `swift build` in `frontends/swift/`, `gradle` in `frontends/kotlin/`.
- iOS section instructs `pod install` + `fix_pods_sandbox.sh` + `.xcworkspace`. v2 Phase 1 explicitly eliminates CocoaPods (gate: "Zero pod install, zero fix_pods_sandbox.sh").
- `## Kotlin Multiplatform (KMP) SDK — Critical Implementation Rules` section (the "iOS as source of truth" bloc, ~200 lines): entirely describes the v1 KMP architecture (`sdk/runanywhere-kotlin/commonMain`, `jvmAndroidMain`, `androidMain`). v2 Kotlin is a ~2,000-LOC adapter in `frontends/kotlin/src/main/kotlin/`.
- The "When it's December 2025 FYI" comment at the top is stale (current date is 2026-04-18).

**`AGENTS.md`:**
- Build table rows for "C++ Commons (core)" and "C++ Commons (full backends)" reference `sdk/runanywhere-commons/` build paths. v2 C++ entry point is root `cmake --preset`.
- "Linux Voice Assistant Quick Start" references `Playground/linux-voice-assistant` which links against v1 commons. v2 equivalent would be `cmake --preset linux-debug && ctest`.
- Row for "Kotlin SDK (Android target)" cites `sdk/runanywhere-kotlin/` and the `@Keep` annotation issue in `jvmAndroidMain` — a v1 KMP implementation detail.

**`CONTRIBUTING.md`:**
- "Android SDK Setup" section: `cd sdk/runanywhere-kotlin/ && ./scripts/sdk.sh android`. v2: `cd frontends/kotlin && gradle build`.
- "iOS SDK Setup" section (implied via CocoaPods prerequisites): references `fix_pods_sandbox.sh`. Eliminated in v2.
- Pre-commit hook setup still valid if the repo retains a `.pre-commit-config.yaml`. Content of hooks (SwiftLint path, Kotlin lint path) will need updating to point at v2 frontend paths.

---

## Backwards-compat shims found

1. **Root `Package.swift` `useLocalNatives` toggle** — a boolean flag at line 43 that switches the same Package.swift between local XCFramework paths (`sdk/runanywhere-swift/Binaries/`) and remote GitHub Release download URLs. This dual-mode file is a v1 shim that exists because SPM does not support conditional source resolution natively. `frontends/swift/Package.swift` does not carry this toggle — it uses `.binaryTarget(path:)` unconditionally.

2. **`settings.gradle.kts` JitPack repository in `dependencyResolutionManagement`** — `maven { url = uri("https://jitpack.io") }` at line 21. This was added to allow consuming the v1 Kotlin SDK via JitPack during development. v2 `frontends/kotlin` has no JitPack reference.

3. **`release.yml` `validate_consumer_*` jobs with `continue-on-error: true`** — five consumer-validation jobs (swift-starter-example, kotlin-starter-example, web-starter-app, flutter-starter-example, react-native-starter-app) all carry `continue-on-error: true`. These are the last 5 of the 46 `continue-on-error` directives the MASTER_PLAN (IMM-1) aims to eliminate. They exist because starter repos evolve independently and the team accepted soft failures here deliberately.

4. **`gradle.properties` `runanywhere.useLocalNatives=false`** — v1 KMP SDK feature flag that switches between downloading pre-built JNI libs from GitHub Releases vs. building locally. `frontends/kotlin` is independent of this flag and has no equivalent toggle.

5. **`build.gradle.kts` `metalrtRemoteBinaryAvailable = false`** flag pattern in root `Package.swift` — gates the MetalRT product/targets behind a boolean because the XCFramework was never published with a real checksum. v2 MetalRT becomes an L1 runtime plugin compiled by CMake; no Swift-level gating needed.
