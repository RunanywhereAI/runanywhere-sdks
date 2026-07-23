# AGENTS.md

This file provides guidance to AI coding assistants (Claude Code, Cursor, etc.) when working with code in this repository.
- Focus on SIMPLICITY, and following Clean SOLID principles when writing code. Reusability, Clean architecture(not strictly) style, clear separation of concerns.

> **`AGENTS.md` is the real file; each `CLAUDE.md` is a symlink to the `AGENTS.md` beside it.**
> Editing either name edits the same bytes, so the two can never drift and Claude Code, Cursor, and every
> other assistant read identical guidance. The symlinks are committed, so a fresh clone recreates them
> automatically on macOS/Linux — and `scripts/setup/setup.sh` plus the post-checkout/post-merge git hooks
> re-create any missing link (e.g. on Windows). To add the symlink in a new directory (or repair a broken
> one), run `bash scripts/validation/gates/check_agents_claude_sync.sh --fix`; a pre-commit hook and the
> `pr-build.yml` gate fail if any tracked `AGENTS.md` is missing its committed `CLAUDE.md` symlink.

### ⚠️ Resource discipline — use available capacity responsibly
Use the machine's available capacity for local builds and verification instead of defaulting to low worker caps:
- **Builds should use full local capacity by default.** Prefer explicit worker counts based on the host CPU count for reproducibility, e.g. `cmake --build <dir> -j "$(sysctl -n hw.logicalcpu)"`, `make -j"$(sysctl -n hw.logicalcpu)"`, `ninja -j "$(sysctl -n hw.logicalcpu)"`, Gradle `--max-workers="$(sysctl -n hw.logicalcpu)"`, and Xcode `-jobs "$(sysctl -n hw.logicalcpu)"`.
- **Use lower caps only when there is real pressure.** Scale down if the machine is memory constrained, swapping, thermally throttling, or a build is failing because of resource exhaustion; do not wait solely because load average is above an arbitrary threshold.
- **Parallelize with intent.** Running independent light checks or agents in parallel is fine. Avoid uncontrolled process storms, repeated repo-wide scans, or multiple native rebuilds that compete for the same memory-heavy toolchain without a clear benefit.
- **Check `uptime` before a heavy step** as situational awareness, then proceed with the worker count that fits the current machine state and user urgency.

### Before starting work.
- Do NOT write ANY MOCK IMPLEMENTATION unless specified otherwise.
- DO NOT PLAN or WRITE any unit tests unless specified otherwise.
- Always in plan mode to make a plan refer to `thoughts/shared/plans/{descriptive_name}.md`.
- After get the plan, make sure you Write the plan to the appropriate file as mentioned in the guide that you referred to.
- If the task require external knowledge or certain package, also research to get latest knowledge (Use Task tool for research)
- Don't over plan it, always think MVP.
- Once you write the plan, firstly ask me to review it. Do not continue until I approve the plan.
### While implementing
- You should update the plan as you work - check `thoughts/shared/plans/{descriptive_name}.md` if you're running an already created plan via `thoughts/shared/plans/{descriptive_name}.md`
- After you complete tasks in the plan, you should update and append detailed descriptions of the changes you made, so following tasks can be easily hand over to other engineers.
- Always make sure that you're using structured types, never use strings directly so that we can keep things consistent and scalable and not make mistakes.
- Read files FULLY to understand the FULL context. Only use offset/limit when the file is large and you are short on context.
- When fixing issues focus on SIMPLICITY, and following Clean SOLID principles, do not add complicated logic unless necessary!
- When looking up something: It's December 2025 FYI

## Swift specific rules:
- Use the latest Swift 6 APIs always.
- Do not use NSLock as it is outdated.

## Business Logic Layering Rules

**The single most important architectural rule in this repo:** logic must live at the lowest layer that can serve all consumers.

> **Corollary — the SDK must be seamless inside every example app.** Each feature/modality (LLM, STT, TTS, VAD, VLM, RAG, LoRA, Voice) is invoked through **one** SDK entry point; the SDK — and below it, C++ commons — does *all* the heavy lifting: segmentation, derivation, download, orchestration, prompt control. If an example app builds a multi-step sequence, hardcodes a model/engine constant, or post-processes model output, that is a bug in the **SDK**, not the app — fix it down a layer.

### Decision hierarchy (top = preferred)

1. **C++ commons** (`sdk/runanywhere-commons/`) — If logic is cross-platform and not I/O-specific, it belongs here. All 5 SDKs get the fix for free. Examples: model lifecycle, registry management, download orchestration, RAG session management, inference routing.

2. **Platform SDK layer** — If logic is platform-specific I/O or runtime bridging (e.g. Web OPFS persistence, iOS Keychain, Android Keystore, WASM MEMFS mirroring), it belongs in the platform SDK, not the example app. Examples: `OPFSBridge`, platform adapter registration, WASM module broadcast, MEMFS hydration.

