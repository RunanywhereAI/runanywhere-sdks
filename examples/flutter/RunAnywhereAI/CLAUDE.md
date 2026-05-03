# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This App Is

A Flutter reference app demonstrating the RunAnywhere on-device AI SDK. It mirrors the native iOS app's feature set: LLM chat (streaming + non-streaming), speech-to-text, text-to-speech, voice assistant pipeline (STT→LLM→TTS), vision/VLM with live camera, tool calling, RAG with PDF ingestion, structured JSON output, and a solutions YAML runner. Eight tabs: Chat, Vision, STT, Speak, Voice, Tools, Solutions, Settings.

## Common Commands

```bash
# From this directory (examples/flutter/RunAnywhereAI/)

# Resolve packages (must run first)
flutter pub get

# Static analysis (strict mode — dead_code/unused_import are errors)
flutter analyze

# Run on connected device or emulator
flutter run

# Run on specific iOS simulator
flutter run -d "iPhone 16 Pro"

# Build debug APK (no device needed)
flutter build apk --debug

# Build iOS simulator app
flutter build ios --simulator --debug

# Format
dart format lib/ test/

# Run tests (only one smoke test exists)
flutter test

# Quick smoke check (greps for SDK API coverage + runs flutter analyze)
./scripts/smoke.sh

# Full verification (pub get + analyze + APK build)
./scripts/verify.sh

# Full verification including iOS
RUN_IOS=1 ./scripts/verify.sh

# Rebuild native binaries if C++ layer changed (run from repo root)
# Android:
../../../scripts/build-core-android.sh arm64-v8a
# iOS:
../../../scripts/build-core-xcframework.sh
```

For iOS, after `flutter pub get`, you may need `cd ios && pod install && cd ..` if Pods are stale.

## SDK Dependency Chain

The app depends on four local Flutter SDK packages via `path:` dependencies in `pubspec.yaml`:

```
runanywhere           → ../../../sdk/runanywhere-flutter/packages/runanywhere
runanywhere_llamacpp  → ../../../sdk/runanywhere-flutter/packages/runanywhere_llamacpp
runanywhere_genie     → ../../../sdk/runanywhere-flutter/packages/runanywhere_genie
runanywhere_onnx      → ../../../sdk/runanywhere-flutter/packages/runanywhere_onnx
```

These packages wrap pre-built native C++ libraries via Dart FFI (`dart:ffi`), not method channels. AI inference calls go directly from Dart → native `.so`/xcframework without any platform channel hop.

- **Android**: `.so` files live in each SDK package's `android/src/main/jniLibs/` dirs. The Gradle property `runanywhere.useLocalNatives=true` (in `android/gradle.properties`) tells the build to use these local files instead of downloading from GitHub releases.
- **iOS**: xcframeworks (`RACommons`, `RABackendLLAMACPP`, `RABackendONNX`, `RABackendSherpa`) are vendored in each SDK package's `ios/Frameworks/` dirs. Static linkage (`use_frameworks! :linkage => :static` in Podfile) is required so `DynamicLibrary.executable()` can find the symbols at runtime.

If native binaries are missing (fresh clone), they must be staged first — see README's "Clean-Clone Bring-Up" or use `scripts/verify.sh` with `REFRESH_ANDROID_NATIVE=1` / `REFRESH_IOS_NATIVE=1`.

## Architecture

### Initialization (runanywhere_ai_app.dart)

App startup runs a multi-phase sequence in `initState` via `addPostFrameCallback`:

1. **Eager .so loading** (Android only) — `DynamicLibrary.open()` on 6 `.so` files to preload before any SDK call
2. **SDK init** — reads API key / base URL from secure storage (`KeychainHelper`); calls `RunAnywhereSDK.instance.initialize(...)` with or without credentials
3. **Module registration** — guarded by a static `_modulesRegistered` flag to survive hot-reload. Registers: LlamaCpp (9 GGUF models), Genie NPU (Android/Snapdragon only, chip-conditional models), VLM (SmolVLM 500M), Sherpa STT/TTS (Whisper + Piper models), RAG embeddings (MiniLM), ONNX backend, RAG backend
4. **Model refresh** — `ModelManager.shared.refresh()` notifies all listeners

### State Management

Three patterns coexist:

1. **Provider** (app-wide) — only `ModelManager.shared` is in the `MultiProvider` tree at the root
2. **Singleton ChangeNotifier + ListenableBuilder** (feature-level) — `ModelListViewModel.shared`, `ToolSettingsViewModel.shared`, `ConversationStore.shared`, `DeviceInfoService.shared` are accessed directly, not through Provider
3. **Local setState** (per-screen ephemeral state) — recording flags, streaming text buffers, error messages

### Navigation

`ContentView` uses `Scaffold` + `NavigationBar` + `IndexedStack` (all 8 tabs stay mounted). No named routes or GoRouter. Secondary screens (`RagDemoView`, `StructuredOutputView`, `VLMCameraView`) use `Navigator.push(MaterialPageRoute(...))`. Model pickers use `showModalBottomSheet`.

### Core Services (singletons in core/services/)

