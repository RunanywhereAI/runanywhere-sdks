# CLAUDE.md — RunAnywhere Flutter SDK

## Repository Structure

This is a **Melos-managed monorepo** containing four Flutter plugin packages that wrap a shared C++ native library (`runanywhere-commons` / `RACommons`) via Dart FFI. No Flutter platform channels are used for AI operations — all inference routes through direct FFI calls.

```
sdk/runanywhere-flutter/
├── pubspec.yaml                # Dart workspace + Melos config (4 packages, 4 scripts)
├── analysis_options.yaml       # Shared lint rules (strict-casts, strict-inference)
├── scripts/package-sdk.sh      # Packaging/validation script
├── docs/
│   ├── ARCHITECTURE.md         # Layer diagrams, data flows, binary inventory
│   └── Documentation.md        # Full public API reference
└── packages/
    ├── runanywhere/            # Core SDK (FFI bridge, public API, events, models)
    ├── runanywhere_llamacpp/   # LlamaCpp backend (LLM + VLM)
    ├── runanywhere_onnx/       # ONNX Runtime backend (STT + TTS + VAD)
    └── runanywhere_genie/      # Qualcomm Genie NPU backend (LLM, Android-only, experimental)
```

**Example app**: `examples/flutter/RunAnywhereAI/` — full demo with chat, voice, VLM camera, RAG, structured output, solutions, tool calling.

## Package Dependency Graph

```
runanywhere_llamacpp ──┐
runanywhere_onnx    ───┼──→ depends on: runanywhere (core)
runanywhere_genie   ───┘    (experimental, Android-only NPU)
```

All three backend packages depend on `runanywhere ^0.19.0`. The core package vendors `RACommons` (C++ library), backend packages vendor their own XCFrameworks/`.so` files.

## Development Commands

```bash
# Melos commands (from sdk/runanywhere-flutter/)
melos bootstrap        # flutter pub get for the Dart workspace
melos run analyze      # flutter analyze --no-pub in all 4 packages
melos run format       # dart format in all 4 packages
melos run test         # flutter test in all 4 packages
melos run clean        # flutter clean in all 4 packages
melos version          # Bump versions + generate workspace CHANGELOG

# Packaging script
./scripts/package-sdk.sh                      # Validate all packages (pub publish --dry-run)
./scripts/package-sdk.sh --natives-from PATH  # Stage native binaries from PATH, then validate

# Example app (from examples/flutter/RunAnywhereAI/)
flutter pub get
flutter run                    # Run on connected device/emulator
flutter run -d <device-id>     # Run on specific device
flutter build apk              # Build Android APK
flutter build ios              # Build iOS
```

## System Requirements

- Flutter 3.24.0+
- Dart 3.5.0+
- iOS 15.1+ deployment target (podspec), 14.0+ minimum supported
- Android API 24+ (minSdk), compileSdk 34
- Xcode 15.0+
- NDK 25.2.9519653 (for Android native builds)

## Architecture Overview

### Layer Stack

```
Flutter Application
    ↓
RunAnywhereSDK.instance (Singleton)  →  Capability accessors (.llm, .stt, .tts, .vad, .vlm, .voice, .rag, ...)
    ↓
DartBridge (Static coordinator)  →  DartBridgeLLM, DartBridgeSTT, DartBridgeTTS, DartBridgeVAD, DartBridgeVLM, ...
    ↓
NativeFunctions / PlatformLoader   →  Dart FFI (ffi package) → DynamicLibrary
    ↓
RACommons (C++ library)  →  ModuleRegistry, ServiceRegistry, EventPublisher
    ↓
LlamaCPP Backend  |  ONNX/Sherpa Backend  |  Genie NPU Backend
```

### Key Architectural Patterns

