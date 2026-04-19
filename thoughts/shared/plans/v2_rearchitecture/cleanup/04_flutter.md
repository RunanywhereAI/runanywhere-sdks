# runanywhere-flutter — v1/v2 cleanup audit

> Root: `sdk/runanywhere-flutter/`
> Audited: 2026-04-18
> v2 reference: `frontends/dart/` (Phase 3A, implementation_plan.md:1249-1264)

---

## Summary

- Total measurable LOC across all meaningful file types (Dart, Swift, Kotlin, Gradle, podspecs, scripts, C++): **~37,470**
- Dart LOC in `packages/runanywhere/lib/`: **31,742** (the "22,838 LOC bridge" MASTER_PLAN cites is the native/ sublayer alone; total Dart is larger)
- DELETE-NOW: **~396 LOC** (8 files — method-channel stubs plus genie iOS podspec stub)
- DELETE-AFTER-V2-ENGINES: **~17,200 LOC** (the entire 3-layer FFI bridge: 32 dart_bridge files + ffi_types + native_backend)
- KEEP: **~14,600 LOC** (public API types, data/network layer, audio managers, features layer — anything v2 Dart adapter will re-expose or restructure around)
- INSPECT: **~5,270 LOC** (scripts, C++ RAG bridge, melos.yaml, android CMakeLists — ownership depends on how v2 CI and build infra land)
- Surviving files after full v2: **~39%** of current LOC; ~61% is deleted once Phase 3A is complete

---

## DELETE-NOW

These files have no function beyond wrapping a hardcoded version string inside a Flutter method channel. v2 gets version from `core/abi/ra_version.h` + the single `vcpkg.json` version field; no method channel is needed because Dart FFI talks directly to the C ABI.

| Path | Lines | Bucket | Reason | Replaced-by | Blocker |
|------|-------|--------|--------|-------------|---------|
| `packages/runanywhere/ios/Classes/RunAnywherePlugin.swift` | 36 | DELETE-NOW | Method channel stub; only exposes `getSDKVersion → "0.15.8"` and `getCommonsVersion → "0.1.4"`. Dart FFI bypasses Flutter method channels entirely. | v2 has no method channel; version comes from `core/abi/ra_version.h` | None |
| `packages/runanywhere/android/src/main/kotlin/ai/runanywhere/sdk/RunAnywherePlugin.kt` | 77 | DELETE-NOW | Same as iOS stub plus `getSocModel()`. SoC detection moves to `core/router/hardware_profile.cpp` (`detect_hardware()`). | `core/router/hardware_profile.cpp:detect_hardware()` | None |
| `packages/runanywhere_llamacpp/ios/Classes/LlamaCppPlugin.swift` | 31 | DELETE-NOW | Returns `getBackendVersion → "0.1.4"`. No other logic. In v2 the llamacpp engine plugin is a static lib with no Flutter method channel. | v2 `engines/llamacpp/llamacpp_plugin.cpp` registered via `PluginRegistry::register_static<>()` | None |
| `packages/runanywhere_llamacpp/android/src/main/kotlin/ai/runanywhere/sdk/llamacpp/LlamaCppPlugin.kt` | 60 | DELETE-NOW | Same as iOS — loads `rac_backend_llamacpp_jni` and returns version string only. | v2 `dlopen`-based `PluginLoader<LlamaCppVTable>` | None |
| `packages/runanywhere_onnx/ios/Classes/OnnxPlugin.swift` | 33 | DELETE-NOW | Returns `getBackendVersion → "0.1.4"` and `getCapabilities → ["stt","tts","vad"]`. Capabilities declared in `SherpaVTable` in v2. | v2 `engines/sherpa/sherpa_plugin.cpp` | None |
| `packages/runanywhere_onnx/android/src/main/kotlin/ai/runanywhere/sdk/onnx/OnnxPlugin.kt` | 65 | DELETE-NOW | Loads `onnxruntime`, `sherpa-onnx-c-api`, `rac_backend_onnx_jni`; returns version only. | v2 `PluginLoader<SherpaVTable>` | None |
| `packages/runanywhere_genie/ios/Classes/GeniePlugin.swift` | 32 | DELETE-NOW | Pure stub — Genie is Android/Snapdragon only; comment in file says "no actual NPU functionality on iOS". In v2, the router simply won't select Genie on non-Snapdragon hardware. | `core/router/engine_router.cpp` hardware routing | None |
| `packages/runanywhere_genie/ios/runanywhere_genie.podspec` | 42 | DELETE-NOW | Exists only to satisfy Flutter plugin registry on iOS for an Android-only backend. v2 has no per-backend CocoaPod. | v2 CMake `RA_STATIC_PLUGINS` path for iOS | None |

