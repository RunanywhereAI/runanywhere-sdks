# RunAnywhere Flutter SDK – Architecture

> Updated: 2026-05-13. This document reflects the current Flutter implementation
> plan while code is still in progress: exact Swift parity, deletion-forward
> cleanup, and pending runtime validation. Do not treat it as a final success
> report until both Flutter lanes pass full E2E.

## 1. Overview

The RunAnywhere Flutter SDK is a production-grade, on-device AI SDK for iOS and
Android. It is a thin Dart FFI bridge over the shared C++ core
(`runanywhere-commons` / `RACommons`) and backend plugin libraries.

Design goals:

- **Modular backends**: separate Flutter plugin packages per backend. LlamaCPP
  and ONNX/Sherpa are in scope for the current validation pass; Genie is a
  deferred backend and should not create active gap rows by itself.
- **C++ commons does the work**: registries, event publisher, plugin router, HTTP,
  download orchestration, and all inference live in the C ABI (`rac_*`).
- **Dart orchestration**: the SDK exposes a static namespace + capability accessors and
  ferries proto messages between C++ and the app.
- **No platform channels for AI**: all inference calls go through `dart:ffi`.
- **Two-phase initialization**: Phase 1 (sync) wires the C ABI and is sufficient
  for offline inference; Phase 2 (async, fire-and-forget) handles auth + device
  registration + telemetry flush.
- **Proto wire types are canonical**: every cross-platform type is defined in
  `idl/*.proto` and code-generated into `lib/generated/`. No hand-written enums.

---

## 2. Multi-Package Architecture

### 2.1 Package Layout

```
sdk/runanywhere-flutter/
├── pubspec.yaml                     # Dart workspace + Melos config
├── analysis_options.yaml
├── docs/                            # ARCHITECTURE.md, Documentation.md
├── scripts/package-sdk.sh
└── packages/
    ├── runanywhere/                 # Core SDK (required)
    │   ├── lib/                     # see §3 for layout
    │   ├── ios/                     # podspec + RACommons.xcframework + URLSession transport
    │   └── android/                 # gradle + RunAnywherePlugin.kt + OkHttp transport
    ├── runanywhere_llamacpp/        # LLM + VLM (GGUF via llama.cpp)
    ├── runanywhere_onnx/            # STT + TTS + VAD (Sherpa-ONNX)
    └── runanywhere_genie/           # Qualcomm Genie NPU LLM (Android-only)
```

Backend packages depend on `runanywhere ^0.19.0` and vendor their own
XCFramework + `.so` files.

### 2.2 Layer Stack

```
┌─────────────────────────────────────────────────────────────────────┐
│                       Flutter Application                            │
├─────────────────────────────────────────────────────────────────────┤
│              RunAnywhere (static namespace)                         │
│   capability accessors: .llm .stt .tts .vad .vlm .voice .models     │
│      .modelLifecycle .downloads .tools .rag .solutions .hardware    │
├─────────────────────────────────────────────────────────────────────┤
│        public/capabilities/* (RunAnywhereLLM, RunAnywhereSTT, ...)   │
├─────────────────────────────────────────────────────────────────────┤
│        lib/native/dart_bridge_*.dart  (33 FFI slices, one per         │
│        C++ subsystem)                                                │
├─────────────────────────────────────────────────────────────────────┤
│        NativeFunctions + PlatformLoader  (cached FFI lookups,        │
│        per-platform DynamicLibrary load)                             │
├─────────────────────────────────────────────────────────────────────┤
│        runanywhere-commons (C++ core)                                │
│        ModuleRegistry · ServiceRegistry · EventPublisher · Router    │
├──────────────┬───────────────┬────────────────────────────────────┬─┘
│  LlamaCpp    │   Sherpa /    │       Qualcomm Genie NPU           │
│ (LLM, VLM)   │    ONNX       │       (LLM, Android-only)          │
│              │ (STT,TTS,VAD) │                                    │
└──────────────┴───────────────┴────────────────────────────────────┘
```

