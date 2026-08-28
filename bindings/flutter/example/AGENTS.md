# AGENTS.md

## What This App Is

A Flutter reference app demonstrating the RunAnywhere on-device AI SDK. It mirrors the native iOS/Android apps' feature set: LLM chat (streaming + non-streaming), speech-to-text, text-to-speech, a voice assistant pipeline (STT→LLM→TTS), VLM image description (gallery- or camera-app-picked image — no in-app live camera preview), tool calling, RAG with PDF ingestion, and a solutions YAML runner. Five bottom tabs: Chat, Vision, Voice, More, Settings. The More hub pushes Transcribe (STT), Speak (TTS), Document Q&A (RAG), Voice Activity (VAD), Storage, and Solutions.

## Design System

Brand primary is RunAnywhere orange **#FF6900** (the logo color) — see the canonical
`../../../docs/DESIGN_GUIDELINE.md`. Theme lives in `lib/core/design_system/app_colors.dart`
(`AppColors.brandOrange`/`primaryAccent`) and the two `ThemeData` blocks in
`lib/app/runanywhere_ai_app.dart` (Material 3, seed = brand orange with `primary`
pinned exactly, light + dark via `ThemeMode.system`). `primaryBlue` is a genuine
secondary blue, not the brand. When changing brand colors, edit `app_colors.dart` and
keep it in sync with the guideline.

## Common Commands

```bash
# From this directory (bindings/flutter/example/)

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
../../../scripts/build/build-core-android.sh arm64-v8a
# iOS:
../../../bindings/swift/scripts/build-core-xcframework.sh
```

For iOS, after `flutter pub get`, you may need `cd ios && pod install && cd ..` if Pods are stale.

## SDK Dependency Chain

The app depends on five local Flutter SDK packages via `path:` dependencies in `pubspec.yaml`:

```
runanywhere           → ../../../bindings/flutter/packages/runanywhere
runanywhere_llamacpp  → ../../../bindings/flutter/packages/runanywhere_llamacpp
runanywhere_mlx       → ../../../bindings/flutter/packages/runanywhere_mlx
runanywhere_qhexrt    → ../../../bindings/flutter/packages/runanywhere_qhexrt
runanywhere_onnx      → ../../../bindings/flutter/packages/runanywhere_onnx
```

These packages wrap pre-built native C++ libraries via Dart FFI (`dart:ffi`), not method channels. AI inference calls go directly from Dart → native `.so`/xcframework without any platform channel hop.

- **Android**: `.so` files live in each SDK package's `android/src/main/jniLibs/` dirs. The Gradle property `runanywhere.useLocalNatives=true` (in `android/gradle.properties`) tells the build to use these local files instead of downloading from GitHub releases.
- **iOS**: xcframeworks (`RACommons`, `RABackendLLAMACPP`, `RABackendMLX`, `RunAnywhereMLXRuntime`, `RunAnywhereMLXMetal`, `RABackendONNX`, `RABackendSherpa`) are staged in each SDK package's `ios/<package>/Frameworks/` directory. MLX intentionally uses CocoaPods so Hub/Crypto are app-root bundles; the other plugins can use SwiftPM. CocoaPods statically links the MLX core/backend archives and embeds the tiny dynamic `RunAnywhereMLXMetal` framework carrying the selected `default.metallib`. The loader uses `DynamicLibrary.process()` with `executable()` fallback. MLX executes only on a physical iOS device; its arm64 simulator slices support package, compile, link, and startup validation.

If native binaries are missing (fresh clone), they must be staged first — see README's "Setup" section (step 2, "Build and stage native artifacts") or use `scripts/verify.sh` with `REFRESH_ANDROID_NATIVE=1` / `REFRESH_IOS_NATIVE=1`.

## Architecture

### Initialization (runanywhere_ai_app.dart)

App startup runs `_initializeSDK()` from `initState` via `addPostFrameCallback`. There is no eager native-library preloading step — the SDK's own FFI bridge loads `.so`/xcframework symbols lazily on first use:

1. **Backend registration** (`_registerBackends()`) — guarded by a static flag to survive hot-reload. Registers LlamaCpp, physical-device-only Apple MLX, ONNX/Sherpa, then QHexRT NPU (`QHexRT.isAvailable` guards Android/Snapdragon only; a no-op elsewhere); MLX reports unavailable in the iOS Simulator
2. **SDK init** — reads API key / base URL from secure storage (`KeychainHelper`); calls `RunAnywhere.initialize(...)` with or without credentials
3. **Catalog registration** (`ModelCatalogBootstrap.registerAll(mlxRegistered:)`) — seeds the curated model catalog on every cold launch (safe to re-run; commons merges runtime fields). Only the Apple MLX catalog section is gated on `mlxRegistered`; ONNX and QHexRT catalog entries register unconditionally regardless of whether those backends actually registered

### State Management

Two patterns coexist:

1. **Singleton ChangeNotifier + ListenableBuilder** (feature-level) — `ModelListViewModel.shared`, `ToolSettingsViewModel.shared`, `ConversationStore.shared`, `DeviceInfoService.shared` are accessed directly
2. **Local setState** (per-screen UI state) — recording flags, streaming text buffers, error messages, voice setup state

### Navigation

`ContentView` uses `Scaffold` + `NavigationBar` + `IndexedStack` over 5 tabs (Chat, Vision, Voice, More, Settings). Each tab builds lazily on first visit and then stays mounted (`_visitedTabs`), so a hidden tab's `initState`/event-bus subscriptions don't run until selected. No named routes or GoRouter. `MoreView` is a list hub that pushes secondary screens (`SpeechToTextView`, `TextToSpeechView`, `RagDemoView`, `VADView`, `StorageView`, `SolutionsView`) via `Navigator.push(MaterialPageRoute(...))`; `VisionHubView` similarly pushes `VLMCameraView`. Model pickers use `showModalBottomSheet`.

### Core Services (singletons in core/services/)

There is no local audio-recording or audio-playback service in this app — STT capture and TTS playback are fully SDK-owned (`.stt.openStream()` / `.tts.speak()` with `playbackState`/`playbackProgress` streams); see `bindings/flutter/AGENTS.md`.

- **ConversationStore** — file-based JSON persistence under `<documents>/Conversations/<id>.json`; messages carry optional `thinkingContent` and `MessageAnalytics`
- **KeychainService / KeychainHelper** — wraps `flutter_secure_storage`; iOS Keychain with `first_unlock_this_device`, Android Keystore-backed secure storage; keys prefixed with `com.runanywhere.RunAnywhereAI_`
- **PermissionService** — wraps `permission_handler`; requests microphone + speech (iOS only) for STT, camera for VLM
- **DeviceInfoService** — device model/OS/app version via `device_info_plus`/`package_info_plus`. Chip/NPU/total-memory fields are intentionally left empty and hidden by the UI: the SDK's hardware ABI was removed when the routing scorer was retired, so there is nothing to read anymore

### SDK API Surface Used

All AI calls go through `RunAnywhere`:
- `.llm.generate()` / `.generateStream()` / `.cancel()`; tool calling nests under `.llm.tools.register()` / `.list()` / `.unregister()` — there is no separate top-level `.tools` capability call site in this app
- `.stt.transcribe()` (batch) / `.openStream()` (live)
- `.tts.synthesize()` / `.speak()` / `.stop()`, driven by `.playbackState` / `.playbackProgress` streams
- `.vlm.generateStream(ImageInput.file(path), prompt, options:)` / `.cancel()`
- `.voice.createSession(stt:, llm:, tts:)` → session `.events` (a sealed `VoiceEvent` hierarchy) + `.start()` / `.close()`
- `.rag.open(embeddingModel:, llmModel:)` → session `.ingest(RagDocument(text))` / `.close()`
- `.models.register()` / `.load()` / `.download()` / `.delete()` / `.list()` / `.state()` / `.unloadAll()`
- `.lora.register()` / `.list()` / `.apply()` / `.download()` / `.remove()` / `.catalog()`
- `.solutions.run(yaml:)`; `.hybrid.registerCloud()` / `.createSttRouter()`; `.events.listen()`

There is no `.downloads` or `.hardware` capability in current use: downloads go through `.models.download()`, and the chip/hardware ABI was removed with the routing scorer (see `DeviceInfoService` above).

### Feature-Specific Notes

