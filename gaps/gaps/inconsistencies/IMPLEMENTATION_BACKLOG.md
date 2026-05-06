# Current Implementation Backlog

Date: 2026-05-05
Branch: feat/v2-architecture @ 6217d9e67
Total open rows: 76

## Execution rules

- DELETE, don't deprecate
- iOS Swift is cross-SDK naming source of truth
- All business logic in C++ commons
- One agent per row, one commit per row, never push
- Update gap doc + remove entry when resolved

## Priority waves (ordered by dependency)

### Wave 1: Commons + IDL (upstream for all SDKs) — 16 rows

| ID | Task | Files | Validation | Severity |
|----|------|-------|------------|----------|
| CPP-04 | Delete `rac_rag_pipeline.{h,cpp}` after refactoring `rac_rag_proto_abi.cpp` to construct `RAGBackend` directly and removing RN RAG bridge callers. | `sdk/runanywhere-commons/include/rac/features/rag/rac_rag_pipeline.h`, `sdk/runanywhere-commons/src/features/rag/rac_rag_pipeline.cpp`, `sdk/runanywhere-commons/src/features/rag/rac_rag_proto_abi.cpp:166,175,181,245,317,318,330,344,389` (new internal header `src/features/rag/rac_rag_pipeline_internal.h`) | `ctest -R rag`; `cd sdk/runanywhere-react-native && yarn typecheck`; `cmake --build build` | MED |
| CPP-05 | Migrate all 5 SDKs to consume server-populated proto `thinking`/`response`/`thinking_tokens`/`completion_tokens` fields; strip `RAC_API` from 3 thinking fns; drop exports lines. | `sdk/runanywhere-commons/include/rac/features/llm/rac_llm_thinking.h:58,71,90`; `sdk/runanywhere-commons/src/features/llm/rac_llm_proto_service.cpp:576,580` (verify stream path); `sdk/runanywhere-commons/exports/RACommons.exports:445,448,449`; `sdk/runanywhere-swift/Sources/RunAnywhere/Foundation/Bridge/Extensions/CppBridge+LLMThinking.swift`; `sdk/runanywhere-web/packages/core/src/Features/LLM/LlmThinking.ts`; Kotlin/Dart/RN equivalents | `swift test`; `./gradlew build`; RN/Web typecheck; `ctest -R llm_thinking` | MED |
| CPP-06 | Delete legacy non-proto JNI entries whose Kotlin callers are already migrated (audit `runanywhere_commons_jni.cpp` 7235 LOC / 254 `JNIEXPORT`s vs 76 Proto-suffixed). | `sdk/runanywhere-commons/src/jni/runanywhere_commons_jni.cpp`; `sdk/runanywhere-kotlin/src/jvmAndroidMain/kotlin/com/runanywhere/sdk/foundation/bridge/RunAnywhereBridge.kt` | `./gradlew :app:assembleDebug && ./gradlew test` (no `UnsatisfiedLinkError`) | MED |
| CPP-07 | Add smoke-test CHECK per Wave D proto entry point (8 APIs) in `test_proto_runtime_smoke.cpp`. | `sdk/runanywhere-commons/tests/test_proto_runtime_smoke.cpp:205-208` | `ctest -R proto_runtime_smoke` | LOW |
| CPP-08 | Update stale CMake comment "Wave D-1 audit restored ~301 SDK-called RAC_API symbols (150 -> 453)" to reflect current 465 exports. | `sdk/runanywhere-commons/CMakeLists.txt:804-805`; `sdk/runanywhere-commons/exports/RACommons.exports` (TODO header) | Docs-only | LOW |
| CPP-11 | Harden homebrew protobuf 34.x / abseil cold-configure. Pin via `FetchContent_Declare(... FIND_PACKAGE_ARGS NAMES absl protobuf REQUIRED OFF)` or document Docker-first recipe. | `sdk/runanywhere-commons/CMakeLists.txt:952-993`; optionally `sdk/runanywhere-commons/tests/Dockerfile.linux-tests` | `cmake --preset macos-debug` on fresh machine | LOW |
| CPP-12 | Roadmap tracker — backlog slot for future L1 runtimes (MLX / ExecuTorch / CUDA / Vulkan / QNN / NNAPI / WebGPU). Each new runtime follows `runtimes/onnxrt/rac_runtime_onnxrt.cpp` template (~600 LOC). Row exists so router rejection of unknown `runtime_ids` is explicit, not silent. | `runtimes/`; `sdk/runanywhere-commons/src/router/rac_engine_router.cpp` | No action until an engine declares a new runtime id | LOW (backlog only) |
| CPP-13 | Unblock WASM ONNX + Sherpa: vendor `libonnxruntime.a` + static sherpa archives, flip EMSCRIPTEN gates, register backends in Web WASM. | `engines/onnx/CMakeLists.txt:56-57`; `engines/sherpa/CMakeLists.txt:95-97`; `sdk/runanywhere-web/wasm/CMakeLists.txt`; new `sdk/runanywhere-commons/third_party/onnxruntime-wasm/`, `sdk/runanywhere-commons/third_party/sherpa-onnx-wasm/`; delete `sdk/runanywhere-web/packages/onnx/src/Foundation/SherpaONNXBridge.ts` + 12 MB standalone WASM (see `thoughts/shared/plans/wasm_onnx_unblock.md`) | `grep -oE 'rac_backend_[a-z_]+_register' racommons-llamacpp.js` shows all backends; Playwright STT/TTS/VAD round-trip | HIGH |
| CPP-14 | Add per-session backend handle to `rac_stt_stream_session` + `rac_stt_service_ops_t` so Sherpa recognizer state is allocated once per stream. | `sdk/runanywhere-commons/src/features/stt/rac_stt_stream.cpp:220,321`; `engines/sherpa/rac_stt_sherpa.cpp` | `ctest -R stt_vad_stream_events`; new 100-chunk test asserts single allocation | MED |
| CPP-15 | Add router test that sets `rac_hardware_set_accelerator_preference(GPU)` / `(CPU)` and asserts the winning engine changes between two engines with identical primitives but differing `runtime_ids`. | `sdk/runanywhere-commons/tests/test_engine_router.cpp`; `sdk/runanywhere-commons/router/rac_hardware_abi.h` | `ctest -R engine_router` | MED |
| IDL-05 | Delete `ModelCompatibilityResult` (8-field duplicate); rename `ModelCompatibilityCheckResult` to `ModelCompatibilityResult`; retarget `ModelRegistryEvent.compatibility_result`. | `idl/model_types.proto:482` (delete), `idl/model_types.proto:740` (rename), `idl/sdk_events.proto:825` (retarget) | `grep -c "ModelCompatibilityResult\|ModelCompatibilityCheckResult" idl/*.proto` shows exactly one type in use | MED |
| IDL-06 | Delete `enum LLMTokenKind`; import `voice_events.proto` into `llm_service.proto`; retype `LLMStreamEvent.kind` to canonical `TokenKind`. | `idl/llm_service.proto:141` (delete), `idl/llm_service.proto:103` (retype), add `import "voice_events.proto";` | `grep -c "LLMTokenKind" idl/*.proto` returns 0 | MED |
| IDL-09/10 | Add `option csharp_namespace = "Runanywhere.V1";` and `option go_package = "github.com/runanywhere/runanywhere-sdks/idl/v1;runanywherev1";` to 4 schemas. | `idl/llm_service.proto`, `idl/pipeline.proto`, `idl/router.proto`, `idl/solutions.proto` | `grep -L "option go_package" idl/*.proto` returns empty | LOW |
| IDL-19a | Add `component_types.proto` to Kotlin + TypeScript codegen scripts. | `idl/codegen/generate_kotlin.sh`, `idl/codegen/generate_ts.sh` | All scripts pass same proto file set (matches `ls idl/*.proto`) | MED |
| IDL-19b | Add `router.proto` to Swift + Dart + TypeScript codegen scripts. | `idl/codegen/generate_swift.sh`, `idl/codegen/generate_dart.sh`, `idl/codegen/generate_ts.sh` | Same as above | MED |
| IDL-19c | Introduce canonical shared proto-file-list shell variable in `generate_all.sh` used by all per-language scripts to prevent future drift. | `idl/codegen/generate_all.sh` + per-language scripts | `./idl/codegen/generate_all.sh` + `git diff --exit-code` is clean | MED |

### Wave 2: Engines + Runtimes (active backends only) — 24 rows (engines 11 + runtimes 13)