### 2.3 Binary Size

| Package | iOS | Android | Provides |
|---------|------|---------|----------|
| `runanywhere` | ~5 MB | ~3 MB | Core SDK, registries, events, FFI bridge |
| `runanywhere_llamacpp` | ~15–25 MB | ~10–15 MB | LLM + VLM (GGUF) |
| `runanywhere_onnx` | ~50–70 MB | ~40–60 MB | STT, TTS, VAD (Sherpa-ONNX + Piper) |
| `runanywhere_genie` | n/a | varies | Deferred Genie NPU package |

---

## 3. Core Package Source Layout (`packages/runanywhere/lib/`)

```
lib/
├── runanywhere.dart                  # Barrel (≈150 re-exports)
├── runanywhere_protos.dart           # Proto re-export hub
├── adapters/                         # http_client_adapter, voice_agent_stream_adapter
├── core/
│   ├── module/runanywhere_module.dart  # Backend module contract
│   └── native/rac_native.dart         # Hand-written FFI bindings (~2.1K LOC)
├── transport/                         # Network config + HTTP transport helpers
├── features/
│   ├── stt/services/audio_capture_manager.dart   # 16 kHz mono Int16 via `record`
│   └── tts/services/audio_playback_manager.dart  # PCM playback via `audioplayers`
├── foundation/
│   ├── constants/                     # sdk_constants.dart
│   ├── errors/                        # sdk_exception.dart (40+ factory constructors)
│   ├── logging/                       # sdk_logger.dart
│   └── security/                      # keychain_manager.dart + secure_storage_keys.dart
├── generated/                         # 58 runtime proto files
├── internal/                          # small internal helpers; stale SDK mirror state is deletion scope
├── native/                            # 33 dart_bridge_*.dart slices + native_functions + platform_loader + types/ + type_conversions/
└── public/
    ├── runanywhere.dart               # RunAnywhere static entry point
    ├── capabilities/                  # 18 capability classes (flat)
    ├── configuration/                 # sdk_environment.dart
    ├── events/                        # event_bus.dart  (pure `dart:async`)
    └── extensions/                    # rag_module, runanywhere_logging, _storage,
                                        # _structured_output, _thinking_utils, stt/stt_options_helpers
```

There is **no** top-level `lib/capabilities/`, **no** `lib/infrastructure/`,
**no** `dart_bridge_llm_streaming.dart`, and **no** `native_backend.dart`.

### 3.1 Public API Surface (`lib/public/`)

`RunAnywhere` is the lifecycle static namespace + capability dispatcher. Each
capability (LLM/STT/TTS/VLM/voice/models/downloads/tools/RAG/solutions/…) is a
separate class in `lib/public/capabilities/` and is exposed as a lazy property
on the namespace.

```dart
await RunAnywhere.initialize(/* … */);
final result = await RunAnywhere.llm.generate(prompt, options);
```

The current 18 capability accessors:

```
.llm  .stt  .tts  .vad  .vlm  .voice  .visionLanguage
.models  .modelLifecycle  .downloads  .tools  .rag  .solutions
.diffusion  .embeddings  .lora  .hardware  .pluginLoader
```

### 3.2 FFI Bridge (`lib/native/`)

`DartBridge` is the static coordinator. Each C++ subsystem has a slice file:

```
dart_bridge.dart                  # coordinator
dart_bridge_auth.dart             # auth + secure-storage vtable
dart_bridge_device.dart           # device id, registration
dart_bridge_diffusion.dart        # diffusion (Stable-Diffusion-class)
dart_bridge_download.dart         # download orchestrator
dart_bridge_embeddings.dart       # embeddings (ONNX MiniLM, etc.)
dart_bridge_environment.dart      # environment proto
dart_bridge_events.dart           # SDK event stream from C++
dart_bridge_file_manager.dart     # file ops
dart_bridge_hardware.dart         # hardware profile
dart_bridge_http.dart             # HTTP transport (Dart side)
dart_bridge_llm.dart              # LLM generate / generateStream
dart_bridge_lora.dart             # LoRA adapter ops
dart_bridge_model_assignment.dart # model-assignment proto
dart_bridge_model_lifecycle.dart  # load / unload / current
dart_bridge_model_paths.dart      # storage roots, model dirs
dart_bridge_model_registry.dart   # registry CRUD + URL → format/artifact inference
dart_bridge_platform.dart         # platform adapter + services registration
dart_bridge_plugin_loader.dart    # dynamic plugin loading
dart_bridge_proto_utils.dart      # proto helpers
dart_bridge_rag.dart              # RAG pipelines
dart_bridge_solutions.dart        # solutions YAML runner
dart_bridge_state.dart            # SDK state queries
dart_bridge_storage.dart          # storage info
dart_bridge_stt.dart              # STT transcribe / stream
dart_bridge_telemetry.dart        # telemetry flush
dart_bridge_tool_calling.dart     # tool calling
dart_bridge_tts.dart              # TTS synthesize / speak
dart_bridge_vad.dart              # VAD process
dart_bridge_vlm.dart              # VLM processImageStream
dart_bridge_voice_agent.dart      # voice pipeline
```

Plus supporting modules:

- `native_functions.dart` — cached FFI function-pointer lookup registry (~380 LOC).
- `platform_loader.dart` — per-platform `DynamicLibrary` strategy (`.process()`
  on iOS, `.open()` on Android, fallback `.executable()` on macOS).
- `types/` (struct/typedef bundles) and `type_conversions/` (proto ↔ C
  struct mappers) — importers depend on individual files directly.

---

## 4. Key Architectural Patterns

1. **Proto-driven public surface.** All public types are protobuf-generated.
   58 runtime `.pb.dart` / `.pbenum.dart` files live under `lib/generated/`.
   Never hand-edit; modify the `.proto` and regenerate.

2. **Worker-isolate usage is gated by event-publish safety.** Blocking FFI ops
   may use `Isolate.run` only when the C++ path cannot publish back through an
   isolate-local Dart callback. Heavy model lifecycle calls remain pending the
   commons event-publish fix.

3. **`NativeCallable.listener` for streaming.** LLM streaming, voice agent
   events, and download progress use `NativeCallable.listener` so C++
   background threads can post events into a broadcast `StreamController`.
   Commons SDK event publishing must follow the same cross-isolate-safe rule
   before heavy load paths can move back to worker isolates.

4. **Two-phase SDK init.** Phase 1 (sync, ~15 steps): load lib → register
   `rac_platform_adapter_t` → `rac_sdk_init_phase1_proto` → configure logging
   → register event / device / file-manager / telemetry callbacks. Phase 2
   (async, fire-and-forget) uses `rac_sdk_init_phase2_proto` for
   device registration + authentication + model assignment + telemetry flush.
   Offline inference works without Phase 2 completing.

5. **Platform HTTP transport injection.** iOS registers a URLSession-backed
   `rac_http_transport_ops_t` vtable from ObjC++; Android registers an
   OkHttp-backed vtable via JNI. C++ uses the installed transport for all HTTP.

6. **EventBus is pure `dart:async`.** `lib/public/events/event_bus.dart` is a
   `StreamController.broadcast()` singleton. **`rxdart` is not a dependency.**

7. **Secure-storage vtable.** The C++ auth manager calls Dart secure-storage
   callbacks synchronously via a `_secureCache` map; the Dart side wraps
   `flutter_secure_storage` (and `EncryptedSharedPreferences` on Android).

8. **Hand-written FFI bindings.** No `ffigen` is used. `core/native/rac_native.dart`
   plus `native/native_functions.dart` define every C ABI binding by hand.

---

## 5. Native Library Loading