**DELETE-NOW total: 376 LOC**

---

## DELETE-AFTER-V2-ENGINES

These files form the 3-layer FFI bridge (described as "3 hand-written layers per call" in MASTER_PLAN). They become pointless once:
1. v2 Phase 3A lands the `frontends/dart/` adapter, and
2. The engine plugins (Phase 0: llama.cpp, sherpa) provide a real C ABI.

### Layer 1: `lib/native/dart_bridge.dart` — Central 2-phase init coordinator

`packages/runanywhere/lib/native/dart_bridge.dart` (411 lines) orchestrates all bridge modules (auth, device, download, environment, events, file_manager, http, llm, lora, model_assignment, model_paths, model_registry, platform, platform_services, rag, state, storage, stt, telemetry, tts, vad, vlm, voice_agent). In v2 this collapses to `frontends/dart/lib/adapter/runanywhere.dart:16-27` — a single `VoiceSession.create(config)` call backed by `ra_pipeline_run()`.

### Layer 2: All `dart_bridge_*.dart` per-domain bridge files

| File | Lines | Bucket | Reason |
|------|-------|--------|--------|
| `lib/native/dart_bridge.dart` | 411 | DELETE-AFTER-V2-ENGINES | Entire 2-phase init coordinator; replaced by `frontends/dart/lib/adapter/runanywhere.dart` |
| `lib/native/dart_bridge_auth.dart` | 910 | DELETE-AFTER-V2-ENGINES | Auth state synced to C++ via `rac_state_*`; v2 auth flows through `core/abi/ra_primitives.h` session config |
| `lib/native/dart_bridge_dev_config.dart` | 109 | DELETE-AFTER-V2-ENGINES | Dev config flags; v2 uses `CMakePresets.json` build flags |
| `lib/native/dart_bridge_device.dart` | 722 | DELETE-AFTER-V2-ENGINES | Device registration, SoC detection; replaced by `core/router/hardware_profile.cpp` |
| `lib/native/dart_bridge_download.dart` | 245 | DELETE-AFTER-V2-ENGINES | Download management bridged to C++; v2 model downloads are handled by CMake install rules |
| `lib/native/dart_bridge_environment.dart` | 365 | DELETE-AFTER-V2-ENGINES | `rac_sdk_init` env config; v2 config is a single `VoiceAgentConfig` proto3 struct |
| `lib/native/dart_bridge_events.dart` | 139 | DELETE-AFTER-V2-ENGINES | Analytics routing callback; v2 surfaces events as `Stream<VoiceEvent>` proto3 types |
| `lib/native/dart_bridge_file_manager.dart` | 472 | DELETE-AFTER-V2-ENGINES | File I/O callbacks registered with C++; v2 removes the platform adapter pattern for file ops |
| `lib/native/dart_bridge_http.dart` | 485 | DELETE-AFTER-V2-ENGINES | HTTP executor callback for C++ download manager; v2 has no C++-driven HTTP in the Dart layer |
| `lib/native/dart_bridge_llm.dart` | 676 | DELETE-AFTER-V2-ENGINES | `rac_llm_component_*` wrapper; replaced by `ra_pipeline_run()` with typed `VoiceAgentConfig` |
| `lib/native/dart_bridge_lora.dart` | 500 | DELETE-AFTER-V2-ENGINES | LoRA adapter management; v2 engine plugins handle LoRA via session config |
| `lib/native/dart_bridge_model_assignment.dart` | 373 | DELETE-AFTER-V2-ENGINES | Backend model assignment fetch; v2 uses `PluginRegistry::find_engine()` routing |
| `lib/native/dart_bridge_model_paths.dart` | 253 | DELETE-AFTER-V2-ENGINES | Model path management bridged to C++; v2 CMake install rules own binary placement |
| `lib/native/dart_bridge_model_registry.dart` | 1,170 | DELETE-AFTER-V2-ENGINES | 1,170-line model registry bridge; v2 reduces to `ra_model_spec_t` in session config |
| `lib/native/dart_bridge_platform.dart` | 724 | DELETE-AFTER-V2-ENGINES | Platform adapter registration (file/log/keychain callbacks); v2 removes this indirection |
| `lib/native/dart_bridge_platform_services.dart` | 80 | DELETE-AFTER-V2-ENGINES | Foundation Models / System TTS callbacks; v2 system TTS is an L2 engine plugin |
| `lib/native/dart_bridge_rag.dart` | 485 | DELETE-AFTER-V2-ENGINES | RAG pipeline bridge over `_flutter_rag_*` ABI; v2 RAG is `solutions/rag/` in C++ core |
| `lib/native/dart_bridge_state.dart` | 523 | DELETE-AFTER-V2-ENGINES | `rac_state_initialize` with apiKey/baseURL/deviceId; v2 init is `ra_pipeline_create()` only |
| `lib/native/dart_bridge_storage.dart` | 120 | DELETE-AFTER-V2-ENGINES | Storage info callbacks; v2 omits Dart-level storage management |
| `lib/native/dart_bridge_structured_output.dart` | 345 | DELETE-AFTER-V2-ENGINES | Structured output JSON schema extraction; v2 LLM session config handles this |
| `lib/native/dart_bridge_stt.dart` | 436 | DELETE-AFTER-V2-ENGINES | `rac_stt_component_*` wrapper; replaced by `ra_stt_session_t` in SherpaVTable |
| `lib/native/dart_bridge_telemetry.dart` | 764 | DELETE-AFTER-V2-ENGINES | Telemetry event batching and HTTP flush; v2 moves telemetry into C++ core or drops it |
| `lib/native/dart_bridge_tool_calling.dart` | 437 | DELETE-AFTER-V2-ENGINES | Tool call parsing; v2 LLM engine handles tool-call formatting in `LlamaCppEngine` |
| `lib/native/dart_bridge_tts.dart` | 427 | DELETE-AFTER-V2-ENGINES | `rac_tts_component_*` wrapper; replaced by `ra_tts_session_t` in SherpaVTable |
| `lib/native/dart_bridge_vad.dart` | 331 | DELETE-AFTER-V2-ENGINES | `rac_vad_component_*` wrapper; replaced by `ra_vad_session_t` in SherpaVTable |
| `lib/native/dart_bridge_vlm.dart` | 910 | DELETE-AFTER-V2-ENGINES | VLM (vision-language model) bridge; v2 VLM is a future primitive, not in Phase 3 scope |
| `lib/native/dart_bridge_voice_agent.dart` | 652 | DELETE-AFTER-V2-ENGINES | Entire batch sequential voice agent loop; replaced by v2 streaming `VoiceAgentPipeline` |