| ID | Task | Files | Validation | Severity |
|----|------|-------|------------|----------|
| ENG-LLAMA-03 | Add static-register shims for sherpa + onnx OR retire llamacpp's shim in favor of force-referenced symbols. | `engines/llamacpp/rac_static_register_llamacpp.cpp:28`; new `engines/sherpa/rac_static_register_sherpa.cpp`, `engines/onnx/rac_static_register_onnx.cpp` | iOS + WASM builds register all active backends; `nm` confirms symbols | MED |
| ENG-LLAMA-04 | Consolidate duplicate `DeviceType` enum from llamacpp + sherpa into shared internal header OR delete (one call site each: `llamacpp_backend.cpp:219`, `sherpa_backend.cpp:65`). | `engines/llamacpp/llamacpp_backend.h:28`; `engines/sherpa/sherpa_backend.h:62`; `engines/llamacpp/llamacpp_backend.cpp:219-227`; `engines/sherpa/sherpa_backend.cpp:65-66` | `cmake --build build`; `grep -rn "enum class DeviceType" engines/` returns 0 or single location | MED |
| ENG-SHERPA-03 | Standardize registration: either add ELF-constructor shim to onnx + llamacpp, or promote `rac_registry_load_plugin` as the only mechanism and delete sherpa's constructor. | `engines/sherpa/rac_plugin_entry_sherpa.cpp:168`; `engines/llamacpp/rac_plugin_entry_llamacpp.cpp`; `engines/onnx/rac_plugin_entry_onnx.cpp` | Boot trace shows all backends register via same mechanism | MED |
| ENG-ONNX-02 | Pull `onnx_embedding_provider.cpp` into `engines/onnx/` OR move plugin-entry/ops struct back into commons. | `engines/onnx/rac_plugin_entry_onnx.cpp:25,80`; `engines/onnx/CMakeLists.txt:124-133`; `sdk/runanywhere-commons/src/features/rag/rac_onnx_embeddings_register.cpp` | `cmake --build build`; ONNX engine owns its embeddings TU | MED |
| ENG-ONNX-05 | Audit / delete `rac_storage_strategy_register(RAC_FRAMEWORK_ONNX, ...)` + `rac_download_strategy_register(RAC_FRAMEWORK_ONNX, ...)` if no commons consumer. | `engines/onnx/rac_backend_onnx_register.cpp:165-166,195` | `ctest`; grep confirms no commons consumer of `RAC_FRAMEWORK_ONNX` storage/download | LOW |
| DELETE-LLAMA-load_model | Delete `rac_llm_llamacpp_load_model` no-op and its declaration in the public header. | `engines/llamacpp/rac_llm_llamacpp.cpp:120-128`; corresponding public header decl | `cmake --build build`; symbol absent from nm of plugin archive | LOW |
| DUP-01 | Extract `convert_int16_to_float32` into shared commons helper `rac_audio_pcm16_to_float32()` so Iteration-I STT backends inherit one copy. | `engines/sherpa/rac_backend_sherpa_register.cpp:40-50`; new `sdk/runanywhere-commons/include/rac/audio/rac_audio_convert.h` + `.cpp` | Sherpa tests pass; helper is in commons | LOW |
| DUP-03 | Factor the 7-line `<primitive>_create_impl` scaffold into `RAC_DEFINE_CREATE_ADAPTER(primitive, name)` macro. | `sdk/runanywhere-commons/include/rac/plugin/rac_plugin_entry.h` (new macro); `engines/sherpa/rac_backend_sherpa_register.cpp:141-153`; `engines/llamacpp/rac_backend_llamacpp_register.cpp:290-336` | `cmake --build build`; LOC net-negative in both engines | LOW |
| DUP-05 | Factor llamacpp's duplicated `StreamAdapter` + `VLMStreamAdapter` into shared `rac/plugin/rac_stream_adapter.h`. | `engines/llamacpp/rac_backend_llamacpp_register.cpp:160-172`; `engines/llamacpp/rac_backend_llamacpp_vlm_register.cpp:46-58`; new shared header | `cmake --build build`; LOC net-negative | LOW |
| DUP-06 | Lift `rac_event_track("*.backend.created", ...)` into commons service-layer emit so future backends inherit it. | `engines/llamacpp/rac_llm_llamacpp.cpp:114`; `engines/sherpa/rac_stt_sherpa.cpp:97`, `rac_tts_sherpa.cpp:74`, `rac_vad_sherpa.cpp:78`; `sdk/runanywhere-commons/src/features/*/` service-layer | `ctest` + event capture shows commons-side emission | LOW |
| DUP-07 | Move Android 16K page-alignment link options into `cmake/plugins.cmake` helper. | `engines/llamacpp/CMakeLists.txt:281-282,309-310,374-375`; `engines/sherpa/CMakeLists.txt:358-361`; `engines/onnx/CMakeLists.txt:209-210,281-282`; new `cmake/plugins.cmake` | Android ABI builds produce correctly aligned `.so` | LOW |
| RT-CPU-01 | Un-gate CPU supported-primitives list beyond `GENERATE_TEXT` so STT/TTS/VAD/EMBED/RERANK provider registrations succeed; keep dynamic `primitive_is_supported` consistent. | `runtimes/cpu/rac_runtime_cpu.cpp:62-69,98-103,209-211` | `ctest`; providers for all primitives register successfully | MED |
| RT-CPU-02 | Implement real V2 `run_session_v2` path so owned-output + buffer-backed tensors don't flatten to V1. | `runtimes/cpu/rac_runtime_cpu.cpp:198-206,265-329`; `rac_cpu_runtime_provider_t` ABI | `ctest`; owned-output round-trip test passes | MED |
| RT-CPU-03 | Promote `rac_cpu_runtime_provider_t` provider registry into shared runtime vtable so onnxrt can use the same escape hatch (thermal hints, memory-pressure, accelerator profile). | `runtimes/cpu/rac_runtime_cpu.cpp:564-615`; `sdk/runanywhere-commons/include/rac/runtime/rac_runtime_vtable.h`; `runtimes/onnxrt/rac_runtime_onnxrt.cpp` | `ctest`; both runtimes accept provider registration via shared API | MED |
| RT-ONNX-01 | Implement onnxrt `run_session_v2` so V2 callers don't NULL-deref; fill tensor/buffer ownership semantics. | `runtimes/onnxrt/rac_runtime_onnxrt.cpp:527` | `ctest`; V2 test exercises onnxrt path | MED |
| RT-ONNX-02 | Fix onnxrt output marshaling to honor output tensor dtype (i64 / f16 / u8 / bf16) instead of force-casting to float32. | `runtimes/onnxrt/rac_runtime_onnxrt.cpp:267-277`; `runtimes/onnxrt/rac_runtime_onnxrt.h:16-19` | `ctest`; i64 output model produces correct bytes | MED |
| RT-ONNX-03 | Signal "buffer too small" to caller when output capacity is insufficient (distinct error vs zero-byte legitimate output); don't silently drop. | `runtimes/onnxrt/rac_runtime_onnxrt.cpp:375-381` | `ctest`; capacity-undersize test returns discrete error code | MED |
| RT-ONNX-04 | Expose EP selection (CoreML / CUDA / DirectML / NNAPI / QNN) via `SessionOptions` + manifest so router can pick onnxrt for non-CPU device classes. | `runtimes/onnxrt/rac_runtime_onnxrt.cpp:82,501`; `runtimes/onnxrt/rac_runtime_onnxrt.h:35-39`; `Session::create` | `ctest`; manifest device-class list extends beyond CPU | MED |
| RT-ONNX-05 | Remove STT/TTS/VAD from onnxrt's `k_supported_primitives` unless backed by wired providers; document onnxrt as "generic tensor runner" otherwise. | `runtimes/onnxrt/rac_runtime_onnxrt.cpp:87-92` | `ctest`; router doesn't pick onnxrt for TRANSCRIBE without engine-side front-end | MED |
| RT-ONNX-06 | Add `rac_onnxrt_runtime_register_provider` (symmetric to CPU). | `runtimes/onnxrt/rac_runtime_onnxrt.cpp`; `runtimes/onnxrt/rac_runtime_onnxrt.h:67` | `ctest`; ONNX engine registers EMBED provider via symmetric API | MED |
| RT-ONNX-07 | Replace `SharedOrt::mutex` around `CreateSession` with per-model locking so concurrent model loads don't serialize. | `runtimes/onnxrt/rac_runtime_onnxrt.cpp:21-54,150-158` | `ctest`; concurrent-load test measures parallel timing | LOW |
| DUP-RT-01 | Replace inlined `release_tensor` in CPU + ONNXRT with `rac::runtime::rac_runtime_release_tensor(tensor, free_buffer)`. | `runtimes/cpu/rac_runtime_cpu.cpp:473-497`; `runtimes/onnxrt/rac_runtime_onnxrt.cpp:483-495`; `sdk/runanywhere-commons/include/rac/runtime/rac_runtime_helpers.h` | `cmake --build build`; LOC net-negative | LOW |
| DUP-RT-02 | Replace inlined `copy_buffer` range-check+memmove in both runtimes with `rac::runtime::rac_runtime_copy_buffer(...)`. | `runtimes/cpu/rac_runtime_cpu.cpp:450-471`; `runtimes/onnxrt/rac_runtime_onnxrt.cpp:465-481`; helper header | Same as above | LOW |
| DUP-RT-03 | Either delete `onnxrt_alloc_buffer` shim (route callers through CPU runtime) OR have onnxrt buffer slot forward to CPU allocator. | `runtimes/onnxrt/rac_runtime_onnxrt.cpp:389-408` | `ctest`; alloc path consolidated | LOW |

### Wave 3: SDK dead-code sweeps + correctness — 40 rows

#### Kotlin (9 rows)

| ID | Task | Files | Validation | Severity |
|----|------|-------|------------|----------|
| KOT-05 | Migrate VLM `loadResolvedArtifacts` off legacy `racVlmCreate`/`racVlmInitialize`/`racVlmDestroy` trio to proto-backed `rac_vlm_component_load_resolved_artifacts_proto`. | `sdk/runanywhere-kotlin/src/jvmAndroidMain/kotlin/com/runanywhere/sdk/foundation/bridge/extensions/CppBridgeModalityProto.kt:478-498`; `sdk/runanywhere-kotlin/src/jvmAndroidMain/kotlin/com/runanywhere/sdk/foundation/bridge/RunAnywhereBridge.kt:299,302,323`; commons: new proto message + API | `./gradlew build`; `ctest` | MED |
| KOT-14 | Replace stub `currentDiffusionFramework(): InferenceFramework?` returning null + empty-stub `CppBridgeDiffusionProto.capabilities()` with real proto bridge calls. | `sdk/runanywhere-kotlin/src/jvmAndroidMain/kotlin/com/runanywhere/sdk/public/extensions/RunAnywhere+Diffusion.jvmAndroid.kt:104-107`; `sdk/runanywhere-kotlin/src/jvmAndroidMain/kotlin/com/runanywhere/sdk/foundation/bridge/extensions/CppBridgeModalityProto.kt`; commons: `rac_diffusion_current_framework_proto` | `./gradlew build`; proto capabilities populated | LOW |
| KOT-HARDWARE-FALLBACK | Delete Android-side `Runtime.exec("getprop ro.board.platform")` chip-name heuristic; force all hardware-profile population through commons `rac_hardware_profile_get`. | `sdk/runanywhere-kotlin/src/jvmAndroidMain/kotlin/com/runanywhere/sdk/public/extensions/RunAnywhere+Hardware.jvmAndroid.kt:42-76` | `./gradlew build`; Android device reports chip via commons only | LOW |
| KOT-DEAD-AUDIOCAPTURE | Delete `AudioCaptureManager` + `AudioChunk` + `AudioCaptureError` + `createAudioCaptureManager()` and both platform actuals; delete `PlatformTime` expect/actuals (only consumer was dead audio-capture). | `sdk/runanywhere-kotlin/src/commonMain/kotlin/com/runanywhere/sdk/features/stt/services/AudioCaptureManager.kt`; `sdk/runanywhere-kotlin/src/androidMain/kotlin/com/runanywhere/sdk/features/stt/AndroidAudioCaptureManager.kt`; `sdk/runanywhere-kotlin/src/jvmMain/kotlin/com/runanywhere/sdk/features/stt/JvmAudioCaptureManager.kt`; `sdk/runanywhere-kotlin/src/commonMain/kotlin/com/runanywhere/sdk/foundation/PlatformTime.kt` + android/jvm actuals | `./gradlew build`; 6 files deleted | LOW |
| KOT-DEAD-SDKCONSTANTS | Delete `Environment`, `API`, `Defaults`, `Storage`, `SecureStorage`, `ErrorCodes` subobjects and `platform`/`version` accessors; keep only `VERSION`, `SDK_VERSION`, `SDK_NAME`, `USER_AGENT`. Wire canonical `VERSION = "0.19.13"` via `sync-versions.sh` or Gradle resource. | `sdk/runanywhere-kotlin/src/commonMain/kotlin/com/runanywhere/sdk/utils/SDKConstants.kt`; `sdk/runanywhere-commons/VERSION` sync | `./gradlew build`; `SDKConstants.VERSION` matches canonical VERSION | LOW |
| KOT-DEAD-BUILDCONFIG | Delete unused `BuildConfig` expect + Android/JVM actuals and `SharedBuildConfig` (zero callers). | 4 files: `sdk/runanywhere-kotlin/src/commonMain/kotlin/com/runanywhere/sdk/utils/BuildConfig.kt` + `androidMain`/`jvmMain` actuals; `sdk/runanywhere-kotlin/src/jvmAndroidMain/kotlin/com/runanywhere/sdk/utils/SharedBuildConfig.kt` | `./gradlew build`; ~30 LOC gone | LOW |
| KOT-DEAD-PLATFORMUTILS | Delete `PlatformUtils` expect + Android/JVM actuals (only consumer was dead `SDKConstants.platform`). | 3 files: `sdk/runanywhere-kotlin/src/commonMain/kotlin/com/runanywhere/sdk/utils/PlatformUtils.kt` + `androidMain`/`jvmMain` actuals | `./gradlew build`; ~220 LOC gone | LOW |
| KOT-DEAD-SIMPLEINSTANT | Replace `SimpleInstant` with `Long` (millis) in `LogEntry.timestamp` and delete `SimpleInstant.kt`. | `sdk/runanywhere-kotlin/src/commonMain/kotlin/com/runanywhere/sdk/utils/SimpleInstant.kt`; `sdk/runanywhere-kotlin/src/commonMain/kotlin/com/runanywhere/sdk/utils/SDKLogger.kt:28` | `./gradlew build`; 23 LOC gone | LOW |
| KOT-DEAD-CRYPTOUTILS | Delete unused `calculateSHA256` (zero callers; legacy auth-token signing gone). | `sdk/runanywhere-kotlin/src/jvmAndroidMain/kotlin/com/runanywhere/sdk/utils/CryptoUtils.kt` | `./gradlew build`; 12 LOC gone | LOW |

