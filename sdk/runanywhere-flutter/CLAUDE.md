# CLAUDE.md — RunAnywhere Flutter SDK

Verified state: 2026-05-11 against working tree on `feat/v2-architecture`.
For exhaustive file-by-file inventory, see `gaps/gaps/file organization/flutter.md`.

## Repository Structure

Melos-managed monorepo with 4 Flutter plugin packages that wrap the shared C++ core (`runanywhere-commons` / `RACommons`) via Dart FFI. No Flutter platform channels are used for AI operations — all inference routes through direct FFI calls.

```
sdk/runanywhere-flutter/
├── pubspec.yaml                # Dart workspace + Melos config
├── analysis_options.yaml       # Strict lint rules
├── scripts/package-sdk.sh      # Packaging/validation script
├── docs/                       # ARCHITECTURE.md, Documentation.md
└── packages/
    ├── runanywhere/            # Core SDK (FFI bridge, public API, events, models)
    ├── runanywhere_llamacpp/   # LlamaCpp backend (LLM + VLM)
    ├── runanywhere_onnx/       # Sherpa/ONNX Runtime backend (STT + TTS + VAD)
    └── runanywhere_genie/      # Qualcomm Genie NPU backend (LLM, Android-only)
```

Example app: `examples/flutter/RunAnywhereAI/`.

## Package Dependency Graph

```
runanywhere_llamacpp ──┐
runanywhere_onnx    ───┼──→ runanywhere (core)
runanywhere_genie   ───┘
```

All three backend packages depend on `runanywhere ^0.19.0`. The core package vendors `RACommons` (C++ library); backend packages vendor their own XCFrameworks/`.so` files.

## Development Commands

```bash
# From sdk/runanywhere-flutter/
melos bootstrap        # flutter pub get across the Dart workspace
melos run analyze      # flutter analyze --no-pub in all 4 packages
melos run format       # dart format in all 4 packages
melos run test         # flutter test in all 4 packages
melos run clean        # flutter clean in all 4 packages
melos version          # Bump versions + generate workspace CHANGELOG

./scripts/package-sdk.sh                      # Validate all packages (pub publish --dry-run)
./scripts/package-sdk.sh --natives-from PATH  # Stage native binaries then validate

# Example app (from examples/flutter/RunAnywhereAI/)
flutter pub get
flutter run                    # Run on connected device/emulator
flutter run -d <device-id>     # Run on specific device
flutter build apk | ios        # Build per-platform artifacts
```

## System Requirements

| Tool | Version |
|---|---|
| Flutter | 3.24.0+ |
| Dart | 3.5.0+ |
| iOS deployment target | 15.1+ |
| Android minSdk / compileSdk | 24 / 34 |
| Xcode | 15.0+ |
| Android NDK | **27.0.12077973** (`racFlutterNdkVersion` in root `gradle.properties`) |

## Architecture Overview

### Layer Stack

```
Flutter Application
    ↓
RunAnywhereSDK.instance              (Public singleton; 20 capability accessors)
    ↓
public/capabilities/* (20 classes)   (RunAnywhereLLM, RunAnywhereSTT, etc.)
    ↓
lib/native/dart_bridge_*.dart (33)   (DartBridge slice per C++ subsystem)
    ↓
NativeFunctions + PlatformLoader     (Cached FFI lookups + DynamicLibrary load)
    ↓
RACommons (C++ core)                 (ModuleRegistry, ServiceRegistry, EventPublisher)
    ↓
LlamaCpp | Sherpa/ONNX | Genie NPU   (Backend engines registered via vtable v3)
```

### Key Architectural Patterns