### Layer 3: FFI type declarations and loader

| File | Lines | Bucket | Reason |
|------|-------|--------|--------|
| `lib/native/ffi_types.dart` | 1,354 | DELETE-AFTER-V2-ENGINES | 1,354 lines of hand-written Dart FFI structs (`RacPlatformAdapterStruct`, `RacLlmOptionsStruct`, `RacSttOnnxResultStruct`, etc.) mirroring v1 `rac_*.h` headers. In v2 these are replaced by `protobuf.dart` generated types from `idl/voice_events.proto`. |
| `lib/native/native_backend.dart` | 981 | DELETE-AFTER-V2-ENGINES | 981-line high-level wrapper with backend-type-dispatch string (`'llamacpp'`, `'onnx'`) and manual `calloc/free` for every FFI call. v2 single call-site: `ra_pipeline_run()`. |
| `lib/native/native_functions.dart` | 308 | DELETE-AFTER-V2-ENGINES | Cached `lookupFunction` handles for `rac_*` symbols; obviated by v2 C ABI vtable. |
| `lib/native/platform_loader.dart` | 302 | DELETE-AFTER-V2-ENGINES | `PlatformLoader.loadCommons()` — dlopen per-platform logic for `librac_commons.so` / `RACommons.xcframework`. In v2 this is a single `DynamicLibrary.open()` call in `frontends/dart/lib/adapter/voice_session.dart`. |
| `lib/native/type_conversions/model_types_cpp_bridge.dart` | 295 | DELETE-AFTER-V2-ENGINES | Conversion utilities between Dart model enums and C++ integer constants. Replaced by proto3 enum codegen. |

**DELETE-AFTER-V2-ENGINES Dart subtotal: ~14,900 LOC across 31 files**

### Per-backend packages (Dart lib only)