#### Swift (9 rows)

| ID | Task | Files | Validation | Severity |
|----|------|-------|------------|----------|
| SWF-SENDABLE-01 | Add `Foundation/Bridge/CSendability.swift` with `@retroactive @unchecked Sendable` conformances for `OpaquePointer`/`UnsafeMutableRawPointer`; fix 28 Swift 6 sendability warning sites (AudioCaptureManager `@preconcurrency`, SystemTTSService MainActor, LLMStreamAdapter didInstall mutation, unused variables). | `sdk/runanywhere-swift/Sources/RunAnywhere/Foundation/Bridge/CSendability.swift` (new); `sdk/runanywhere-swift/Sources/RunAnywhere/Foundation/Bridge/Extensions/CppBridge+Telemetry.swift:75,81,99,117,134,140`; `.../Adapters/LLMStreamAdapter.swift:70,112,163,189`; `.../Adapters/VoiceAgentStreamAdapter.swift:95,134,160`; `.../Foundation/Bridge/Extensions/CppBridge+Download.swift:182`; `.../CppBridge+SDKEvents.swift:77`; `.../Public/Extensions/RunAnywhere+Solutions.swift:35,39,91`; `.../RunAnywhere+VisionLanguage.swift:17`; `.../Platform/Audio/AudioCaptureManager.swift:9,163,166,177,507`; `.../Platform/TTS/SystemTTSService.swift:93`; `.../Features/FoundationModels/SystemFoundationModelsService.swift:64`; `.../Features/Diffusion/DiffusionPlatformService.swift:234`; `.../Adapters/URLSessionHttpTransport.swift:308` | `swift build` unique warning sites < 5; `swiftlint` still 0 errors | MED |
| SWF-CROSS-01 | Add public `RunAnywhere.initializeVoiceAgentWithLoadedModels()` + `RunAnywhere.getVoiceAgentComponentStates()` static APIs (cross-SDK parity; Kotlin/Web already expose). | `sdk/runanywhere-swift/Sources/RunAnywhere/Public/Extensions/VoiceAgent/RunAnywhere+VoiceAgent.swift` | `grep "static func initializeVoiceAgentWithLoadedModels\|static func getVoiceAgentComponentStates" sdk/runanywhere-swift/Sources` returns 2 hits | LOW |
| SWF-CROSS-02 | Add public `RunAnywhere.clearCache()` / `RunAnywhere.cleanTempFiles()` static APIs forwarding to `CppBridge.FileManager`; downgrade `SimplifiedFileManager` to `internal`; migrate iOS example call sites. | `sdk/runanywhere-swift/Sources/RunAnywhere/Public/Extensions/Storage/RunAnywhere+Storage.swift`; `sdk/runanywhere-swift/Sources/RunAnywhere/Infrastructure/FileManagement/Services/SimplifiedFileManager.swift:127-141`; `examples/ios/RunAnywhereAI/RunAnywhereAI/ViewModels/SettingsViewModel.swift:428,439`; `examples/ios/RunAnywhereAI/RunAnywhereAI/ViewModels/StorageViewModel.swift:64,74` | `grep "SimplifiedFileManager\." examples/ios/RunAnywhereAI` returns 0; iOS example builds | LOW |
| SWF-CROSS-03 | Either promote `RunAnywhere.registerModel(id:name:url:framework:...)` into canonical SDK API (composes `RAModelImportRequest`), or add it to example-local shim file and clarify docs. | `sdk/runanywhere-swift/Sources/RunAnywhere/Public/Extensions/Storage/RunAnywhere+Storage.swift` OR `examples/ios/RunAnywhereAI/RunAnywhereAI/Extensions/RunAnywhere+ExampleShims.swift` | Cross-SDK naming parity row in `gaps/gaps/inconsistencies/swift.md` satisfied | LOW |
| SWF-DOC-01 | Trim "App-Local Convenience Shims" section of example CLAUDE.md down to just `getRegisteredFrameworks()` (only real remaining shim). | `examples/ios/RunAnywhereAI/CLAUDE.md:341-386` | `grep -c "loadSTTModel\|detectSpeech\|getCurrentModelId" examples/ios/RunAnywhereAI/CLAUDE.md` returns 0 | LOW |
| SWF-DELETE-01 | Delete dead `var lastProgress` (written, never read). | `sdk/runanywhere-swift/Sources/RunAnywhere/Features/Diffusion/DiffusionPlatformService.swift:234` | `swift build` | LOW |
| SWF-DELETE-02 | Rename internal `HTTPService.shared`/`await HTTPService.shared.configure(...)` to `HTTPClientAdapter.shared`; delete legacy `public typealias HTTPService = HTTPClientAdapter`. | `sdk/runanywhere-swift/Sources/RunAnywhere/Adapters/HTTPClientAdapter.swift:477-482`; `sdk/runanywhere-swift/Sources/RunAnywhere/Foundation/Bridge/Extensions/CppBridge+HTTP.swift:21-45` | `swift build`; `grep -rn "HTTPService" sdk/runanywhere-swift/Sources` returns 0 | LOW |
| SWF-DELETE-03 | Audit `CppBridge+Device.swift:74` "Legacy fields" comment: either scrub fields from `rac_telemetry_types.h:199` + Swift callback if unread by backend, or drop the comment if still read. | `sdk/runanywhere-swift/Sources/RunAnywhere/Foundation/Bridge/Extensions/CppBridge+Device.swift:74`; `sdk/runanywhere-commons/include/rac/telemetry/rac_telemetry_types.h:199` | `swift build`; comment or fields consistent with current use | LOW |
| SWF-DELETE-04 | Delete historical doc-comment "Replaces the legacy `SDKError` struct..." from `SDKException.swift`. | `sdk/runanywhere-swift/Sources/RunAnywhere/Foundation/Errors/SDKException.swift:9` | `swift build`; `grep "Replaces the legacy" sdk/runanywhere-swift/Sources/RunAnywhere/Foundation/Errors/SDKException.swift` returns 0 | LOW |

#### Flutter (7 rows)

| ID | Task | Files | Validation | Severity |
|----|------|-------|------------|----------|
| FLT-05 | Pick one `RacBindings`: either finish ffigen migration by porting `dart_bridge_*.dart` consumers and deleting hand-written class, OR delete generated file + `ffigen` devDep + `ffigen.yaml` until team is ready. | `sdk/runanywhere-flutter/packages/runanywhere/lib/core/native/rac_native.dart:1117` (hand-written); `sdk/runanywhere-flutter/packages/runanywhere/lib/native/generated/rac_bindings.dart:12` (ffigen); `sdk/runanywhere-flutter/packages/runanywhere/pubspec.yaml:66`; `sdk/runanywhere-flutter/packages/runanywhere/ffigen.yaml` | `flutter analyze`; `grep -rn "class RacBindings" sdk/runanywhere-flutter` returns 1 hit | MED |
| FLT-07 | Align backend version metadata — all podspecs, gradle files, and 6 hard-coded `'0.1.4'` / `'0.15.8'` / `'0.16.0'` sites bumped to canonical `0.19.13` (or read dynamically). | `sdk/runanywhere-flutter/packages/runanywhere_genie/ios/runanywhere_genie.podspec:12`; `.../runanywhere_llamacpp/ios/runanywhere_llamacpp.podspec:13`; `.../runanywhere_onnx/ios/runanywhere_onnx.podspec:17`; `.../runanywhere_genie/android/build.gradle:16`; `.../runanywhere_llamacpp/android/build.gradle:14`; `.../runanywhere_onnx/android/build.gradle:14`; `.../runanywhere_llamacpp/ios/Classes/LlamaCppPlugin.swift:24`; `.../runanywhere_llamacpp/android/src/main/kotlin/.../LlamaCppPlugin.kt:21`; `.../runanywhere_onnx/ios/Classes/OnnxPlugin.swift:24`; `.../runanywhere_onnx/android/src/main/kotlin/.../OnnxPlugin.kt:21`; `.../runanywhere/ios/Classes/RunAnywherePlugin.swift:38`; `.../runanywhere/android/src/main/kotlin/.../RunAnywherePlugin.kt:25`; `.../runanywhere/lib/native/dart_bridge_device.dart:558`; `.../runanywhere/lib/native/dart_bridge_telemetry.dart:123` | `grep -rn "0\.1\.4\|0\.15\.8\|0\.16\.0" sdk/runanywhere-flutter/packages` returns 0; `./scripts/sync-versions.sh 0.19.13` clean | LOW |
| FLT-08 | Delete unreferenced `DeviceInfo` model + `DeviceIdentity` service (self-referential dead pair — 254 LOC). | `sdk/runanywhere-flutter/packages/runanywhere/lib/infrastructure/device/models/device_info.dart:11-200`; `sdk/runanywhere-flutter/packages/runanywhere/lib/infrastructure/device/services/device_identity.dart:11-54` | `flutter analyze`; `grep -rn "DeviceInfo\|DeviceIdentity" sdk/runanywhere-flutter/packages` only returns the empty/deleted refs | LOW |
| FLT-10 | Delete adapter-layer wrappers `protoModelFormatFromPath` + `withInferredArtifact`; migrate callers directly to `DartBridgeModelFormat.shared.formatFromUrl` / `.applyInferredArtifact`. | `sdk/runanywhere-flutter/packages/runanywhere/lib/native/type_conversions/model_types_cpp_bridge.dart:416-456` | `flutter analyze`; ~40 LOC gone | LOW |
| FLT-11 | Delete `_extractFirstJson` / `_findClosing` / `_isValidJson` + `extractStructuredOutput` (~70 LOC); wire to commons `rac_structured_output_extract_proto` (needs commons-side addition). | `sdk/runanywhere-flutter/packages/runanywhere/lib/public/extensions/runanywhere_thinking_utils.dart:117-158`; `sdk/runanywhere-commons/include/rac/features/llm/rac_llm_structured_output.h` (add `extract_proto`) | `flutter analyze`; `ctest -R structured_output` | LOW |
| FLT-12 | Replace `SDKException.featureNotAvailable` stubs with real proto calls once commons lands `rac_tts_synthesize_stream_lifecycle_proto`, `rac_tts_stop_lifecycle_proto`, `rac_vad_configure_lifecycle_proto`, `rac_vad_start_lifecycle_proto`, `rac_vad_stop_lifecycle_proto`, `rac_vad_reset_lifecycle_proto`. (Cross-cut with commons backlog — diffusion portion of original FLT-12 deferred.) | `sdk/runanywhere-flutter/packages/runanywhere/lib/public/capabilities/runanywhere_tts.dart:162-187`; `sdk/runanywhere-flutter/packages/runanywhere/lib/public/capabilities/runanywhere_vad.dart:48-130`; commons new ABIs | `flutter analyze`; no `featureNotAvailable` in TTS/VAD capabilities | MED |
| FLT-13 | Clean stale `.cxx/Debug/**/flutter_rag_bridge.dir/` CMake API cache (source long removed). | `sdk/runanywhere-flutter/packages/runanywhere/android/.cxx/Debug/**/flutter_rag_bridge.dir/` | `flutter clean` + rebuild leaves no stale target ref | LOW |

