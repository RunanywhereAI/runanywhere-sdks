# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.
- Focus on SIMPLICITY, and following Clean SOLID principles when writing code. Reusability, Clean architecture(not strictly) style, clear separation of concerns.
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

---

## Repository Overview

Cross-platform on-device AI SDK monorepo. A single C/C++ core (`runanywhere-commons`, ~51K LOC) implements all AI business logic behind a pure C ABI (`rac_*` prefix). Five platform SDKs are thin bridges that supply platform services (file I/O, HTTP, Keychain, audio) via an inversion-of-control struct and call into the C core for all inference. Protobuf IDL schemas generate type-safe bindings for every language.

**Current version**: `0.19.13` (canonical source: `sdk/runanywhere-commons/VERSION`)

### SDK Implementations
| SDK | Path | Bridge Mechanism | Platforms |
|-----|------|-----------------|-----------|
| Swift | `sdk/runanywhere-swift/` | XCFramework + CRACommons module map | iOS 17+, macOS 14+ |
| Kotlin Multiplatform | `sdk/runanywhere-kotlin/` | JNI (`librunanywhere_jni.so`) | Android (min 24), JVM 17 |
| Flutter | `sdk/runanywhere-flutter/` | Dart FFI (`ffi` package) | iOS, Android |
| React Native | `sdk/runanywhere-react-native/` | NitroModules (JSI HybridObject) | iOS 15.1+, Android arm64 |
| Web | `sdk/runanywhere-web/` | Emscripten WASM + TypeScript | Browsers (Chrome, Safari, Firefox) |

### Native Core
| Directory | Contents |
|-----------|----------|
| `sdk/runanywhere-commons/` | C/C++ core library — all AI logic, plugin registry, event system |
| `engines/` | 8 backend plugins: llamacpp, sherpa, onnx, whispercpp, whisperkit_coreml, metalrt, genie, diffusion-coreml |
| `runtimes/` | 4 runtime adapters: cpu (always), onnxrt, coreml, metal |
| `idl/` | 23 Protobuf schemas + per-language codegen scripts |

### Example Applications
| App | Path | Build System |
|-----|------|-------------|
| Android | `examples/android/RunAnywhereAI/` | Gradle/Compose |
| iOS | `examples/ios/RunAnywhereAI/` | SwiftUI + SPM |
| Flutter | `examples/flutter/RunAnywhereAI/` | Flutter + Dart FFI |
| React Native | `examples/react-native/RunAnywhereAI/` | RN 0.83 + NitroModules |
| Web | `examples/web/RunAnywhereAI/` | Vanilla TS + Vite |

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
                    │  Service Layer (routing)       │
                    │  Plugin Registry + Router      │
                    └───────────────┬───────────────┘
                                    │ rac_engine_vtable_t (v3)
          ┌─────────────┬───────────┼───────────┬─────────────┐
          ▼             ▼           ▼           ▼             ▼
      llamacpp      sherpa-onnx  metalrt    platform     whispercpp
     (LLM,VLM)    (STT,TTS,VAD) (Apple)  (Apple FM)      (STT)
```

### Key Architectural Patterns

**Platform Adapter IoC**: `rac_platform_adapter_t` is a flat C struct of function pointers populated by each SDK before calling `rac_init()`. C++ never calls platform APIs directly — all file I/O, HTTP, Keychain, logging, and memory queries pass through this struct.

**Two-Phase SDK Initialization**: All SDKs follow the same pattern: Phase 1 (synchronous — register platform adapter, load native libs, configure logging) then Phase 2 (async — authenticate, register device, fetch model assignments, discover downloaded models).

**Plugin ABI v3**: Every backend publishes a `rac_engine_vtable_t` with 8 primitive slots (`llm_ops`, `stt_ops`, `tts_ops`, `vad_ops`, `embedding_ops`, `rerank_ops`, `vlm_ops`, `diffusion_ops`). NULL slot = not supported. `RAC_PLUGIN_API_VERSION = 3u` — version mismatch causes immediate rejection.

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
./scripts/build-core-xcframework.sh
# Also syncs XCFrameworks into React Native and Flutter SDK plugin dirs

# Android: Build .so for all ABIs → copies into all SDK jniLibs/ dirs
./scripts/build-core-android.sh

# WASM: Build racommons-llamacpp.wasm → sdk/runanywhere-web/packages/llamacpp/wasm/
./scripts/build-core-wasm.sh

# Version bump across all manifests
./scripts/sync-versions.sh <version>

# Update Package.swift checksums after building release zips
./scripts/sync-checksums.sh <zip_dir>

# Full IDL codegen (requires protoc toolchain — see scripts/setup-toolchain.sh)
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

See `sdk/runanywhere-commons/CLAUDE.md` for detailed architecture and C++ conventions.

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
swift build

# Run tests
swift test

# Build for specific platform
xcodebuild build -scheme RunAnywhere -destination 'platform=iOS Simulator,name=iPhone 16 Pro'

# Run SwiftLint
swiftlint
```