1. **Isolate-per-FFI-call**: LLM, STT, TTS, VLM all run blocking C FFI calls in `Isolate.run()` or `Isolate.spawn()`. Handle addresses passed as `int` between isolates.
2. **Proto types as canonical wire types**: All public API returns protobuf-generated types (`LLMGenerationResult`, `STTOutput`, `TTSOutput`, etc.). Generated from IDL into `lib/generated/`.
3. **Two-phase SDK initialization**: Phase 1 (sync): library load + platform adapter + C++ config. Phase 2 (async, fire-and-forget): device registration + authentication. Offline inference works without Phase 2.
4. **Platform HTTP transport injection**: iOS registers URLSession (ObjC++ vtable), Android registers OkHttp (JNI). C++ uses the installed transport for all HTTP.
5. **NativeCallable.listener for streaming**: Thread-safe callbacks from C++ background threads for proto event streaming.
6. **Secure storage vtable**: C++ auth manager calls Dart secure storage callbacks synchronously via `_secureCache` map.

### Native Library Loading

| Platform | Core Library | Method |
|---|---|---|
| iOS | `RACommons.xcframework` (static) | `DynamicLibrary.executable()` — symbols in main binary |
| Android | `librac_commons.so` | `DynamicLibrary.open('librac_commons.so')` then fallback to `librunanywhere_jni.so` |
| macOS | varies | `process()` → `executable()` → explicit dylib path |

iOS requires `use_frameworks! :linkage => :static` in Podfile and `-all_load` / `DEAD_CODE_STRIPPING=NO` linker flags (set in podspecs).

## Core Package (`packages/runanywhere/`)

### Entry Point: `RunAnywhereSDK` (singleton)

**File**: `lib/public/runanywhere_v4.dart`

```dart
// Initialization
await RunAnywhereSDK.instance.initialize(
  apiKey: 'optional',
  baseURL: 'optional',
  environment: SDKEnvironment.development, // or staging, production
);

// Capability accessors (lazy singletons)
RunAnywhereSDK.instance.llm       // RunAnywhereLLM
RunAnywhereSDK.instance.stt       // RunAnywhereSTT
RunAnywhereSDK.instance.tts       // RunAnywhereTTS
RunAnywhereSDK.instance.vad       // RunAnywhereVAD
RunAnywhereSDK.instance.vlm       // RunAnywhereVLM
RunAnywhereSDK.instance.voice     // RunAnywhereVoice
RunAnywhereSDK.instance.models    // RunAnywhereModels
RunAnywhereSDK.instance.downloads // RunAnywhereDownloads
RunAnywhereSDK.instance.tools     // RunAnywhereTools
RunAnywhereSDK.instance.rag       // RunAnywhereRAG
RunAnywhereSDK.instance.solutions // RunAnywhereSolutions
RunAnywhereSDK.instance.voiceAgent // RunAnywhereVoiceAgent
RunAnywhereSDK.instance.diffusion  // RunAnywhereDiffusion
RunAnywhereSDK.instance.lora       // RunAnywhereLoRACapability
RunAnywhereSDK.instance.hardware   // RunAnywhereHardware
```

### Source Organization

