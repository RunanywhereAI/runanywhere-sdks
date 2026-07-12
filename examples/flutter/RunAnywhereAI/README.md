# RunAnywhere AI - Flutter Example

<p align="center">
  <img src="../../../examples/logo.svg" alt="RunAnywhere Logo" width="120"/>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/Platform-iOS%2017.5%2B%20%7C%20Android%207.0%2B-02569B?style=flat-square&logo=flutter&logoColor=white" alt="iOS 17.5+ | Android 7.0+" />
  <img src="https://img.shields.io/badge/Flutter-3.44.6%2B-02569B?style=flat-square&logo=flutter&logoColor=white" alt="Flutter 3.44.6+" />
  <img src="https://img.shields.io/badge/Dart-3.12.2%2B-0175C2?style=flat-square&logo=dart&logoColor=white" alt="Dart 3.12.2+" />
  <img src="https://img.shields.io/badge/License-RunAnywhere-blue?style=flat-square" alt="RunAnywhere License" />
</p>

**A production-ready reference app demonstrating the [RunAnywhere Flutter SDK](../../../sdk/runanywhere-flutter/) capabilities for on-device AI.** This app showcases how to build privacy-first, offline-capable AI features with LLM chat, speech-to-text, text-to-speech, and a complete voice assistant pipeline—all running locally on your device.

---

## Running This App (Local Development)

> **Important:** This sample app consumes the [RunAnywhere Flutter SDK](../../../sdk/runanywhere-flutter/) through local path dependencies. A clean clone needs Flutter packages plus the Android JNI libraries and iOS XCFrameworks staged into the Flutter plugin packages.

### Clean-Clone Bring-Up

Prerequisites:

- Flutter 3.44.6+ and Dart 3.12.2+ on `PATH`.
- Android Studio with Android SDK 24+, platform tools, CMake, and NDK; export `ANDROID_HOME` and `ANDROID_NDK_HOME`.
- Xcode 26+ and CocoaPods for iOS simulator builds.
- JDK 17 and enough disk for native artifacts and downloaded AI models.

From a fresh checkout:

```bash
cd examples/flutter/RunAnywhereAI
flutter pub get

# Build or refresh local native artifacts when the checkout has no staged binaries.
cd ../../..
./scripts/build/build-core-android.sh arm64-v8a
./sdk/runanywhere-swift/scripts/build-core-xcframework.sh
cd examples/flutter/RunAnywhereAI

flutter analyze
flutter build apk --debug
flutter build ios --simulator --debug
```

Notes:

- `scripts/build/build-core-android.sh` stages JNI libraries into `sdk/runanywhere-flutter/packages/*/android/src/main/jniLibs`.
- `sdk/runanywhere-swift/scripts/build-core-xcframework.sh` stages all package-owned Apple frameworks. Core/LlamaCPP/ONNX can use SwiftPM; MLX intentionally uses CocoaPods so Hub/Crypto are copied to the app root.
- If the iOS build reports stale Pods or generated Flutter config, run `cd ios && pod install && cd ..` after `flutter pub get`.
- `scripts/verify.sh` runs `pub get`, analysis, APK build, and optional iOS/native artifact refresh gates.

### Private HNPU / QHexRT Downloads on Android

The Flutter example includes the `runanywhere_qhexrt` package and registers QHexRT on supported Snapdragon/Hexagon Android devices. QHexRT native libraries are private local artifacts: stage them into `sdk/runanywhere-flutter/packages/runanywhere_qhexrt/android/src/main/jniLibs/arm64-v8a/` before building, and do not commit them.

To test private `runanywhere/*_HNPU` bundles from the app:

1. Open `Settings` -> `Downloads`.
2. Paste a Hugging Face token into `HuggingFace token` and tap `Save token`.
3. Download and load an HNPU model through the normal model UI. The app registers logical HNPU URLs; the SDK resolves the matching Hexagon arch natively.
4. Tap `Clear` to return to public/no-auth downloads.

The token is passed to the SDK through `RunAnywhere.setHfToken(...)`; it is not stored in catalogs, assets, logs, or source files.

### How It Works

This sample app's `pubspec.yaml` uses path dependencies to reference the local Flutter SDK packages:

```
This Sample App → Local Flutter SDK packages (sdk/runanywhere-flutter/packages/)
                          ↓
              Local XCFrameworks/JNI libs (in package-owned ios/<package>/Frameworks/ and android/src/main/jniLibs/)
                          ↑
           Built by: ./sdk/runanywhere-swift/scripts/build-core-xcframework.sh + ./scripts/build/build-core-android.sh
```