#### React Native (9 rows)

| ID | Task | Files | Validation | Severity |
|----|------|-------|------------|----------|
| RN-01 | Decide: either recreate `tests/streaming/*.rn.test.ts` parity harness consuming C++ golden fixtures, OR delete `test` script + `jest`/`ts-jest`/`@types/jest` devDeps from `packages/core/package.json` (today Jest is on disk with no config). | `sdk/runanywhere-react-native/packages/core/package.json:35,75,77,80`; `sdk/runanywhere-react-native/CLAUDE.md:77` (phantom harness reference) | `yarn typecheck`; either harness runs or no ghost deps | MED |
| RN-02 | Delete duplicate backend podspecs with stale `CORE_VERSION = "0.1.4"` + dead GitHub org path. | `sdk/runanywhere-react-native/packages/llamacpp/ios/LlamaCPPBackend.podspec`; `sdk/runanywhere-react-native/packages/onnx/ios/ONNXBackend.podspec` | `yarn typecheck`; `pod install` in RN example uses canonical podspecs only | LOW |
| RN-03 | Delete `checkCompatibility(modelId)` from Nitro spec + generated C++ impl; regenerate nitrogen. If cross-SDK compat needed, add `modelCompatibilityProto(request: ArrayBuffer)` instead. | `sdk/runanywhere-react-native/packages/core/src/specs/RunAnywhereCore.nitro.ts:171`; `sdk/runanywhere-react-native/packages/core/nitrogen/generated/shared/c++/HybridRunAnywhereCoreSpec.hpp`; nitrogen regen | `yarn typecheck`; `grep "checkCompatibility" sdk/runanywhere-react-native/packages/core/src` returns 0 | LOW |
| RN-04 | Delete `authenticate(apiKey)` from Nitro spec + generated C++ impl; regenerate nitrogen. Canonical auth is `authAuthenticate`. | `sdk/runanywhere-react-native/packages/core/src/specs/RunAnywhereCore.nitro.ts:75`; `sdk/runanywhere-react-native/packages/core/nitrogen/generated/shared/c++/HybridRunAnywhereCoreSpec.hpp`; nitrogen regen | `yarn typecheck`; `grep "authenticate" sdk/runanywhere-react-native/packages/core/src/specs` returns canonical `authAuthenticate` only | LOW |
| RN-06 | Either add proto messages (`SDKInitConfig`, `DeviceRegisterRequest`, `AuthResponse`, `BackendInfo`, `DeviceCapabilities`) and convert the 7 JSON-string surfaces to proto, OR document the JSON subset as a canonical exception in `docs/CPP_PROTO_OWNERSHIP.md`. | `sdk/runanywhere-react-native/packages/core/src/specs/RunAnywhereCore.nitro.ts:48,63,104,378,397,412,434`; `idl/*.proto` (new messages) OR `docs/CPP_PROTO_OWNERSHIP.md` | All Nitro spec wire types are proto, OR explicit documented exception covers all 7 | MED |
| RN-07 | Wire `rac_hardware_set_accelerator_preference` through Nitro spec; delete JS `_acceleratorPreference` in-memory cache; rename `setAccelerationPreference` to `setAcceleratorPreference` for Swift parity. | `sdk/runanywhere-react-native/packages/core/src/Public/Extensions/RunAnywhere+Hardware.ts:43-44,197-227`; `sdk/runanywhere-react-native/packages/core/src/specs/RunAnywhereCore.nitro.ts:283`; commons `rac_hardware_set_accelerator_preference` proto bridge | `yarn typecheck`; name matches Swift `setAcceleratorPreference` | LOW |
| RN-08 | Add `RunAnywhere.hardware.getNPUChip(): Promise<NPUChip>` (Swift parity: `NPUChipDetector`). Backed by commons resolver via Nitro, or JS string-to-enum parser. | `sdk/runanywhere-react-native/packages/core/src/Public/Extensions/RunAnywhere+Hardware.ts`; `sdk/runanywhere-react-native/packages/core/src/types/index.ts:160` | `yarn typecheck`; hardware-aware backends consume structured enum instead of free-form label | MED |
| RN-12 | Add "Hermes streaming" subsection to top-level README + `packages/core/README.md` documenting manual `iterator.next()` consumer pattern; replace misleading `for await` example in Quick Start. | `sdk/runanywhere-react-native/README.md:218`; `sdk/runanywhere-react-native/packages/core/README.md` | Both READMEs mention Hermes caveat; Quick Start uses manual iteration | LOW |
| RN-15 | Rewrite EventBus section of `packages/core/README.md` to describe the proto-byte pipe via `RunAnywhere.subscribeSDKEvents(...)`; delete `EventBus.on` snippets + `RunAnywhere.events.*` + "Event Categories" table (all deleted post-H-4). | `sdk/runanywhere-react-native/packages/core/README.md:321-351`; `sdk/runanywhere-react-native/packages/core/src/Internal/Events/EventBus.ts` (current surface reference) | Readme matches current publish-only facade | LOW |

#### Web (6 rows)

| ID | Task | Files | Validation | Severity |
|----|------|-------|------------|----------|
| WEB-01 | Flip WASM ONNX + Sherpa engine gates; vendor `libonnxruntime.a` + static sherpa archives; wire backend register exports from WASM module (see `thoughts/shared/plans/wasm_onnx_unblock.md`, ~5-6 engineer-days). Shares work with CPP-13. | `engines/onnx/CMakeLists.txt:55-57`; `engines/sherpa/CMakeLists.txt:94-98`; `sdk/runanywhere-web/wasm/CMakeLists.txt:182-184`; new `third_party/onnxruntime-wasm/`, `third_party/sherpa-onnx-wasm/` | `grep _rac_backend_onnx_register sdk/runanywhere-web/packages/llamacpp/wasm/racommons-llamacpp.js` shows matches; Playwright STT/TTS/VAD round-trip | P0 |
| WEB-03 | Delete legacy standalone sherpa-onnx WASM assets (12 MB + ~165 KB helpers) + Emscripten `a.out` remnants. BLOCKED BY WEB-01. | `sdk/runanywhere-web/packages/onnx/wasm/sherpa/sherpa-onnx.wasm`, `sherpa-onnx-asr.js`, `-tts.js`, `-vad.js`, `-wave.js`, `-glue.js`; `sdk/runanywhere-web/wasm/a.out.{js,wasm}`; `examples/web/RunAnywhereAI/vite.config.ts:36` (copy entry); `sdk/runanywhere-web/wasm/scripts/build.sh:144,215` (also clean `wasm/` dir) | `ls sdk/runanywhere-web/packages/onnx/wasm/sherpa/` returns empty; `ls sdk/runanywhere-web/wasm/a.out.*` returns empty | LOW (blocked on WEB-01) |
| WEB-06 | Replace `BackendNotAvailable` return from `RunAnywhere.stt.*` / `tts.*` / `vad.*` after WEB-01 lands (commons + backend register symbols then available). BLOCKED BY WEB-01. | `sdk/runanywhere-web/packages/core/src/Public/Extensions/RunAnywhere+STT.ts`, `RunAnywhere+TTS.ts`, `RunAnywhere+VAD.ts` | STT/TTS/VAD round-trip test passes | P0 (blocked on WEB-01) |
| WEB-07 | Install voice-agent + RAG providers / session handles after WEB-01 lands (`setVoiceAgentProvider`, `setVoiceAgentHandle`, `setRAGProvider`, `setRAGSessionHandle`). BLOCKED BY WEB-01. | `sdk/runanywhere-web/packages/core/src/Public/Extensions/RunAnywhere+VoiceAgent.ts`; `RunAnywhere+RAG.ts`; `packages/onnx/src/` backend registration | Voice agent view real (not placeholder); RAG test round-trip | MED (blocked on WEB-01) |
| WEB-08 | Re-land example app views: `views/vision.ts` (independent of WEB-01, wire against existing `VLMWorkerBridge`); `views/voice.ts` / `transcribe.ts` / `speak.ts` (blocked on WEB-01). | `examples/web/RunAnywhereAI/src/views/vision.ts`, `voice.ts`, `transcribe.ts`, `speak.ts`; `sdk/runanywhere-web/packages/llamacpp/src/Infrastructure/VLMWorkerBridge.ts`; `examples/web/RunAnywhereAI/src/services/model-catalog.ts:100-112` | Vision view real with SmolVLM flow; other 3 real after WEB-01 | MED (vision independent; rest blocked on WEB-01) |
| WEB-09 | Add CI workflow + E2E test that downloads SmolLM2-360M + runs `generateStream` (LLM-only E2E lands independent of WEB-01). | New `.github/workflows/web-e2e.yml`; `sdk/runanywhere-web/tests/browser/` new LLM spec | CI green on LLM E2E; SmolLM2-360M stream produces tokens | LOW |