```
packages/runanywhere/lib/
├── runanywhere.dart              # Barrel file (150+ re-exports)
├── public/
│   ├── runanywhere_v4.dart       # RunAnywhereSDK singleton
│   ├── capabilities/             # RunAnywhereLLM, RunAnywhereSTT, RunAnywhereTTS, etc.
│   ├── events/                   # EventBus (8 typed broadcast controllers), SDKEvent hierarchy
│   └── configuration/            # SDKEnvironment, SDKInitParams
├── core/
│   ├── types/model_types.dart    # ModelInfo, InferenceFramework, ModelCategory, ModelFormat enums
│   └── native/rac_native.dart    # RacBindings (HTTP, download, model registry FFI)
├── native/
│   ├── dart_bridge.dart          # DartBridge static coordinator (8-step Phase 1, 4-step Phase 2)
│   ├── platform_loader.dart      # PlatformLoader: loads DynamicLibrary per platform
│   ├── native_functions.dart     # NativeFunctions: all FFI function pointers as static finals
│   ├── native_backend.dart       # NativeBackend: high-level wrapper for sub-packages
│   ├── ffi_types.dart            # Barrel for native/types/
│   ├── types/                    # RacHandle, result codes, struct types (LLM, STT, TTS, VLM, tools)
│   ├── dart_bridge_llm.dart      # LLM generate/stream via Isolate.run/Isolate.spawn
│   ├── dart_bridge_llm_streaming.dart  # Proto streaming path check
│   ├── dart_bridge_stt.dart      # STT transcribe via Isolate.run
│   ├── dart_bridge_tts.dart      # TTS synthesize via Isolate.run
│   ├── dart_bridge_vad.dart      # VAD process (synchronous, no isolate)
│   ├── dart_bridge_vlm.dart      # VLM processImage via Isolate.run/Isolate.spawn
│   ├── dart_bridge_auth.dart     # Auth with secure storage vtable bridge
│   ├── dart_bridge_device.dart   # Device registration with pending-HTTP-POST pattern
│   ├── dart_bridge_events.dart   # C++ event callback → SDKEvent stream
│   ├── dart_bridge_lora.dart     # LoRA load/remove/registry
│   ├── dart_bridge_model_paths.dart  # Model folder resolution
│   ├── dart_bridge_storage.dart  # Key-value storage bridge
│   └── dart_bridge_tool_calling.dart  # Tool call parsing via C++
├── adapters/
│   ├── llm_stream_adapter.dart   # LLMStreamAdapter with NativeCallable.listener fan-out
│   └── model_download_adapter.dart  # ModelDownloadService: orchestrate + poll every 250ms
├── features/                     # STT audio capture, TTS playback, voice session, structured output
├── foundation/
│   ├── error_types/sdk_exception.dart  # SDKException with 40+ factory constructors
│   └── dependency_injection/service_container.dart  # HTTP client + telemetry setup
├── internal/
│   ├── sdk_state.dart            # SdkState: isInitialized, registeredModels, hasRunDiscovery
│   └── sdk_init.dart             # Background helpers: registerDevice, authenticate, runDiscovery
├── infrastructure/               # Device, download, events, file services
├── data/                         # Network layer
├── capabilities/                 # Voice session handling
└── generated/                    # Protobuf-generated types (DO NOT EDIT)
```

### iOS Platform Code

- `ios/Classes/RunAnywherePlugin.swift` — Registers URLSession HTTP transport
- `ios/Classes/URLSessionHttpTransport.swift` — Swift enum calling ObjC++ `@_silgen_name` functions
- `ios/Classes/URLSessionHttpTransport.mm` — ObjC++ vtable wiring
- `ios/runanywhere.podspec` — Vendors `RACommons.xcframework`, links `-lc++ -larchive -lbz2 -lz`

### Android Platform Code

- `android/src/.../RunAnywherePlugin.kt` — Registers OkHttp HTTP transport via JNI
- `android/src/.../RunAnywhereBridge.kt` — `System.loadLibrary("runanywhere_jni")`
- `android/src/.../OkHttpTransport.kt` — Blocking OkHttp calls + streaming chunk delivery
- `android/build.gradle` — Downloads `.so` from GitHub releases when `testLocal=false`
- `android/CMakeLists.txt` — Builds `flutter_rag_bridge` shared library linking against `rac_commons`

### Binary Source Toggle (Local vs Remote)

- **Android**: `binary_config.gradle` → `useLocalNatives` (default `true`). Set `false` to download from GitHub releases.
- **iOS**: `.testlocal` marker file in `ios/` directory. Presence = use local frameworks.

## Backend Packages

### `runanywhere_llamacpp` (LLM + VLM)

