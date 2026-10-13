# AGENTS.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

The repo-root `AGENTS.md` keeps SDK build commands here rather than duplicating them — this
file is the authoritative source for Kotlin SDK commands, architecture, and conventions.

## Build & Development Commands

```bash
cd bindings/kotlin/

# Build (Android library)
./gradlew build

# Individual builds
./gradlew assembleDebug             # Android Debug AAR
./gradlew assembleRelease           # Android Release AAR

# Tests
./gradlew test                      # All unit tests (debug + release variants)
./gradlew testDebugUnitTest         # Android Debug unit tests only

# Code quality
./gradlew detekt                    # Static analysis (maxIssues: 0, warningsAsErrors)
./gradlew ktlintCheck               # Kotlin lint check
./gradlew ktlintFormat              # Auto-fix lint issues
./gradlew lint                      # Android Lint

# Publishing
./gradlew publishToMavenLocal       # Publish to ~/.m2/repository

# Native library management
./gradlew setupLocalDevelopment     # First-time: builds C++ JNI libs from source
./gradlew rebuildCommons            # Rebuild C++ after source changes
./gradlew downloadJniLibs           # Download pre-built .so from GitHub Releases

# Clean
./gradlew clean                     # Clean build directories
```

**Build outputs:**
- Android AAR: `build/outputs/aar/runanywhere-kotlin-{debug,release}.aar`
- Sub-module AARs: `modules/runanywhere-core-{llamacpp,onnx,qhexrt}/build/outputs/aar/*.aar`

**Native lib sourcing** is controlled by `gradle.properties`:
- `runanywhere.useLocalNatives=true` (default) → runs `scripts/build/build-core-android.sh` to compile C++ from source
- `runanywhere.useLocalNatives=false` → downloads pre-built `.so` from GitHub Releases using `runanywhere.nativeLibVersion`

`runanywhere.nativeLibVersion` pins a GitHub **release tag that has Android `.so` assets**,
not the SDK's own package version — a release that only republished other platforms'
packages (e.g. `0.20.20` was Electron-only) has no Android archives and `downloadJniLibs`
404s against it. Keep the property on the last release that actually shipped `.so` files.

Full contributor setup walkthrough (prerequisites, first-time native build, sample app): `docs/DEVELOPMENT.md`.

## Architecture Overview

### Core Pattern: Kotlin Wrapper over C++ Core

The Kotlin SDK builds as an Android library (`alias(libs.plugins.android.library)` in `build.gradle.kts`), not as a Kotlin Multiplatform module. All AI inference (LLM, STT, TTS, VAD, VLM, RAG, diffusion) runs in a shared C++ library (`librac_commons.so` + `librunanywhere_jni.so`). The Kotlin SDK is a typed wrapper that provides:
- Public API surface (`object RunAnywhere` + extension functions, mirrors Swift `enum RunAnywhere`)
- JNI bridge to the C++ `rac_*` function API
- Kotlin coroutines/Flow integration for async and streaming
- Wire protobuf types as the canonical data model

### Source Set Layout

```
bindings/kotlin/
    src/main/kotlin/        (all Kotlin sources — public API, JNI bridges, generated Wire proto classes)
    src/main/jniLibs/       (prebuilt .so files staged by build-core-android.sh)
    src/test/kotlin/        (unit tests — no JNI required)
    modules/
        runanywhere-core-llamacpp/  (Android library sub-module; registers llama.cpp backend, bundles librac_backend_llamacpp_jni.so)
        runanywhere-core-onnx/      (Android library sub-module; registers ONNX/Sherpa backend, bundles librac_backend_onnx_jni.so)
        runanywhere-core-qhexrt/    (Android library sub-module, arm64-v8a only; registers the Qualcomm Hexagon NPU backend)
```

Standard single-target Android library — there is no `commonMain`/`jvmAndroidMain`/`androidMain`/`jvmMain` hierarchy. Subdirectories named `JNI` or `bridge` under `src/main/kotlin/com/runanywhere/sdk/` mirror the iOS bridge layout but compile as a single Android target. Platform-specific suffixes like `AndroidTTSService.kt` are kept by convention so future re-introduction of a JVM or KMP variant remains low-friction.

### Two-Phase Initialization