Repo-root native build scripts (called from project root):
1. `./sdk/runanywhere-swift/scripts/build-core-xcframework.sh` — builds iOS XCFrameworks and stages them into package-owned `sdk/runanywhere-flutter/packages/*/ios/<package>/Frameworks/` directories.
2. `./scripts/build/build-core-android.sh <ABI>` — builds Android `.so` libraries and stages them into `sdk/runanywhere-flutter/packages/*/android/src/main/jniLibs/<ABI>/`.

Local consumption is enabled by the `runanywhere.useLocalNatives=true` Gradle property (default for development checkouts).

### After Modifying the SDK

- **Dart SDK code changes**: Run `flutter run` again (hot reload works for most changes).
- **C++ code changes** (in `runanywhere-commons`):
  ```bash
  # From repo root
  ./scripts/build/build-core-android.sh arm64-v8a
  ./sdk/runanywhere-swift/scripts/build-core-xcframework.sh
  ```

---

## See It In Action

<p align="center">
  <a href="https://apps.apple.com/us/app/runanywhere/id6756506307">
    <img src="https://img.shields.io/badge/App_Store-Download-0D96F6?style=for-the-badge&logo=apple&logoColor=white" alt="Download on App Store" />
  </a>
  <a href="https://play.google.com/store/apps/details?id=com.runanywhere.runanywhereai">
    <img src="https://img.shields.io/badge/Google_Play-Download-3DDC84?style=for-the-badge&logo=android&logoColor=white" alt="Get it on Google Play" />
  </a>
</p>

Try the native iOS and Android apps to experience on-device AI capabilities immediately. The Flutter sample app demonstrates the same features using the cross-platform Flutter SDK.

---

## Screenshots

<p align="center">
  <img src="../../../docs/screenshots/main-screenshot.jpg" alt="RunAnywhere AI Chat Interface" width="220"/>
</p>

---

## Features

This sample app demonstrates the full power of the RunAnywhere Flutter SDK:

| Feature | Description | SDK Integration |
|---------|-------------|-----------------|
| **AI Chat** | Interactive LLM conversations with streaming responses | `RunAnywhere.llm.generateStream()` |
| **Apple MLX** | Physical-iOS-device LLM, VLM, embeddings, STT, and TTS through the Swift MLX runtime | `MLX.register()` |
| **Thinking Mode** | Support for models with `<think>...</think>` reasoning | Thinking tag parsing |
| **Real-time Analytics** | Token speed, generation time, inference metrics | `MessageAnalytics` |
| **Speech-to-Text** | Voice transcription with batch & live modes | `RunAnywhere.stt.transcribe()` |
| **Text-to-Speech** | Neural voice synthesis with Piper TTS | `RunAnywhere.tts.synthesize()` |
| **Voice Assistant** | Full STT to LLM to TTS pipeline with auto-detection | `RunAnywhere.voice` |
| **Model Management** | Download, load, and manage multiple AI models | `RunAnywhere.models` / `RunAnywhere.downloads` |
| **Storage Management** | View storage usage and delete models | `RunAnywhere.downloads.getStorageInfo()` |
| **Offline Support** | All features work without internet | On-device inference |

---

## Architecture

The app follows Flutter best practices with a clean architecture pattern:

```
┌─────────────────────────────────────────────────────────────────────┐
│                        Flutter/Material UI                           │
│  ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌────────────┐ │
│  │  Chat    │ │   STT    │ │   TTS    │ │  Voice   │ │  Settings  │ │
│  │Interface │ │  View    │ │  View    │ │Assistant │ │   View     │ │
│  └────┬─────┘ └────┬─────┘ └────┬─────┘ └────┬─────┘ └─────┬──────┘ │
├───────┼────────────┼────────────┼────────────┼─────────────┼────────┤
│       ▼            ▼            ▼            ▼             ▼        │
│  ┌──────────────────────────────────────────────────────────────┐   │
│  │                 Feature ViewModels + UI State                 │   │
│  │           (SDK facades, Services, ListenableBuilder)          │   │
│  └──────────────────────────────────────────────────────────────┘   │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│                    RunAnywhere Flutter SDK                          │
│  ┌──────────────────────────────────────────────────────────────┐   │
│  │  Core API (generate, transcribe, synthesize)                  │   │
│  │  Model Management (download, load, unload, delete)            │   │
│  │  Voice Session (STT → LLM → TTS pipeline)                     │   │
│  └──────────────────────────────────────────────────────────────┘   │
│                              │                                      │
│           ┌──────────────────┴──────────────────┐                  │
│           ▼                                      ▼                  │
│  ┌─────────────────┐                  ┌─────────────────┐          │
│  │   LlamaCpp      │                  │   ONNX Runtime  │          │
│  │   (LLM/GGUF)    │                  │   (STT/TTS)     │          │
│  └─────────────────┘                  └─────────────────┘          │
└─────────────────────────────────────────────────────────────────────┘
```