### Kotlin SDK (`sdk/runanywhere-kotlin/`)

```bash
cd sdk/runanywhere-kotlin/

# Build all (JVM + Android)
./scripts/sdk.sh build

# Individual targets
./scripts/sdk.sh jvm           # JVM JAR
./scripts/sdk.sh android       # Android AAR

# Test
./scripts/sdk.sh test          # All tests
./scripts/sdk.sh test-jvm      # JVM only

# Publish to Maven Local
./scripts/sdk.sh publish

# Direct Gradle
./gradlew assembleDebug        # Android debug AAR
./gradlew jvmJar               # JVM JAR
./gradlew publishToMavenLocal
```

Build outputs: `build/libs/RunAnywhereKotlinSDK-jvm-*.jar`, `build/outputs/aar/RunAnywhereKotlinSDK-*.aar`

Backend modules at `modules/runanywhere-core-llamacpp/` and `modules/runanywhere-core-onnx/`.

### Flutter SDK (`sdk/runanywhere-flutter/`)

Managed by Melos. Four packages: `runanywhere` (core), `runanywhere_llamacpp`, `runanywhere_onnx`, `runanywhere_genie`.

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
./wasm/scripts/build.sh --llamacpp --vlm       # CPU variant
./wasm/scripts/build.sh --llamacpp --webgpu     # WebGPU variant
./wasm/scripts/build-sherpa-onnx.sh             # Sherpa-ONNX WASM

# Build TypeScript
npm run build:ts

# Type-check
npm run typecheck
```

WASM outputs: `packages/llamacpp/wasm/racommons-llamacpp.{js,wasm}`, `packages/onnx/wasm/sherpa/sherpa-onnx.wasm`

### IDL Codegen

```bash
# Install toolchain (protoc, protoc-gen-swift, wire-compiler, ts-proto, etc.)
./scripts/setup-toolchain.sh

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

# CI verification
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
./gradlew detekt               # Static analysis
./gradlew ktlintCheck          # Lint
./scripts/verify.sh            # Full build gate
```

Uses local project references via `settings.gradle.kts` to SDK modules.

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
npm run dev          # Vite dev server at port 5173
npm run build        # Production build
```

Requires WASM pre-built. `SharedArrayBuffer` needs cross-origin isolation headers (COOP + COEP).

---

## Version Management

Canonical version: `sdk/runanywhere-commons/VERSION` (single-line file, e.g. `0.19.13`).

```bash
# Bump everywhere: VERSION, Package.swift, gradle.properties, package.json, pubspec.yaml
./scripts/sync-versions.sh 0.20.0
```

Release lifecycle: `sync-versions.sh` → PR with `release:minor` label → merge → `auto-tag.yml` pushes `v0.20.0` tag → `release.yml` builds all artifacts and creates draft GitHub Release.

---

## CI/CD Workflows (`.github/workflows/`)