### Wave 4: Example apps — 0 rows

All example-app-specific issues were merged into Wave 3 SDK rows (SWF-CROSS-02 migrates iOS example call sites; SWF-DOC-01 trims iOS example CLAUDE.md; RN-12 rewrites RN README; WEB-08 re-lands Web example views; FLT-07 covers Flutter plugin apps).

### Wave 5: CI / build gates — infrastructure rows (outside the 80 feature-gap count)

| Task | Files | Validation | Severity |
|------|-------|------------|----------|
| Package.swift `useLocalNatives` toggle for release flow | `sdk/runanywhere-swift/Package.swift:50`; root `Package.swift:54` | Release tag flow flips automatically | LOW |
| VERSION sync gate — CI fails if `SDKConstants.VERSION` / `pubspec.yaml` / `package.json` / `gradle.properties` diverge from canonical `sdk/runanywhere-commons/VERSION`. | `./scripts/sync-versions.sh`; new `.github/workflows/version-drift-check.yml` | CI green | LOW |
| WASM `a.out` cleanup — `build.sh` clean step covers `wasm/a.out.*`. | `sdk/runanywhere-web/wasm/scripts/build.sh:144,215` | Clean build leaves no a.out in `wasm/` | LOW |
| Web CI Playwright — gate the LLM E2E from WEB-09 into `.github/workflows/`. | New `.github/workflows/web-e2e.yml` | CI green on web E2E | LOW |
| C++ lint gate — `./scripts/lint-cpp.sh` runs in CI. | `.github/workflows/pr-build.yml` | CI green | LOW |
| Pre-commit Web hook — typecheck + vitest on any PR touching `sdk/runanywhere-web/`. | `.pre-commit-config.yaml`; `.github/workflows/pr-build.yml` | Hook runs green | LOW |
| IDL drift guard — verify existing `idl-drift-check.yml` covers IDL-19 file-list drift detection. | `.github/workflows/idl-drift-check.yml`; `idl/codegen/generate_all.sh` | CI fails if per-language proto file lists diverge | LOW |
| Legacy-files blocklist — verify existing `legacy-files-blocklist.yml` covers files deleted in Waves 1-3. | `.github/workflows/legacy-files-blocklist.yml` | CI fails if any deleted file reappears | LOW |

### Final: seven-lane E2E validation

Run the seven-lane modality validation (lanes per `test_workflows/instructions/common/modality_matrix.md`) using:

- **MobileUse MCP** for iOS + Android + Flutter iOS + Flutter Android + RN iOS + RN Android lanes
- **Playwright MCP** for the Web lane

Per `test_workflows/instructions/common/run_contract.md`: every lane produces `logs/<lane>/actions.jsonl` + `logs/<lane>/screenshots/*.png` + `logs/<lane>/report.json` conforming to `test_workflows/instructions/common/report_schema.md`. Each report declares PASS / FAIL per modality (LLM, STT, TTS, VAD, VLM, RAG, Voice Agent).

Then run a 6-agent bug-discovery pass over the seven lanes' logs, screenshots, and `actions.jsonl` files. Each discovery agent contributes `BUG-NNN` entries appended to this backlog with:

- ID: `BUG-<laneTag>-<NNN>`
- Task: reproduce + fix
- Files: evidence (log path + offending SDK/commons file)
- Validation: re-run the failing lane
- Severity: P0 / P1 / P2

Loop back to the top of this backlog and drain the newly added BUG rows. Iterate until all lanes PASS and no new BUG entries are produced.

## Wave F — Bug-discovery (from 7-lane E2E 20260505T183402)

> **Source**: `test_workflows/logs/20260505T183402-0700-seven-lane-validation/REPORT.md`
> **Total lanes**: 7. Status: 0 PASS, 1 PARTIAL, 4 FAIL, 2 BLOCKED.
> **BUGs filed pre-discovery-pass**: 20 (13 HIGH, 5 MEDIUM, 2 LOW)
> **BUGs filed in discovery pass**: (appended below by 6 parallel agents)

### Lane-level BUGs already captured in run-level artifacts
See `test_workflows/logs/20260505T183402-0700-seven-lane-validation/failure_summary.tsv` for the full 20-row table. IDs: BUG-ANDROID-KOTLIN-{001,002}, BUG-SWIFT-IOS-{001,002}, BUG-RN-ANDROID-{001,LANE-CONFLICT}, BUG-RN-IOS-{001}, BUG-FLT-ANDROID-{001,002,003}, BUG-FLT-IOS-{001,002,003,004}, BUG-WEB-{001,002,003,004,005}.