**Capabilities**: `SDKComponent.llm`, `SDKComponent.vlm`
**Registration**: `await LlamaCpp.register()` → FFI `rac_backend_llamacpp_register()` + `rac_backend_llamacpp_vlm_register()`
**Model detection**: `.gguf` extension
**Constants**: `version = '2.0.0'`, `llamaCppVersion = 'b7199'`

```dart
LlamaCpp.addModel(
  id: 'my-model',
  name: 'My Model',
  url: 'https://huggingface.co/.../model.Q4_K_M.gguf',
  memoryRequirement: 4000000000,
  supportsThinking: false,
);
```

**iOS**: Vendors `RABackendLLAMACPP.xcframework` (static `.a`). Weak-links Metal, MetalKit, MetalPerformanceShaders.
**Android**: Ships `librac_backend_llamacpp.so` + `librac_backend_llamacpp_jni.so` per ABI.

### `runanywhere_onnx` (STT + TTS + VAD)

**Capabilities**: `SDKComponent.stt`, `SDKComponent.tts`, `SDKComponent.vad`
**Registration**: `await Onnx.register()` → FFI `rac_backend_onnx_register()`
**Model detection**: Contains `whisper`/`zipformer`/`paraformer` (STT), `piper`/`vits` (TTS), always handles VAD
**Constants**: `version = '2.0.0'`, `onnxRuntimeVersion = '1.23.2'`
**Custom download**: `OnnxDownloadStrategy` handles `.tar.bz2` archives and direct `.onnx` files with native extraction via `rac_extract_archive_native`.

```dart
Onnx.addModel(
  id: 'my-stt-model',
  name: 'My STT Model',
  url: 'https://...',
  modality: ModelCategory.speechRecognition,
);
```

**iOS**: Vendors `RABackendONNX.xcframework` (ONNX Runtime statically linked in). Links `-lc++ -larchive -lbz2 -lz`. `RABackendSherpa.xcframework` present but not in podspec vendored_frameworks.
**Android**: Ships `libonnxruntime.so`, `libsherpa-onnx-c-api.so`, `librac_backend_onnx.so`, `librac_backend_sherpa.so` + more per ABI (9 `.so` files each). Declares `RECORD_AUDIO` permission.
**Android load order**: `libonnxruntime.so` → `libsherpa-onnx-c-api.so` → `librac_backend_onnx.so` → `librac_backend_sherpa.so` (constructor auto-registers Sherpa STT/TTS/VAD).

### `runanywhere_genie` (NPU LLM, Android-only)

**Capabilities**: Dynamic — `{SDKComponent.llm}` only when registered on Snapdragon device
**Registration**: `await Genie.register(priority: 200)` → FFI `rac_backend_genie_register()`
**Model detection**: Contains `genie` or `npu`
**Platform guard**: `checkAvailability()` returns `false` on non-Android
**Closed-source**: No native `.so` committed to repo. Download may fail silently (build continues).

**iOS**: Pod exists for Flutter plugin registration only. No xcframework, no `runanywhere` dependency.
**Android**: Ships only `libc++_shared.so`. Backend `.so` downloaded from private release URL.

## Data Flows

### LLM Generation
1. `RunAnywhereSDK.instance.llm.generate(prompt, options)` → `RunAnywhereLLM.shared.generate()`
2. Validates `SdkState.isInitialized`, `DartBridge.llm.isLoaded`
3. `DartBridge.llm.generate()` → passes handle address + params to `Isolate.run()`
4. In isolate: `PlatformLoader.loadCommons()` → lookup `rac_llm_component_generate` → call with `RacLlmOptionsStruct`
5. Returns `LLMGenerationResult` proto

### LLM Streaming
1. `RunAnywhereSDK.instance.llm.generateStream(prompt, options)` → checks proto streaming availability
2. Struct fallback path: `DartBridge.llm.generateStream()` uses `Isolate.spawn` with `ReceivePort`
3. C++ calls token/complete/error callbacks → tokens sent to main isolate via `SendPort`
4. Main isolate emits `LLMStreamEvent` on `StreamController.broadcast()`

