# RunAnywhere AI - Flutter Example

<p align="center">
  <img src="../../../examples/logo.svg" alt="RunAnywhere Logo" width="120"/>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/Platform-iOS%2013.0%2B%20%7C%20Android%207.0%2B-02569B?style=flat-square&logo=flutter&logoColor=white" alt="iOS 13.0+ | Android 7.0+" />
  <img src="https://img.shields.io/badge/Flutter-3.10%2B-02569B?style=flat-square&logo=flutter&logoColor=white" alt="Flutter 3.10+" />
  <img src="https://img.shields.io/badge/Dart-3.0%2B-0175C2?style=flat-square&logo=dart&logoColor=white" alt="Dart 3.0+" />
  <img src="https://img.shields.io/badge/License-Apache%202.0-blue?style=flat-square" alt="License" />
</p>

**A production-ready reference app demonstrating the [RunAnywhere Flutter SDK](../../../sdk/runanywhere-flutter/) capabilities for on-device AI.** This app showcases how to build privacy-first, offline-capable AI features with LLM chat, speech-to-text, text-to-speech, and a complete voice assistant pipeline—all running locally on your device.

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
| **AI Chat** | Interactive LLM conversations with streaming responses | `RunAnywhere.generateStream()` |
| **Thinking Mode** | Support for models with `<think>...</think>` reasoning | Thinking tag parsing |
| **Real-time Analytics** | Token speed, generation time, inference metrics | `MessageAnalytics` |
| **Speech-to-Text** | Voice transcription with batch & live modes | `RunAnywhere.transcribe()` |
| **Text-to-Speech** | Neural voice synthesis with Piper TTS | `RunAnywhere.synthesize()` |
| **Voice Assistant** | Full STT to LLM to TTS pipeline with auto-detection | `VoiceSession` API |
| **Model Management** | Download, load, and manage multiple AI models | `ModelManager` |
| **Storage Management** | View storage usage and delete models | `RunAnywhere.getStorageInfo()` |
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
│  │                   Provider State Management                   │   │
│  │                   (ModelManager, Services)                    │   │
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

- **Provider Pattern** — `ChangeNotifier` + `Provider` for state management
- **Feature-First Structure** — Each feature is self-contained with its own views and logic
- **Shared Core Services** — `ModelManager`, `AudioRecordingService`, `AudioPlayerService`
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
│   │   │   ├── model_manager.dart     # SDK model management wrapper
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