3. **Example apps** — Only UI rendering, tab navigation, and thin SDK API calls. **No business logic, no workarounds, no internal SDK knowledge.** If you find yourself writing multi-step bootstrap sequences, duplicating internal constants (e.g. filesystem path patterns), or routing around SDK limitations inside an example, **stop and fix the SDK instead**.

### Concrete rules

- **Example apps call SDK APIs directly.** `downloadModel()`, `loadModel()`, `ragIngest()` — these are the right entry points. The SDK handles everything beneath.
- **Never duplicate SDK-internal knowledge in example apps.** Framework→directory mappings, OPFS path patterns, MEMFS write helpers, WASM module iteration — all belong in the SDK.
- **Never add workaround logic to example apps.** If a download path is broken for multi-file models, fix `downloadModel()` in the SDK. If OPFS state needs cold-start hydration, add `hydrateModelRegistry()` to the SDK. Don't paper over SDK bugs in example code.
- **Never add multi-step bootstrap in example views.** If a view needs to call `register()` + `reRegisterCatalog()` + `downloadDependency()` + `createPipeline()` before it can work, those steps belong in the SDK's single entry point (e.g. `createPipeline()` should handle its own prerequisites or surface a clear error).
- **When fixing a bug, always ask: can this be fixed at the C++ level?** A C++ fix benefits iOS, Android, Flutter, React Native, and Web simultaneously. A TS/Swift/Kotlin fix only helps one SDK. Only go to the platform layer when the fix is genuinely platform-specific.

### iOS SDK as source of truth

When the correct behavior is ambiguous, check the iOS Swift implementation first. iOS is the canonical reference for all business logic patterns. Copy the logic exactly and adapt only syntax.

---

## Repository Overview

Cross-platform on-device AI SDK monorepo. A single C/C++ core (`runanywhere-commons`, ~118K first-party LOC plus ~420K generated proto bindings) implements all AI business logic behind a pure C ABI (`rac_*` prefix). Five platform SDKs are thin bridges that supply platform services (file I/O, HTTP, Keychain, audio) via an inversion-of-control struct and call into the C core for all inference. Protobuf IDL schemas generate type-safe bindings for every language.

**Current version**: `0.20.11` (canonical source: `sdk/runanywhere-commons/VERSION`)

### SDK Implementations
| SDK | Path | Bridge Mechanism | Platforms |
|-----|------|-----------------|-----------|
| Swift | `sdk/runanywhere-swift/` | XCFramework + CRACommons module map | iOS 17.5+, macOS 14.5+ |
| Kotlin (Android library) | `sdk/runanywhere-kotlin/` | JNI (`librunanywhere_jni.so`) | Android (min 24) |
| Flutter | `sdk/runanywhere-flutter/` | Dart FFI (`ffi` package) | iOS, Android |
| React Native | `sdk/runanywhere-react-native/` | NitroModules (JSI HybridObject) | iOS 17.5+, Android arm64 |
| Web | `sdk/runanywhere-web/` | Emscripten WASM + TypeScript | Browsers (Chrome, Safari, Firefox) |

### Native Core
| Directory | Contents |
|-----------|----------|
| `sdk/runanywhere-commons/` | C/C++ core library — all AI logic, plugin registry, event system |
| `engines/` | 6 backend plugins: llamacpp, sherpa, onnx, cloud, qhexrt, coreml |
| `runtimes/` | 3 runtime adapters: cpu (always), onnxrt, coreml |
| `idl/` | 23 Protobuf schemas + per-language codegen scripts |

### Example Applications
| App | Path | Build System |
|-----|------|-------------|
| Android | `examples/android/RunAnywhereAI/` | Gradle/Compose |
| iOS | `examples/ios/RunAnywhereAI/` | SwiftUI + SPM |
| Flutter | `examples/flutter/RunAnywhereAI/` | Flutter + Dart FFI |
| React Native | `examples/react-native/RunAnywhereAI/` | RN 0.85 + NitroModules |
| Web | `examples/web/RunAnywhereAI/` | Vanilla TS + Vite |

All example apps share one visual identity — brand orange `#FF6900` (the logo primary, **not** the legacy `#FF5500`), documented in `examples/DESIGN_GUIDELINE.md`. Each app hand-maintains a small theme file that mirrors that doc; see the "Design System" section in each app's `AGENTS.md`.

### Playground
`Playground/` contains 6 standalone demo projects (not part of any build system): YapRun (iOS dictation app), swift-starter-app, on-device-browser-agent, android-use-agent, linux-voice-assistant, openclaw-hybrid-assistant.

---

## Cross-Platform Architecture