1. **Proto-driven public surface.** All public API types (LLM/STT/TTS/VAD/VLM/voice/RAG/tools/etc.) are protobuf-generated. 104 `.pb*.dart` files live under `lib/generated/`. Never hand-edit.
2. **Isolate-per-FFI-call for blocking ops.** Capability layer + bridge slices wrap blocking C calls in `Isolate.run` (LLM generate, TTS synthesize, VLM process, voice agent turns, tool calls, downloads, HTTP, platform probes). Streaming uses **`NativeCallable.listener`** with a broadcast `StreamController` for fan-out (`dart:async`, never rxdart).
3. **Two-phase SDK init.** Phase 1 (sync): library load → register `rac_platform_adapter_t` → `rac_sdk_init` → configure logging → register events/device/file-manager/telemetry callbacks. Phase 2 (async, fire-and-forget): device registration + authentication + model assignment + telemetry flush. Offline inference works without Phase 2.
4. **Platform HTTP transport injection.** iOS registers a URLSession-backed `rac_http_transport_ops_t` vtable from ObjC++; Android registers an OkHttp-backed vtable via JNI. C++ uses the installed transport for all HTTP.
5. **EventBus = pure `dart:async`.** `lib/public/events/event_bus.dart` is a `StreamController.broadcast()` singleton. rxdart is **not** a dependency.
6. **Secure storage vtable.** C++ auth manager calls Dart secure storage callbacks synchronously via a `_secureCache` map; Dart side wraps `flutter_secure_storage`.
7. **Hand-written FFI bindings.** No `ffigen` is used. `lib/core/native/rac_native.dart` (~2.1K LOC) plus `lib/native/native_functions.dart` (~380 LOC cached lookup registry) define every C ABI binding.

### Native Library Loading

| Platform | Mechanism |
|---|---|
| iOS | `RACommons.xcframework` (static); `DynamicLibrary.process()` → symbols in main binary |
| Android | `DynamicLibrary.open('librac_commons.so')`; fallback `librunanywhere_jni.so` |
| macOS | `process()` → `executable()` → explicit dylib path (3rd `RACommons.xcframework` slice supports unit tests) |

iOS requires `use_frameworks! :linkage => :static` in the Podfile and `-all_load` / `DEAD_CODE_STRIPPING=NO` linker flags (set in each podspec).

## Core Package (`packages/runanywhere/`)

### Entry Point

```dart
// lib/public/runanywhere.dart  (singleton)
await RunAnywhereSDK.instance.initialize(
  apiKey: 'optional',
  baseURL: 'optional',
  environment: SDKEnvironment.development, // or staging, production
);

// 20 capability accessors (lazy singletons)
RunAnywhereSDK.instance.llm       // RunAnywhereLLM
RunAnywhereSDK.instance.stt       // RunAnywhereSTT
RunAnywhereSDK.instance.tts       // RunAnywhereTTS
RunAnywhereSDK.instance.vad       // RunAnywhereVAD
RunAnywhereSDK.instance.vlm       // RunAnywhereVLM
RunAnywhereSDK.instance.vlmModels // RunAnywhereVLMModels
RunAnywhereSDK.instance.voice     // RunAnywhereVoice
RunAnywhereSDK.instance.voiceAgent // RunAnywhereVoiceAgent
RunAnywhereSDK.instance.models    // RunAnywhereModels
RunAnywhereSDK.instance.modelLifecycle // RunAnywhereModelLifecycle
RunAnywhereSDK.instance.downloads // RunAnywhereDownloads
RunAnywhereSDK.instance.tools     // RunAnywhereTools
RunAnywhereSDK.instance.rag       // RunAnywhereRAG
RunAnywhereSDK.instance.solutions // RunAnywhereSolutions
RunAnywhereSDK.instance.diffusion // RunAnywhereDiffusion
RunAnywhereSDK.instance.embeddings // RunAnywhereEmbeddings
RunAnywhereSDK.instance.lora      // RunAnywhereLoRACapability
RunAnywhereSDK.instance.hardware  // RunAnywhereHardware
// + RunAnywherePluginLoader
```

### Source Layout