Mirrors the iOS Swift SDK pattern:

**Phase 1** — `RunAnywhere.initialize(apiKey, environment)` — synchronous, ~1-5ms:
- Loads native library via `System.loadLibrary("runanywhere_jni")`
- Registers platform adapter, OkHttp transport, C++ logging, telemetry/events, and device callbacks in `CppBridge.initialize`
- Runs SDK phase-1 state validation, auth storage setup, file manager registration, and model-path base setup from `RunAnywhere.performCoreInit`
- Protected by `synchronized(lock)`

**Phase 2** — `RunAnywhere.completeServicesInitialization()` — suspend, makes network calls:
- Authenticates with backend (prod/staging only)
- Fetches model assignments
- Registers platform services, including Android System TTS callbacks, flushes telemetry, triggers device registration
- Protected by coroutine `Mutex`, auto-called by `ensureServicesReady()` on first feature use

### JNI Bridge Architecture

```
Kotlin code (RunAnywhere extensions)
    → CppBridge* extension objects (type conversion, error mapping)
        → RunAnywhereBridge external fun declarations (JNI boundary)
            → librac_commons.so C functions (rac_llm_*, rac_stt_*, etc.)
```

Key files in this chain (all under `src/main/kotlin/com/runanywhere/sdk/`):
- `native/bridge/RunAnywhereBridge.kt` — all JNI `external fun` declarations
- `foundation/bridge/CppBridge.kt` — initialization orchestrator
- `foundation/bridge/extensions/CppBridge*.kt` — per-domain bridge wrappers (Auth, LLM, STT, TTS, VAD, VLM, Download, Device, Telemetry, etc.)
- `foundation/http/OkHttpTransport.kt` — HTTP transport registered into C++ vtable
- `public/PlatformBridge.kt` — Android platform implementation for the three core platform functions used by `RunAnywhere.kt`

### Public API Surface

`RunAnywhere` (object singleton, `public/RunAnywhere.kt`) is the sole entry point; every
feature is an extension function one-per-file under `public/extensions/`: LLM, STT, TTS,
VAD, VLM, VoiceAgent, Models (lifecycle + registry), RAG, ToolCalling, StructuredOutput,
LoRA, Diffusion, Solutions (YAML pipelines), Storage, Auth, Hardware. Full file → capability
→ signature table: [`docs/reference/public-api-surface.md`](docs/reference/public-api-surface.md).

### Type System

**Wire protobuf types are the canonical data model.** Generated bindings live in `src/main/kotlin/com/runanywhere/sdk/generated/ai/runanywhere/proto/v1/` (~370 files). That whole tree — plus `generated/RADefaultsPool.kt` and `generated/convenience/RAConvenience.kt` — is **not tracked**: a fresh clone has none of it until the `generateIdlKotlinBindings` Gradle task runs, which `preBuild` (and ktlint/detekt) depend on, so any `./gradlew assemble*` / `compile*Kotlin` / `test*` generates it first. Run `./idl/codegen/generate_all.sh --only kotlin` to refresh it by hand. The compiler pins (protoc, wire-compiler, the Python protobuf runtime) are downloaded and checksum-verified by `idl/codegen/bootstrap_*.sh`; nothing needs installing. The SDK uses these types directly or via typealiases:

```kotlin
typealias SDKEnvironment = ai.runanywhere.proto.v1.SDKEnvironment
typealias AudioFormat = ai.runanywhere.proto.v1.AudioFormat
```

Consumers construct the Wire-generated types directly (for example `VLMImage(raw_rgb = bytes.toByteString(), width = w, height = h, format = VLMImageFormat.VLM_IMAGE_FORMAT_RAW_RGB)`). There is no `foundation/protoext/` package — previous ergonomic wrappers were removed in KOT-DEAD-PROTOEXT after they were found to have zero active consumers.

Hand-rolled Kotlin types exist in `src/main/kotlin/com/runanywhere/sdk/public/extensions/` for public API ergonomics: `LLMTypes.kt`, `ToolCallingTypes.kt`, `ModelTypes.kt`, `VoiceAgentTypes.kt`, `VLMStreamingResult.kt`.

### Error Handling