| Package | File | Lines | Bucket | Reason |
|---------|------|-------|--------|--------|
| `runanywhere_llamacpp` | `lib/llamacpp.dart` + `lib/llamacpp_error.dart` + `lib/native/llamacpp_bindings.dart` | 582 total | DELETE-AFTER-V2-ENGINES | Registers `rac_backend_llamacpp_register()` and wraps errors. v2: `engines/llamacpp/llamacpp_plugin.cpp` self-registers via vtable. |
| `runanywhere_onnx` | `lib/onnx.dart` + `lib/onnx_download_strategy.dart` + `lib/native/onnx_bindings.dart` | 739 total | DELETE-AFTER-V2-ENGINES | Registers ONNX backend and manages download strategy. v2: sherpa engine plugin + CMake install rules. |
| `runanywhere_genie` | `lib/genie.dart` + `lib/genie_error.dart` + `lib/native/genie_bindings.dart` | 525 total | DELETE-AFTER-V2-ENGINES | Registers Genie NPU backend. v2: Genie becomes a `PluginLoader<GenieVTable>` dlopen plugin on Snapdragon Android. |

### C++ RAG bridge (Flutter-specific)

| File | Lines | Bucket | Reason |
|------|-------|--------|--------|
| `packages/runanywhere/src/flutter_rag_bridge.cpp` | 476 | DELETE-AFTER-V2-ENGINES | Flutter-specific C++ shim exposing `_flutter_rag_*` symbols over the RAG pipeline. v2 RAG is a first-class C ABI solution (`solutions/rag/rag_plugin.h`); no Flutter-specific shim needed. |
| `packages/runanywhere/src/flutter_rag_bridge.h` | 116 | DELETE-AFTER-V2-ENGINES | Header for the above. |
| `packages/runanywhere/src/third_party/nlohmann/json.hpp` | large | DELETE-AFTER-V2-ENGINES | Vendored for flutter_rag_bridge.cpp JSON serialization. v2 uses protobuf wire format throughout. |

---

## KEEP