### Model Download
1. `RunAnywhereSDK.instance.downloads.start(modelId)` → `ModelDownloadService.downloadModel()`
2. `DartBridgeDownload.orchestrateDownload()` → returns `taskId`
3. Polls `DartBridgeDownload.getProgress(taskId)` every 250ms
4. On completion: resolves model path via `rac_model_paths_get_model_folder`, updates registry

### SDK Initialization
1. `RunAnywhereSDK.instance.initialize()` → Phase 1 (sync): load native lib → register platform adapter → configure logging → `rac_sdk_init` → register events callback → telemetry → device callbacks → file manager
2. Phase 2 (async services): state init → model assignment → platform services → telemetry flush
3. `DartBridge.modelPaths.setBaseDirectory()` → set model storage root
4. Background (fire-and-forget): device registration + authentication

## Generated Code

**`packages/runanywhere/lib/generated/`** contains protobuf-generated Dart files. DO NOT EDIT these files. They include:
- `chat.pb.dart`, `llm_options.pb.dart`, `llm_service.pb.dart` — LLM types
- `stt_options.pb.dart`, `tts_options.pb.dart`, `vad_options.pb.dart` — Speech types
- `vlm_options.pb.dart` — Vision types
- `model_types.pb.dart`, `download_service.pb.dart` — Model management types
- `voice_events.pb.dart`, `voice_agent_service.pb.dart` — Voice pipeline types
- `sdk_events.pb.dart`, `errors.pb.dart` — Event and error types
- `pipeline.pb.dart`, `solutions.pb.dart` — Pipeline/solutions types
- `rag.pb.dart`, `embeddings_options.pb.dart` — RAG types
- `tool_calling.pb.dart`, `structured_output.pb.dart` — Tool use types
- `lora_options.pb.dart`, `diffusion_options.pb.dart` — LoRA and diffusion types
- `hardware_profile.pb.dart`, `storage_types.pb.dart` — Infrastructure types
- Plus corresponding `.pbenum.dart`, `.pbjson.dart`, `.pbserver.dart` files

## Example App (`examples/flutter/RunAnywhereAI/`)

Feature-complete demo with Provider state management showing:

| Feature | Files |
|---|---|
| Chat (LLM) | `features/chat/chat_interface_view.dart`, `tool_call_views.dart` |
| Voice Assistant | `features/voice/voice_assistant_view.dart` |
| Speech-to-Text | `features/voice/speech_to_text_view.dart` |
| Text-to-Speech | `features/voice/text_to_speech_view.dart` |
| Vision (VLM) | `features/vision/vision_hub_view.dart`, `vlm_camera_view.dart`, `vlm_view_model.dart` |
| RAG | `features/rag/rag_demo_view.dart`, `rag_view_model.dart`, `document_service.dart` |
| Model Management | `features/models/models_view.dart`, `model_list_view_model.dart`, `add_model_from_url_view.dart` |
| Settings | `features/settings/combined_settings_view.dart`, `tool_settings_view_model.dart` |
| Structured Output | `features/structured_output/structured_output_view.dart` |
| Solutions | `features/solutions/solutions_view.dart` |
| Tool Calling | `features/tools/tools_view.dart` |

**SDK initialization in example**: `runanywhere_ai_app.dart` → `_initializeSDK()` (reads custom API key/URL from keychain) → `_registerModulesAndModels()` (registers LlamaCpp with 9 LLM models, Genie NPU models per chip, VLM model, Sherpa STT/TTS models, system TTS, ONNX embeddings, ONNX backend, RAG backend).

**Running the example**:
```bash
cd examples/flutter/RunAnywhereAI/
flutter pub get
flutter run  # on connected device
```

## Lint Rules

