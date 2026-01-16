# RunAnywhere Flutter SDK

<p align="center">
  <img src="../../examples/logo.svg" alt="RunAnywhere Logo" width="140"/>
</p>

<p align="center">
  <strong>On-Device AI for Flutter Applications</strong><br/>
  Run LLMs, Speech-to-Text, Text-to-Speech, and Voice AI pipelines locally—privacy-first, offline-capable, production-ready.
</p>

<p align="center">
  <a href="https://flutter.dev"><img src="https://img.shields.io/badge/Flutter-3.10+-02569B?style=flat-square&logo=flutter&logoColor=white" alt="Flutter 3.10+" /></a>
  <a href="https://dart.dev"><img src="https://img.shields.io/badge/Dart-3.0+-0175C2?style=flat-square&logo=dart&logoColor=white" alt="Dart 3.0+" /></a>
  <a href="#"><img src="https://img.shields.io/badge/iOS-14.0+-000000?style=flat-square&logo=apple&logoColor=white" alt="iOS 14.0+" /></a>
  <a href="#"><img src="https://img.shields.io/badge/Android-API%2024+-3DDC84?style=flat-square&logo=android&logoColor=white" alt="Android API 24+" /></a>
  <a href="../../LICENSE"><img src="https://img.shields.io/badge/License-Apache%202.0-blue?style=flat-square" alt="License" /></a>
</p>

---

## Quick Links