| Path | Lines (approx) | Bucket | Reason |
|------|---------------|--------|--------|
| `packages/runanywhere/lib/data/network/` (all 6 files) | ~800 | KEEP | HTTP client, telemetry service, network configuration. v2 Dart adapter still needs Dart-side HTTP for model downloads and auth until the C++ download manager lands. |
| `packages/runanywhere/lib/features/stt/services/audio_capture_manager.dart` | ~200 | KEEP | Microphone capture via Flutter `record` package. v2 `audio_capture.dart` in `frontends/dart/` does the same thing (`MicrophoneCapture` — 20ms chunk feed). |
| `packages/runanywhere/lib/features/tts/services/audio_playback_manager.dart` | ~200 | KEEP | Audio playback via `audioplayers`. v2 Dart adapter owns playback of `AudioFrame` events from the C++ pipeline. |
| `packages/runanywhere/lib/features/vad/simple_energy_vad.dart` | ~150 | KEEP | Energy-based VAD fallback. Retained as fallback until sherpa VAD engine plugin lands. |
| `packages/runanywhere/lib/public/types/` (all type files) | ~800 | KEEP | `generation_types.dart`, `message_types.dart`, `voice_agent_types.dart`, etc. These are the Dart-facing public API types. v2 proto codegen replaces most, but the Dart adapter re-exposes them as idiomatic Dart wrappers. |
| `packages/runanywhere/lib/public/errors/errors.dart` | ~100 | KEEP | Error hierarchy. v2 maps `RA_ERR_*` codes to these types. |
| `packages/runanywhere/lib/public/events/event_bus.dart` + `sdk_event.dart` | ~150 | KEEP | Event bus used by audio managers. v2 replaces with `Stream<VoiceEvent>` but the event bus may be retained for backward compat. |
| `packages/runanywhere/lib/public/extensions/rag_module.dart` + `runanywhere_rag.dart` | ~200 | KEEP | RAG public API surface. v2 `SolutionConfig.rag(RAGConfig)` provides equivalent. Kept until v2 RAG ships (Phase 2). |
| `packages/runanywhere/lib/public/runanywhere.dart` | ~400 | KEEP | Main SDK entry point. v2 produces `frontends/dart/lib/adapter/runanywhere.dart` which is structurally equivalent but slimmer. The v1 version is kept until the v2 adapter is complete. |
| `packages/runanywhere/lib/foundation/` (all 8 files) | ~400 | KEEP | `SDKConstants`, `ServiceContainer`, `SDKLogger`, `SDKError`. Foundational types that v2 Dart adapter will reference. |
| `packages/runanywhere/lib/capabilities/voice/models/` (2 files) | ~150 | KEEP | `VoiceSession`, `VoiceSessionHandle`. v2 replaces with `frontends/dart/lib/adapter/voice_session.dart` but v1 is kept for backward compat. |
| `packages/runanywhere/lib/features/llm/structured_output/` (5 files) | ~400 | KEEP | Structured output streaming and JSON extraction. These are retained until v2 LLM engine handles structured output in C++ natively. |
| `packages/runanywhere/lib/core/types/` (all type files) | ~250 | KEEP | `ModelTypes`, `ComponentState`, `SDKComponent`, `NpuChip`. Core enums the Dart layer uses. |
| `packages/runanywhere/lib/infrastructure/download/download_service.dart` | ~200 | KEEP | Model download service. Needed until v2 build system and CMake install rules fully replace GitHub-release downloads. |
| `packages/runanywhere/lib/infrastructure/events/event_publisher.dart` | ~80 | KEEP | Internal event bus. |
| `packages/runanywhere/ios/Classes/RACommons.exports` | ~490 lines | KEEP | Symbol export list for `dlsym()` via Flutter FFI. In v2 this is replaced by `core/abi/ra_primitives.h` exported symbols, but until Phase 3A lands this file drives the iOS link map. |
| `packages/runanywhere/ios/runanywhere.podspec` | 184 | KEEP | Downloads `RACommons.xcframework` from GitHub releases for iOS. Needed until v2 produces `RunAnywhereCore.xcframework` via `cmake/xcframework.cmake`. |
| `packages/runanywhere_llamacpp/ios/runanywhere_llamacpp.podspec` | 150 | KEEP | Downloads `RABackendLLAMACPP.xcframework`. Needed until v2 engine plugin build ships. |
| `packages/runanywhere_onnx/ios/runanywhere_onnx.podspec` | 196 | KEEP | Downloads `RABackendONNX.xcframework` + `onnxruntime.xcframework`. Needed until sherpa engine plugin build ships. |
| `packages/runanywhere/android/binary_config.gradle` | 60 | KEEP | Controls `commonsVersion = "0.1.6"` download URL. Needed until Android NDK build in v2 replaces GitHub releases. |
| `packages/runanywhere_llamacpp/android/binary_config.gradle` | 51 | KEEP | Same pattern, `coreVersion = "0.1.6"`. |
| `packages/runanywhere_onnx/android/binary_config.gradle` | 51 | KEEP | Same pattern. |
| `packages/runanywhere_genie/android/binary_config.gradle` | 52 | KEEP | `genieVersion = "0.3.0"` download URL. |
| `melos.yaml` | 25 | KEEP | Monorepo package management for the 4 Flutter packages. Needed for as long as v1 Flutter packages exist. |

---

## INSPECT

| Path | Lines | Bucket | Reason |
|------|-------|--------|--------|
| `scripts/build-flutter.sh` | 697 | INSPECT | 697-line build script that copies JNI libs (IMM-7 candidate), runs pod install, downloads binaries. Has 484-LOC JNI-copy section duplicated across SDKs (per implementation_plan.md:196-225). Ownership unclear: if v2 uses CMake presets this whole script is replaced; if v1 keeps shipping, it's needed. |
| `scripts/package-sdk.sh` | 94 | INSPECT | Packages the SDK for distribution. Replaced by v2 GitHub Actions + CMake install rules, but not yet. |
| `packages/runanywhere/android/CMakeLists.txt` | ~40 (embedded in RACommons.exports) | INSPECT | Builds `flutter_rag_bridge` shared lib for Android. Goes away with flutter_rag_bridge.cpp, but the CMake file itself could be repurposed as a template for v2 Android builds. |
| `packages/runanywhere/lib/features/llm/llm_configuration.dart` + `stt/stt_configuration.dart` + `tts/tts_configuration.dart` + `vad/vad_configuration.dart` | ~400 total | INSPECT | Per-primitive configuration types. v2 replaces with a single `VoiceAgentConfig` proto3 struct, but until Phase 3A is done these may need to remain as Dart-facing wrappers. |
| `packages/runanywhere/lib/infrastructure/file_management/services/simplified_file_manager.dart` | ~150 | INSPECT | File manager abstractions used by download service. May be retained or replaced by v2 path management. |
| `packages/runanywhere/lib/public/extensions/runanywhere_frameworks.dart` + `runanywhere_device.dart` + `runanywhere_logging.dart` + `runanywhere_lora.dart` + `runanywhere_storage.dart` | ~400 total | INSPECT | Extension modules; some (logging, device) may be retained; lora/storage move to engine config. |
| `packages/runanywhere/lib/infrastructure/device/` (2 files) | ~200 | INSPECT | Device info and identity. `hardware_profile.cpp` covers this in v2, but Dart-layer device ID may still be needed for auth. |
| `analysis_options.yaml` | 10 | INSPECT | Dart analyzer config. Keep if any v1 Dart files remain; remove when v2 fully replaces. |