`SDKException` wraps a proto `SDKError(code, category, message, c_abi_code)`. Factory methods map C ABI negative return codes to typed exceptions:

```kotlin
val result = racLlmGenerate(...)
result.throwIfCAbiErrorAsException("llm.generate")  // throws SDKException if < 0
```

`CommonsErrorMapping.kt` defines all C ABI constants (`RAC_SUCCESS = 0`, `RAC_ERROR = -1`, etc.) and extension functions on `Int` for ergonomic error checking.

### Event System

`EventBus` is a singleton `MutableSharedFlow<SDKEvent>(replay=0, extraBufferCapacity=64)`. All components publish typed events (model download progress, LLM tokens, STT transcription, lifecycle events). Subscribe via:

```kotlin
RunAnywhere.events.llmEvents.collect { event -> ... }
// Extract proto envelope payloads (Wire generates SDKEvent as a oneof envelope,
// so payload messages like ModelEvent are siblings, not subclasses):
RunAnywhere.events.modelEventPayloads.collect { model: ModelEvent -> ... }
RunAnywhere.events.eventsOfPayload { it.generation }.collect { ... }
```

### Modules

Three optional backend modules in `modules/`:

- **`runanywhere-core-llamacpp`** — LLM backend. Single file (`LlamaCPP.kt`) calling `rac_backend_llamacpp_register()`. Bundles `librac_backend_llamacpp_jni.so`.
- **`runanywhere-core-onnx`** — co-distributed generic ONNX + Sherpa speech backends. `ONNX.kt` explicitly registers both engines and the module bundles their native `.so` files.
- **`runanywhere-core-qhexrt`** — Qualcomm Hexagon NPU backend, `arm64-v8a` only. `QHexRT.kt` exposes `probeNpu()` / `register()` / `unregister()`; `QHexRTSkelInstaller.kt` extracts the per-arch (V75/V79/V81) DSP skel at install time. The AAR is binary-only (proprietary QAIRT/QNN host libs + skels are gitignored upstream, only staged by authorized builds), so **every entry point guards on `QHexRTBridge.ensureNativeLibraryLoaded()` and no-ops instead of throwing** when the native lib is absent — a contributor checkout without the private binary must still build and run. Packaged separately via `scripts/package-qhexrt.sh` (not `package-sdk.sh`); that script is not yet wired into `release.yml`. Building it locally needs `ANDROID_NDK_HOME` (or the default SDK Manager path) even when `useLocalNatives=false`, to stage `libc++_shared.so` alongside the prebuilt `.so`s.

All three follow the same pattern: thin Android-library sub-modules that register a C++ backend with the core's plugin system. They depend on the root SDK via `api()`.

### Streaming Adapters

`LLMStreamAdapter` and `VoiceAgentStreamAdapter` (`src/main/kotlin/com/runanywhere/sdk/adapters/`) solve the single-callback-slot problem: C++ only supports one callback per handle, but Kotlin needs multiple concurrent `Flow` collectors. They use `SharedFlow` fan-out with `ConcurrentHashMap<(handle, bridge), FanOut>`.

## Key Conventions

- **All business logic in `src/main/kotlin/com/runanywhere/sdk/`.** Keep the public API surface under `public/` and JNI bridges under `foundation/bridge/`; do not push business logic into the Android `Activity`/`Service` layer or into example apps.
- **Platform file naming:** `AndroidTTSService.kt` — keep the `Android` prefix on platform-bound services so future JVM/desktop or KMP reintroductions stay low-friction.
- **VLM on Android routes through core JNI, not llamacpp-JNI.** The dedicated `librac_backend_llamacpp_jni.so` bridge only exposes LLM primitives (`nativeCreate`, `nativeGenerate`, `nativeCancel`) plus the two registration shims. Kotlin VLM callers invoke the commons `rac_vlm_component_*` proto APIs via `librunanywhere_jni.so` (same path iOS uses via `CppBridgeVLM`). Do not add `nativeCreateVLM` / `nativeProcessVLM` entry points to the llamacpp JNI — the VLM plugin registers its vtable, and `rac_plugin_find` dispatches from core.

## Build System Details

**Gradle:** 9.5.0 | **Kotlin:** 2.4.0 | **AGP:** 9.2.1 | **JVM target:** 17 | **Android minSdk:** 24 | **compileSdk:** 37

