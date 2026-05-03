# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build & Development Commands

```bash
# Build all platforms (JVM + Android)
./gradlew build

# Individual platform builds
./gradlew jvmJar                    # JVM JAR only
./gradlew assembleDebug             # Android Debug AAR
./gradlew assembleRelease           # Android Release AAR

# Tests
./gradlew allTests                  # All tests (JVM + Android)
./gradlew jvmTest                   # JVM tests only
./gradlew testDebugUnitTest         # Android unit tests only

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
- JVM JAR: `build/libs/RunAnywhereKotlinSDK-jvm-*.jar`
- Android AAR: `build/outputs/aar/RunAnywhereKotlinSDK-{debug,release}.aar`

**Native lib sourcing** is controlled by `gradle.properties`:
- `runanywhere.useLocalNatives=true` → runs `build-core-android.sh` to compile C++ from source
- `runanywhere.useLocalNatives=false` → downloads pre-built `.so` from GitHub Releases using `runanywhere.nativeLibVersion`

## Architecture Overview

### Core Pattern: Kotlin Wrapper over C++ Core

All AI inference (LLM, STT, TTS, VAD, VLM, RAG, diffusion) runs in a shared C++ library (`librac_commons.so` + `librunanywhere_jni.so`). The Kotlin SDK is a typed wrapper that provides:
- Platform-agnostic public API via `expect`/`actual`
- JNI bridge to the C++ `rac_*` function API
- Kotlin coroutines/Flow integration for async and streaming
- Wire protobuf types as the canonical data model

### Source Set Hierarchy

```
commonMain          (public API, types, interfaces, proto extensions — NO inference logic)
    │
    └── jvmAndroidMain    (JNI bridge, CppBridge, OkHttp transport, Sentry — shared JVM+Android)
            ├── androidMain    (Android platform actuals: AudioRecord, EncryptedSharedPreferences, Build.*)
            └── jvmMain        (JVM desktop actuals: javax.sound, File-based encryption, System.getProperty)
```

- **`commonMain`** (~174 files): All business logic, public API surface, type definitions, proto extensions. Contains zero inference code — everything delegates to `expect` functions.
- **`jvmAndroidMain`** (~62 files): The JNI bridge layer. Contains `RunAnywhereBridge.kt` (~1,650 lines of `external fun` JNI declarations), `CppBridge.kt` (two-phase init coordinator), 22+ `CppBridge*` extension objects, OkHttp HTTP transport, Sentry logging, and all `actual` implementations for feature extension functions.
- **`androidMain`** (~19 files): Android-only `actual` implementations using Android APIs.
- **`jvmMain`** (~16 files): JVM desktop `actual` implementations using `java.io`, `javax.sound`, `java.util.prefs`.

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

Key files in this chain:
- `jvmAndroidMain/.../native/bridge/RunAnywhereBridge.kt` — all JNI `external fun` declarations
- `jvmAndroidMain/.../foundation/bridge/CppBridge.kt` — initialization orchestrator
- `jvmAndroidMain/.../foundation/bridge/extensions/CppBridge*.kt` — per-domain bridge wrappers (Auth, LLM, STT, TTS, VAD, VLM, Download, Device, Telemetry, etc.)
- `jvmAndroidMain/.../foundation/http/OkHttpTransport.kt` — HTTP transport registered into C++ vtable
- `jvmAndroidMain/.../public/PlatformBridge.kt` — `actual` for the three core `expect` functions from RunAnywhere.kt

### Public API Surface

The entry point is `RunAnywhere` (a Kotlin `object` singleton in `commonMain/public/RunAnywhere.kt`). All feature APIs are `expect` extension functions on `RunAnywhere`, organized one-per-file in `commonMain/public/extensions/`:

| File | Capability |
|------|-----------|
| `RunAnywhere+TextGeneration.kt` | `chat()`, `generate()`, `generateStream()`, `cancelGeneration()` |
| `RunAnywhere+STT.kt` | `transcribe()`, `transcribeStream()`, streaming audio processing |
| `RunAnywhere+TTS.kt` | `synthesize()`, `speak()`, `synthesizeStream()`, voice management |
| `RunAnywhere+VAD.kt` | `detectVoiceActivity()`, `streamVAD()`, VAD lifecycle & callbacks |
| `RunAnywhere+VisionLanguage.kt` | `describeImage()`, `processImage()`, `processImageStream()` |
| `RunAnywhere+VoiceAgent.kt` | Full voice pipeline: `initializeVoiceAgent()`, `streamVoiceAgent()` |
| `RunAnywhere+ModelManagement.kt` | `registerModel()`, `downloadModel()`, `loadLLMModel()`, model CRUD |
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

**Wire protobuf types are the canonical data model.** Generated bindings live in `commonMain/generated/ai/runanywhere/proto/v1/` (~190 files). The SDK uses these directly or via typealiases:

```kotlin
typealias SDKEnvironment = ai.runanywhere.proto.v1.SDKEnvironment
typealias AudioFormat = ai.runanywhere.proto.v1.AudioFormat
```

Proto extension files in `commonMain/foundation/protoext/` add Kotlin-idiomatic computed properties and validation to the generated types without modifying them.

Hand-rolled Kotlin types exist in `commonMain/public/extensions/` for public API ergonomics: `LLMTypes.kt`, `ToolCallingTypes.kt`, `ModelTypes.kt`, `VoiceAgentTypes.kt`, `VLMStreamingResult.kt`.

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
RunAnywhere.events.eventsOfType<ModelEvent>().collect { ... }
```