```
packages/runanywhere/lib/
├── runanywhere.dart              # Barrel (271 LOC, ~150 re-exports)
├── runanywhere_protos.dart       # Proto re-export hub
├── adapters/                     # http_client_adapter, model_download_adapter, voice_agent_stream_adapter
├── core/
│   ├── module/runanywhere_module.dart  # Module interface implemented by backends
│   └── native/rac_native.dart    # Hand-written FFI bindings (~2.1K LOC)
├── data/network/                 # Network config struct + barrel
├── features/
│   ├── stt/services/audio_capture_manager.dart   # 16kHz mono Int16 via package:record
│   └── tts/services/audio_playback_manager.dart  # PCM playback via audioplayers
├── foundation/
│   ├── constants/                # sdk_constants.dart
│   ├── dependency_injection/     # service_container.dart
│   ├── errors/                   # sdk_exception.dart (40+ factory constructors)
│   ├── logging/                  # sdk_logger.dart
│   └── security/                 # keychain_manager.dart + secure_storage_keys.dart
├── generated/                    # 104 protobuf-generated files (DO NOT EDIT)
├── internal/                     # sdk_init.dart, sdk_state.dart
├── native/                       # 33 dart_bridge_*.dart slices + native_functions + platform_loader + types/ + type_conversions/
└── public/
    ├── runanywhere.dart          # RunAnywhereSDK singleton (~513 LOC)
    ├── capabilities/             # 20 capability classes (flat layout)
    ├── configuration/            # sdk_environment.dart
    ├── events/                   # event_bus.dart (dart:async)
    └── extensions/               # rag_module, runanywhere_logging, _storage, _structured_output, _thinking_utils
```

**Not present (do not search for):** no top-level `lib/capabilities/`, no `lib/infrastructure/`, no `core/types/model_types.dart`, no `dart_bridge_llm_streaming.dart`, no `native_backend.dart`.

### 33 DartBridge Slices (`lib/native/`)

`dart_bridge.dart` (coordinator) + slices for: **auth, dev_config, device, diffusion, download, embeddings, environment, events, file_manager, hardware, http, llm, lora, model_assignment, model_format, model_lifecycle, model_paths, model_registry, platform, platform_services, plugin_loader, proto_utils, rag, solutions, state, storage, stt, telemetry, tool_calling, tts, vad, vlm, voice_agent**.

Supporting: `native_functions.dart` (cached lookup registry), `platform_loader.dart` (per-platform `DynamicLibrary`), `types/` (8 struct/typedef bundles imported directly), `type_conversions/` (proto ↔ C struct mappers).

### iOS Plumbing (`packages/runanywhere/ios/`)

| File | Role |
|---|---|
| `Classes/RunAnywherePlugin.swift` | Flutter plugin entry; calls `URLSessionHttpTransport.register()` before Dart FFI fires HTTP |
| `Classes/URLSessionHttpTransport.swift` | Swift façade; `@_silgen_name("ra_flutter_register_urlsession_transport")`, idempotent |
| `Classes/URLSessionHttpTransport.mm` | ObjC++ vtable wiring; owns static `rac_http_transport_ops_t` + URLSession machinery |
| `Classes/RACommons.exports` | Symbol exports list controlling linker visibility from `RACommons.xcframework` |
| `Frameworks/RACommons.xcframework` | Vendored static archive — **3 slices**: `ios-arm64`, `ios-arm64-simulator`, `macos-arm64` |
| `runanywhere.podspec` | iOS 15.1+; `-lc++ -larchive -lbz2 -lz -ObjC -all_load -Wl,-export_dynamic`; `DEAD_CODE_STRIPPING=NO` |

### Android Plumbing (`packages/runanywhere/android/`)