| Platform | Mechanism |
|----------|-----------|
| iOS | `RACommons.xcframework` (static archive) → `DynamicLibrary.process()` resolves symbols in the main binary |
| Android | `DynamicLibrary.open('librac_commons.so')`, fallback `librunanywhere_jni.so` |
| macOS (tests) | `process()` → `executable()` → explicit dylib path; the 3rd `RACommons.xcframework` slice (`macos-arm64`) supports unit tests |

iOS requires `use_frameworks! :linkage => :static` in the Podfile and
`-all_load` / `DEAD_CODE_STRIPPING=NO` linker flags (set in each podspec).

---

## 6. Data & Control Flow

### 6.1 LLM Generation

```
App → RunAnywhere.llm.generate(prompt, options)
    → RunAnywhereLLM.shared.generate()
    → validates SdkState.isInitialized + isLoaded
    → DartBridge.llm.generate() calls the C ABI directly or through a worker
      isolate only when that path has no isolate-local callback hazard
    → returns LLMGenerationResult proto
```

### 6.2 LLM Streaming

```
App → RunAnywhere.llm.generateStream(prompt, options)
    → registers a NativeCallable.listener for C++ token callbacks
    → tokens land in a broadcast StreamController as LLMStreamEvent protos
    → multiple subscribers share one C-callback registration (fan-out)
```

### 6.3 Model Download

```
App → RunAnywhere.downloads.start(modelId)
    → DownloadManager.downloadModel()
    → DartBridgeDownload.orchestrateDownload() returns a taskId
    → Dart polls DartBridgeDownload.getProgress(taskId) every 250 ms
    → on completion: resolves model path via rac_model_paths_get_model_folder
    → updates the C++ registry with localPath
```

### 6.4 SDK Initialization

```
Phase 1 (sync):
  load native lib → register platform adapter → configure logging
  → rac_sdk_init_phase1_proto → register events / device / file-manager / telemetry callbacks
  → setBaseDirectory()

Phase 2 (background, fire-and-forget):
  rac_sdk_init_phase2_proto → model assignment → platform services → device registration → authentication
  → telemetry flush
```

---

## 7. Backend Modules

Backends are pluggable Flutter packages. Each one calls
`rac_backend_<name>_register()` over FFI on `register()` and registers an engine
vtable with the C++ plugin registry. The router scores plugins by priority +
runtime + format compatibility on inference.

| Module | Package | Capabilities | Priority |
|--------|---------|--------------|----------|
| `LlamaCpp` | `runanywhere_llamacpp` | LLM, VLM | 100 |
| `Onnx` | `runanywhere_onnx` | STT, TTS, VAD | 90 |
| `Genie` | `runanywhere_genie` | Deferred LLM backend | 200 (when registered) |
| `RAGModule` | core extension | RAG pipelines | — |

---

## 8. Concurrency & Threading

| Pattern | Usage |
|---------|-------|
| `async / await` | All public API methods |
| `Stream` (broadcast) | Streaming generation, download progress, voice agent events |
| `Isolate.run` | Blocking FFI ops only after callback/event-publish safety is confirmed |
| `NativeCallable.listener` | Thread-safe C++ → Dart callbacks for streaming |
| `Completer` | Bridging callbacks to futures |

**Thread safety**: `Pointer.fromFunction` callbacks may only be called from the
Dart isolate thread. C++ download orchestration spawns `std::thread`, so the
SDK passes null callbacks where unsafe and polls instead (e.g., download progress).

---

## 9. Build System

### Native Library Sources

Native libraries come from `runanywhere-commons` (the shared C++ core). The
top-level repo provides:

```
sdk/runanywhere-swift/scripts/build-core-xcframework.sh   # iOS XCFrameworks → packages/*/ios/Frameworks/
scripts/build/build-core-android.sh       # Android .so → packages/*/android/src/main/jniLibs/
```

### Melos Workflow

```bash
melos bootstrap        # flutter pub get across the 4-package workspace
melos run analyze      # flutter analyze --no-pub everywhere
melos run format       # dart format
melos run test         # flutter test
melos run clean        # flutter clean
melos version          # bump versions + generate workspace CHANGELOG
```