| Workflow | Trigger | Purpose |
|----------|---------|---------|
| `pr-build.yml` | PR to main, push to main/feat branch | Parallel native builds (macOS/Linux/iOS/Android) + per-SDK typecheck |
| `release.yml` | Tag `v*.*.*` or manual | Full artifact build matrix, SDK packaging, consumer validation, draft Release |
| `auto-tag.yml` | PR merged to main with `release:*` label | Computes next semver, pushes git tag |
| `idl-drift-check.yml` | Changes to `idl/` or generated files | Regenerates protos, fails if `git diff` is non-empty |
| `streaming-perf.yml` | Changes to `tests/streaming/` or voice agent | Cross-SDK streaming parity + performance tests |
| `legacy-files-blocklist.yml` | All PRs/pushes | Prevents 5 specific deleted files from being re-introduced |
| `secret-scan.yml` | PRs and pushes to main | Incremental gitleaks scan on diff range |

---

## Cross-SDK Streaming Parity Tests (`tests/streaming/`)

C++ "golden producer" binaries generate deterministic fixture files. Equivalent Swift, Kotlin, Dart, and TypeScript tests read the same fixtures and verify wire-format parity.

```bash
# Build and run parity tests
cmake -B build -DRAC_BUILD_TESTS=ON -DCMAKE_BUILD_TYPE=Debug
cmake --build build --target parity_test_cpp perf_producer cancel_producer
ctest --test-dir build -R parity
```

Test categories: voice agent parity (`golden_events.txt`), LLM streaming parity (`llm_golden_events.txt`), perf bench (p50 decode < 1ms assertion), cancel parity (interrupt at index 500).

---

## Key Architectural Decisions

### iOS SDK is Source of Truth
When implementing features in any other SDK (especially Kotlin KMP), always check the iOS Swift implementation first. Copy logic exactly, adapting only for language syntax, not business logic.

### All Business Logic in C++ or commonMain
Platform-specific code should only handle: native library loading, platform adapter registration, audio capture/playback, secure storage, and UI. All AI inference, model management, event routing, and pipeline orchestration live in C++ (`runanywhere-commons`) or Kotlin `commonMain`.