- [Architecture Overview](#architecture-overview) — How the SDK works
- [Quick Start](#quick-start) — Get running in 5 minutes
- [API Reference](Documentation.md) — Complete public API documentation
- [Flutter Starter Example](https://github.com/RunanywhereAI/flutter-starter-example) — Minimal starter project
- [FAQ](#faq) — Common questions answered
- [Troubleshooting](#troubleshooting) — Problems & solutions
- [Contributing](#contributing) — How to contribute

---

## Features

### Large Language Models (LLM)
- On-device text generation with streaming support
- **LlamaCPP** backend for GGUF models with Metal/GPU acceleration
- Customizable generation parameters (temperature, max tokens, etc.)
- Support for thinking/reasoning models (`<think>...</think>` patterns)
- Token-by-token streaming for responsive UX

### Speech-to-Text (STT)
- Real-time streaming transcription
- Batch audio transcription with Whisper models via ONNX Runtime
- Multi-language support
- Confidence scores and timestamps

### Text-to-Speech (TTS)
- Neural voice synthesis with Piper TTS
- System voices fallback via `flutter_tts`
- Customizable voice, pitch, rate, and volume
- PCM audio output for flexible playback

### Voice Activity Detection (VAD)
- Energy-based speech detection with Silero VAD
- Configurable sensitivity thresholds
- Real-time audio stream processing

### Voice Agent Pipeline
- Full VAD → STT → LLM → TTS orchestration
- Complete voice conversation flow
- Session-based management with events

### Infrastructure
- Automatic model discovery and download with progress tracking
- Comprehensive event system via `EventBus`
- Structured logging with `SDKLogger`
- Platform-optimized native binaries (XCFrameworks + JNI)

---

## System Requirements

| Component | Minimum | Recommended |
|-----------|---------|-------------|
| **Flutter** | 3.10.0+ | 3.24.0+ |
| **Dart** | 3.0.0+ | 3.5.0+ |
| **iOS** | 14.0+ | 15.0+ |
| **Android** | API 24 (7.0) | API 28+ |
| **Xcode** | 14.0+ | 15.0+ |
| **RAM** | 2GB | 4GB+ for larger models |
| **Storage** | Variable | Models: 100MB–8GB |

> **Note:** ARM64 devices are recommended for best performance. Metal GPU acceleration on iOS and NEON SIMD on Android provide significant speedups over CPU-only inference.

---

## Installation

### Add Dependencies

Add the packages you need to your `pubspec.yaml`:

**Core + LlamaCpp (LLM):**

```yaml
dependencies:
  runanywhere: ^0.15.11
  runanywhere_llamacpp: ^0.15.11
```

**Core + ONNX (STT/TTS/VAD):**

```yaml
dependencies:
  runanywhere: ^0.15.11
  runanywhere_onnx: ^0.15.11
```

**All Backends (LLM + STT + TTS + VAD):**

```yaml
dependencies:
  runanywhere: ^0.15.11
  runanywhere_llamacpp: ^0.15.11
  runanywhere_onnx: ^0.15.11
```

Then run:

```bash
flutter pub get
```

---

## Platform Setup

### iOS Setup (Required)

After adding the packages, update your iOS Podfile:

**1. Update `ios/Podfile`:**

```ruby
# Set minimum iOS version to 14.0
platform :ios, '14.0'

target 'Runner' do
  # REQUIRED: Add static linkage
  use_frameworks! :linkage => :static

  flutter_install_all_ios_pods File.dirname(File.realpath(__FILE__))
end

post_install do |installer|
  installer.pods_project.targets.each do |target|
    flutter_additional_ios_build_settings(target)
    target.build_configurations.each do |config|
      config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '14.0'
      # Required for microphone permission (STT/Voice features)
      config.build_settings['GCC_PREPROCESSOR_DEFINITIONS'] ||= [
        '$(inherited)',
        'PERMISSION_MICROPHONE=1',
      ]
    end
  end
end
```

> **Important:** Without `use_frameworks! :linkage => :static`, you will see "symbol not found" errors at runtime.

**2. Update `ios/Runner/Info.plist`:**

Add microphone permission for STT/Voice features:

```xml
<key>NSMicrophoneUsageDescription</key>
<string>This app needs microphone access for speech recognition</string>
```

**3. Run pod install:**

```bash
cd ios && pod install && cd ..
```

### Android Setup

Add microphone permission to `android/app/src/main/AndroidManifest.xml`:

```xml
<uses-permission android:name="android.permission.RECORD_AUDIO" />
```

---

## Quick Start

### 1. Initialize the SDK

```dart
import 'package:runanywhere/runanywhere.dart';
import 'package:runanywhere_llamacpp/runanywhere_llamacpp.dart';
import 'package:runanywhere_onnx/runanywhere_onnx.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 1. Initialize SDK (development mode - no API key needed)
  await RunAnywhere.initialize();

  // 2. Register backend modules
  await LlamaCpp.register();  // LLM backend (GGUF models)
  await Onnx.register();      // STT/TTS backend (Whisper, Piper)

  print('RunAnywhere SDK initialized: v${RunAnywhere.version}');

  runApp(const MyApp());
}
```

### 2. Register Models

```dart
// Register an LLM model
LlamaCpp.addModel(
  id: 'smollm2-360m-q8_0',
  name: 'SmolLM2 360M Q8_0',
  url: 'https://huggingface.co/prithivMLmods/SmolLM2-360M-GGUF/resolve/main/SmolLM2-360M.Q8_0.gguf',
  memoryRequirement: 500000000,
);

// Register an STT model
Onnx.addModel(
  id: 'sherpa-onnx-whisper-tiny.en',
  name: 'Whisper Tiny English',
  url: 'https://github.com/RunanywhereAI/sherpa-onnx/releases/download/runanywhere-models-v1/sherpa-onnx-whisper-tiny.en.tar.gz',
  modality: ModelCategory.speechRecognition,
);

// Register a TTS voice
Onnx.addModel(
  id: 'vits-piper-en_US-lessac-medium',
  name: 'Piper US English',
  url: 'https://github.com/RunanywhereAI/sherpa-onnx/releases/download/runanywhere-models-v1/vits-piper-en_US-lessac-medium.tar.bz2',
  modality: ModelCategory.textToSpeech,
);
```

### 3. Download & Load Models

```dart
// Download with progress
await for (final progress in RunAnywhere.downloadModel('smollm2-360m-q8_0')) {
  print('Download: ${(progress.bytesDownloaded / progress.totalBytes * 100).toStringAsFixed(1)}%');
  if (progress.state == DownloadProgressState.completed) break;
}

// Load the model
await RunAnywhere.loadModel('smollm2-360m-q8_0');
print('Model loaded: ${RunAnywhere.currentModelId}');
```

### 4. Generate Text

```dart
// Simple chat interface
final response = await RunAnywhere.chat('What is the capital of France?');
print(response);  // "The capital of France is Paris."

// Full generation with metrics
final result = await RunAnywhere.generate(
  'Explain quantum computing in simple terms',
  options: LLMGenerationOptions(
    maxTokens: 200,
    temperature: 0.7,
  ),
);
print('Response: ${result.text}');
print('Speed: ${result.tokensPerSecond.toStringAsFixed(1)} tok/s');
print('Latency: ${result.latencyMs.toStringAsFixed(0)}ms');
```

### 5. Streaming Generation

```dart
final streamResult = await RunAnywhere.generateStream(
  'Write a short poem about AI',
  options: LLMGenerationOptions(maxTokens: 150),
);

// Display tokens in real-time
await for (final token in streamResult.stream) {
  print(token, terminator: '');
}

// Get final metrics
final metrics = await streamResult.result;
print('\nSpeed: ${metrics.tokensPerSecond.toStringAsFixed(1)} tok/s');

// Cancel if needed
// streamResult.cancel();
```

### 6. Speech-to-Text

```dart
// Load STT model
await RunAnywhere.loadSTTModel('sherpa-onnx-whisper-tiny.en');

// Transcribe audio data (PCM16 at 16kHz mono)
final transcription = await RunAnywhere.transcribe(audioBytes);
print('Transcription: $transcription');

// With detailed result
final result = await RunAnywhere.transcribeWithResult(audioBytes);
print('Text: ${result.text}');
print('Confidence: ${result.confidence}');
```

### 7. Text-to-Speech

```dart
// Load TTS voice
await RunAnywhere.loadTTSVoice('vits-piper-en_US-lessac-medium');

// Synthesize speech
final ttsResult = await RunAnywhere.synthesize(
  'Hello! Welcome to RunAnywhere.',
  rate: 1.0,
  pitch: 1.0,
);
// ttsResult.samples contains PCM Float32 audio
// ttsResult.sampleRate is typically 22050 Hz
```

### 8. Voice Agent Pipeline

```dart
// Ensure all components are loaded
if (!RunAnywhere.isVoiceAgentReady) {
  await RunAnywhere.loadSTTModel('sherpa-onnx-whisper-tiny.en');
  await RunAnywhere.loadModel('smollm2-360m-q8_0');
  await RunAnywhere.loadTTSVoice('vits-piper-en_US-lessac-medium');
}

// Start voice session
final session = await RunAnywhere.startVoiceSession();

// Listen to session events
session.events.listen((event) {
  switch (event.runtimeType) {
    case VoiceSessionListening:
      print('Listening... Level: ${(event as VoiceSessionListening).audioLevel}');
    case VoiceSessionTurnCompleted:
      final completed = event as VoiceSessionTurnCompleted;
      print('User: ${completed.transcript}');
      print('AI: ${completed.response}');
  }
});

// Stop when done
await session.stop();
```

---

## Architecture Overview

The RunAnywhere Flutter SDK follows a **modular, provider-based architecture** with a C++ commons layer for cross-platform performance:

```
┌─────────────────────────────────────────────────────────────────┐
│                      Your Flutter Application                     │
├─────────────────────────────────────────────────────────────────┤
│                    RunAnywhere Flutter SDK                        │
│  ┌──────────────┐  ┌───────────────┐  ┌──────────────────────┐  │
│  │ Public APIs  │  │  EventBus     │  │  ModelRegistry       │  │
│  │ (generate,   │  │  (events,     │  │  (model discovery,   │  │
│  │  transcribe) │  │   lifecycle)  │  │   download)          │  │
│  └──────────────┘  └───────────────┘  └──────────────────────┘  │
├─────────────────────────────────────────────────────────────────┤
│                    Native Bridge Layer (FFI)                      │
│                  DartBridge → C++ Commons APIs                    │
├────────────┬─────────────┬──────────────────────────────────────┤
│  LlamaCpp  │    ONNX     │        Future Backends...            │
│  Backend   │   Backend   │                                       │
│  (LLM)     │ (STT/TTS)   │                                       │
└────────────┴─────────────┴──────────────────────────────────────┘
```

### Key Components

| Component | Description |
|-----------|-------------|
| **RunAnywhere** | Static class providing all public SDK methods |
| **EventBus** | Dart Stream-based event subscription for reactive UI |
| **DartBridge** | FFI bridge to C++ native libraries |
| **ModelRegistry** | Model discovery, registration, and persistence |

### Package Composition

| Package | Size | Provides |
|---------|------|----------|
| `runanywhere` | ~5MB | Core SDK, APIs, infrastructure |
| `runanywhere_llamacpp` | ~15-25MB | LLM capability (GGUF models) |
| `runanywhere_onnx` | ~50-70MB | STT, TTS, VAD (ONNX models) |

> For detailed architecture documentation, see [ARCHITECTURE.md](ARCHITECTURE.md).

---

## Configuration

### SDK Initialization Parameters

```dart
// Development mode (default) - no API key needed
await RunAnywhere.initialize();

// Production mode - requires API key and backend URL
await RunAnywhere.initialize(
  apiKey: '<YOUR_API_KEY>',
  baseURL: 'https://api.runanywhere.ai',
  environment: SDKEnvironment.production,
);
```

### Environment Modes

| Environment | Description |
|-------------|-------------|
| `.development` | Verbose logging, local-only, no auth required |
| `.staging` | Testing with real services |
| `.production` | Minimal logging, full authentication, telemetry |

### Generation Options

```dart
final options = LLMGenerationOptions(
  maxTokens: 256,              // Maximum tokens to generate
  temperature: 0.7,            // Sampling temperature (0.0–2.0)
  topP: 0.95,                  // Top-p sampling parameter
  stopSequences: ['END'],      // Stop generation at these sequences
  systemPrompt: 'You are a helpful assistant.',
);
```

---

## Error Handling

The SDK provides comprehensive error handling through `SDKError`:

```dart
try {
  final response = await RunAnywhere.generate('Hello!');
} on SDKError catch (error) {
  switch (error.code) {
    case SDKErrorCode.notInitialized:
      print('SDK not initialized. Call RunAnywhere.initialize() first.');
    case SDKErrorCode.modelNotFound:
      print('Model not found. Download it first.');
    case SDKErrorCode.modelNotDownloaded:
      print('Model not downloaded. Call downloadModel() first.');
    case SDKErrorCode.componentNotReady:
      print('Component not ready. Load the model first.');
    default:
      print('Error: ${error.message}');
  }
}
```

### Error Categories

| Category | Description |
|----------|-------------|
| `general` | General SDK errors |
| `llm` | LLM generation errors |
| `stt` | Speech-to-text errors |
| `tts` | Text-to-speech errors |
| `voiceAgent` | Voice pipeline errors |
| `download` | Model download errors |
| `validation` | Input validation errors |

---

## Logging & Observability

### Subscribe to Events

```dart
// Subscribe to all events
RunAnywhere.events.events.listen((event) {
  print('Event: ${event.type}');
});

// Subscribe to specific event types
RunAnywhere.events.events
    .where((e) => e is SDKModelEvent)
    .listen((event) {
      print('Model Event: ${event.type}');
    });
```

### Event Types

| Event | Description |
|-------|-------------|
| `SDKInitializationStarted` | SDK initialization began |
| `SDKInitializationCompleted` | SDK initialized successfully |
| `SDKModelEvent.loadStarted` | Model loading started |
| `SDKModelEvent.loadCompleted` | Model loaded successfully |
| `SDKModelEvent.downloadProgress` | Download progress update |

---

## Performance & Best Practices

### Model Selection

| Model Size | RAM Required | Use Case |
|------------|--------------|----------|
| 360M–500M (Q8) | ~500MB | Fast, lightweight chat |
| 1B–3B (Q4/Q6) | 1–2GB | Balanced quality/speed |
| 7B (Q4) | 4–5GB | High quality, slower |

### Memory Management

```dart
// Unload models when not in use
await RunAnywhere.unloadModel();
await RunAnywhere.unloadSTTModel();
await RunAnywhere.unloadTTSVoice();

// Check storage before downloading
final storageInfo = await RunAnywhere.getStorageInfo();
print('Available: ${storageInfo.deviceStorage.freeSpace} bytes');

// Delete unused models
await RunAnywhere.deleteStoredModel('old-model-id');
```

### Best Practices

1. **Prefer streaming** for better perceived latency
2. **Unload unused models** to free memory
3. **Handle errors gracefully** with user-friendly messages
4. **Test on physical devices** — emulators may be slow
5. **Use smaller models** for faster iteration during development
6. **Register models at startup** before calling `availableModels()`

---

## Troubleshooting

### Model Download Fails

**Symptoms:** Download stuck or fails with network error

**Solutions:**
1. Check internet connection
2. Verify sufficient storage (need 2x model size for extraction)
3. Try on WiFi instead of cellular
4. Check if model URL is accessible

### Out of Memory

**Symptoms:** App crashes during model loading or inference

**Solutions:**
1. Use a smaller model (360M instead of 7B)
2. Unload unused models first
3. Close other memory-intensive apps
4. Test on device with more RAM

### iOS: Symbol Not Found

**Symptoms:** Runtime crash with "symbol not found" error

**Solutions:**
1. Ensure `use_frameworks! :linkage => :static` in Podfile
2. Run `cd ios && pod install --repo-update`
3. Clean and rebuild: `flutter clean && flutter run`

### Android: Library Load Failed

**Symptoms:** `UnsatisfiedLinkError` or library load failure

**Solutions:**
1. Ensure NDK is properly installed
2. Check that `jniLibs` folder contains `.so` files
3. Rebuild native libraries with `./scripts/build-flutter.sh --setup`

### Model Not Found After Download

**Symptoms:** `modelNotFound` error even though download completed

**Solutions:**
1. Call `await RunAnywhere.refreshDiscoveredModels()` to refresh registry
2. Check model path in storage
3. Delete and re-download the model

---

## FAQ

### Q: Do I need an internet connection?
**A:** Only for initial model download. Once downloaded, all inference runs 100% on-device with no network required.

### Q: How much storage do models need?
**A:** Varies by model:
- Small LLMs (360M–1B): 200MB–1GB
- Medium LLMs (3B–7B Q4): 2–5GB
- STT models (Whisper): 50–250MB
- TTS voices (Piper): 20–100MB

### Q: Is user data sent to the cloud?
**A:** No. All inference happens on-device. Only anonymous analytics (latency, error rates) are collected in production mode, and this can be disabled.

### Q: Which devices are supported?
**A:** iOS 14+ and Android API 24+. ARM64 devices are recommended for best performance.

### Q: Can I use custom models?
**A:** Yes! Any GGUF model works with LlamaCpp backend. ONNX models work for STT/TTS with the appropriate format.

### Q: How do I test on iOS Simulator?
**A:** The SDK supports both arm64 and x86_64 simulators, but performance will be significantly slower than physical devices.

---

## Local Development & Contributing

Contributions are welcome. This section explains how to set up your development environment to build the SDK from source and test your changes with the sample app.

### Prerequisites

- **Flutter** 3.10.0 or later
- **Xcode** 14+ (for iOS builds)
- **Android Studio** with NDK (for Android builds)
- **CMake** 3.21+

### First-Time Setup (Build from Source)

The SDK depends on native C++ libraries from `runanywhere-commons`. The setup script builds these locally so you can develop and test the SDK end-to-end.

```bash
# 1. Clone the repository
git clone https://github.com/RunanywhereAI/runanywhere-sdks.git
cd runanywhere-sdks/sdk/runanywhere-flutter

# 2. Run first-time setup (~10-20 minutes)
./scripts/build-flutter.sh --setup

# 3. Bootstrap Flutter packages
melos bootstrap   # If melos is installed
# OR manually:
cd packages/runanywhere && flutter pub get && cd ..
cd packages/runanywhere_llamacpp && flutter pub get && cd ..
cd packages/runanywhere_onnx && flutter pub get && cd ..
```

**What the setup script does:**
1. Downloads dependencies (ONNX Runtime, Sherpa-ONNX)
2. Builds `RACommons.xcframework` and JNI libraries
3. Builds `RABackendLLAMACPP` (LLM backend)
4. Builds `RABackendONNX` (STT/TTS/VAD backend)
5. Copies frameworks to `ios/Frameworks/` and JNI libs to `android/src/main/jniLibs/`
6. Creates `.testlocal` marker files (enables local library consumption)

### Understanding testLocal

The SDK has two modes:

| Mode | Description |
|------|-------------|
| **Local** | Uses frameworks/JNI libs from package directories (for development) |
| **Remote** | Downloads from GitHub releases during `pod install`/Gradle sync (for end users) |

When you run `--setup`, the script automatically enables local mode via:
- **iOS**: `.testlocal` marker files in `ios/` directories
- **Android**: `testLocal = true` in `binary_config.gradle` files

### Testing with the Flutter Sample App

The recommended way to test SDK changes is with the sample app:

```bash
# 1. Ensure SDK is set up (from previous step)

# 2. Navigate to the sample app
cd ../../examples/flutter/RunAnywhereAI

# 3. Install dependencies
flutter pub get

# 4. Run on iOS
cd ios && pod install && cd ..
flutter run

# 5. Or run on Android
flutter run
```

You can open the sample app in **Android Studio** or **VS Code** for development.

The sample app's `pubspec.yaml` uses path dependencies to reference the local SDK packages:

```
Sample App → Local Flutter SDK Packages → Local Frameworks/JNI libs
                                                ↑
                               Built by build-flutter.sh --setup
```

### Development Workflow

**After modifying Dart SDK code:**
- Changes are picked up automatically when you run `flutter run`

**After modifying runanywhere-commons (C++ code):**

```bash
cd sdk/runanywhere-flutter
./scripts/build-flutter.sh --local --rebuild-commons
```

### Build Script Reference

| Command | Description |
|---------|-------------|
| `--setup` | First-time setup: downloads deps, builds all libraries, enables local mode |
| `--local` | Use local libraries from package directories |
| `--remote` | Use remote libraries from GitHub releases |
| `--rebuild-commons` | Rebuild runanywhere-commons from source |
| `--ios` | Build for iOS only |
| `--android` | Build for Android only |
| `--clean` | Clean build artifacts before building |
| `--abis=ABIS` | Android ABIs to build (default: `arm64-v8a`) |

### Code Style

We follow standard Dart style guidelines:

```bash
# Format code
dart format lib/ test/

# Analyze code
flutter analyze

# Fix issues automatically
dart fix --apply
```

### Pull Request Process

1. Fork the repository
2. Create a feature branch: `git checkout -b feature/my-feature`
3. Make your changes with tests
4. Ensure all tests pass: `flutter test`
5. Run analyzer: `flutter analyze`
6. Commit with a descriptive message
7. Push and open a Pull Request

### Reporting Issues

Open an issue on GitHub with:
- SDK version: `RunAnywhere.version`
- Flutter version: `flutter --version`
- Platform and OS version
- Device model
- Steps to reproduce
- Expected vs actual behavior
- Relevant logs (with sensitive info redacted)

---

## Support

- **Discord**: [discord.gg/N359FBbDVd](https://discord.gg/N359FBbDVd)
- **GitHub Issues**: [github.com/RunanywhereAI/runanywhere-sdks/issues](https://github.com/RunanywhereAI/runanywhere-sdks/issues)
- **Email**: san@runanywhere.ai
- **Twitter**: [@RunanywhereAI](https://twitter.com/RunanywhereAI)

---

## License

Apache License 2.0 — See [LICENSE](../../LICENSE) for details.

For commercial licensing inquiries, contact san@runanywhere.ai.

---

## Related Documentation

- [Architecture Overview](ARCHITECTURE.md) — Detailed system design
- [API Reference](Documentation.md) — Complete public API documentation
- [Flutter Starter Example](https://github.com/RunanywhereAI/flutter-starter-example) — Minimal starter project
- [Swift SDK](../runanywhere-swift/) — iOS/macOS native SDK
- [Kotlin SDK](../runanywhere-kotlin/) — Android native SDK
- [React Native SDK](../runanywhere-react-native/) — Cross-platform option

## Packages on pub.dev

- [runanywhere](https://pub.dev/packages/runanywhere) — Core SDK
- [runanywhere_llamacpp](https://pub.dev/packages/runanywhere_llamacpp) — LLM backend
- [runanywhere_onnx](https://pub.dev/packages/runanywhere_onnx) — STT/TTS/VAD backend