```
                          idl/*.proto
                              │
                    idl/codegen/generate_all.sh
                              │
          ┌───────────────────┼───────────────────┐
          ▼                   ▼                   ▼
   *.pb.swift          Wire Kotlin        ts-proto / protoc-gen-dart
   (committed)          (committed)            (committed)

Platform SDKs (thin bridges — supply platform services, call C ABI)
  ┌──────────┬──────────┬──────────┬──────────┬──────────┐
  │  Swift   │  Kotlin  │ Flutter  │React Nat.│   Web    │
  │XCFramewk │   JNI    │ Dart FFI │NitroMods │  WASM    │
  └────┬─────┴────┬─────┴────┬─────┴────┬─────┴────┬─────┘
       │          │          │          │          │
       └──────────┴──────────┴──────┬───┴──────────┘
                                    │ rac_* C API
                    ┌───────────────▼───────────────┐
                    │      runanywhere-commons       │
                    │  Component Layer (lifecycle)   │
                    │  Service Layer (dispatch)      │
                    │  Plugin Registry               │
                    └───────────────┬───────────────┘
                                    │ rac_engine_vtable_t (v4)
          ┌─────────────┬───────────┼───────────┬─────────────┐
          ▼             ▼           ▼           ▼             ▼
      llamacpp      sherpa-onnx  qhexrt     coreml/cloud    onnx
     (LLM,VLM)    (STT,TTS,VAD) (HNPU)     (Apple/HTTP)   (Embed)
```

### Key Architectural Patterns

**Platform Adapter IoC**: `rac_platform_adapter_t` is a flat C struct of function pointers populated by each SDK before calling `rac_init()`. C++ never calls platform APIs directly — all file I/O, HTTP, Keychain, logging, and memory queries pass through this struct.

**Two-Phase SDK Initialization**: All SDKs follow the same pattern: Phase 1 (synchronous — register platform adapter, load native libs, configure logging) then Phase 2 (async — authenticate, register device, fetch model assignments, discover downloaded models).

**Plugin ABI v4**: Every backend publishes a `rac_engine_vtable_t` with 7 primitive slots (`llm_ops`, `stt_ops`, `tts_ops`, `vad_ops`, `embedding_ops`, `vlm_ops`, `diffusion_ops`). NULL slot = not supported. `RAC_PLUGIN_API_VERSION = 4u` — version mismatch causes immediate rejection. (Wire value 6, formerly `rerank_ops`/`RAC_PRIMITIVE_RERANK`, is retired.)

**Static vs Dynamic Plugins**: iOS and WASM force `RAC_STATIC_PLUGINS=ON` (no `dlopen`). Android/Linux/macOS default to dynamic loading via `rac_registry_load_plugin()`. Static registration uses `RAC_STATIC_PLUGIN_REGISTER(name)` macro with `-force_load` / `--whole-archive` linker flags.

**Streaming Fan-Out**: C++ allows only one proto-byte callback per component handle. Each SDK implements a `HandleFanOut` that multiplexes one C callback to multiple subscribers (Swift `AsyncStream`, Kotlin `Flow`, Dart `StreamController`, TS `AsyncIterable`).

**Proto Types Are Canonical**: All structured types (environments, model formats, error codes, voice events, LLM stream events) are defined in `idl/*.proto` and code-generated per SDK. Never hand-write enum values — use the generated types and typealiases.

---

## Building the Native Core

The root `CMakeLists.txt` is the single entry point for all native builds. Version is read from `sdk/runanywhere-commons/VERSION`.

### CMake Presets (`CMakePresets.json`)

```bash
# macOS (development)
cmake --preset macos-debug && cmake --build build/macos-debug
ctest --preset macos-debug

# macOS release
cmake --preset macos-release && cmake --build build/macos-release

# Linux (with sanitizer)
cmake --preset linux-asan && cmake --build build/linux-asan

# iOS (device + simulator)
cmake --preset ios-device && cmake --build build/ios-device --config Release
cmake --preset ios-simulator && cmake --build build/ios-simulator --config Release

# Android (requires ANDROID_NDK_HOME)
cmake --preset android-arm64 && cmake --build build/android-arm64

# WASM (requires EMSDK)
cmake --preset wasm && cmake --build build/wasm
```

### Cross-Platform Build Scripts (in `scripts/`)

```bash
# iOS: Build XCFrameworks for all slices → sdk/runanywhere-swift/Binaries/
./sdk/runanywhere-swift/scripts/build-core-xcframework.sh
# Also syncs XCFrameworks into React Native and Flutter SDK plugin dirs

# Android: Build .so for all ABIs → copies into all SDK jniLibs/ dirs
./scripts/build/build-core-android.sh

# WASM: Build racommons-llamacpp.wasm → sdk/runanywhere-web/packages/llamacpp/wasm/
./sdk/runanywhere-web/scripts/build-core-wasm.sh

# Version bump across all manifests
./scripts/release/sync-versions.sh <version>

# Update Package.swift checksums after building release zips
./sdk/runanywhere-swift/scripts/sync-checksums.sh <zip_dir>

# Full IDL codegen (requires protoc toolchain — see scripts/setup/setup-toolchain.sh)
./idl/codegen/generate_all.sh
```