**Version catalog:** `gradle/libs.versions.toml`, local to this module (not shared with the other SDKs).

**Source layout:** Single-target Android library — `src/main/kotlin/` and `src/test/kotlin/` only. No KMP source-set hierarchy. Backend sub-modules (`modules/runanywhere-core-{llamacpp,onnx,qhexrt}/`) follow the same Android-library plugin layout.

**Wire codegen:** Not applied as a Gradle plugin (`wire` isn't in the catalog's `[plugins]` — only the `wire-runtime` library is). Codegen runs via a custom `generateIdlKotlinBindings` `Exec` task that calls `idl/codegen/generate_all.sh --only kotlin` directly (see Type System above for what it produces and why). `idl-drift-check.yml` verifies the schema lock still matches and that the generated tree exists and stays untracked.

**Maven group resolution:** Determined at configuration time from env vars — `com.github.RunanywhereAI.runanywhere-sdks` (JitPack), `com.runanywhere` (official), or `io.github.sanchitmonga22` (default).

**Code quality:** Detekt (v1.23.8, `maxIssues: 0`, `warningsAsErrors: true`) and ktlint (v1.5.0, `max_line_length=250`) are enforced. Detekt config disables complexity/naming/comments rule sets but activates coroutine, empty-block, potential-bug, and unused-code rules.

## Testing

Tests live under `src/test/kotlin/` (Android library test source set). They cover Kotlin-layer surface tests (generated proto adapters, extension surfaces, stream adapter fan-out) and do not require JNI.

There is no shared cross-SDK streaming parity harness wired into this module today. A prior revision of this file referenced an external `../../tests/streaming/` srcDir mount and `PerfBenchTest` / `CancelParityTest` / `ChecksumPlumbingTest` classes — none of those paths or files exist. The only streaming-parity coverage anywhere in the repo is Flutter's self-contained `bindings/flutter/packages/runanywhere/test/parity_test.dart` (and its sibling `cancel_parity_test.dart`), which builds its own fixtures in-package and does not drive other SDKs.

Most tests can run without JNI loaded (they test Kotlin-layer logic). Tests requiring the native library need `setupLocalDevelopment` to have been run first.

## CI/CD

- **`pr-build.yml`** (`kotlin-android` job) — `./gradlew testDebugUnitTest assembleDebug`, a composite-build `assembleDebug` of `bindings/kotlin/example`, then `./gradlew ktlintCheck detekt` as a separate lint step. Runs after `scripts/build/build-core-android.sh` builds the JNI libs from source.
- **`release.yml`** — `native_android` matrix-builds native libs for **3 ABIs** (`arm64-v8a`, `armeabi-v7a`, `x86_64`; legacy 32-bit `x86` was dropped, not wired into the current build path). `sdk_kotlin` then packages the staged natives via `scripts/package-sdk.sh` into a versioned local Maven repository with SHA256 checksums. `scripts/package-qhexrt.sh` packages the QHexRT AAR separately and is not yet called from this workflow.
- **`idl-drift-check.yml`** — Regenerates every binding, then verifies the committed `idl/SCHEMA_LOCK` still matches the `.proto` digest and this module's generated tree exists and is untracked.

## Related docs

`docs/DEVELOPMENT.md` (contributor setup) is linked above under Build & Development Commands.

- [`docs/reference/public-api-surface.md`](docs/reference/public-api-surface.md) — full public API file → capability → signature table (see Public API Surface above).
- [`docs/Documentation.md`](docs/Documentation.md) — narrated usage examples; covers only the Core/LLM/STT/TTS/VAD/VoiceAgent/Model-Management subset (see caveat in the reference doc above).
- [`docs/KOTLIN_MAVEN_CENTRAL_PUBLISHING.md`](docs/KOTLIN_MAVEN_CENTRAL_PUBLISHING.md) — per-artifact Maven Central publishing details, including the QHexRT AAR's native-lib manifest.
- [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) — internal design write-up. **Stale**: it describes a KMP `commonMain`/`androidMain`/`jvmMain` split that no longer exists. This file's Source Set Layout above is current; treat `ARCHITECTURE.md`'s topology claims with suspicion until it's refreshed.