### Backend Registration Pattern
All SDKs follow the same pattern:
1. Load the backend native library
2. Call `rac_backend_*_register()` (which registers the engine's vtable with the plugin registry)
3. The router scores registered plugins by priority + runtime + format compatibility
4. On inference, the highest-scoring plugin's vtable ops are invoked

Backend priorities: metalrt=120 (highest, Apple-only), llamacpp=100, sherpa=90. Pinned engine matches get +10000.

### HTTP Transport is Platform-Provided
libcurl was removed. Each SDK registers a `rac_http_transport_ops_t` vtable: Swift uses URLSession, Kotlin/Flutter/RN use OkHttp (Android) or URLSession (iOS), Web uses `emscripten_fetch`.

### Proto-Generated Types Replace Hand-Written Enums
All cross-platform types are defined in `idl/*.proto`. SDKs use typealiases to the generated types (e.g., `typealias SDKEnvironment = RASDKEnvironment` in Swift, `typealias SDKEnvironment = ai.runanywhere.proto.v1.SDKEnvironment` in Kotlin). Never add enum values by hand — modify the `.proto` file and regenerate.

---

## Platform Requirements

| Platform | Min Version | Build Tool | Key Versions |
|----------|------------|------------|--------------|
| iOS | 17.0 | Xcode 15+ | Swift 5.9+ |
| macOS | 14.0 | Xcode 15+ | Swift 5.9+ |
| Android | API 24 | AGP 8.11.2 | Kotlin 2.1.21, NDK 27.0.12077973 |
| JVM | 17 | Gradle 8.13 | Kotlin 2.1.21 |
| Flutter | 3.10+ | Melos | Dart 3.0+ |
| React Native | 0.83.1 | Yarn Berry 3.6.1 | NitroModules, Hermes |
| Web | Chrome 86+ | Vite | Emscripten 5.0+, Node 18+ |
| C++ Core | N/A | CMake 3.22+ | C++20, Ninja |

---

## Kotlin Multiplatform (KMP) SDK - Critical Implementation Rules

### iOS as Source of Truth
**NEVER make assumptions when implementing KMP code. ALWAYS refer to the iOS implementation as the definitive source of truth.**

1. **iOS First**: When encountering missing logic or unclear requirements in KMP, check the corresponding iOS implementation, copy the logic exactly, adapt only for Kotlin syntax.

2. **commonMain First**: ALL business logic, interfaces, data models, and enums MUST be in `commonMain/`. Platform-specific modules (`androidMain`, `jvmMain`) only contain platform service implementations.

3. **Platform Naming Convention**: Platform-specific implementations MUST use prefixes: `AndroidTTSService.kt`, `JvmTTSService.kt`, `IosTTSService.kt`.

### KMP Source Set Hierarchy

```
commonMain           (~80 hand-written .kt + ~190 Wire-generated proto files)
    └── jvmAndroidMain    (~62 files — JNI bridge, CppBridge*, OkHttp)
            ├── androidMain   (~19 files — AudioRecord, EncryptedSharedPreferences)
            └── jvmMain       (~16 files — javax.sound, file-based crypto)
```

Manually configured (no `applyDefaultHierarchyTemplate`). Use `expect/actual` only for truly platform-specific code.

### Cross-SDK Alignment

| Concern | iOS Swift | Kotlin KMP | Flutter | React Native | Web |
|---------|-----------|-----------|---------|-------------|-----|
| Entry point | `enum RunAnywhere` | `object RunAnywhere` | `RunAnywhereSDK.instance` | `RunAnywhere` object | `RunAnywhere` object |
| Two-phase init | `initialize()` + `completeServicesInitialization()` | Same | Same | Same | Same |
| Bridge layer | `CppBridge` enum + extensions | `CppBridge` object + extensions | `DartBridge` + `DartBridge*.dart` | `HybridRunAnywhereCore` (Nitro) | `LlamaCppBridge` + `SherpaONNXBridge` |
| Streaming | `AsyncStream` | `Flow` | `Stream` (via `StreamController`) | `AsyncIterable` (manual iteration) | `AsyncIterable` |
| Events | `EventBus` (Combine) | `EventBus` (SharedFlow) | `EventBus` (rxdart) | `EventBus` (NativeEventEmitter) | `EventBus` (custom pub/sub) |
| Error type | `SDKException` (proto-backed) | `SDKException` (proto-backed) | `SDKException` | `SDKException` | `SDKException` |
| Secure storage | Keychain | EncryptedSharedPrefs (Android), AES files (JVM) | flutter_secure_storage + cache | Keychain (iOS), EncryptedSharedPrefs (Android) | localStorage |
| HTTP transport | URLSession | OkHttp | OkHttp (Android), URLSession (iOS) | OkHttp (Android), URLSession (iOS) | emscripten_fetch / fetch() |

---

## Non-Obvious Configuration Details

**`Package.swift:43`** — `let useLocalNatives = true` is hard-coded for local dev. External SPM consumers need `false`. Scripts toggle this.

**`Package.swift:186-191`** — Three `.grpc.swift` files are excluded from compilation. They require iOS 18 / macOS 15, above the SDK's minimums. In-process C callback path replaces gRPC.

**`gradle.properties`** — `runanywhere.useLocalNatives=true` means local `.so` files. CI overrides with `-Prunanywhere.useLocalNatives=false` to download from GitHub Releases.

**Two NDK versions** — `racNdkVersion=27.0.12077973` for Kotlin/RN/Commons, `racFlutterNdkVersion=25.2.9519653` for Flutter (Flutter ships its own NDK pin).

**Flutter xcframework workaround** — `build-core-xcframework.sh` strips `rac_plugin_entry_whisperkit_coreml.o` from Flutter's copy of the commons archive because Flutter uses `-all_load` which would drag in an unresolvable symbol.

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

On `feat/v2-architecture` branch, 5 tracked regressions relative to `main`:
- **001/002/005** (HIGH): Swift, Kotlin, and Web SDKs collapsed backends into monolithic artifacts, losing per-backend selective linking.
- **003** (MEDIUM): React Native backend packages are TypeScript-only, missing native plumbing.
- **004** (LOW): Flutter is currently a symlink to main branch.

Live state document: `thoughts/shared/plans/sdk_current_state.md`