| File | Role |
|---|---|
| `src/main/kotlin/ai/runanywhere/sdk/RunAnywherePlugin.kt` | Flutter plugin; static `init {}` registers OkHttp transport via JNI before FFI HTTP fires |
| `src/main/kotlin/com/runanywhere/sdk/native/bridge/RunAnywhereBridge.kt` | JNI shim; `System.loadLibrary("runanywhere_jni")` |
| `src/main/kotlin/com/runanywhere/sdk/foundation/http/OkHttpTransport.kt` | OkHttp 4.12 vtable backing `rac_http_request_*`; 30s/120s/60s timeouts, 32 KB streaming chunks |
| `build.gradle` | NDK `27.0.12077973`, AGP 8.1.0, Kotlin 1.9.10, ABIs: arm64-v8a, armeabi-v7a, x86_64 |
| `binary_config.gradle` | `testLocal` toggle + GitHub-release URL + checksum |

## Backend Packages

### `runanywhere_llamacpp` — LLM + VLM

- `await LlamaCpp.register()` → FFI `rac_backend_llamacpp_register()` + `rac_backend_llamacpp_vlm_register()`
- Model format: `.gguf` extension
- Constants: `version='2.0.0'`, `llamaCppVersion='b7199'`
- iOS: `RABackendLLAMACPP.xcframework` (static `.a`); weak-links Metal/MetalKit/MetalPerformanceShaders
- Android: ships `librac_backend_llamacpp.so`, `librac_backend_llamacpp_jni.so`, `libc++_shared.so` per ABI

### `runanywhere_onnx` — STT + TTS + VAD

- `await Onnx.register()` → FFI `rac_backend_onnx_register()`; Sherpa auto-registers STT/TTS/VAD via ELF constructor
- Model detection: `whisper`/`zipformer`/`paraformer` (STT), `piper`/`vits` (TTS), always handles VAD
- Constants: `version='2.0.0'`, `onnxRuntimeVersion='1.23.2'`
- Custom downloader: `OnnxDownloadStrategy` handles `.tar.bz2` archives via `rac_extract_archive_native`
- iOS: `RABackendONNX.xcframework` (vendored), `RABackendSherpa.xcframework` (present but not in podspec)
- Android: 8 `.so` per ABI (`libonnxruntime`, `libsherpa-onnx-{c-api,cxx-api,jni}`, `librac_backend_{onnx,onnx_jni,sherpa}`, `libc++_shared`); declares `RECORD_AUDIO` permission; load order: `onnxruntime` → `sherpa-onnx-c-api` → backends

### `runanywhere_genie` — Qualcomm NPU LLM (Android-only)

- `await Genie.register(priority: 200)` → FFI `rac_backend_genie_register()`
- Capabilities dynamic; only registers on Snapdragon devices (`checkAvailability()`)
- iOS: pod exists for plugin registration only — no xcframework, no `runanywhere` dependency
- Android: ships only `libc++_shared.so`; backend `.so` downloaded from private release URL (may fail silently)
- Closed-source backend; not committed to repo

## Generated Code

`packages/runanywhere/lib/generated/` contains **104 `.pb*.dart` files** generated by `protoc` + `protoc-gen-dart` from `idl/*.proto`. Excluded from analyzer. Do not hand-edit.

26 proto schemas with full codegen (4 files each — `.pb.dart`, `.pbenum.dart`, `.pbjson.dart`, `.pbserver.dart`): `chat`, `component_types`, `diffusion_options`, `download_service`, `embeddings_options`, `errors`, `hardware_profile`, `lifecycle_service`, `llm_options`, `llm_service`, `lora_options`, `model_types`, `pipeline`, `rag`, `sdk_events`, `solutions`, `storage_types`, `structured_output`, `stt_options`, `thinking_tag_pattern`, `tool_calling`, `tts_options`, `vad_options`, `vlm_options`, `voice_agent_service`, `voice_events`.

**Missing Dart codegen** (drift items as of 2026-05-11): `idl/sdk_init.proto`, `idl/rac_options.proto`, `idl/router.proto` — no `.pb*.dart` outputs yet.

## Data Flows

### LLM Generation
1. `RunAnywhereSDK.instance.llm.generate(prompt, options)` → `RunAnywhereLLM.shared.generate()`
2. Validates `SdkState.isInitialized`, `DartBridge.llm.isLoaded`
3. `DartBridge.llm.generate()` runs the blocking C call inside `Isolate.run()`; handle address passed as `int`
4. Returns `LLMGenerationResult` proto