### Packaging

```bash
./scripts/package-sdk.sh                      # pub publish --dry-run
./scripts/package-sdk.sh --natives-from PATH  # stage native binaries then validate
```

---

## 10. Extensibility

### 10.1 Adding a New Backend

1. Create a new Flutter plugin package.
2. Implement a C++ backend with the standard `rac_engine_vtable_t` (v4).
3. Vendor the resulting `.xcframework` / `.so` in your package.
4. Expose Dart FFI bindings + a `register()` entry point that calls
   `rac_backend_<name>_register()`.
5. Optionally add convenience `addModel(...)` helpers that delegate to
   `RunAnywhere.models.register(...)`.

### 10.2 Custom Event Subscribers

```dart
RunAnywhere.events.allEvents.listen((event) {
  // proto-typed SDKEvent — branch on oneof payload
});
```

---

## 11. Trade-offs

### Static Namespace vs Multiple Instances

`RunAnywhere` is a static namespace. Trade-off: simple, discoverable API
(`RunAnywhere.llm.generate(...)`) vs. harder multi-instance testing.
Global state is intentionally kept small and should continue moving toward the
Swift source-of-truth shape rather than growing Flutter-only mirror state.

### FFI vs MethodChannel

Direct FFI to C++ instead of MethodChannel:

- **Advantages**: lower latency, direct memory access for audio/binary, parity
  with iOS/Android native SDKs.
- **Trade-offs**: more complex error handling, platform-specific binary management.

### Thin Backend Wrappers

Backend Flutter packages are thin Dart shims; all model loading + inference
lives in the bundled C++ backend library.

- **Advantages**: logic shared with the other SDKs; consistent behavior
  cross-platform.
- **Trade-offs**: debugging requires native tooling (lldb / Android Studio NDK
  debugger).

---

## 12. Versions

| Component | Version |
|-----------|---------|
| `runanywhere` (Dart) | 0.19.13 |
| `runanywhere_llamacpp` | 0.19.13 |
| `runanywhere_onnx` | 0.19.13 |
| `runanywhere_genie` | 0.19.13 |
| `RACommons` native | 0.1.6 |
| llama.cpp engine | b7199 |
| ONNX Runtime | 1.23.2 |
| Android NDK | 27.0.12077973 |
| iOS deployment target | 15.1 |
| Canonical source | `sdk/runanywhere-commons/VERSION` |

---

## 13. Native Binary Inventory

### iOS XCFrameworks (static archives)

| Package | Framework | Slices |
|---------|-----------|--------|
| `runanywhere` | `RACommons.xcframework` | `ios-arm64`, `ios-arm64-simulator`, `macos-arm64` |
| `runanywhere_llamacpp` | `RABackendLLAMACPP.xcframework` | `ios-arm64`, `ios-arm64-simulator` |
| `runanywhere_onnx` | `RABackendONNX.xcframework`, `RABackendSherpa.xcframework` | `ios-arm64`, `ios-arm64-simulator` |
| `runanywhere_genie` | — | none |

### Android Shared Libraries (per ABI: arm64-v8a, armeabi-v7a, x86_64)

| Package | Libraries |
|---------|-----------|
| `runanywhere` | `librac_commons.so`, `librunanywhere_jni.so`, `libc++_shared.so`, `libomp.so` |
| `runanywhere_llamacpp` | `librac_backend_llamacpp.so`, `librac_backend_llamacpp_jni.so`, `libc++_shared.so` |
| `runanywhere_onnx` | `libonnxruntime.so`, `libsherpa-onnx-c-api.so`, `libsherpa-onnx-cxx-api.so`, `libsherpa-onnx-jni.so`, `librac_backend_onnx.so`, `librac_backend_onnx_jni.so`, `librac_backend_sherpa.so`, `libc++_shared.so` |
| `runanywhere_genie` | `libc++_shared.so` only (backend `.so` downloaded at runtime) |