### Native Build Outputs

| Platform | Output | Consumed by |
|----------|--------|------------|
| iOS | `sdk/runanywhere-swift/Binaries/*.xcframework` | Swift SPM, Flutter iOS, RN iOS |
| Android | `*/jniLibs/{abi}/*.so` | Kotlin, Flutter Android, RN Android |
| WASM | `sdk/runanywhere-web/packages/llamacpp/wasm/*.wasm` | Web SDK |
| macOS/Linux | `build/<preset>/librac_commons.a` or `.so` | Local dev/testing |

---

## SDK Development Commands

### C++ Core (`sdk/runanywhere-commons/`)

See `sdk/runanywhere-commons/AGENTS.md` for detailed architecture and C++ conventions.

```bash
# Build with backends + tests
cmake -B build -DRAC_BUILD_TESTS=ON -DRAC_BUILD_BACKENDS=ON -DCMAKE_BUILD_TYPE=Debug
cmake --build build
ctest --test-dir build --output-on-failure

# Lint C++
./scripts/lint-cpp.sh          # Check formatting
./scripts/lint-cpp.sh --fix    # Auto-fix
```

### Swift SDK (`sdk/runanywhere-swift/`)

```bash
# Build (requires XCFrameworks in sdk/runanywhere-swift/Binaries/)
RUNANYWHERE_USE_LOCAL_NATIVES=1 swift build

# Run tests
RUNANYWHERE_USE_LOCAL_NATIVES=1 swift test

# Build for specific platform
xcodebuild build -scheme RunAnywhere -destination 'platform=iOS Simulator,name=iPhone 16 Pro'

# Run SwiftLint
swiftlint
```

### Kotlin SDK (`sdk/runanywhere-kotlin/`)

```bash
cd sdk/runanywhere-kotlin/

# Build (Android library)
./gradlew build

# Individual targets
./gradlew assembleDebug        # Android Debug AAR
./gradlew assembleRelease      # Android Release AAR

# Test
./gradlew testDebugUnitTest    # Android unit tests
./gradlew test                 # All unit tests (debug + release variants)

# Publish to Maven Local
./gradlew publishToMavenLocal

# Native library management (C++ JNI)
./gradlew setupLocalDevelopment   # First-time: builds C++ JNI libs (runs scripts/build/build-core-android.sh)
./gradlew rebuildCommons          # Rebuild C++ after source changes
./gradlew downloadJniLibs         # Download pre-built .so from GitHub Releases
```

Build outputs: `build/outputs/aar/runanywhere-kotlin-{debug,release}.aar` (plus sub-module AARs under `modules/runanywhere-core-{llamacpp,onnx}/build/outputs/aar/`).

Backend modules at `modules/runanywhere-core-llamacpp/` and `modules/runanywhere-core-onnx/`.

### Flutter SDK (`sdk/runanywhere-flutter/`)

Managed by Melos. Four packages: `runanywhere` (core), `runanywhere_llamacpp`, `runanywhere_onnx`, `runanywhere_qhexrt`.

```bash
cd sdk/runanywhere-flutter/
melos bootstrap         # Install deps across all packages
melos run analyze       # Dart analysis
```

### React Native SDK (`sdk/runanywhere-react-native/`)

Managed by Yarn Berry 3.6.1. Three packages: `@runanywhere/core`, `@runanywhere/llamacpp`, `@runanywhere/onnx`.

```bash
cd sdk/runanywhere-react-native/
yarn install
yarn typecheck          # Primary verification gate
```

NitroModules specs in `packages/core/src/specs/*.nitro.ts`. After spec changes, run `nitrogen` to regenerate C++ bridge code, then `scripts/fix-nitrogen-output.js`.

### Web SDK (`sdk/runanywhere-web/`)

Three npm packages: `@runanywhere/web` (core TS), `@runanywhere/web-llamacpp` (WASM), `@runanywhere/web-onnx` (Sherpa WASM).

```bash
cd sdk/runanywhere-web/

# Build WASM (requires Emscripten SDK)
npm run build:wasm -- --core
npm run build:wasm -- --llamacpp                 # CPU variant
npm run build:wasm -- --webgpu                   # WebGPU variant
npm run build:wasm -- --onnx                     # ONNX + Sherpa artifact

# Build TypeScript
npm run build

# Type-check
npm run typecheck
```

The current artifact and deployment contract is maintained in
`sdk/runanywhere-web/AGENTS.md`; it supersedes historical standalone
`wasm/sherpa/` paths. Do not use or recreate those removed paths.