### Key Architecture Decisions

- **Feature-Local State** — Screens keep ephemeral UI state local and call SDK facades directly
- **Feature-First Structure** — Each feature is self-contained with its own views and logic
- **Shared Core Services** — `AudioRecordingService`, `AudioPlayerService`, persistence and device helpers
- **Design System** — Consistent `AppColors`, `AppTypography`, `AppSpacing` tokens
- **SDK Integration** — Direct SDK calls with async/await and Stream support

---

## Project Structure

```
RunAnywhereAI/
├── lib/
│   ├── main.dart                      # App entry point
│   │
│   ├── app/
│   │   ├── runanywhere_ai_app.dart    # SDK initialization, model registration
│   │   └── content_view.dart          # Main tab navigation (5 tabs)
│   │
│   ├── core/
│   │   ├── design_system/
│   │   │   ├── app_colors.dart        # Color palette with dark mode support
│   │   │   ├── app_spacing.dart       # Spacing constants
│   │   │   └── typography.dart        # Text styles
│   │   │
│   │   ├── models/
│   │   │   └── app_types.dart         # Shared type definitions
│   │   │
│   │   ├── services/
│   │   │   ├── audio_recording_service.dart  # Microphone capture
│   │   │   ├── audio_player_service.dart     # TTS playback
│   │   │   ├── permission_service.dart       # Permission handling
│   │   │   ├── conversation_store.dart       # Chat history persistence
│   │   │   └── device_info_service.dart      # Device capabilities
│   │   │
│   │   └── utilities/
│   │       ├── constants.dart         # Preference keys, defaults
│   │       └── keychain_helper.dart   # Secure storage wrapper
│   │
│   ├── features/
│   │   ├── chat/
│   │   │   └── chat_interface_view.dart   # LLM chat with streaming
│   │   │
│   │   ├── voice/
│   │   │   ├── speech_to_text_view.dart   # Batch & live STT
│   │   │   ├── text_to_speech_view.dart   # TTS synthesis & playback
│   │   │   └── voice_assistant_view.dart  # Full STT→LLM→TTS pipeline
│   │   │
│   │   ├── models/
│   │   │   ├── models_view.dart           # Model browser
│   │   │   ├── model_selection_sheet.dart # Model picker bottom sheet
│   │   │   ├── model_list_view_model.dart # Model list logic
│   │   │   ├── model_components.dart      # Reusable model UI widgets
│   │   │   ├── model_status_components.dart # Status badges, indicators
│   │   │   ├── model_types.dart           # Framework enums, model info
│   │   │   └── add_model_from_url_view.dart # Import custom models
│   │   │
│   │   └── settings/
│   │       └── combined_settings_view.dart # Storage & logging config
│   │
│   └── helpers/
│       └── adaptive_layout.dart       # Responsive layout utilities
│
├── pubspec.yaml                       # Dependencies, SDK references
├── android/                           # Android platform config
├── ios/                               # iOS platform config
└── README.md                          # This file
```

---

## Quick Start

### Prerequisites

