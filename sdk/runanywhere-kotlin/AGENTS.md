# runanywhere-kotlin (Kotlin/Android SDK)

## Info

Global rules: see repo-root AGENTS.md (iOS is the source of truth — translate Swift logic exactly, adapt only syntax).

Single-target **Android library** (not KMP; no `commonMain`/`androidMain` source sets), minSdk 24, compileSdk 35, Kotlin 2.1.21, AGP 8.13.0, JVM toolchain 17. All AI inference runs in the C++ core (`librac_commons.so` + `librunanywhere_jni.so`); Kotlin provides the typed public API, JNI bridges, coroutines/Flow integration, and Wire proto types.

Layout:
- `src/main/kotlin/com/runanywhere/sdk/` — all sources. `public/RunAnywhere.kt` (`object` singleton entry point) + one-per-feature extension files under `public/extensions/` (LLM, STT, TTS, VAD, VLM, VoiceAgent, Models, RAG, ToolCalling, StructuredOutput, LoRA, Diffusion, Solutions, Storage, Auth, Hardware).
- JNI chain: `RunAnywhere` extensions → `foundation/bridge/extensions/CppBridge*.kt` (type conversion, error mapping) → `native/bridge/RunAnywhereBridge.kt` (`external fun` declarations) → `rac_*` C functions. HTTP: `foundation/http/OkHttpTransport.kt` registered into the C++ vtable.
- `src/main/jniLibs/` — prebuilt `.so` staged by `scripts/build/android.sh`. `src/test/kotlin/` — unit tests (no JNI required).
- `modules/runanywhere-core-llamacpp/` and `modules/runanywhere-core-onnx/` — thin Android-library sub-modules registering the C++ backends (`rac_backend_llamacpp_register()` / `rac_backend_onnx_register()`), bundling their per-backend JNI `.so`; depend on the root SDK via `api()`.

Patterns to preserve:
- **Two-phase init** mirroring Swift: `initialize(apiKey, environment)` (sync — `System.loadLibrary("runanywhere_jni")`, platform adapter, OkHttp transport, logging, telemetry/device callbacks; `synchronized(lock)`) then `completeServicesInitialization()` (suspend — auth, model assignments, System TTS callbacks, device registration; coroutine `Mutex`, auto-called by `ensureServicesReady()`).
- **Wire proto types are canonical** (`generated/ai/runanywhere/proto/v1/`, ~190 files, committed). Construct them directly with named arguments; typealiases like `typealias SDKEnvironment = ai.runanywhere.proto.v1.SDKEnvironment`. Do NOT re-introduce a `foundation/protoext/` wrapper package (removed for zero consumers). Hand-rolled ergonomic types live only under `public/extensions/` (`LLMTypes.kt`, `ModelTypes.kt`, …).
- **Errors**: `SDKException` wraps proto `SDKError`; `CommonsErrorMapping.kt` defines C ABI constants and `Int` extensions (`result.throwIfCAbiErrorAsException("llm.generate")`).
- **Events**: `EventBus` singleton `MutableSharedFlow<SDKEvent>(replay=0, extraBufferCapacity=64)`; Wire generates `SDKEvent` as a oneof envelope — payload messages are siblings, not subclasses (`RunAnywhere.events.modelEventPayloads`, `eventsOfPayload { it.generation }`).
- **Streaming fan-out**: `LLMStreamAdapter` / `VoiceAgentStreamAdapter` (`adapters/`) multiplex the single C callback slot to multiple `Flow` collectors via `SharedFlow` + `ConcurrentHashMap`.
- **VLM routes through core JNI, not llamacpp-JNI**: `librac_backend_llamacpp_jni.so` exposes only LLM primitives + registration shims; VLM callers use the commons `rac_vlm_component_*` proto APIs via `librunanywhere_jni.so` (same path iOS uses). Do not add VLM entry points to the llamacpp JNI.
- Platform-bound services keep the `Android` prefix (`AndroidTTSService.kt`). Structured types over raw strings everywhere. Public API additions only after the Swift facade has landed.

## Build Info

`./run` at repo root is the dev entry point; all scripts live under root `scripts/`.

```bash
cd sdk/runanywhere-kotlin/
./gradlew assembleDebug|assembleRelease   # AARs → build/outputs/aar/runanywhere-kotlin-{debug,release}.aar
./gradlew test                            # unit tests (testDebugUnitTest for debug only)
./gradlew detekt ktlintCheck lint         # quality gates (detekt maxIssues=0, warningsAsErrors)
./gradlew ktlintFormat
./gradlew publishToMavenLocal

# Native libs (JNI): controlled by gradle.properties runanywhere.useLocalNatives
#   true  → builds C++ from source via repo-root scripts/build/android.sh
#   false → downloads prebuilt .so from GitHub Releases (runanywhere.nativeLibVersion)
./gradlew setupLocalDevelopment           # first-time C++ build
./gradlew rebuildCommons                  # rebuild after C++ changes
./gradlew downloadJniLibs                 # prebuilt path

# Repo-root equivalents
./run sdk commons build-android           # scripts/build/android.sh — all ABIs, stages .so into consumers
./run sdk kotlin build|test|lint|publish
./scripts/release/package-kotlin.sh       # CI packaging
./scripts/codegen/generate_kotlin.sh      # regenerate Wire protos (or: ./run codegen kotlin)
```

Version catalog is shared at `../../gradle/libs.versions.toml`. NDK pin `racNdkVersion` in `gradle.properties` mirrors `sdk/runanywhere-commons/VERSIONS::NDK_VERSION`. The Wire Gradle plugin is NOT applied (Kotlin DSL clash) — generated protos are committed; `idl-drift-check.yml` CI enforces freshness. detekt disables complexity/naming/comments rule sets but enforces coroutine, empty-block, potential-bug, unused-code; ktlint `max_line_length=250`.

## Work Ground

- 2026-07-05: There is no shared cross-SDK streaming parity harness wired into this module — old references to `../../tests/streaming/` srcDir mounts and `PerfBenchTest`/`CancelParityTest` classes are stale. The only streaming-parity coverage is Flutter's self-contained `parity_test.dart`.
- 2026-07-05: Kotlin-layer unit tests run without JNI; tests needing native libs require `setupLocalDevelopment` first.