- **AudioRecordingService** — wraps `record` package; 16kHz mono WAV; emits normalized dB levels on a broadcast stream
- **AudioPlayerService** — wraps `audioplayers`; constructs WAV headers from raw PCM16 bytes; writes temp files for playback
- **ConversationStore** — file-based JSON persistence under `<documents>/Conversations/<id>.json`; messages carry optional `thinkingContent` and `MessageAnalytics`
- **KeychainService / KeychainHelper** — wraps `flutter_secure_storage`; iOS Keychain with `first_unlock_this_device`, Android `EncryptedSharedPreferences`; keys prefixed with `com.runanywhere.RunAnywhereAI_`
- **PermissionService** — wraps `permission_handler`; requests microphone + speech (iOS only) for STT, camera for VLM

### Platform Channel (com.runanywhere.sdk/native)

Both platforms implement the same 6 methods for audio session and device info — this is separate from the AI SDK's FFI path:

- `configureAudioSession(mode)` / `activateAudioSession` / `deactivateAudioSession`
- `requestMicrophonePermission` / `hasMicrophonePermission`
- `getDeviceCapabilities` (memory, processors)

iOS: `AppDelegate.swift`. Android: `PlatformChannelHandler.kt`.

### SDK API Surface Used

All AI calls go through `RunAnywhereSDK.instance`:
- `.llm.generate()` / `.llm.generateStream()` / `.llm.load()` / `.llm.unload()`
- `.stt.transcribe()` / `.stt.load()`
- `.tts.synthesize()` / `.tts.loadVoice()`
- `.vlm.processImageStream()` / `.vlm.load()`
- `.voice.eventStream()` / `.voice.initializeWithLoadedModels()`
- `.tools.register()` / `.tools.generateWithTools()`
- `.rag.createPipeline()` / `.rag.ingest()` / `.rag.query()` / `.rag.destroyPipeline()`
- `.solutions.run(yaml:)`
- `.downloads.start()` / `.downloads.delete()` / `.downloads.list()` / `.downloads.getStorageInfo()`
- `.models.register()` / `.models.registerMultiFile()` / `.models.available()`
- `.hardware.getChipEnum()`

### Feature-Specific Notes

- **Chat**: streaming generation appends tokens to a placeholder message at a fixed list index via `setState`. Tool calling detects `lfm2`+`tool` in the model name to select `ToolCallFormatNames.lfm2`. Thinking content parsed from `<think>...</think>` blocks.
- **VLM**: `VLMViewModel` (non-singleton, created per view) uses a `Timer.periodic` at 2.5s for auto-streaming mode. Camera frames are BGRA→file→`VLMImage(filePath:)`.
- **Voice Assistant**: subscribes to `voice.eventStream()` which emits protobuf `VoiceEvent` messages. Event payload types: `state`, `vad`, `userSaid`, `assistantToken`, `audio`, `error`.
- **RAG**: `DocumentService` uses `syncfusion_flutter_pdf` for PDF text extraction. The RAG model selection flow does NOT pre-load models into memory — it only passes paths to `RAGConfiguration`.
- **Tools**: three demo tools registered (`get_weather`, `calculate`, `get_current_time`). Weather tool uses Open-Meteo free API via `package:http`.
- **Structured Output**: uses `LLMGenerationOptions(jsonSchema:)` with predefined schemas.

## Build Configuration Gotchas

- **Android `packagingOptions`** (`android/app/build.gradle`): `pickFirst '**/libc++_shared.so'` and `pickFirst '**/libomp.so'` — required because multiple SDK plugin packages each bundle these shared libs
- **Android `extractNativeLibs="true"`** and `<uses-native-library android:name="libcdsprpc.so" android:required="false"/>` in `AndroidManifest.xml` — required for Genie NPU (Qualcomm FastRPC)
- **iOS Podfile post_install**: forces `EXCLUDED_ARCHS[sdk=iphonesimulator*] = x86_64` on all pods and Runner — locally built xcframeworks only contain arm64 simulator slices
- **iOS Podfile permission flags**: `PERMISSION_MICROPHONE=1`, `PERMISSION_SPEECH_RECOGNIZER=1`, `PERMISSION_CAMERA=1` must be set for `permission_handler` to compile those capabilities
- **Gradle heap**: `-Xmx6g` in `gradle.properties` — native compilation is memory-intensive
- **Kotlin 2.1.21 / AGP 8.9.1 / Gradle 8.11.1** — these versions must stay in sync; mismatches cause build failures

## Analysis Options

`analysis_options.yaml` enables strict Dart analysis:
- `strict-casts`, `strict-inference`, `strict-raw-types` all enabled
- `dead_code`, `unused_import`, `unused_local_variable`, `unused_element`, `unused_field` are **errors** (not warnings)
- Generated files (`*.g.dart`, `*.freezed.dart`, `lib/generated/**`) are excluded

## Platform Requirements

- Flutter `>=3.10.0`, Dart `>=3.0.0 <4.0.0`
- Android: compileSdk 36, targetSdk 34, minSdk from Flutter default, JVM 17
- iOS: deployment target 15.1 (enforced by Podfile), Xcode 15+
- Physical ARM64 device recommended — native libs are optimized for arm64