- **Chat**: streaming generation appends tokens to a placeholder message at a fixed list index via `setState`. Tool-call format detection (e.g. matching `lfm2`+`tool` in a model name) now lives in the SDK, not this app. Thinking content comes from the SDK (`thinkingText` / stream thought deltas) — the app does not parse `<think>` tags.
- **VLM**: `VLMViewModel` (non-singleton, created per view) has no in-app camera preview. Mirroring the Android Kotlin `VisionViewModel`, the user picks a gallery or camera-app image via `image_picker`, then `RunAnywhere.vlm.generateStream(ImageInput.file(path), prompt, options: LlmOptions(maxOutputTokens: 300))` streams the description.
- **Voice Assistant**: `voice_agent_view_model.dart` opens a session with `RunAnywhere.voice.createSession(stt:, llm:, tts:)`, then listens on `session.events` — a sealed `VoiceEvent` hierarchy (`VoiceSpeechStarted`, `VoiceSpeechEnded`, `VoiceUserTranscribed`, …) matched with Dart pattern-matching `switch`, not a `oneof`-style payload field. `session.start()` / `session.close()` bookend the conversation.
- **RAG**: `DocumentService` uses `syncfusion_flutter_pdf` for PDF text extraction. `RAGViewModel` extracts text first, then opens a session via `RunAnywhere.rag.open(embeddingModel:, llmModel:)` and calls `session.ingest(RagDocument(extractedText))` — extracted text is ingested directly, not a file path passed to a config object.
- **Tools**: three demo tools registered from the Settings tab's `ToolSettingsViewModel` (`get_weather`, `calculate`, `get_current_time`; there is no standalone Tools tab). Weather tool uses the free Open-Meteo API via `package:http`.
- **Remaining SDK-owned cleanup**: the large model catalog still lives in app startup because moving it safely requires shared SDK/package ownership beyond this example-app lane.

## Build Configuration Gotchas

- **Android `packaging` block** (`android/app/build.gradle`, current AGP DSL): `jniLibs.pickFirsts += ['**/libc++_shared.so', '**/libomp.so']` — required because multiple SDK plugin packages each bundle these shared libs. It also sets `jniLibs { useLegacyPackaging = true }`: QHexRT's HTP skel `.so`s (`libQnnHtpV*Skel.so`) must exist as real on-disk files for FastRPC's `fopen()` to reach them — the AGP default (`useLegacyPackaging=false`) page-maps libs straight from the APK with no on-disk file, so the cDSP load fails (`errno 2`). The `.so` set is built 16 KB-aligned, so legacy-extracted files still mmap cleanly on 16 KB-page (Android 15+/16) devices.
- **Android `extractNativeLibs="true"`** and `<uses-native-library android:name="libcdsprpc.so" android:required="false"/>` in `AndroidManifest.xml` — required for QHexRT/QNN FastRPC
- **iOS Podfile post_install**: forces `EXCLUDED_ARCHS[sdk=iphonesimulator*] = x86_64` on all pods and Runner — locally built xcframeworks only contain arm64 simulator slices
- **iOS Podfile permission flags**: `PERMISSION_MICROPHONE=1`, `PERMISSION_SPEECH_RECOGNIZER=1`, `PERMISSION_CAMERA=1` must be set for `permission_handler` to compile those capabilities
- **Gradle heap**: `-Xmx6g` in `gradle.properties` — native compilation is memory-intensive
- **Flutter 3.44.6 / AGP 9.0.1 / Gradle 9.1.0** — canonical pins live in `core/VERSIONS`

## Analysis Options

`analysis_options.yaml` enables strict Dart analysis:
- `strict-casts`, `strict-inference`, `strict-raw-types` all enabled
- `dead_code`, `unused_import`, `unused_local_variable`, `unused_element`, `unused_field` are **errors** (not warnings)
- Generated files (`*.g.dart`, `*.freezed.dart`, `lib/generated/**`) are excluded

## Platform Requirements

Shared SDK pins (Flutter/Dart/Android/iOS/NDK versions) are identical to `bindings/flutter/AGENTS.md`'s System Requirements table — see that file, not here. App-specific additions:

- `pubspec.yaml` environment constraint: `sdk: '>=3.12.0 <4.0.0'`, `flutter: '>=3.44.0 <4.0.0'`
- JVM 17 (`compileOptions` + Kotlin `jvmTarget` in `android/app/build.gradle`)
- Physical ARM64 device recommended — native libs are optimized for arm64, and Apple MLX requires one