### IDL Codegen

```bash
# Install toolchain (protoc, protoc-gen-swift, wire-compiler, ts-proto, etc.)
./scripts/setup/setup-toolchain.sh

# Regenerate all language bindings
./idl/codegen/generate_all.sh

# Individual languages
./idl/codegen/generate_swift.sh
./idl/codegen/generate_kotlin.sh
./idl/codegen/generate_dart.sh
./idl/codegen/generate_ts.sh
./idl/codegen/generate_cpp.sh
```

Generated files are committed. CI `idl-drift-check.yml` fails if they're out of sync.

---

## Example App Commands

### iOS Example

```bash
cd examples/ios/RunAnywhereAI/

# Build and run on simulator (recommended)
./scripts/build_and_run_ios_sample.sh simulator "iPhone 16 Pro" --build-sdk

# Build and run on device
./scripts/build_and_run_ios_sample.sh device

# macOS target
./scripts/build_and_run_ios_sample.sh mac

# Local verification
./scripts/verify.sh     # Checks XCFrameworks exist, resolves packages, xcodebuild
./scripts/smoke.sh      # Greps source for SDK API calls (no compilation)

# SDK logs (in separate terminal)
log stream --predicate 'subsystem CONTAINS "com.runanywhere"' --info --debug
```

Requires 4 XCFrameworks in `sdk/runanywhere-swift/Binaries/`: `RACommons`, `RABackendLLAMACPP`, `RABackendONNX`, `RABackendSherpa`.

### Android Example

```bash
cd examples/android/RunAnywhereAI/

./gradlew :app:assembleDebug   # Build
./gradlew :app:installDebug    # Install on device/emulator
./scripts/verify.sh            # Full build gate
```

Consumes the SDK + engine modules as raw local AARs — `app/build.gradle.kts` declares `implementation(files("../libs/runanywhere-{sdk,llamacpp,onnx,qhexrt}.aar"))`, not Maven Local coordinates. Local AARs carry no POM, so the app declares the SDK's transitive runtime deps itself. Discrete steps:
- `./run sdk commons build-android` — build the commons `.so` for all Android ABIs.
- `./run example android stage` — build the SDK release AARs and copy them into `examples/android/RunAnywhereAI/libs/` (via `scripts/stage-sdk-aars.sh release`).
- `./run example android build` — stage, then `:app:assembleDebug`.
- `./run example android install` — stage, then `:app:installDebug` and launch.

Re-run `build-android` + `stage` after any change to C++ commons or the Kotlin SDK.

### Flutter Example

```bash
cd examples/flutter/RunAnywhereAI/

flutter pub get
flutter run
flutter run -d "iPhone 16 Pro"
./scripts/verify.sh            # pub get + analyze + APK build
RUN_IOS=1 ./scripts/verify.sh  # Also builds iOS
```

### React Native Example

```bash
cd examples/react-native/RunAnywhereAI/

yarn install
yarn start          # Metro bundler
yarn ios            # iOS simulator
yarn android        # Android device
yarn typecheck      # Primary verification gate
./scripts/verify.sh # typecheck + optional builds
```

**Hermes caveat**: Does not support `for await...of` with NitroModules async iterables. Use manual `iterator.next()` loops.

### Web Example

```bash
cd examples/web/RunAnywhereAI/

npm install
npm run dev          # Vite dev server at port 3000
npm run build        # Production build
```

Requires WASM pre-built. `SharedArrayBuffer` needs cross-origin isolation headers (COOP + COEP).

---

## Version Management

Canonical version: `sdk/runanywhere-commons/VERSION` (single-line file, e.g. `0.20.0`).

```bash
# Bump everywhere: VERSION, Package.swift, gradle.properties, package.json, pubspec.yaml
./scripts/release/sync-versions.sh 0.20.0
```

Release lifecycle: `sync-versions.sh` → PR with `release:minor` label → merge → `auto-tag.yml` pushes `v0.20.0` tag → `release.yml` builds all artifacts and creates draft GitHub Release.

---

## CI/CD Workflows (`.github/workflows/`)

| Workflow | Trigger | Purpose |
|----------|---------|---------|
| `pr-build.yml` | PR to main, push to main/feat branch | Parallel native builds (macOS/Linux/iOS/Android) + per-SDK typecheck |
| `release.yml` | Tag `v*.*.*` or manual | Full artifact build matrix, SDK packaging, consumer validation, draft Release |
| `auto-tag.yml` | PR merged to main with `release:*` label | Verifies the reviewed semver bump, then pushes that exact git tag |
| `idl-drift-check.yml` | Changes to `idl/` or generated files | Regenerates protos, fails if `git diff` is non-empty |
| `legacy-files-blocklist.yml` | All PRs/pushes | Prevents 5 specific deleted files from being re-introduced |
| `secret-scan.yml` | PRs and pushes to main | Incremental gitleaks scan on diff range |
| `check-no-pii-logging.yml` | All PRs/pushes to main, master, feat-branch | Regression guard against Android logcat / RAC_LOG_INFO calls that emit signed URLs alongside active-download destination paths |