### LLM Streaming
1. `RunAnywhereSDK.instance.llm.generateStream(prompt, options)` registers a `NativeCallable.listener` for C++ token callbacks
2. Tokens land in a broadcast `StreamController` emitting `LLMStreamEvent` protos
3. Multiple subscribers share one C-callback registration (fan-out)

### Model Download
1. `RunAnywhereSDK.instance.downloads.start(modelId)` → `ModelDownloadService.downloadModel()`
2. `DartBridgeDownload.orchestrateDownload()` returns a `taskId`
3. Polls `DartBridgeDownload.getProgress(taskId)` every 250 ms
4. On completion: resolves model path via `rac_model_paths_get_model_folder`; updates registry

### SDK Initialization
1. `RunAnywhereSDK.instance.initialize()` runs Phase 1 synchronously: load native lib → register platform adapter → configure logging → `rac_sdk_init` → register events / device / file-manager / telemetry callbacks
2. Phase 2 (async): model assignment → platform services → telemetry flush
3. `DartBridge.modelPaths.setBaseDirectory()` sets the model storage root
4. Background fire-and-forget: device registration + authentication

## Lint Rules

Extends `package:flutter_lints/flutter.yaml` with:
- Strict mode: `strict-casts`, `strict-inference`, `strict-raw-types`
- Errors: `dead_code`, `unused_import`, `unused_local_variable`, `unused_element`, `unused_field`
- Warnings: `avoid_dynamic_calls`, `avoid_print`, `prefer_const_constructors`, `prefer_final_locals`
- Excluded: `**/*.g.dart`, `**/*.freezed.dart`, `lib/generated/**`

## Native Binary Inventory

### iOS XCFrameworks (static archives)

| Package | Framework | Slices |
|---|---|---|
| `runanywhere` | `RACommons.xcframework` | `ios-arm64`, `ios-arm64-simulator`, `macos-arm64` |
| `runanywhere_llamacpp` | `RABackendLLAMACPP.xcframework` | `ios-arm64`, `ios-arm64-simulator` |
| `runanywhere_onnx` | `RABackendONNX.xcframework` | `ios-arm64`, `ios-arm64-simulator` |
| `runanywhere_onnx` | `RABackendSherpa.xcframework` (present, not vendored in podspec) | `ios-arm64`, `ios-arm64-simulator` |
| `runanywhere_genie` | — | none |

### Android Shared Libraries (per ABI: arm64-v8a, armeabi-v7a, x86_64)

| Package | Libraries |
|---|---|
| `runanywhere` | `librac_commons.so`, `librunanywhere_jni.so`, `libc++_shared.so`, `libomp.so` |
| `runanywhere_llamacpp` | `librac_backend_llamacpp.so`, `librac_backend_llamacpp_jni.so`, `libc++_shared.so` |
| `runanywhere_onnx` | `libonnxruntime.so`, `libsherpa-onnx-c-api.so`, `libsherpa-onnx-cxx-api.so`, `libsherpa-onnx-jni.so`, `librac_backend_onnx.so`, `librac_backend_onnx_jni.so`, `librac_backend_sherpa.so`, `libc++_shared.so` |
| `runanywhere_genie` | `libc++_shared.so` only (backend `.so` downloaded separately) |

## Versions

| Package / Artifact | Version |
|---|---|
| `runanywhere` (Dart package) | 0.19.13 |
| `runanywhere_llamacpp` | 0.19.13 |
| `runanywhere_onnx` | 0.19.13 |
| `runanywhere_genie` | 0.19.13 |
| `RACommons` native | 0.1.6 |
| Genie native | 0.3.0 |
| llama.cpp engine | b7199 |
| ONNX Runtime | 1.23.2 |
| Canonical version source | `sdk/runanywhere-commons/VERSION` (0.19.13) |