- **Flutter** 3.10.0 or later ([install guide](https://flutter.dev/docs/get-started/install))
- **Dart** 3.0.0 or later (included with Flutter)
- **iOS** — Xcode 14+ (for iOS builds)
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
import 'package:runanywhere_onnx/runanywhere_onnx.dart';

// 1. Initialize SDK in development mode
await RunAnywhere.initialize();

// 2. Register LlamaCpp module for LLM models (GGUF)
await LlamaCpp.register();
LlamaCpp.addModel(
  id: 'smollm2-360m-q8_0',
  name: 'SmolLM2 360M Q8_0',
  url: 'https://huggingface.co/prithivMLmods/SmolLM2-360M-GGUF/resolve/main/SmolLM2-360M.Q8_0.gguf',
  memoryRequirement: 500000000,
);

// 3. Register ONNX module for STT/TTS models
await Onnx.register();
Onnx.addModel(
  id: 'sherpa-onnx-whisper-tiny.en',
  name: 'Sherpa Whisper Tiny (ONNX)',
  url: 'https://github.com/RunanywhereAI/sherpa-onnx/releases/download/runanywhere-models-v1/sherpa-onnx-whisper-tiny.en.tar.gz',
  modality: ModelCategory.speechRecognition,
  memoryRequirement: 75000000,
);
```

### Download & Load a Model

```dart
// Download with progress tracking (via ModelManager)
await ModelManager.shared.downloadModel(modelInfo);

// Load LLM model
await sdk.RunAnywhere.loadLLMModel('smollm2-360m-q8_0');

// Check if model is loaded
final isLoaded = sdk.RunAnywhere.isModelLoaded;
```

### Stream Text Generation

```dart
// Generate with streaming (real-time tokens)
final streamResult = await RunAnywhere.generateStream(prompt, options: options);

await for (final token in streamResult.stream) {
  // Display each token as it arrives
  setState(() {
    _responseText += token;
  });
}

// Or non-streaming
final result = await RunAnywhere.generate(prompt, options: options);
print('Response: ${result.text}');
print('Speed: ${result.tokensPerSecond} tok/s');
```

### Speech-to-Text

```dart
// Load STT model
await RunAnywhere.loadSTTModel('sherpa-onnx-whisper-tiny.en');

// Transcribe audio bytes
final transcription = await RunAnywhere.transcribe(audioBytes);
print('Transcription: $transcription');
```

### Text-to-Speech

```dart
// Load TTS voice
await RunAnywhere.loadTTSVoice('vits-piper-en_US-lessac-medium');

// Synthesize speech with options
final result = await RunAnywhere.synthesize(
  text,
  rate: 1.0,
  pitch: 1.0,
  volume: 1.0,
);

// Play audio (result.samples is Float32List)
await audioPlayer.play(result.samples, result.sampleRate);
```

### Voice Assistant Pipeline (STT to LLM to TTS)

```dart
// Start voice session
final session = await RunAnywhere.startVoiceSession(
  config: VoiceSessionConfig(),
);

// Listen to session events
session.events.listen((event) {
  if (event is VoiceSessionTranscribed) {
    print('User said: ${event.text}');
  } else if (event is VoiceSessionResponded) {
    print('AI response: ${event.text}');
  } else if (event is VoiceSessionSpeaking) {
    // Audio is being played
  }
});

// Stop session
session.stop();
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
- `RunAnywhere.generateStream()` — Streaming generation
- `RunAnywhere.generate()` — Non-streaming generation
- `RunAnywhere.currentLLMModel()` — Get loaded model info

### 2. Speech-to-Text Screen (`speech_to_text_view.dart`)

**What it demonstrates:**
- Batch mode: Record full audio, then transcribe
- Live mode: Real-time streaming transcription (when supported)
- Audio level visualization
- Mode selection (batch vs. live)

**Key SDK APIs:**
- `RunAnywhere.loadSTTModel()` — Load Whisper model
- `RunAnywhere.transcribe()` — Batch transcription
- `RunAnywhere.isSTTModelLoaded` — Check model status

### 3. Text-to-Speech Screen (`text_to_speech_view.dart`)

**What it demonstrates:**
- Neural voice synthesis with Piper TTS
- Speed and pitch controls with sliders
- Audio playback with progress indicator
- Audio metadata display (duration, sample rate, size)

**Key SDK APIs:**
- `RunAnywhere.loadTTSVoice()` — Load TTS model
- `RunAnywhere.synthesize()` — Generate speech audio
- `RunAnywhere.isTTSVoiceLoaded` — Check voice status

### 4. Voice Assistant Screen (`voice_assistant_view.dart`)

**What it demonstrates:**
- Complete voice AI pipeline (STT to LLM to TTS)
- Model configuration for all 3 components
- Audio level visualization during recording
- Conversation turn management
- Session state machine (connecting, listening, processing, speaking)

**Key SDK APIs:**
- `RunAnywhere.startVoiceSession()` — Start voice session
- `RunAnywhere.isVoiceAgentReady` — Check all components loaded
- `VoiceSessionEvent` — Session event stream

### 5. Settings Screen (`combined_settings_view.dart`)

**What it demonstrates:**
- Storage usage overview (total, available, model storage)
- Downloaded model list with details
- Model deletion with confirmation dialog
- Analytics logging toggle

**Key SDK APIs:**
- `RunAnywhere.getStorageInfo()` — Get storage details
- `RunAnywhere.getDownloadedModelsWithInfo()` — List models
- `RunAnywhere.deleteStoredModel()` — Remove model

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
    environment: SDKEnvironment.production,
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
- **Live STT** — Requires WhisperKit-compatible models (limited in ONNX)
- **Platform Channels** — Some SDK features use FFI/platform channels

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

This project is licensed under the Apache License 2.0 - see [LICENSE](../../../LICENSE) for details.

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