---

## 3-layer FFI bridge collapse

The MASTER_PLAN ("3 hand-written layers per call") refers to the three depths visible in `lib/native/`:

**Layer A — DartBridge coordinator** (`dart_bridge.dart:53-411`)
Manages two-phase init. Holds refs to all 25+ domain bridges. In v2 this becomes ~20 lines: load library, call `ra_pipeline_create()`.

**Layer B — Per-domain `dart_bridge_*.dart` bridges**
One file per C++ subsystem. Pattern: `lib.lookupFunction<NativeType, DartType>('rac_symbol')`. 25 files, ~10,000 LOC. Each file reimplements memory management (`calloc`, `free`), error-code mapping, and Dart callback registration.

What v2 renders pointless:
- `dart_bridge_llm.dart` (676 LOC): Replaced by `ra_generate()` token callback in `LlamaCppVTable`.
- `dart_bridge_stt.dart` (436 LOC): Replaced by `ra_stt_feed_audio()` / `ra_stt_get_result()` in `SherpaVTable`.
- `dart_bridge_tts.dart` (427 LOC): Replaced by `ra_tts_synthesize()` in `SherpaVTable`.
- `dart_bridge_vad.dart` (331 LOC): Replaced by `ra_vad_feed()` in `SherpaVTable`.
- `dart_bridge_voice_agent.dart` (652 LOC): Replaced entirely by `ra_pipeline_run()` with barge-in handled in C++.
- `dart_bridge_rag.dart` (485 LOC): Replaced by `ra_rag_query()` in `solutions/rag/rag_plugin.h`.
- `dart_bridge_auth.dart` (910 LOC): Auth state moves into session config; no separate C++ auth subsystem in v2.
- `dart_bridge_model_registry.dart` (1,170 LOC): Model registry is `PluginRegistry::find_engine()` in v2.