Extends `package:flutter_lints/flutter.yaml` with:
- **Strict mode**: `strict-casts`, `strict-inference`, `strict-raw-types` all enabled
- **Errors**: `dead_code`, `unused_import`, `unused_local_variable`, `unused_element`, `unused_field`
- **Warnings**: `avoid_dynamic_calls`, `avoid_print`, `prefer_const_constructors`, `prefer_final_locals`
- Generated files excluded: `**/*.g.dart`, `**/*.freezed.dart`, `lib/generated/**`

## Native Binary Inventory

### iOS XCFrameworks (static archives)

| Package | Framework | Slices |
|---|---|---|
| `runanywhere` | `RACommons.xcframework` | `ios-arm64`, `ios-arm64-simulator` |
| `runanywhere_llamacpp` | `RABackendLLAMACPP.xcframework` | `ios-arm64`, `ios-arm64-simulator` |
| `runanywhere_onnx` | `RABackendONNX.xcframework` | `ios-arm64`, `ios-arm64-simulator` |
| `runanywhere_onnx` | `RABackendSherpa.xcframework` (repo-only) | `ios-arm64`, `ios-arm64-simulator` |

### Android Shared Libraries (per ABI: arm64-v8a, armeabi-v7a, x86_64)

| Package | Libraries |
|---|---|
| `runanywhere` | `librac_commons.so`, `librunanywhere_jni.so`, `libc++_shared.so`, `libomp.so` |
| `runanywhere_llamacpp` | `librac_backend_llamacpp.so`, `librac_backend_llamacpp_jni.so`, `libc++_shared.so` |
| `runanywhere_onnx` | `libonnxruntime.so`, `libsherpa-onnx-c-api.so`, `libsherpa-onnx-cxx-api.so`, `libsherpa-onnx-jni.so`, `librac_backend_onnx.so`, `librac_backend_onnx_jni.so`, `librac_backend_sherpa.so`, `libc++_shared.so` |
| `runanywhere_genie` | `libc++_shared.so` only (backend `.so` downloaded separately) |

### Approximate Binary Sizes

| Package | iOS | Android |
|---|---|---|
| `runanywhere` | ~5 MB | ~3 MB |
| `runanywhere_llamacpp` | ~15–25 MB | ~10–15 MB |
| `runanywhere_onnx` | ~50–70 MB | ~40–60 MB |

## Key Dependencies

### Core (`runanywhere`)
- `ffi: ^2.1.0` — Dart FFI
- `protobuf: ^3.1.0` — Proto-generated types
- `rxdart: ^0.27.7` — Reactive extensions
- `path_provider`, `shared_preferences`, `flutter_secure_storage`, `sqflite` — Storage
- `device_info_plus` — Device info
- `flutter_tts` — System TTS fallback
- `record: '>=5.1.2 <7.0.0'` — Audio capture
- `audioplayers: ^6.0.0` — Audio playback
- `permission_handler: ^11.3.1` — Runtime permissions

### Backend packages
- `runanywhere: ^0.19.0` — Core SDK
- `ffi: ^2.1.0` — Dart FFI

### Example app (additional)
- `provider: ^6.1.0` — State management
- `flutter_markdown` — Markdown rendering
- `camera: ^0.11.0` — VLM camera
- `image_picker: ^1.0.0` — Gallery photos
- `image: ^4.0.0` — BGRA→RGB conversion
- `file_picker: ^8.0.0` — RAG document selection
- `syncfusion_flutter_pdf` — PDF text extraction

## All Versions

| Package | Version |
|---|---|
| `runanywhere` | 0.19.13 |
| `runanywhere_llamacpp` | 0.19.13 |
| `runanywhere_onnx` | 0.19.13 |
| `runanywhere_genie` | 0.19.13 |
| Core native version | 0.1.6 |
| Genie native version | 0.3.0 |
| LlamaCpp engine | b7199 |
| ONNX Runtime | 1.23.2 |
| Remote download base | `github.com/RunanywhereAI/runanywhere-sdks/releases/download/commons-v0.1.6/` |