**RESOLVED (Wave F-0 housekeeping)**: BUG-SWIFT-IOS-001 (commit 2dedd19ad), BUG-FLT-IOS-001 (commit e081a475c).
**RESOLVED (Wave F-1)**: BUG-RN-IOS-002 (auto-run `bundle exec pod install` via `postinstall` script in `examples/react-native/RunAnywhereAI/package.json`); BUG-ANDROID-KOTLIN-001 + BUG-ANDROID-KOTLIN-004 (migrated 5 example-app call-sites to construct `VLMImage` / `STTOptions.language` directly from Wire-generated proto types; deleted path was intentional per KOT-DEAD-PROTOEXT (commit 765692eae); CLAUDE.md doc-drift fixed); BUG-ANDROID-KOTLIN-002 + BUG-ANDROID-KOTLIN-003 (migrated 9 `VoiceAssistantViewModel.kt` call-sites to `ai.runanywhere.proto.v1.ErrorCode` per IDL-08 mapping; deleted orphan generated `VoiceSessionErrorCode.kt` left behind by Wire 4.x additive codegen); BUG-SWIFT-IOS-002 (re-seeded the iOS example-app model catalog — 25 entries across LLM / VLM / STT / TTS / VAD / embedding / diffusion / MetalRT — via new `registerModulesAndModels()` in `examples/ios/RunAnywhereAI/RunAnywhereAI/App/RunAnywhereAIApp.swift`, called from `initializeSDK()` between `runSDKInitialize()` and `refreshSDKCatalogs()`; mirrors the Flutter / Kotlin / RN / Web example catalogs since the SDK does not ship a default seed; BUG-SWIFT-IOS-003's cross-contamination caveat verified against code — Swift app file had zero `RunAnywhere.registerModel(...)` calls prior to this fix).
**RESOLVED (Wave F-2)**: BUG-RN-ANDROID-002 + BUG-WEB-001 (passed `model: ModelInfo` submessage to `DownloadPlanRequest` so `download_orchestrator.cpp`'s `request.has_model()` gate no longer rejects downloads. RN: `RunAnywhere+ModelManagement.ts` now fetches `ModelInfo` via `native.getModelInfoProto(modelId)` and decodes before building the plan request, mirroring iOS `RunAnywhere+Storage.swift:100-105`. Web: `examples/web/RunAnywhereAI/src/components/model-selection.ts` now calls `RunAnywhere.modelRegistry.get(modelId)` before `downloads.plan(...)` and passes the full model).
**RESOLVED (Wave F-3)**: BUG-WEB-002 (web SDK now installs a synthetic `/opfs` base dir immediately after `rac_init` via `rac_model_paths_set_base_dir`, so the C++ download orchestrator's `g_base_dir.empty()` check no longer rejects `rac_model_paths_get_model_folder`. Emscripten MEMFS treats the prefix as a normal absolute path and the PlatformAdapter `file_*` callbacks handle I/O against it. Note: this fix unblocks the download path only — the MEMFS-is-volatile gap remains tracked separately as BUG-WEB-MEMFS-VOLATILE. Exports `_rac_model_paths_set_base_dir` + `_rac_model_paths_get_base_dir` added to `sdk/runanywhere-web/wasm/CMakeLists.txt`; call added in `LlamaCppBridge._initRACommons()`); BUG-WEB-003 (WebGPU WASM variant was missing the 15 `_rac_wasm_offsetof_platform_adapter_*` exports + `_rac_wasm_offsetof_config_platform_adapter` because the shipped `racommons-llamacpp-webgpu.{js,wasm}` (built 2026-05-03 19:24) predated commit `9226feb2c` (2026-05-04 23:29) that added those helpers to `wasm_exports.cpp` + CMakeLists. Source is already correct — all 15 fields carry `EMSCRIPTEN_KEEPALIVE` and appear in `RAC_EXPORTED_FUNCTIONS` unconditionally for BOTH CPU and WebGPU variants. Deleted the stale WebGPU artifacts from `sdk/runanywhere-web/packages/llamacpp/wasm/` + `examples/web/RunAnywhereAI/dist/assets/` and added a CMakeLists comment pinning the parity requirement. **Requires a fresh `./wasm/scripts/build.sh --llamacpp --webgpu` run before shipping to regenerate the WebGPU binaries**).

### Discovery-pass BUGs (appended by agents 1-6)

<!-- Agents append new BUG rows below this line. Format:
BUG-<TAG>-<NNN> — title (SEVERITY)
Lane / Category / Evidence / Reproduction / Root cause / Fix pointer
-->

### BUG-STREAMING-HARNESS-NEW — Materialize a shared cross-SDK streaming parity harness (NEW-FEATURE, MEDIUM)
**Lane**: test-infra
**Category**: new-feature
**Evidence**:
- Flutter's `sdk/runanywhere-flutter/packages/runanywhere/test/parity_test.dart` + `cancel_parity_test.dart` are the only streaming-parity tests in the repo and build fixtures in-package (`fixtures/streaming_proto_fixtures.dart`). They cannot currently detect drift in Swift, Kotlin, RN, or Web.
- Stale references to `../../tests/streaming/`, `PerfBenchTest`, `CancelParityTest`, `ChecksumPlumbingTest`, and `golden_events.txt` have been removed from `sdk/runanywhere-kotlin/CLAUDE.md` (prior BUG-STREAMING-004 fix). No current doc claims a shared harness exists.
**Scope**: Port Flutter's `streaming_proto_fixtures.dart` byte sequences to a language-neutral `tests/streaming/fixtures/` (checked-in proto-encoded bytes + expected decoded JSON). Add thin readers per SDK: Swift XCTest, Kotlin JUnit + Wire decode, Dart (reuse existing), TS vitest. Wire a CI workflow that runs all four and diffs decoded output against a shared golden JSON. Without this, regressions like BUG-STREAMING-001 (Flutter iOS hang) / BUG-STREAMING-002 can only be caught at manual 7-lane runs.
**Severity**: MEDIUM (no current regression — feature request to prevent future ones)

### BUG-WEB-007 — Example app's Settings tab hardcodes stale SDK version `0.1.0` instead of reading `RunAnywhere.version` (LOW)
**Lane**: 07_web
**Category**: example-app-drift
**Evidence**:
- `examples/web/RunAnywhereAI/src/views/settings.ts:73` — `<span class="setting-value">0.1.0</span>` is hardcoded in the template string.
- Actual SDK version is `0.19.13` (per `sdk/runanywhere-commons/VERSION`, and per startup log `[RunAnywhere] SDK initialized, version: 0.19.13 | storage backend: opfs` captured at `test_workflows/logs/20260505T183402-0700-seven-lane-validation/07_web/logs/browser_console_final_all.jsonl`).
- `screenshots/090_settings_tab.png` displays `0.1.0` to the user, leading them to misreport SDK version in bug reports.
- `RunAnywhere.version` is available via the exposed singleton (already used by `main.ts:298`) but `settings.ts` never imports it.
**Reproduction**:
  1. Run the web example app, navigate to Settings tab.
  2. Compare "SDK Version" row to the startup console log.
  3. Version mismatch: `0.1.0` vs `0.19.13`.
**Root cause (suspected)**: Template string was never updated when SDK version was bumped. No pre-commit guard for hardcoded version strings in examples.
**Fix pointer**: Replace `<span class="setting-value">0.1.0</span>` with `<span class="setting-value" id="settings-sdk-version"></span>` and populate in init with `textContent = RunAnywhere.version` (import `RunAnywhere` from `@runanywhere/web`). Matches the dynamic pattern already used in `storage.ts` for the storage-backend status row.
**Severity**: LOW

### BUG-WEB-MEMFS-VOLATILE — PlatformAdapter file callbacks bind to Emscripten MEMFS, not OPFS; downloaded models are lost on page reload (MEDIUM, follow-up from deleted BUG-WEB-008)
**Lane**: 07_web
**Category**: SDK-defect | runtime
**Evidence**:
- `sdk/runanywhere-web/packages/llamacpp/src/Foundation/PlatformAdapter.ts:174-201` implements `file_read` / `file_write` / `file_exists` / `file_delete` by calling `m.FS.readFile` / `writeFile` / `unlink` / `analyzePath`. `m.FS` is **Emscripten MEMFS** — in-memory, volatile, reset on page reload — NOT OPFS.
- Any model downloaded by the C++ orchestrator is written only to volatile MEMFS; on next page reload the model is gone.
- The `storageBackend: opfs` label printed at startup (from `RunAnywhere.storageBackend` capability check) is therefore misleading: OPFS detection returns true, but nothing writes to it.
- Predecessor BUG-WEB-008 deleted the orphan `OPFSStorage` class (440 lines of never-instantiated code). This row tracks the remaining architectural gap.
**Reproduction**:
  1. Download a model successfully.
  2. Reload the page.
  3. The model has to be downloaded again.
**Root cause (suspected)**: V2 collapsed model-storage ownership into the C++ download orchestrator + platform-adapter file callbacks. No one implemented an OPFS-backed file callback, so the default `m.FS` (MEMFS) path is invoked.
**Fix pointer**: Wire PlatformAdapter's `file_*` callbacks to an OPFS FileSystem Sync Access Handle inside a dedicated Worker so C++ can keep synchronous file semantics. This is a non-trivial piece of work (async-to-sync bridging via Atomics or similar) and is tracked separately from the orphan-code cleanup.
**Severity**: MEDIUM

### BUG-WEB-009 — Vite `copyWasmPlugin` ships unused 12 MB `sherpa-onnx.wasm` into `dist/assets/`; `SherpaONNXBridge` never loads it (LOW)
**Lane**: 07_web
**Category**: build-tooling | example-app-drift
**Evidence**:
- `examples/web/RunAnywhereAI/vite.config.ts:35-40` configures `copyWasmPlugin` to copy three WASM files, including `sherpa-onnx.wasm` (12 MB).
- `examples/web/RunAnywhereAI/dist/assets/sherpa-onnx.wasm` exists at 12 MB after build (confirmed via `ls -lah`).
- `sdk/runanywhere-web/packages/onnx/src/Foundation/SherpaONNXBridge.ts:9-12` explicitly documents: "This bridge does NOT load `sherpa-onnx.wasm` directly — that file is a standalone Sherpa-ONNX library used only by the legacy direct-sherpa-JS path which V2 deletes." The bridge loads `racommons-llamacpp.js` as the commons module for both LLM and ONNX.
- Build log `logs/03_example_build.log` confirms the copy: `✓ Copied sherpa-onnx.wasm (12.1 MB)`.
- `logs/browser_network_final.log` confirms the browser NEVER requests `sherpa-onnx.wasm` (only the two `racommons-llamacpp*.wasm` fetches). The file is pure deploy-size bloat.
**Reproduction**:
  1. `cd examples/web/RunAnywhereAI && npm run build`.
  2. `ls -lah dist/assets/*.wasm` → `sherpa-onnx.wasm` 12 MB present.
  3. Load the app in a browser, inspect Network tab → `sherpa-onnx.wasm` is never requested.
**Root cause (suspected)**: V2 architecture pivot away from direct-sherpa-JS loading did not prune the corresponding `vite.config.ts` `wasmFiles` entry. The commons WASM path was added but the legacy sherpa WASM copy was left in place.
**Fix pointer**: Remove the `{ src: path.join(onnxWasmDir, 'sherpa-onnx.wasm'), dest: 'sherpa-onnx.wasm' }` entry from `vite.config.ts:35-40`. Also audit `sdk/runanywhere-web/wasm/scripts/build-sherpa-onnx.sh` — if the standalone sherpa wasm is not consumed anywhere in V2, delete that build step. Savings: 12 MB per deployment.
**Severity**: LOW

### BUG-WEB-010 — Example app's `feature-unavailable` placeholder hardcodes obsolete text claiming `@runanywhere/web-llamacpp` and `@runanywhere/web-onnx` are "empty stubs" (LOW)
**Lane**: 07_web
**Category**: example-app-drift
**Evidence**:
- `examples/web/RunAnywhereAI/src/components/feature-unavailable.ts:45-47` — hardcoded text: "currently `@runanywhere/web-llamacpp` and `@runanywhere/web-onnx` are intentionally empty stubs that will receive the new wiring in a follow-up."
- The message is rendered on the Voice tab (`views/voice.ts:18-23`) — see `screenshots/030_voice_tab.png`, explicitly cited in the agent report (`agent_report.md:40`) and modality table (`modality_table.tsv` voice_agent row).
- Reality check:
  - `@runanywhere/web-llamacpp` is fully wired — `logs/browser_console_final_all.jsonl` lines 30-37 show WASM load, vtable registration, and `LlamaCPP.register()` returning `accelerationMode: 'cpu'` successfully.
  - `@runanywhere/web-onnx` is NOT an empty stub — `sdk/runanywhere-web/packages/onnx/src/ONNX.ts` and `Foundation/SherpaONNXBridge.ts` contain a full implementation. Registration fails not because the package is a "stub" but because `rac_backend_onnx_register` is missing from the WASM build (pending CPP-13).
- The inaccurate placeholder misleads test agents: this very run's `BUG-WEB-004` description ("empty stub") is downstream of this text.
**Reproduction**:
  1. Launch the example app, click Voice tab.
  2. Read the large placeholder text referencing "empty stubs".
  3. Compare against actual source — both packages have real, non-stub implementations.
**Root cause (suspected)**: Placeholder text was written when WEB-01 deferred backend wiring; it was never updated after `SherpaONNXBridge` and the LlamaCPP registration path were re-landed. It bleeds incorrect framing into every observational test report.
**Fix pointer**: Update `feature-unavailable.ts:45-47` to reflect current reality: the LLM backend is fully wired via `LlamaCPP.register()`; the ONNX backend bridge is wired but `rac_backend_onnx_register` is missing from the WASM build (RAC_WASM_ONNX=OFF pending CPP-13). Cross-reference `BUG-WEB-004` / `CPP-13` rather than claiming the packages are stubs.
**Severity**: LOW

### BUG-FLT-ANDROID-004 — Android 16 KB page-size compatibility failure: NDK-shipped `libc++_shared.so` and `libomp.so` are 4 KB-aligned (HIGH)
**Lane**: 05_flutter_android
**Category**: build-tooling
**Evidence**:
- `test_workflows/logs/20260505T183402-0700-seven-lane-validation/05_flutter_android/logs/session.log:273` → `W AppWarnings: Showing PageSizeMismatchDialog for package com.runanywhere.runanywhere_ai` (Android 16 / Pixel 8 Pro husky / API 36).
- `test_workflows/logs/20260505T183402-0700-seven-lane-validation/05_flutter_android/logs/view_compat_dialog.xml` captures the OS dialog text listing 19 `.so` files as "not 16 KB aligned"; two have the explicit reason `LOAD segment not aligned`: `libc++_shared.so`, `libomp.so`. The rest are listed as `Unknown error` by the OS scanner.
- Local ELF header inspection (arm64-v8a): `libc++_shared.so` (3 copies under `sdk/runanywhere-flutter/packages/*/android/src/main/jniLibs/arm64-v8a/`) and `libomp.so` all report `LOAD align=0x1000` (4 KB). All `rac_*` / `librunanywhere_jni.so` / `libsherpa-onnx-*.so` / `libonnxruntime.so` are `LOAD align=0x4000` (16 KB) and pass.
- Screenshots `000_launch.png`, `001_after_dialog.png` show the warning dialog appearing on first launch, dismissed by the agent.
**Reproduction**:
  1. Install Flutter example APK on a Pixel 8 Pro running Android 16 (16 KB page-size enabled).
  2. Launch app — the OS-level "Android App Compatibility" dialog pops up immediately after splash.
**Root cause (suspected)**: Flutter SDK packages are pinned to NDK `25.2.9519653` (see `sdk/runanywhere-flutter/packages/*/android/build.gradle` fallback + `racFlutterNdkVersion` root property). NDK 25.x ships 4 KB-aligned `libc++_shared.so` / `libomp.so`. NDK 27.x (used by the Kotlin / React-Native / commons SDKs — `racNdkVersion=27.0.12077973`) ships 16 KB-aligned runtime sidecars. Flutter is pinned to 25.x per root CLAUDE.md ("Flutter ships its own NDK pin"), but 25.x is incompatible with Android 16 page-size enforcement.
**Fix pointer**: Upgrade Flutter SDK `racFlutterNdkVersion` to 27.0.12077973 (matching Kotlin) OR manually replace `libc++_shared.so` / `libomp.so` in the three Flutter package jniLibs dirs with the 16 KB-aligned variants from NDK r27. Verify every `LOAD` program-header `align` is `0x4000`. Ref: https://developer.android.com/16kb-page-size.
**Severity**: HIGH — currently only a warning on debug builds (OS dialog auto-dismissible) but BLOCKS Play Store submissions targeting Android 15+ from Nov 2025, and WILL cause hard load failure on Android 16 devices running 16 KB-mode kernels.

### BUG-FLT-ANDROID-005 — AndroidManifest missing `android:enableOnBackInvokedCallback="true"` (LOW)
**Lane**: 05_flutter_android
**Category**: example-app-drift
**Evidence**:
- `test_workflows/logs/20260505T183402-0700-seven-lane-validation/05_flutter_android/logs/session.log` — `05-05 19:09:33.300 13080 13080 W WindowOnBackDispatcher: OnBackInvokedCallback is not enabled for the application.` followed immediately by `Set 'android:enableOnBackInvokedCallback="true"' in the application manifest.`
- `examples/flutter/RunAnywhereAI/android/app/src/main/AndroidManifest.xml:7-11` — the `<application>` element has no `android:enableOnBackInvokedCallback` attribute.
**Reproduction**:
  1. Launch Flutter example on any device running Android 13+.
  2. Perform any back gesture — warning logged repeatedly.
**Root cause (suspected)**: Android 13+ deprecates the legacy `onBackPressed` in favor of predictive-back. Flutter's PopScope widget handles the callback but the manifest must opt-in.
**Fix pointer**: Add `android:enableOnBackInvokedCallback="true"` to the `<application>` element in `examples/flutter/RunAnywhereAI/android/app/src/main/AndroidManifest.xml`.
**Severity**: LOW — warning only; Android system falls back silently.

### BUG-PERF-001 — Flutter Android app native SIGSEGV in dart-code region during LLM session (HIGH)
**Lane(s)**: 05_flutter_android
**Category**: memory | perf
**Evidence**:
- `test_workflows/logs/20260505T183402-0700-seven-lane-validation/05_flutter_android/logs/session.log:26209` — `F libc : Fatal signal 11 (SIGSEGV), code 1 (SEGV_MAPERR), fault addr 0x75b826a488 in tid 15467 (.runanywhere_ai)`.
- Tombstone context at session.log:26227-26241: backtrace `#00 pc 0x92630 [anon:dart-code]`, esr=0x92000007 (Data Abort Exception 0x24). Only 1 frame — backtrace unwind failed across a JIT-compiled Dart frame.
- Force-finish cascade at session.log:26259-26307: ActivityManager `Force finishing activity com.runanywhere.runanywhere_ai/.MainActivity`; tombstone filed to DropBox as `SYSTEM_TOMBSTONE`.
- Process-kill history at lines 13582, 14944, 17795, 22286, 27960, 29437, 32541: 7+ Zygote `signal 9 (Killed)` events for Flutter child processes during the 35-minute lane run. Multiple repeated LMK-style kills suggest memory churn.
- `BUG-FLT-ANDROID-001` InvalidProtocolBufferException spam hits 4958 occurrences in same session (grep confirmed count). The SEGV is likely downstream of the same proto-ABI drift.
**Root cause (suspected)**: Dart JIT frame crash during `rac_llm_*` or download-progress native callback dispatch. A raw C callback struct is being interpreted as proto bytes; when the Dart decoder reads past the struct it dereferences into unmapped memory. Stack-frame fingerprint (1 frame in anon:dart-code) is consistent with a Dart FFI boundary crash, not pure C++.
**Fix pointer**: Rooted in same fix as BUG-STREAMING-005 / BUG-FLT-ANDROID-001 — align the C `rac_download_progress_callback_proto_t` wire encoding with what `DartBridge.Download` decodes. Also add an `Isolate.current.addErrorListener` / SIGSEGV isolate-level handler in `sdk/runanywhere-flutter/packages/runanywhere/lib/src/bridge/dart_bridge.dart` to surface any native ABI drift as a Dart exception instead of a process crash.
**Severity**: HIGH

### BUG-PERF-002 — Flutter iOS LLM inference hangs indefinitely (>2 minutes) on simulator with no error (HIGH)
**Lane(s)**: 06_flutter_ios
**Category**: perf
**Evidence**:
- `test_workflows/logs/20260505T183402-0700-seven-lane-validation/06_flutter_ios/agent_report.md:46` — `DartBridge.llm.generate` dispatched but `no token, no complete, no error callback arrives within 2+ minutes. UI shows '0.3s 0.0 tok/s' placeholder indefinitely.`
- `06_flutter_ios/actions.jsonl:28` — `llm_hang: UI shows 0.3s 0.0 tok/s; no tokens arrive over 2+ minutes; no LLM error in log; app eventually backgrounded`.
- Cascading symptom: `simctl launch then fails with FBSOpenApplicationServiceErrorDomain code=4 until reinstall` — iOS watchdog killed the hung simulator process.
- Screenshots `12_model_download_progress.png` through `23_llm_final.png` all show stalled LLM generation states (generation chain never completes).
- Cross-reference: Matches BUG-STREAMING-001/002 symptom shape — the callback-style `rac_llm_set_stream_proto_callback` path emits only 9 of 17 proto fields.
**Root cause (suspected)**: `Isolate.run { rac_llm_component_generate(...) }` on the iOS simulator — Dart Isolate posts the generate call to C++ but the stream-proto callback registered from the main isolate never fires (possibly because the C callback is invoked on the isolate's worker thread where no message-queue pump exists).
**Fix pointer**: Switch Flutter iOS to the request/response `rac_llm_generate_stream_proto` path (what Kotlin uses) — see `sdk/runanywhere-kotlin/src/jvmAndroidMain/kotlin/com/runanywhere/sdk/foundation/bridge/extensions/CppBridgeModalityProto.kt:170-183`. Or ensure the callback dispatch pumps messages into the Dart isolate's main loop via `RootIsolateToken.send`.
**Severity**: HIGH

### BUG-PERF-003 — React Native iOS LLM inference returns in 0.3s with 0 tokens (HIGH)
**Status**: RESOLVED (likely by BUG-RN-IOS-004 fix commit 766965657); re-verify on Lane 04 rerun.
**Lane(s)**: 04_react_native_ios
**Category**: perf | correctness
**Evidence**:
- `04_react_native_ios/agent_report.md` — two independent prompts each returned `0.3s 0.0 tok/s` with an empty assistant bubble. Already filed as BUG-RN-IOS-001.
- Screenshot `04_react_native_ios/screenshots/004_llm_inference_zero_tokens.png` is the primary evidence artifact.
- `logs/metro.log` — Metro bundler timed out after 60s (`connection terminated with Device for app='org.reactjs.native.example.RunAnywhereAI'`). JS bridge may have lost connection mid-generate.
- Contrasts with BUG-PERF-002 (Flutter iOS hangs 2+ min) — RN path terminates in 0.3s, suggesting the stream completes (with 0 events) rather than hanging. NitroModules `AsyncIterable` fan-out may be closing the iterator before any token arrives.
- `04_react_native_ios/agent_report.md` confirms: `No llama.cpp telemetry appears in 'log stream' output because stderr/NSLog from the NitroModule native thread was not captured`.
**Root cause (suspected)**: NitroModules `HandleFanOut` for the LLM stream receives the `is_final=true` terminal event from C++ but no intermediate token events. The callback emitter `dispatch_llm_stream_event` in `rac_llm_stream.cpp` may be emitting only the terminal event on iOS simulator (CPU path) — related to BUG-STREAMING-001.
**Fix pointer**: Trace `rac_llm_generate_stream_proto` in `sdk/runanywhere-commons/src/features/llm/rac_llm_stream.cpp` on iOS simulator. Verify llama.cpp backend produces tokens (check `rac_llm_component_generate` return) and the fan-out forwards them. Capture NitroModule native thread stderr via direct file descriptor redirection, not `log stream` predicate.
**Severity**: HIGH

## Wave F — Bug-discovery (from 7-lane E2E 20260505T183402)

### BUG-SWIFT-IOS-003 — Lane 02 screenshots/logs cross-contaminated with React Native app, agent report unreliable (HIGH)
**Lane**: 02_ios_swift
**Category**: test-infra
**Evidence**:
- `test_workflows/logs/20260505T183402-0700-seven-lane-validation/02_ios_swift/screenshots/001_after_get_started.png`, `010_voice_tab.png`, `011_vision_tab.png`, `012_transcribe_tab.png`, `013_stt_tab.png`, `014_llm_model_list.png` all show the **8-tab React Native layout** (Chat, Vision, STT, Speak, Voice, Tools, Solutions, Settings). The Swift app's `examples/ios/RunAnywhereAI/RunAnywhereAI/App/ContentView.swift:15-62` defines a **5-tab layout** (Chat, Vision, Voice, More, Settings). These screenshots are therefore the React Native app, not the Swift app.
- `02_ios_swift/logs/sdk_logs.log:3-14` — `[HybridObjectRegistry] Registering HybridObject "RunAnywhereCore"... "LLM"... "RunAnywhereLlama"... "RunAnywhereONNX"` (Nitro registrations are RN-only). Bundle ID in the same log is `org.reactjs.native.example.RunAnywhereAI`, not `com.runanywhere.RunAnywhere` (Swift example app bundle ID per `examples/ios/RunAnywhereAI/RunAnywhereAI.xcodeproj/project.pbxproj`).
- `02_ios_swift/agent_report.md:38` claims "only Platform LLM (Apple) in list" but the screenshot `014_llm_model_list.png` that the agent cites as primary evidence is actually the RN app showing 7 llama.cpp models (LFM2 1.2B Tool Q4, LFM2 1.2B Tool, LFM2 350M Q4_K, LFM2 350M Q8_0, Llama 2 7B Chat Q4_K_M, Mistral 7B Instruct Q4_K_M, Qwen 2.5 0.5B Q6). BUG-SWIFT-IOS-002's "empty catalog" conclusion is therefore drawn from the wrong app's screenshots and must be re-verified against the actual Swift app.
**Reproduction**:
  1. Open `02_ios_swift/screenshots/` and count tabs in any screenshot after `000_launch.png`.
  2. `grep -c 'org.reactjs.native.example' 02_ios_swift/logs/sdk_logs.log` returns 50+ hits.
**Root cause (suspected)**: Lane-02 agent ran `xcrun simctl io <UDID> screenshot` and `log stream --predicate 'subsystem CONTAINS "com.runanywhere"'` while both the Swift and RN example apps were co-resident on the same simulator (`FCDFD4C4-907E-40EC-9C6A-AB95E0BECEBA`). The predicate matched both bundles, and screenshots captured whichever app happened to be foregrounded. Agent report §48 acknowledges that RN app "was co-resident" but only uninstalled it partway through, not before first screenshot.
**Fix pointer**: Add pre-lane gate to every example-lane script: `xcrun simctl uninstall <UDID> <every_other_example_bundle_id>` for all other SDKs' bundle IDs before booting. Tighten `log stream` predicate to `process == "RunAnywhereAI" AND subsystem == "com.runanywhere.RunAnywhereAI"` (exact process + exact subsystem).
**Severity**: HIGH — invalidates a significant portion of the Swift lane's evidence base and cascades into BUG-SWIFT-IOS-002's root-cause narrative.

### BUG-SWIFT-IOS-004 — Example app MARKETING_VERSION (0.17.2) drifted 7 patches behind canonical SDK VERSION (0.19.13) + extensions stuck at 1.0 triggering Xcode bundle-version warnings (MEDIUM)
**Lane**: 02_ios_swift
**Category**: build-tooling | release-hygiene
**Evidence**:
- `examples/ios/RunAnywhereAI/RunAnywhereAI.xcodeproj/project.pbxproj` has 6× `MARKETING_VERSION = 0.17.2` (main app + test targets) and 12× `MARKETING_VERSION = 1.0` (RunAnywhereKeyboard, RunAnywhereActivityExtension).
- Canonical SDK version in `sdk/runanywhere-commons/VERSION` is `0.19.13`.
- `02_ios_swift/logs/06_xcodebuild.log:33-34` — `warning: The CFBundleShortVersionString of an app extension ('1.0') must match that of its containing parent app ('0.17.2').` (2 occurrences, one per extension.)
- `scripts/sync-versions.sh` is supposed to propagate the canonical version across manifests; the iOS example's `project.pbxproj` is not covered.
**Reproduction**:
  1. `grep MARKETING_VERSION examples/ios/RunAnywhereAI/RunAnywhereAI.xcodeproj/project.pbxproj`
  2. Compare to `cat sdk/runanywhere-commons/VERSION`.
**Root cause (suspected)**: `sync-versions.sh` misses the iOS example's `.pbxproj` + doesn't sync extension Info.plist/MARKETING_VERSION. App Store rejects archives with mismatched extension versions; this blocks a future release gate.
**Fix pointer**: Extend `scripts/sync-versions.sh` to `sed` through every `project.pbxproj`'s `MARKETING_VERSION =` assignments. Also update the 2 extension targets to inherit from parent main-app. CI gate: add `legacy-files-blocklist`-style check that greps `MARKETING_VERSION = ` vs `VERSION` file.
**Severity**: MEDIUM — not blocking builds, but guaranteed App Store rejection + false-telemetry noise ("app claims 0.17.2 but running 0.19.13 SDK").

### BUG-SWIFT-IOS-005 — MetalRT.register(priority:100) called unconditionally via #if canImport, but RunAnywhereMetalRT product is not declared in example app Package.swift — dead-code path that silently elides on external SPM consumers (LOW)
**Lane**: 02_ios_swift
**Category**: SDK-defect | example-app-drift
**Evidence**:
- `examples/ios/RunAnywhereAI/RunAnywhereAI/App/RunAnywhereAIApp.swift:92-94` — `#if canImport(MetalRTRuntime) ; MetalRT.register(priority: 100) ; #endif`.
- `examples/ios/RunAnywhereAI/Package.swift:45-50` declares only `RunAnywhere`, `RunAnywhereONNX`, `RunAnywhereLlamaCPP`, `RunAnywhereWhisperKit`. No `RunAnywhereMetalRT` product listed.
- Root `Package.swift:67,324-327` — `includeMetalRT` is gated on `useLocalNatives == true`. Line 43 sets `useLocalNatives = true` for local dev; external consumers flip this to `false`, at which point `RunAnywhereMetalRT` product disappears from the package graph entirely.
**Reproduction**:
  1. Set `useLocalNatives = false` at `Package.swift:43`.
  2. `swift build` inside `examples/ios/RunAnywhereAI/` — MetalRT section silently compiles out. App shipped to external users never registers metalrt despite developer intent.
**Root cause (suspected)**: `#if canImport(MetalRTRuntime)` is a compile-time guard on module presence. When `useLocalNatives == false`, the module does not exist → the entire `MetalRT.register(...)` block is erased. The example does not include `RunAnywhereMetalRT` in its `.product(name:...)` dependency list anyway, so even in local-natives mode the call evaluates to a no-op unless `MetalRTRuntime` happens to get pulled transitively.
**Fix pointer**: Either (a) add `.product(name: "RunAnywhereMetalRT", package: "runanywhere-sdks-main")` to the example's Package.swift targets section and drop the `#if canImport` guard, OR (b) delete the guarded block entirely until MetalRT is published as a remote binary. Don't leave both the guard AND the missing product — ambiguity hides real misconfigurations.
**Severity**: LOW — MetalRT backend is an Apple optimization; app still works without it via llamacpp fallback. Issue is drift between documented behavior and actual wiring.

### BUG-SWIFT-IOS-006 — Swift 6 concurrency warnings + deprecated onChange API in example app (LOW)
**Lane**: 02_ios_swift
**Category**: example-app-drift
**Evidence**:
- `02_ios_swift/logs/06_xcodebuild.log` (after BUG-SWIFT-IOS-001 fix) carries 6 actionable warnings:
  - `RunAnywhereAI/Features/Vision/VLMViewModel.swift:39:5: warning: 'nonisolated(unsafe)' has no effect on property 'autoStreamTask', consider using 'nonisolated'` (appears 2×).
  - `RunAnywhereAI/Features/VoiceKeyboard/FlowSessionManager.swift:408:29` and `:416:40`: `warning: no 'async' operations occur within 'await' expression`.
  - `RunAnywhereAI/Features/Voice/STTViewModel.swift:312:40` and `:314:29`: `warning: no 'async' operations occur within 'await' expression`.
  - `RunAnywhereAI/Features/Voice/VoiceAssistantView.swift:300:26: warning: 'onChange(of:perform:)' was deprecated in iOS 17.0`.
- `CLAUDE.md:47` explicitly says "Use the latest Swift 6 APIs always. Do not use NSLock as it is outdated" — fix drift between rule and code.
- App's `Package.swift:21` declares `.iOS(.v17)` minimum, so the deprecated `onChange(of:perform:)` is a legitimate migration target.
**Reproduction**:
  1. `cd examples/ios/RunAnywhereAI && xcodebuild build -scheme RunAnywhereAI -destination 'generic/platform=iOS Simulator'`.
  2. Search output for `warning:`.
**Root cause (suspected)**: Example app was migrated to Swift 6 proto APIs (Wave C) but `nonisolated(unsafe)` / `await` / `onChange` call-sites were not refreshed. `VLMViewModel.autoStreamTask` was marked `nonisolated(unsafe)` for a Swift 5 pattern that no longer requires the `(unsafe)` qualifier under strict concurrency.
**Fix pointer**: (a) `VLMViewModel.swift:39` — drop `(unsafe)`. (b) `FlowSessionManager.swift:408,416` + `STTViewModel.swift:312,314` — remove `await` from the surrounding call. (c) `VoiceAssistantView.swift:300` — migrate to zero-or-two-parameter `onChange { oldValue, newValue in ... }`.
**Severity**: LOW — warnings only, no runtime impact.

### BUG-RN-IOS-003 — App Xcode project ships with React Native template's default placeholder bundle ID `org.reactjs.native.example.RunAnywhereAI` (MEDIUM)
**Lane**: 04_react_native_ios
**Category**: build-tooling | release-hygiene
**Evidence**:
- `examples/react-native/RunAnywhereAI/ios/RunAnywhereAI.xcodeproj/project.pbxproj` — 4× `PRODUCT_BUNDLE_IDENTIFIER = "org.reactjs.native.example.$(PRODUCT_NAME:rfc1034identifier)";`. This is the RN template default.
- `04_react_native_ios/agent_report.md:7` claims the bundle ID is `com.runanywhere.RunAnywhere`, but every RN lane log confirms `org.reactjs.native.example.RunAnywhereAI` — compare `04_react_native_ios/logs/07_filtered_sdk.log:3,11-12,14-27` and `02_ios_swift/logs/sdk_logs.log:25,32` (cross-contaminated but bundle ID correctly shows RN's default).
- Swift example app correctly uses `com.runanywhere.RunAnywhere` at `examples/ios/RunAnywhereAI/RunAnywhereAI.xcodeproj/project.pbxproj` (6 `PRODUCT_BUNDLE_IDENTIFIER =` hits).
- RN app also has `MARKETING_VERSION = 1.0` (vs canonical SDK 0.19.13) — matching class of drift as BUG-SWIFT-IOS-004.
**Reproduction**:
  1. `grep PRODUCT_BUNDLE_IDENTIFIER examples/react-native/RunAnywhereAI/ios/RunAnywhereAI.xcodeproj/project.pbxproj` — 4 hits, all with `org.reactjs.native.example.*`.
**Root cause (suspected)**: RN example created from `npx @react-native-community/cli@latest init RunAnywhereAI` and bundle ID was never customized. This blocks TestFlight (team provisioning profiles won't match a non-owned reverse-DNS), collides with any other RN app that uses the template default, and breaks Keychain sharing with other RunAnywhere-signed apps since Keychain access groups are namespaced by bundle ID.
**Fix pointer**: Change 4 `PRODUCT_BUNDLE_IDENTIFIER` lines to `com.runanywhere.RunAnywhereReactNative` (or match Swift at `com.runanywhere.RunAnywhere` if bundle collision on the same simulator is acceptable). Also bump `MARKETING_VERSION` to read from the canonical `VERSION` file via `sync-versions.sh`.
**Severity**: MEDIUM — blocks any future TestFlight/App Store release; also invalidates `04_react_native_ios/agent_report.md:7` claim.

## Convergence definition

- Zero FAIL rows in seven-lane (all modalities PASS on all 7 lanes)
- All 5 SDKs green: `swift build` + `./gradlew build` + `melos run analyze` + `yarn typecheck` + `npm run typecheck`
- All 5 SDKs lint clean: `swiftlint` 0 errors, `./gradlew detekt ktlintCheck` 0, `flutter analyze` 0, RN/Web lint clean
- `grep -c "LLMTokenKind" idl/*.proto` returns 0
- `grep -c "ModelCompatibilityResult" idl/*.proto` finds one message (the renamed Check variant)
- `grep -L "option go_package" idl/*.proto` returns empty
- No remaining non-proto JNI exports in `sdk/runanywhere-commons/src/jni/runanywhere_commons_jni.cpp` (target: all 254 `JNIEXPORT`s -> Proto-suffixed or deleted)
- `grep -rn "class RacBindings" sdk/runanywhere-flutter` returns exactly 1 hit
- `grep _rac_backend_onnx_register sdk/runanywhere-web/packages/llamacpp/wasm/racommons-llamacpp.js` shows matches
- No file listed in any "Items to DELETE" row above still exists
- `./scripts/validation/check_rac_api_exports.sh` mismatch count is 0 or clearly documented