### Modules

Two optional backend modules in `modules/`:

- **`runanywhere-core-llamacpp`** — LLM backend. Single file (`LlamaCPP.kt`) calling `rac_backend_llamacpp_register()`. Bundles `librac_backend_llamacpp_jni.so`.
- **`runanywhere-core-onnx`** — STT/TTS/VAD backend. Single file (`ONNX.kt`) calling `rac_backend_onnx_register()`. Bundles sherpa-onnx and ONNX Runtime `.so` files.

Both follow the same pattern: thin KMP wrappers that register a C++ backend with the core's plugin system. They depend on the root SDK via `api()`.

### Streaming Adapters

`LLMStreamAdapter` and `VoiceAgentStreamAdapter` (`jvmAndroidMain/adapters/`) solve the single-callback-slot problem: C++ only supports one callback per handle, but Kotlin needs multiple concurrent `Flow` collectors. They use `SharedFlow` fan-out with `ConcurrentHashMap<(handle, bridge), FanOut>`.

## Key Conventions

- **iOS is the source of truth.** When implementing or fixing KMP features, check the corresponding iOS Swift SDK implementation first. Translate logic exactly; adapt only syntax.
- **All business logic in `commonMain`.** Platform source sets only contain `actual` implementations of `expect` declarations.
- **Platform file naming:** `AndroidTTSService.kt`, `JvmTTSService.kt` — always prefix with platform name.
- **Proto types over hand-rolled types.** Use Wire-generated types from `generated/` as the canonical representation. Add extension properties in `foundation/protoext/` for ergonomics.
- **Structured types, never raw strings.** Use enums, sealed classes, and data classes for all configuration and return values.
- **`expect`/`actual` for platform divergence only.** The `jvmAndroidMain` shared source set handles 90% of platform code; `androidMain` and `jvmMain` only differ where Android/JVM APIs genuinely diverge.

## Build System Details

**Gradle version:** 8.13 | **Kotlin:** 2.1.21 | **AGP:** 8.11.2 | **JVM target:** 17 | **Android minSdk:** 24 | **compileSdk:** 35

**Version catalog:** Shared at `../../gradle/libs.versions.toml` (monorepo-level, used by all SDKs).

**KMP hierarchy:** Manual (`kotlin.mpp.applyDefaultHierarchyTemplate=false`). The `jvmAndroidMain` intermediate source set is configured explicitly with `dependsOn(commonMain)`, and both `jvmMain`/`androidMain` depend on it.

**Wire codegen:** The Wire Gradle plugin is defined in the catalog but NOT applied (Kotlin DSL clash). Generated proto files are committed to git. Regenerate via `idl/codegen/generate_kotlin.sh`. A CI workflow (`idl-drift-check.yml`) enforces freshness.

**Maven group resolution:** Determined at configuration time from env vars — `com.github.RunanywhereAI.runanywhere-sdks` (JitPack), `com.runanywhere` (official), or `io.github.sanchitmonga22` (default).

**Code quality:** Detekt (`maxIssues: 0`, `warningsAsErrors: true`) and ktlint (v1.5.0, `max_line_length=250`) are enforced. Detekt config disables complexity/naming/comments rule sets but activates coroutine, empty-block, potential-bug, and unused-code rules.

## Testing

Tests live in `src/jvmTest/` (4 files). The `jvmTest` source set also mounts `../../tests/streaming/` as an additional srcDir, pulling in cross-SDK streaming parity tests, cancel parity tests, and performance benchmarks.

- `VoiceAgentStreamAdapterFanOutTest` — verifies SharedFlow fan-out for concurrent collectors
- `ChecksumPlumbingTest` — verifies SHA256 checksum fields propagate through model types (no JNI required)
- `PerfBenchTest` — conditional on `/tmp/perf_input.bin` existing; asserts p50 decode latency < 1ms
- `CancelParityTest` — conditional on `/tmp/cancel_input.bin` existing; verifies cancel interrupt markers

Most tests can run without JNI loaded (they test Kotlin-layer logic). Tests requiring the native library need `setupLocalDevelopment` to have been run first.

## CI/CD

- **`pr-build.yml`** — Triggered on PRs to `main` and pushes to `main`/`feat/v2-architecture`. Builds C++ from source, then runs `./gradlew assembleDebug`.
- **`release.yml`** — Triggered by `v*.*.*` tags. Matrix-builds native libs for 4 ABIs, stages into `jniLibs/`, runs `assembleRelease jvmJar`, uploads artifacts with SHA256 checksums.
- **`idl-drift-check.yml`** — Monitors `generated/` directory. Regenerates proto bindings and fails on any `git diff`.
- **`scripts/package-sdk.sh`** — CI packaging script. Accepts `--natives-from PATH` for pre-staged `.so` files, builds all targets, outputs to `dist/sdk-kotlin/` with checksums.