- **Flutter** 3.44.6 or later ([install guide](https://flutter.dev/docs/get-started/install))
- **Dart** 3.12.2 or later (included with Flutter)
- **iOS** — Xcode 26+ with an iOS 17.5+ deployment target
- **Android** — Android Studio + SDK 21+ (for Android builds)
- **~2GB** free storage for AI models
- **Device** — Physical device recommended for best performance

### Clone & Build

```bash
# Clone the repository
git clone https://github.com/RunanywhereAI/runanywhere-sdks.git
cd runanywhere-sdks/examples/flutter/RunAnywhereAI

# Install dependencies
flutter pub get

# Run on connected device
flutter run
```

### Run via IDE

1. Open the project in VS Code or Android Studio
2. Wait for Flutter dependencies to resolve
3. Select a physical device (iOS or Android)
4. Press **F5** (VS Code) or **Run** (Android Studio)

### Build Release APK/IPA

```bash
# Android APK
flutter build apk --release

# Android App Bundle
flutter build appbundle --release

# iOS (requires Xcode)
flutter build ios --release
```

---

## SDK Integration Examples

### Initialize the SDK

The SDK is initialized in `runanywhere_ai_app.dart`:

```dart
import 'package:runanywhere/runanywhere.dart';
import 'package:runanywhere_llamacpp/runanywhere_llamacpp.dart';
import 'package:runanywhere_mlx/runanywhere_mlx.dart';
import 'package:runanywhere_onnx/runanywhere_onnx.dart';

// 1. Register optional backends before SDK initialization.
LlamaCpp.register();
final mlxRegistered = await MLX.register(); // False unless this is a physical iOS device.
await Onnx.register();

// 2. Initialize SDK in development mode.
await RunAnywhere.initialize();

// 3. Seed models only for backends that actually registered.
await RunAnywhere.models.register(
  id: 'smollm2-360m-q8_0',
  name: 'SmolLM2 360M Q8_0',
  url: Uri.parse('https://huggingface.co/prithivMLmods/SmolLM2-360M-GGUF/resolve/main/SmolLM2-360M.Q8_0.gguf'),
  framework: InferenceFramework.INFERENCE_FRAMEWORK_LLAMA_CPP,
  memoryRequirement: 500000000,
);

await RunAnywhere.models.register(
  id: 'sherpa-onnx-whisper-tiny.en',
  name: 'Sherpa Whisper Tiny (ONNX)',
  url: Uri.parse('https://github.com/RunanywhereAI/sherpa-onnx/releases/download/runanywhere-models-v1/sherpa-onnx-whisper-tiny.en.tar.gz'),
  framework: InferenceFramework.INFERENCE_FRAMEWORK_SHERPA,
  modality: ModelCategory.MODEL_CATEGORY_SPEECH_RECOGNITION,
  memoryRequirement: 75000000,
);

if (mlxRegistered) {
  await RunAnywhere.models.register(
    id: 'mlx-qwen3-0.6b-4bit',
    name: 'MLX Qwen3 0.6B 4bit',
    url: 'https://huggingface.co/mlx-community/Qwen3-0.6B-4bit',
    framework: InferenceFramework.INFERENCE_FRAMEWORK_MLX,
    memoryRequirement: 650000000,
    supportsThinking: true,
  );
}
```

### Download & Load a Model

```dart
// Download with progress tracking
final progressStream = RunAnywhere.downloads.start('smollm2-360m-q8_0');
await for (final p in progressStream) {
  if (p.stage == DownloadStage.DOWNLOAD_STAGE_COMPLETED) break;
}

// Load LLM model
await RunAnywhere.llm.load('smollm2-360m-q8_0');

// Check if model is loaded
final isLoaded = RunAnywhere.isLLMModelLoaded;
```

### Stream Text Generation

```dart
// Generate with streaming (real-time tokens)
final stream = RunAnywhere.llm.generateStream(prompt, options);

await for (final event in stream) {
  if (event.isFinal) break;
  if (event.token.isNotEmpty) {
    setState(() {
      _responseText += event.token;
    });
  }
}

// Or non-streaming
final result = await RunAnywhere.llm.generate(prompt, options);
print('Response: ${result.text}');
print('Speed: ${result.tokensPerSecond} tok/s');
```

### Speech-to-Text

```dart
// Load STT model
await RunAnywhere.stt.load('sherpa-onnx-whisper-tiny.en');

// Transcribe audio bytes
final result = await RunAnywhere.stt.transcribe(audioBytes);
print('Transcription: ${result.text}');
```

### Text-to-Speech

```dart
// Load TTS voice
await RunAnywhere.tts.loadVoice('vits-piper-en_US-lessac-medium');

// Synthesize speech with options
final result = await RunAnywhere.tts.synthesize(
  text,
  TTSOptions(rate: 1.0, pitch: 1.0, volume: 1.0),
);

// Play audio (result.audio is Uint8List PCM16)
await audioPlayer.play(result.audio, result.sampleRate);
```

### Voice Assistant Pipeline (STT to LLM to TTS)

```dart
// Subscribe to the voice agent event stream
final sub = RunAnywhere.voice.eventStream().listen((event) {
  if (event.hasUserSaid()) {
    print('User said: ${event.userSaid.text}');
  } else if (event.hasAssistantToken()) {
    print('Token: ${event.assistantToken.text}');
  }
});

// Initialize pipeline with loaded models
await RunAnywhere.voice.initializeWithLoadedModels();

// Cancel when done
await sub.cancel();
```

---

## Key Screens Explained

### 1. Chat Screen (`chat_interface_view.dart`)

**What it demonstrates:**
- Streaming text generation with real-time token display
- Thinking mode support (`<think>...</think>` tags)
- Message analytics (tokens/sec, generation time)
- Conversation history with Markdown rendering
- Model selection bottom sheet integration

**Key SDK APIs:**
- `RunAnywhere.llm.generateStream()` — Streaming generation
- `RunAnywhere.llm.generate()` — Non-streaming generation
- `RunAnywhere.currentLLMModel` — Get loaded model info

### 2. Speech-to-Text Screen (`speech_to_text_view.dart`)

**What it demonstrates:**
- Batch mode: Record full audio, then transcribe
- Live mode: Real-time streaming transcription (when supported)
- Audio level visualization
- Mode selection (batch vs. live)

**Key SDK APIs:**
- `RunAnywhere.stt.load()` — Load Whisper model
- `RunAnywhere.stt.transcribe()` — Batch transcription
- `RunAnywhere.isSTTModelLoaded` — Check model status

### 3. Text-to-Speech Screen (`text_to_speech_view.dart`)

**What it demonstrates:**
- Neural voice synthesis with Piper TTS
- Speed and pitch controls with sliders
- Audio playback with progress indicator
- Audio metadata display (duration, sample rate, size)

**Key SDK APIs:**
- `RunAnywhere.tts.loadVoice()` — Load TTS model
- `RunAnywhere.tts.synthesize()` — Generate speech audio
- `RunAnywhere.isTTSVoiceLoaded` — Check voice status

### 4. Voice Assistant Screen (`voice_assistant_view.dart`)

**What it demonstrates:**
- Complete voice AI pipeline (STT to LLM to TTS)
- Model configuration for all 3 components
- Audio level visualization during recording
- Conversation turn management
- Session state machine (connecting, listening, processing, speaking)

**Key SDK APIs:**
- `RunAnywhere.voice.eventStream()` — Voice agent event stream
- `RunAnywhere.voice.initializeWithLoadedModels()` — Initialize pipeline
- `VoiceEvent` — Proto-typed voice session events

### 5. Settings Screen (`combined_settings_view.dart`)

**What it demonstrates:**
- Storage usage overview (total, available, model storage)
- Downloaded model list with details
- Model deletion with confirmation dialog
- Analytics logging toggle

**Key SDK APIs:**
- `RunAnywhere.downloads.getStorageInfo()` — Get storage details
- `RunAnywhere.downloads.list()` — List models
- `RunAnywhere.downloads.delete()` — Remove model

---

## Supported Models

### LLM Models (LlamaCpp/GGUF)

| Model | Size | Memory | Description |
|-------|------|--------|-------------|
| SmolLM2 360M Q8_0 | ~400MB | 500MB | Fast, lightweight chat |
| Qwen 2.5 0.5B Q6_K | ~500MB | 600MB | Multilingual, efficient |
| LFM2 350M Q4_K_M | ~200MB | 250MB | LiquidAI, ultra-compact |
| LFM2 350M Q8_0 | ~350MB | 400MB | Higher quality version |
| Llama 2 7B Chat Q4_K_M | ~4GB | 4GB | Powerful, larger model |
| Mistral 7B Instruct Q4_K_M | ~4GB | 4GB | High quality responses |

### STT Models (ONNX/Whisper)

| Model | Size | Description |
|-------|------|-------------|
| Sherpa Whisper Tiny (EN) | ~75MB | Fast English transcription |
| Sherpa Whisper Small (EN) | ~250MB | Higher accuracy |

### TTS Models (ONNX/Piper)

| Model | Size | Description |
|-------|------|-------------|
| Piper US English (Medium) | ~65MB | Natural American voice |
| Piper British English (Medium) | ~65MB | British accent |

---

## Testing

### Run Tests

```bash
# Run all tests
flutter test

# Run with coverage
flutter test --coverage

# Run specific test file
flutter test test/widget_test.dart
```

### Run Lint & Analysis

```bash
# Analyze code quality
flutter analyze

# Format code
dart format lib/ test/

# Fix issues automatically
dart fix --apply
```

---

## Debugging

### Enable Verbose Logging

The app uses `debugPrint()` extensively. Filter logs by:

```bash
# Flutter logs
flutter logs | grep -E "RunAnywhere|SDK"
```

### Common Debug Messages

| Log Prefix | Description |
|------------|-------------|
| `SDK` | SDK initialization |
| `SUCCESS` | Success operations |
| `ERROR` | Error conditions |
| `MODULE` | Module registration |
| `LOADING` | Loading/processing |
| `AUDIO` | Audio operations |
| `RECORDING` | Recording operations |

### Memory Profiling

1. Run app in profile mode: `flutter run --profile`
2. Open DevTools: Press `p` in terminal
3. Navigate to Memory tab
4. Expected: ~300MB-2GB depending on model size

---

## Configuration

### Environment Setup

The SDK automatically detects the environment:

```dart
// Development mode (default)
if (kDebugMode) {
  await RunAnywhere.initialize();
}

// Production mode
else {
  await RunAnywhere.initialize(
    apiKey: 'your-api-key',
    baseURL: 'https://api.runanywhere.ai',
    environment: SDKEnvironment.SDK_ENVIRONMENT_PRODUCTION,
  );
}
```

### Preference Keys

User preferences are stored via `SharedPreferences`:

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `useStreaming` | bool | `true` | Enable streaming generation |
| `defaultTemperature` | double | `0.7` | LLM temperature |
| `defaultMaxTokens` | int | `500` | Max tokens per generation |

---

## Known Limitations

- **ARM64 Recommended** — Native libraries optimized for arm64 (x86 emulators may be slow)
- **Memory Usage** — Large models (7B+) require devices with 6GB+ RAM
- **First Load** — Initial model loading takes 1-3 seconds (cached afterward)
- **Live STT** — Best with Sherpa-ONNX streaming models (limited in plain ONNX)
- **Platform Channels** — Some SDK features use FFI/platform channels

---

## iOS Parity Notes

The iOS example app is the canonical reference. This app mirrors its tab
structure, model catalog (`lib/core/services/model_catalog_bootstrap.dart`),
model-picker filtering, generated solutions YAML, ViewModel layering, hybrid
STT, and benchmarks. Intentionally unsupported iOS-only surfaces:

- **Voice Keyboard** — depends on the iOS app-extension targets
  (`RunAnywhereKeyboard`, `RunAnywhereActivityExtension`) and Live
  Activities; there is no Flutter analogue for a system keyboard extension.
- **FoundationModels smart conversation titles** — Apple-platform-gated
  (iOS 26 FoundationModels); the Flutter app uses a deterministic
  first-user-message title fallback instead.

---

## Contributing

We welcome contributions! See [CONTRIBUTING.md](../../../CONTRIBUTING.md) for guidelines.

### Development Setup

```bash
# Fork and clone
git clone https://github.com/YOUR_USERNAME/runanywhere-sdks.git
cd runanywhere-sdks/examples/flutter/RunAnywhereAI

# Create feature branch
git checkout -b feature/your-feature

# Make changes and test
flutter pub get
flutter analyze
flutter test

# Commit and push
git commit -m "feat: your feature description"
git push origin feature/your-feature

# Open Pull Request
```

---

## License

This project is licensed under the RunAnywhere License (Apache 2.0 based, with additional commercial-use terms). See [LICENSE](../../../LICENSE) for details.

---

## Support

- **Discord**: [Join our community](https://discord.gg/N359FBbDVd)
- **GitHub Issues**: [Report bugs](https://github.com/RunanywhereAI/runanywhere-sdks/issues)
- **Email**: san@runanywhere.ai
- **Twitter**: [@RunanywhereAI](https://twitter.com/RunanywhereAI)

---

## Related Documentation

- [RunAnywhere Flutter SDK](../../../sdk/runanywhere-flutter/README.md) — Full SDK documentation
- [iOS Example App](../../ios/RunAnywhereAI/README.md) — iOS counterpart
- [Android Example App](../../android/RunAnywhereAI/README.md) — Android counterpart
- [React Native Example](../../react-native/RunAnywhereAI/README.md) — React Native option
- [Main README](../../../README.md) — Project overview