---

## Key Architectural Decisions

### iOS SDK is Source of Truth
When implementing features in any other SDK (especially Kotlin), always check the iOS Swift implementation first. Copy logic exactly, adapting only for language syntax, not business logic.

### All Business Logic in C++ commons (or the SDK shared layer)
Platform-specific code should only handle: native library loading, platform adapter registration, audio capture/playback, secure storage, and UI. All AI inference, model management, event routing, and pipeline orchestration live in C++ (`runanywhere-commons`) or — when intentionally Kotlin-side — under the Kotlin SDK's shared `src/main/kotlin/com/runanywhere/sdk/` tree.

### Backend Registration Pattern
All SDKs follow the same pattern:
1. Load the backend native library
2. Call `rac_backend_*_register()` (which registers the engine's vtable with the plugin registry)
3. The registry orders registered plugins by base priority, per primitive
4. On inference, the highest-priority plugin that serves the primitive is selected via `rac_plugin_find()` (or `rac_plugin_find_for_engine()` for a name-pinned engine)

Backend base priorities: qhexrt=150 (QNN-context models only), mlx=110 (Apple), llamacpp=100, sherpa=90, onnx/cloud=50. Selection is plain priority order — there is no runtime/format scoring or pinned-engine bonus; an explicit engine name is honored via `rac_plugin_find_for_engine()`.

### HTTP Transport is Platform-Provided
libcurl was removed. Each SDK registers a `rac_http_transport_ops_t` vtable: Swift uses URLSession, Kotlin/Flutter/RN use OkHttp (Android) or URLSession (iOS), Web uses `emscripten_fetch`.

### Proto-Generated Types Replace Hand-Written Enums
All cross-platform types are defined in `idl/*.proto`. SDKs use typealiases to the generated types (e.g., `typealias SDKEnvironment = RASDKEnvironment` in Swift, `typealias SDKEnvironment = ai.runanywhere.proto.v1.SDKEnvironment` in Kotlin). Never add enum values by hand — modify the `.proto` file and regenerate.

---

## Platform Requirements

| Platform | Min Version | Build Tool | Key Versions |
|----------|------------|------------|--------------|
| iOS | 17.5 | Xcode 26+ | Swift 6.2 |
| macOS | 14.5 | Xcode 26+ | Swift 6.2 |
| Kotlin SDK | Android API 24 | AGP 9.2.1 / Gradle 9.5.0 | Kotlin 2.4.0, NDK 27.3.13750724 |
| Android example | Android API 24 | AGP 9.2.1 / Gradle 9.6.0 | Kotlin 2.4.0, compile/target SDK 37 |
| Flutter | 3.44.6 | Melos / AGP 9.0.1 / Gradle 9.1.0 | Dart 3.12.2+, compile/target SDK 36, NDK 28.2.13676358 |
| React Native | 0.85.3 (min 0.83.1) | Yarn Berry 3.6.1 | NitroModules, Hermes |
| Web | Chrome 86+ | Vite | Emscripten 6.0.2, Node 24 LTS |
| C++ Core | N/A | CMake 3.22+ | C++20, Ninja |

---

## Kotlin SDK - Critical Implementation Rules

The Kotlin SDK (`sdk/runanywhere-kotlin/`) ships as an Android library (`alias(libs.plugins.android.library)` in `sdk/runanywhere-kotlin/build.gradle.kts`), not as a Kotlin Multiplatform module. It targets Android only and consumes the C++ commons core through JNI (`librunanywhere_jni.so`). JVM 17 is the toolchain for the Gradle build itself, not a published target.

### iOS as Source of Truth
**NEVER make assumptions when implementing the Kotlin SDK. ALWAYS refer to the iOS implementation as the definitive source of truth.**

1. **iOS First**: When encountering missing logic or unclear requirements in the Kotlin SDK, check the corresponding iOS implementation, copy the logic exactly, adapt only for Kotlin syntax.

2. **Public API symmetry**: The Kotlin SDK mirrors the Swift `RunAnywhere` surface as an `object RunAnywhere` singleton with extension functions one-per-feature in `src/main/kotlin/com/runanywhere/sdk/public/extensions/`. Add new public API only after the Swift facade has landed.

3. **Platform naming convention**: Android-only adapters keep an explicit `Android` prefix (e.g. `AndroidTTSService.kt`) so file naming makes the target unambiguous if a JVM-only or KMP variant is ever reintroduced.

### Source Set Layout

```
sdk/runanywhere-kotlin/
    src/main/kotlin/        (all Kotlin sources — public API, JNI bridges, generated Wire proto types)
    src/main/jniLibs/       (prebuilt .so files staged by build-core-android.sh)
    src/test/kotlin/        (unit tests — no JNI required)
    modules/runanywhere-core-{llamacpp,onnx}/  (Android library sub-modules that register C++ backends)
```

Standard Android library layout. There is no `commonMain`/`jvmAndroidMain`/`androidMain`/`jvmMain` hierarchy at this level (the SDK was migrated away from KMP). Any `expect`/`actual` pairs you see in legacy documentation describe the previous topology; the current build is single-target Android. Reviewer-area names like `A-kotlin-common-domain` in `test_workflows/.../SCOPE_MANIFEST.json` are kept for historical filtering and do not imply KMP source sets exist today.

### Cross-SDK Alignment

| Concern | iOS Swift | Kotlin (Android) | Flutter | React Native | Web |
|---------|-----------|------------------|---------|-------------|-----|
| Entry point | `enum RunAnywhere` | `object RunAnywhere` | `RunAnywhere` (abstract final class with static members) | `RunAnywhere` object | `RunAnywhere` object |
| Two-phase init | `initialize()` + `completeServicesInitialization()` | Same | Same | Same | Same |
| Bridge layer | `CppBridge` enum + extensions | `CppBridge` object + extensions | `DartBridge` + `DartBridge*.dart` | `HybridRunAnywhereCore` (Nitro) | `LlamaCppBridge` + `SherpaONNXBridge` |
| Streaming | `AsyncStream` | `Flow` | `Stream` (via `StreamController`) | `AsyncIterable` (manual iteration) | `AsyncIterable` |
| Events | `EventBus` (Combine) | `EventBus` (SharedFlow) | `EventBus` (custom pub/sub via dart:async broadcast StreamController) | `EventBus` (NativeEventEmitter) | `EventBus` (custom pub/sub) |
| Error type | `SDKException` (proto-backed) | `SDKException` (proto-backed) | `SDKException` | `SDKException` | `SDKException` |
| Secure storage | Keychain | Android Keystore | Keychain (iOS), Android Keystore + atomic no-backup ciphertext files | Keychain (iOS), Android Keystore | localStorage |
| HTTP transport | URLSession | OkHttp | OkHttp (Android), URLSession (iOS) | OkHttp (Android), URLSession (iOS) | emscripten_fetch / fetch() |

---

## Non-Obvious Configuration Details

**`Package.swift`** — remote release artifacts are the fail-closed default. Local builds opt into staged XCFrameworks with `RUNANYWHERE_USE_LOCAL_NATIVES=1`; scripts set this explicitly and never rewrite the manifest.

**`Package.swift:186-191`** — Three `.grpc.swift` files are excluded from compilation. They require iOS 18 / macOS 15, above the SDK's minimums. In-process C callback path replaces gRPC.

**`gradle.properties`** — `runanywhere.useLocalNatives=true` means local `.so` files. CI overrides with `-Prunanywhere.useLocalNatives=false` to download from GitHub Releases.

**NDK version** — `racNdkVersion=27.3.13750724` (matches `sdk/runanywhere-commons/VERSIONS::NDK_VERSION`, the single source of truth) is the pin for the Kotlin SDK in `sdk/runanywhere-kotlin/gradle.properties`. NDK 27 is the current LTS line (r27d) and provides 16 KB page-alignment required by Android 15+ (NDK 25.x's 4 KB-aligned `libc++_shared.so` / `libomp.so` would trip Android 16's 16 KB page-size enforcement). Flutter/RN Android build files carry their own `?: "..."` fallback literals but the canonical version lives in `VERSIONS`; mirror it whenever bumping.

**Web cross-origin isolation** — `SharedArrayBuffer` requires COOP/COEP headers. Safari needs `coi-serviceworker.js` polyfill.

**Web VLM Worker crash recovery** — If `rac_vlm_component_process` causes WASM OOM (`"memory access out of bounds"`), the Worker auto-recovers by creating a fresh WASM instance on the next `process()` call.

**Web Qwen2-VL WebGPU workaround** — Qwen2-VL models produce NaN logits on WebGPU due to f16 M-RoPE overflow. VLM Worker forces CPU WASM for Qwen2-VL even when WebGPU is active.

**Web struct offsets** — TypeScript never hard-codes C struct field offsets. `wasm_exports.cpp` exposes `EMSCRIPTEN_KEEPALIVE` offset functions; the `Offsets` proxy reads them at runtime from the WASM module.

---

## Pre-commit Hooks

```bash
pre-commit run --all-files        # Run all checks
pre-commit run ios-sdk-swiftlint --all-files  # SwiftLint only
```

Configured hooks: gitleaks (secrets), trailing-whitespace, end-of-file-fixer, check-yaml, check-added-large-files (1000 KB max), check-merge-conflict, object file detection, SwiftLint (SDK + example app), periphery (unused code detection).

---

## Active Issues (`thoughts/shared/issues/`)

On `feat/v2-architecture` branch, 4 tracked regressions relative to `main`:
- **001/002/005** (HIGH): Swift, Kotlin, and Web SDKs collapsed backends into monolithic artifacts, losing per-backend selective linking.
- **003** (MEDIUM): React Native backend packages are TypeScript-only, missing native plumbing.

Live state document: `thoughts/shared/plans/sdk_current_state.md`

---

## Cursor Cloud specific instructions

### Environment Overview

This is a cross-platform SDK monorepo. On a Linux cloud VM, the buildable services are:

| Component | Build | Test | Lint | Notes |
|-----------|-------|------|------|-------|
| Kotlin SDK (Android target) | `cd sdk/runanywhere-kotlin && ./gradlew compileDebugKotlin -Prunanywhere.useLocalNatives=false` | Android unit tests require device/emulator | `cd sdk/runanywhere-kotlin && ./gradlew ktlintCheck` | Single-target Android library (no KMP). `androidx.annotation` is always available because the build only targets Android. |
| Web SDK (TypeScript) | `npm run build -w packages/core` (from `sdk/runanywhere-web/`) | N/A | `npm run typecheck -w packages/core` | `llamacpp` package has a pre-existing duplicate index signature TS error |
| Web Example App | `npm run dev` (from `examples/web/RunAnywhereAI/`) | Manual browser testing at `localhost:3000` | N/A | Full Vite app, works in demo mode without WASM |
| C++ Commons (core) | `cmake -B build ... && cmake --build build` (from `sdk/runanywhere-commons/`) | `./build/tests/test_core --run-all` (13 tests, no models needed) | N/A | Must use `gcc`/`g++` via `CC=gcc CXX=g++` (clang lacks C++ stdlib headers). Pass `-DRAC_BUILD_PLATFORM=OFF` on Linux |
| C++ Commons (full backends) | `CC=gcc CXX=g++ ./scripts/build-linux.sh` | Backend tests need downloaded models | N/A | Builds the canonical Linux release preset and packages the staged shared libraries and public headers. |
| Linux Voice Assistant | `cmake -B build && cmake --build build` (from `Playground/linux-voice-assistant/`) | `./build/test-pipeline <audio.wav>` runs full VAD→STT→LLM→TTS pipeline | N/A | Requires: ALSA headers (`libasound2-dev`), built commons with backends, downloaded models (`./scripts/download-models.sh`). Audio capture needs real hardware; `test-pipeline` works headless |
| iOS/Swift SDK | Not buildable | Not buildable | Not available | Requires macOS + Xcode |
| Android emulator | Not runnable | Not runnable | N/A | No KVM support in cloud VM |

### Key Gotchas

- **Android SDK**: Installed at `/opt/android-sdk`. `ANDROID_HOME` and `JAVA_HOME` are set in `~/.bashrc`.
- **JDK 17**: Required by Gradle JVM toolchain. Both JDK 17 and JDK 21 are installed.
- **`useLocalNatives` flag**: Set to `true` in `gradle.properties`. Pass `-Prunanywhere.useLocalNatives=false` to Gradle to avoid needing Android NDK (downloads pre-built JNI libs from GitHub releases instead of building locally).
- **C++ compiler**: Default clang on this VM lacks `libc++` headers. Use `gcc`/`g++` via `-DCMAKE_C_COMPILER=gcc -DCMAKE_CXX_COMPILER=g++`.
- **`local.properties`**: Auto-created at root, `sdk/runanywhere-kotlin/`, and `examples/android/RunAnywhereAI/` with `sdk.dir=/opt/android-sdk`.
- **pre-commit hooks**: Installed via `pre-commit install`. Requires `git config --unset-all core.hooksPath` first if `core.hooksPath` is set.

### Linux Voice Assistant Quick Start

```bash
# 1. Build commons with backends
cd sdk/runanywhere-commons
CC=gcc CXX=g++ ./scripts/build-linux.sh

# 2. Build voice assistant
cd ../../Playground/linux-voice-assistant
CC=gcc CXX=g++ cmake -B build && cmake --build build

# 3. Run test pipeline (headless, no mic needed)
export LD_LIBRARY_PATH="../../sdk/runanywhere-commons/dist/linux/lib:../../sdk/runanywhere-commons/third_party/sherpa-onnx-linux/lib"
./build/test-pipeline /path/to/audio.wav
```

### Standard commands

See the rest of this file for comprehensive build/test/lint commands for all SDK platforms. See `CONTRIBUTING.md` for contributor setup flow.
