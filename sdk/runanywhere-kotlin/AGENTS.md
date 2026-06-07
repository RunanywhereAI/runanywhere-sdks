# AGENTS.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build & Development Commands

```bash
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
- Sub-module AARs: `modules/runanywhere-core-{llamacpp,onnx}/build/outputs/aar/*.aar`

**Native lib sourcing** is controlled by `gradle.properties`:
- `runanywhere.useLocalNatives=true` → runs `build-core-android.sh` to compile C++ from source
- `runanywhere.useLocalNatives=false` → downloads pre-built `.so` from GitHub Releases using `runanywhere.nativeLibVersion`

## Architecture Overview

### Core Pattern: Kotlin Wrapper over C++ Core

The Kotlin SDK builds as an Android library (`alias(libs.plugins.android.library)` in `build.gradle.kts`), not as a Kotlin Multiplatform module. All AI inference (LLM, STT, TTS, VAD, VLM, RAG, diffusion) runs in a shared C++ library (`librac_commons.so` + `librunanywhere_jni.so`). The Kotlin SDK is a typed wrapper that provides:
- Public API surface (`object RunAnywhere` + extension functions, mirrors Swift `enum RunAnywhere`)
- JNI bridge to the C++ `rac_*` function API
- Kotlin coroutines/Flow integration for async and streaming
- Wire protobuf types as the canonical data model

### Source Set Layout

```
sdk/runanywhere-kotlin/
    src/main/kotlin/        (all Kotlin sources — public API, JNI bridges, ~190 Wire-generated proto classes)
    src/main/jniLibs/       (prebuilt .so files staged by build-core-android.sh)
    src/test/kotlin/        (unit tests — no JNI required)
    modules/
        runanywhere-core-llamacpp/  (Android library sub-module; registers llama.cpp backend, bundles librac_backend_llamacpp_jni.so)
        runanywhere-core-onnx/      (Android library sub-module; registers ONNX/Sherpa backend, bundles librac_backend_onnx_jni.so)
```

Standard single-target Android library — there is no `commonMain`/`jvmAndroidMain`/`androidMain`/`jvmMain` hierarchy. Subdirectories named `JNI` or `bridge` under `src/main/kotlin/com/runanywhere/sdk/` mirror the iOS bridge layout but compile as a single Android target. Platform-specific suffixes like `AndroidTTSService.kt` are kept by convention so future re-introduction of a JVM or KMP variant remains low-friction.

### Two-Phase Initialization

Mirrors the iOS Swift SDK pattern:

**Phase 1** — `RunAnywhere.initialize(apiKey, environment)` — synchronous, ~1-5ms:
- Loads native library via `System.loadLibrary("runanywhere_jni")`
- Registers platform adapter, auth, OkHttp transport, telemetry, file manager callbacks
- Protected by `synchronized(lock)`

**Phase 2** — `RunAnywhere.completeServicesInitialization()` — suspend, makes network calls:
- Authenticates with backend (prod/staging only)
- Fetches model assignments
- Registers platform services, flushes telemetry, triggers device registration
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

The entry point is `RunAnywhere` (a Kotlin `object` singleton in `src/main/kotlin/com/runanywhere/sdk/public/RunAnywhere.kt`). All feature APIs are extension functions on `RunAnywhere`, organized one-per-file under `src/main/kotlin/com/runanywhere/sdk/public/extensions/`:

| File | Capability |
|------|-----------|
| `LLM/RunAnywhereTextGeneration.kt` | `generate(prompt, RALLMGenerationOptions?) → RALLMGenerationResult`, `generateStream(...) → Flow<RALLMStreamEvent>`, `cancelGeneration()` |
| `STT/RunAnywhereSTT.kt` | `transcribe(audio, RASTTOptions)`, `transcribeStream(Flow<ByteArray>, RASTTOptions?) → Flow<RASTTPartialResult>` |
| `TTS/RunAnywhereTTS.kt` | `synthesize(text, RATTSOptions)`, `speak()`, `synthesizeStream() → Flow<RATTSOutput>`, `stopSpeaking()`, `stopSynthesis()` |
| `VAD/RunAnywhereVAD.kt` | `detectVoiceActivity()`, `streamVAD(Flow<FloatArray>, RAVADOptions)`, `resetVAD()` |
| `VLM/RunAnywhereVisionLanguage.kt` | `describeImage()`, `processImage()`, `processImageStream()` |
| `VoiceAgent/RunAnywhereVoiceAgent.kt` | Full voice pipeline: `initializeVoiceAgent(VoiceAgentConfig)`, `streamVoiceAgent() → Flow<VoiceEvent>`, `processVoiceTurn()`, `cleanupVoiceAgent()` |
| `Models/RunAnywhereModelLifecycle.kt` | `loadModel(RAModelLoadRequest)`, `unloadModel(ModelUnloadRequest)`, `currentModel(CurrentModelRequest)`, `componentLifecycleSnapshot()` |
| `Models/RunAnywhereModelRegistry.kt` | `registerModel()`, `downloadModel()`, `availableModels()`, `deleteModel()`, model CRUD |
| `RunAnywhere+RAG.kt` | `ragCreatePipeline()`, `ragIngest()`, `ragQuery()` |
| `RunAnywhere+ToolCalling.kt` | `registerTool()`, `generateWithTools()` |
| `RunAnywhere+StructuredOutput.kt` | `generateStructured()`, JSON schema-constrained generation |
| `RunAnywhere+LoRA.kt` | LoRA adapter load/remove/registry |
| `RunAnywhere+Diffusion.kt` | Image generation pipeline |
| `RunAnywhere+Solutions.kt` | Declarative YAML-based pipeline orchestration |
| `RunAnywhere+Storage.kt` | Storage info, cache management, model storage metrics |
| `RunAnywhere+Auth.kt` | `getUserId()`, `isAuthenticated`, device registration status |
| `RunAnywhere+Hardware.kt` | `HardwareProfile`, NPU/accelerator detection |

### Type System

**Wire protobuf types are the canonical data model.** Generated bindings live in `src/main/kotlin/com/runanywhere/sdk/generated/ai/runanywhere/proto/v1/` (~190 files). The SDK uses these directly or via typealiases:

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

Two optional backend modules in `modules/`:

- **`runanywhere-core-llamacpp`** — LLM backend. Single file (`LlamaCPP.kt`) calling `rac_backend_llamacpp_register()`. Bundles `librac_backend_llamacpp_jni.so`.
- **`runanywhere-core-onnx`** — STT/TTS/VAD backend. Single file (`ONNX.kt`) calling `rac_backend_onnx_register()`. Bundles sherpa-onnx and ONNX Runtime `.so` files.

Both follow the same pattern: thin Android-library sub-modules that register a C++ backend with the core's plugin system. They depend on the root SDK via `api()`.

### Streaming Adapters

`LLMStreamAdapter` and `VoiceAgentStreamAdapter` (`src/main/kotlin/com/runanywhere/sdk/adapters/`) solve the single-callback-slot problem: C++ only supports one callback per handle, but Kotlin needs multiple concurrent `Flow` collectors. They use `SharedFlow` fan-out with `ConcurrentHashMap<(handle, bridge), FanOut>`.

## Key Conventions

- **iOS is the source of truth.** When implementing or fixing Kotlin SDK features, check the corresponding iOS Swift SDK implementation first. Translate logic exactly; adapt only syntax.
- **All business logic in `src/main/kotlin/com/runanywhere/sdk/`.** Keep the public API surface under `public/` and JNI bridges under `foundation/bridge/`; do not push business logic into the Android `Activity`/`Service` layer or into example apps.
- **Platform file naming:** `AndroidTTSService.kt` — keep the `Android` prefix on platform-bound services so future JVM/desktop or KMP reintroductions stay low-friction.
- **Proto types over hand-rolled types.** Use Wire-generated types from `generated/` as the canonical representation; construct them directly with named arguments. Do not re-introduce a `foundation/protoext/` wrapper package.
- **Structured types, never raw strings.** Use enums, sealed classes, and data classes for all configuration and return values.
- **VLM on Android routes through core JNI, not llamacpp-JNI.** The dedicated `librac_backend_llamacpp_jni.so` bridge only exposes LLM primitives (`nativeCreate`, `nativeGenerate`, `nativeCancel`) plus the two registration shims. Kotlin VLM callers invoke the commons `rac_vlm_component_*` proto APIs via `librunanywhere_jni.so` (same path iOS uses via `CppBridgeVLM`). Do not add `nativeCreateVLM` / `nativeProcessVLM` entry points to the llamacpp JNI — the VLM plugin registers its vtable, and `rac_plugin_find` dispatches from core.

## Build System Details

**Gradle version:** 8.13 | **Kotlin:** 2.1.21 | **AGP:** 8.13.0 | **JVM target:** 17 | **Android minSdk:** 24 | **compileSdk:** 35

**Version catalog:** Shared at `../../gradle/libs.versions.toml` (monorepo-level, used by all SDKs).

**Source layout:** Single-target Android library — `src/main/kotlin/` and `src/test/kotlin/` only. No KMP source-set hierarchy. Backend sub-modules (`modules/runanywhere-core-llamacpp/`, `modules/runanywhere-core-onnx/`) follow the same Android-library plugin layout.

**Wire codegen:** The Wire Gradle plugin is defined in the catalog but NOT applied (Kotlin DSL clash). Generated proto files are committed to git. Regenerate via `idl/codegen/generate_kotlin.sh`. A CI workflow (`idl-drift-check.yml`) enforces freshness.

**Maven group resolution:** Determined at configuration time from env vars — `com.github.RunanywhereAI.runanywhere-sdks` (JitPack), `com.runanywhere` (official), or `io.github.sanchitmonga22` (default).

**Code quality:** Detekt (`maxIssues: 0`, `warningsAsErrors: true`) and ktlint (v1.5.0, `max_line_length=250`) are enforced. Detekt config disables complexity/naming/comments rule sets but activates coroutine, empty-block, potential-bug, and unused-code rules.

## Testing

Tests live under `src/test/kotlin/` (Android library test source set). They cover Kotlin-layer surface tests (generated proto adapters, extension surfaces, stream adapter fan-out) and do not require JNI.

There is no shared cross-SDK streaming parity harness wired into this module today. A prior revision of this file referenced an external `../../tests/streaming/` srcDir mount and `PerfBenchTest` / `CancelParityTest` / `ChecksumPlumbingTest` classes — none of those paths or files exist. The only streaming-parity coverage anywhere in the repo is Flutter's self-contained `sdk/runanywhere-flutter/packages/runanywhere/test/parity_test.dart` (and its sibling `cancel_parity_test.dart`), which builds its own fixtures in-package and does not drive other SDKs. See backlog row `BUG-STREAMING-HARNESS-NEW` if the shared harness is re-prioritized.

Most tests can run without JNI loaded (they test Kotlin-layer logic). Tests requiring the native library need `setupLocalDevelopment` to have been run first.

## CI/CD

- **`pr-build.yml`** — Triggered on PRs to `main` and pushes to `main`/`feat/v2-architecture`. Builds C++ from source, then runs `./gradlew assembleDebug`.
- **`release.yml`** — Triggered by `v*.*.*` tags. Matrix-builds native libs for 4 ABIs, stages into `src/main/jniLibs/`, runs `assembleRelease`, uploads artifacts with SHA256 checksums.
- **`idl-drift-check.yml`** — Monitors `generated/` directory. Regenerates proto bindings and fails on any `git diff`.
- **`scripts/package-sdk.sh`** — CI packaging script. Accepts `--natives-from PATH` for pre-staged `.so` files, builds all targets, outputs to `dist/sdk-kotlin/` with checksums.