**Layer C — FFI type declarations** (`ffi_types.dart:1-1354`)
1,354 lines of hand-written `Struct` subclasses and function pointer typedefs mirroring `rac_*.h` C headers. In v2 these are generated by `protoc --dart_out` from `idl/voice_events.proto` + `idl/pipeline.proto`. The generated output is ~300 LOC (per MASTER_PLAN's "After" diagram) because the C ABI shrinks to a single pipeline handle with typed proto messages.

Specific FFI types that become redundant after proto3 codegen:
- `RacPlatformAdapterStruct` (18 fields) — platform adapter pattern is removed in v2
- `RacLlmOptionsStruct`, `RacLlmResultStruct` — replaced by `VoiceAgentConfig` proto fields
- `RacSttOnnxConfigStruct`, `RacSttOnnxResultStruct` — replaced by `ra_stt_session_t` handle
- `RacTtsOnnxConfigStruct`, `RacTtsOnnxResultStruct` — replaced by `ra_tts_session_t` handle
- `RacVadOnnxConfigStruct`, `RacVadOnnxResultStruct` — replaced by `ra_vad_session_t` handle
- `RacVlmImageStruct`, `RacVlmOptionsStruct`, `RacVlmResultStruct` — VLM not in Phase 3 proto
- `RacToolCallStruct`, `RacToolCallingOptionsStruct` — tool-call format handled by LLM engine
- `RacStructuredOutputConfigStruct` / `ValidationStruct` — handled by LLM session config
- `RacFileCallbacksStruct` — platform adapter removed
- `RacMemoryInfoStruct` — replaced by `HardwareCaps` in `core/router/hardware_profile.h`

---

## Version string drift

The MASTER_PLAN notes 22+ hardcoded version locations. This audit found the following distinct version strings across the Flutter SDK alone:

| Location | Version string | What it represents |
|----------|---------------|-------------------|
| `packages/runanywhere/pubspec.yaml:3` | `0.19.7` | pub.dev package version |
| `packages/runanywhere_llamacpp/pubspec.yaml:3` | `0.19.7` | pub.dev package version |
| `packages/runanywhere_onnx/pubspec.yaml:3` | `0.19.7` | pub.dev package version |
| `packages/runanywhere_genie/pubspec.yaml:3` | `0.16.0` | pub.dev package version (out of sync with others) |
| `packages/runanywhere/lib/foundation/configuration/sdk_constants.dart:11` | `0.15.8` | `SDKConstants.version` sent in HTTP headers |
| `packages/runanywhere/lib/foundation/configuration/sdk_constants.dart:22` | `0.1.4` | `commonsVersion` (RACommons binary) |
| `packages/runanywhere/lib/foundation/configuration/sdk_constants.dart:27` | `0.1.4` | `coreVersion` (backends binary) |
| `packages/runanywhere/ios/Classes/RunAnywherePlugin.swift:29` | `0.15.8` | `getSDKVersion` method channel response |
| `packages/runanywhere/ios/Classes/RunAnywherePlugin.swift:31` | `0.1.4` | `getCommonsVersion` method channel response |
| `packages/runanywhere/android/src/main/kotlin/.../RunAnywherePlugin.kt:21` | `0.15.8` | `SDK_VERSION` companion const |
| `packages/runanywhere/android/src/main/kotlin/.../RunAnywherePlugin.kt:22` | `0.1.4` | `COMMONS_VERSION` companion const |
| `packages/runanywhere/ios/runanywhere.podspec:18` | `0.1.6` | `COMMONS_VERSION` — **differs from sdk_constants.dart!** |
| `packages/runanywhere/ios/runanywhere.podspec:35` | `0.16.0` | `s.version` — differs from `pubspec.yaml:0.19.7` |
| `packages/runanywhere/android/binary_config.gradle:27` | `0.1.6` | `commonsVersion` — differs from sdk_constants.dart `0.1.4` |
| `packages/runanywhere/android/binary_config.gradle:28` | `0.1.6` | `coreVersion` — differs from sdk_constants.dart `0.1.4` |
| `packages/runanywhere_llamacpp/ios/runanywhere_llamacpp.podspec:17` | `0.1.6` | `LLAMACPP_VERSION` |
| `packages/runanywhere_llamacpp/ios/runanywhere_llamacpp.podspec:35` | `0.16.0` | `s.version` |
| `packages/runanywhere_llamacpp/android/binary_config.gradle:19` | `0.1.6` | `coreVersion` |
| `packages/runanywhere_llamacpp/android/src/main/kotlin/.../LlamaCppPlugin.kt:21` | `0.1.4` | `BACKEND_VERSION` — differs from binary_config.gradle `0.1.6` |
| `packages/runanywhere_onnx/ios/runanywhere_onnx.podspec:22` | `0.1.6` | `ONNX_VERSION` |
| `packages/runanywhere_onnx/android/binary_config.gradle:19` | `0.1.6` | `coreVersion` |
| `packages/runanywhere_onnx/android/src/main/kotlin/.../OnnxPlugin.kt:21` | `0.1.4` | `BACKEND_VERSION` |
| `packages/runanywhere_genie/android/binary_config.gradle:20` | `0.3.0` | `genieVersion` — entirely separate version track |
| `packages/runanywhere_genie/android/src/main/kotlin/.../GeniePlugin.kt:21` | `0.1.6` | `BACKEND_VERSION` — differs from genieVersion `0.3.0` |
| `packages/runanywhere_genie/ios/Classes/GeniePlugin.swift:23` | `0.1.6` | `getBackendVersion` |
| `packages/runanywhere/lib/native/native_backend.dart:908` | `0.1.4` | Hardcoded `get version` return in `NativeBackend` |
| `packages/runanywhere_llamacpp/ios/Classes/LlamaCppPlugin.swift:24` | `0.1.4` | `getBackendVersion` |
| `packages/runanywhere_onnx/ios/Classes/OnnxPlugin.swift:22` | `0.1.4` | `getBackendVersion` |

**v2 single source of truth:** `vcpkg.json:4` (`"version": "2.0.0"`) plus `core/abi/ra_version.h` (defined in Phase 0 Agent E deliverables as `RA_ABI_VERSION 1`). `frontends/dart/pubspec.yaml:3` has `version: 2.0.0-dev.1` as the single Dart package version. No method channels expose version strings; no separate commonsVersion / coreVersion / backendVersion split exists.

---

## Per-backend packages — what collapses?

| v1 Flutter package | v1 role | v2 engine plugin | What collapses in v2 |
|--------------------|---------|------------------|----------------------|
| `runanywhere_llamacpp` (582 Dart LOC + Android Kotlin stub + iOS Swift stub + podspec + binary_config.gradle) | Dart wrapper that calls `rac_backend_llamacpp_register()` and routes `rac_llm_component_*` calls | `engines/llamacpp/` — `LlamaCppVTable` registered via `PluginRegistry::load_plugin()` (Android) or `register_static<LlamaCppEngine>()` (iOS) | The entire per-package concept. In v2 there is no `runanywhere_llamacpp` pub package; the engine is a CMake target. |
| `runanywhere_onnx` (739 Dart LOC + stubs + podspec + binary_config.gradle) | Dart wrapper for `rac_stt_onnx_*`, `rac_tts_onnx_*`, `rac_vad_onnx_*` | `engines/sherpa/` — `SherpaVTable` covering STT + TTS + VAD + wake word | All three ONNX bridges collapse into one vtable entry per primitive. No separate pub package. |
| `runanywhere_genie` (525 Dart LOC + Android Kotlin stub + iOS no-op stub + binary_config.gradle) | Dart wrapper for Qualcomm Genie NPU on Snapdragon Android | Future `engines/genie/` dlopen plugin (not in Phase 0-3 scope; genie is proprietary) | The iOS no-op stub and the Dart registration wrapper. The Android `.so` itself may persist but with a `PluginLoader<GenieVTable>` rather than a method channel. |

---

## Method channel stubs in iOS and Android dirs

All 8 method-channel stub files (4 iOS Swift + 4 Android Kotlin) handle only:
1. `getPlatformVersion` — Android OS / iOS version string
2. `getSDKVersion` / `getBackendVersion` — hardcoded string constant
3. `getCommonsVersion` — hardcoded string constant
4. `getSocModel` (Android `RunAnywherePlugin` only) — `Build.SOC_MODEL` / `Build.HARDWARE`

In v2, none of these exist:
- **Version strings**: Single source in `vcpkg.json` + `ra_version.h`.
- **SoC model**: `detect_hardware()` in `core/router/hardware_profile.cpp` runs in C++ and is available to Dart via the C ABI without a method channel.
- **Flutter method channel**: Dart FFI (`dart:ffi`) speaks directly to the C ABI. There is no Flutter method channel involved; `FlutterMethodChannel` is a message-passing layer that was only needed to reach native code before Dart FFI matured.

The `.so` loading (`System.loadLibrary("rac_commons")` etc.) in the Android `init {}` blocks is the one meaningful action these stubs perform. In v2 this is replaced by `DynamicLibrary.open()` in `frontends/dart/lib/adapter/voice_session.dart` (equivalent of `frontends/swift/Sources/RunAnywhere/Adapter/VoiceSession.swift`'s `OpaquePointer` call).

---

## Backwards-compat shims found

| Location | Shim | Notes |
|----------|------|-------|
| `packages/runanywhere/lib/native/ffi_types.dart:216` | `typedef RaResultCode = RacResultCode;` | Old `ra_*` prefix aliased to new `rac_*` prefix |
| `packages/runanywhere/lib/native/ffi_types.dart:1343-1344` | `typedef RaBackendHandle = RacHandle; typedef RaStreamHandle = RacHandle;` | Legacy handle names retained alongside new names |
| `packages/runanywhere/lib/native/ffi_types.dart:508-509` | `typedef RacLlmStreamCallbackNative = RacLlmComponentTokenCallbackNative; // unused - remove after migration` | Comment explicitly marks this as a migration shim |
| `packages/runanywhere/android/binary_config.gradle:22` | `testLocal = useLocalNatives // legacy alias` | `testLocal` kept as alias for `useLocalNatives` across all 4 `binary_config.gradle` files |
| `packages/runanywhere_genie/lib/genie.dart:45` | `export 'genie_error.dart';` | Re-export for backward compat noted in comment |
| `packages/runanywhere/lib/native/dart_bridge.dart:39` (comments) | "Matches Swift's `CppBridge` pattern exactly" | The entire DartBridge is explicitly designed as a port of the Swift CppBridge; it is itself a compat shim bridging to the v1 C++ ABI |
