# RunAnywhere ONNX Backend

[![pub package](https://img.shields.io/pub/v/runanywhere_onnx.svg)](https://pub.dev/packages/runanywhere_onnx)
[![License](https://img.shields.io/badge/License-RunAnywhere-blue.svg)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/main/LICENSE)
[![Platform](https://img.shields.io/badge/platform-iOS%20%7C%20Android-lightgrey.svg)]()

ONNX Runtime backend for the RunAnywhere Flutter SDK. Provides on-device Speech-to-Text (STT), Text-to-Speech (TTS), and Voice Activity Detection (VAD) capabilities.

---

## Features

| Feature | Description |
|---------|-------------|
| **Speech-to-Text (STT)** | Transcribe audio using Whisper models |
| **Text-to-Speech (TTS)** | Neural voice synthesis with Piper models |
| **Voice Activity Detection** | Real-time speech detection with Silero VAD |
| **Streaming Support** | Real-time transcription and synthesis |
| **Privacy-First** | All processing happens locally on device |
| **Multi-Language** | Support for 100+ languages (Whisper) |

---

## Installation

Add both the core SDK and this backend to your `pubspec.yaml`:

```yaml
dependencies:
  runanywhere: ^0.20.9
  runanywhere_onnx: ^0.20.9
```

Then run:

```bash
flutter pub get
```

> **Note:** This package requires the core `runanywhere` package. It won't work standalone.

---

## Platform Support

| Platform | Minimum Version | Requirements |
|----------|-----------------|--------------|
| iOS      | 17.5+           | Microphone permission |
| Android  | API 24+         | RECORD_AUDIO permission |

---

## Platform Setup

### iOS

Update `ios/Podfile`:

```ruby
platform :ios, '17.5'

target 'Runner' do
  use_frameworks! :linkage => :static  # Required!
  flutter_install_all_ios_pods File.dirname(File.realpath(__FILE__))
end
```

Add to `ios/Runner/Info.plist`:

```xml
<key>NSMicrophoneUsageDescription</key>
<string>Microphone access is needed for speech recognition</string>
```

### Android

Add to `android/app/src/main/AndroidManifest.xml`:

```xml
<uses-permission android:name="android.permission.RECORD_AUDIO" />
```

---

## Quick Start

### 1. Initialize & Register

```dart
import 'package:runanywhere/runanywhere.dart';
import 'package:runanywhere_onnx/runanywhere_onnx.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize SDK
  await RunAnywhere.initialize();

  // Explicitly registers generic ONNX and Sherpa STT/TTS/VAD backends.
  await Onnx.register();

  runApp(MyApp());
}
```

### 2. Register Models

Models are registered through the core SDK registry (backends do not own catalogs).

```dart
// STT Model (Whisper)
RunAnywhere.models.register(
  id: 'whisper-tiny-en',
  name: 'Whisper Tiny English',
  url: Uri.parse('https://github.com/RunanywhereAI/sherpa-onnx/releases/download/runanywhere-models-v1/sherpa-onnx-whisper-tiny.en.tar.gz'),
  framework: InferenceFramework.INFERENCE_FRAMEWORK_SHERPA,
  modality: ModelCategory.MODEL_CATEGORY_SPEECH_RECOGNITION,
  memoryRequirement: 75000000,  // ~75 MB
);

// TTS Model (Piper)
RunAnywhere.models.register(
  id: 'piper-amy-medium',
  name: 'Piper Amy (English)',
  url: Uri.parse('https://github.com/RunanywhereAI/sherpa-onnx/releases/download/runanywhere-models-v1/vits-piper-en_US-amy-medium.tar.gz'),
  framework: InferenceFramework.INFERENCE_FRAMEWORK_SHERPA,
  modality: ModelCategory.MODEL_CATEGORY_SPEECH_SYNTHESIS,
  memoryRequirement: 50000000,  // ~50 MB
);
```

### 3. Speech-to-Text

```dart
// Download and load STT model
final stream = RunAnywhere.downloads.start('whisper-tiny-en');
await for (final p in stream) {
  if (p.stage == DownloadStage.DOWNLOAD_STAGE_COMPLETED) break;
}
await RunAnywhere.stt.load('whisper-tiny-en');

// Transcribe audio (PCM16 @ 16 kHz mono)
final result = await RunAnywhere.stt.transcribe(audioData);
print('Text: ${result.text}');
print('Confidence: ${result.confidence}');
print('Detected language: ${result.detectedLanguage}');
```

### 4. Text-to-Speech

```dart
// Download and load TTS voice
final stream = RunAnywhere.downloads.start('piper-amy-medium');
await for (final p in stream) {
  if (p.stage == DownloadStage.DOWNLOAD_STAGE_COMPLETED) break;
}
await RunAnywhere.tts.loadVoice('piper-amy-medium');

// Synthesize speech
final result = await RunAnywhere.tts.synthesize(
  'Hello! Welcome to RunAnywhere.',
  TTSOptions(rate: 1.0, pitch: 1.0),
);

print('Sample rate: ${result.sampleRate} Hz');
print('Audio bytes: ${result.audio.length}');

// `result.audio` is PCM16 Uint8List; wrap in a WAV header for playback.
```

---

## API Reference

### Onnx Class

#### `register()`

Register the ONNX backend with the SDK.

```dart
static Future<void> register({int priority = 100})
```

**Parameters:**
- `priority` – Backend priority (higher = preferred). Default: 100.

#### Registering models

The `Onnx` module does not own a model catalog. Register Sherpa/ONNX/Piper
models through the core SDK registry after calling `Onnx.register()`:

```dart
RunAnywhere.models.register(
  id: 'my-stt-model',
  name: 'My STT Model',
  url: Uri.parse('https://.../whisper.tar.gz'),
  framework: InferenceFramework.INFERENCE_FRAMEWORK_SHERPA,
  modality: ModelCategory.MODEL_CATEGORY_SPEECH_RECOGNITION,
);
```

Archive downloads (`.tar.gz`, `.tar.bz2`, `.zip`) are auto-extracted by the
Sherpa download strategy.

---

## Supported Models

### Speech-to-Text (Whisper)

| Model | Size | Memory | Languages | Speed |
|-------|------|--------|-----------|-------|
| whisper-tiny.en | ~40MB | ~75MB | English only | Fastest |
| whisper-tiny | ~75MB | ~150MB | Multilingual | Fast |
| whisper-base.en | ~75MB | ~150MB | English only | Fast |
| whisper-base | ~150MB | ~300MB | Multilingual | Medium |
| whisper-small.en | ~250MB | ~500MB | English only | Slower |

> **Recommendation:** Use `whisper-tiny.en` for English-only apps. Use `whisper-tiny` for multilingual support.

### Text-to-Speech (Piper)

| Voice | Language | Size | Quality |
|-------|----------|------|---------|
| amy-medium | English (US) | ~50MB | Medium |
| amy-low | English (US) | ~25MB | Lower |
| lessac-medium | English (US) | ~50MB | Medium |
| Various | 30+ languages | Varies | Medium |

> **Recommendation:** Use `amy-medium` for good quality English TTS.

---

## Voice Agent Integration

For full voice assistant functionality, combine STT + LLM + TTS:

```dart
import 'package:runanywhere/runanywhere.dart';
import 'package:runanywhere_onnx/runanywhere_onnx.dart';
import 'package:runanywhere_llamacpp/runanywhere_llamacpp.dart';

// Initialize all backends
await RunAnywhere.initialize();
await Onnx.register();
await LlamaCpp.register();

// Load all models
await RunAnywhere.stt.load('whisper-tiny-en');
await RunAnywhere.llm.load('smollm2-360m');
await RunAnywhere.tts.loadVoice('piper-amy-medium');

// Initialize the voice pipeline with currently loaded models
await RunAnywhere.voice.initializeWithLoadedModels();

// Subscribe to voice events (proto-typed VoiceEvent stream)
final sub = RunAnywhere.voice.eventStream().listen((event) {
  if (event.hasUserSaid())       print('User: ${event.userSaid.text}');
  if (event.hasAssistantToken()) stdout.write(event.assistantToken.text);
});

await RunAnywhere.voice.start();
// ... later
await RunAnywhere.voice.stop();
await sub.cancel();
```

---

## Audio Format Requirements

### STT Input

| Property | Requirement |
|----------|-------------|
| Format | PCM16 (signed 16-bit) |
| Sample Rate | 16000 Hz |
| Channels | Mono (1 channel) |
| Encoding | Little-endian |

### TTS Output

| Property | Value |
|----------|-------|
| Format | Float32 PCM |
| Sample Rate | 22050 Hz (Piper default) |
| Channels | Mono (1 channel) |

---

## Troubleshooting

### STT Returns Empty Text

**Possible Causes:**
1. Audio too short (< 0.5 seconds)
2. Audio too quiet (no speech detected)
3. Wrong audio format (not PCM16 @ 16kHz)

**Solutions:**
1. Ensure audio is at least 1 second
2. Check microphone input levels
3. Verify audio format matches requirements

### TTS Sounds Robotic

**Solutions:**
1. Use `*-medium` quality models instead of `*-low`
2. Adjust rate/pitch parameters
3. Try different voice models

### Model Loading Fails

**Solutions:**
1. Verify model is fully downloaded
2. Check model format compatibility
3. Ensure sufficient memory available

### Permission Denied

**iOS:**
- Add `NSMicrophoneUsageDescription` to Info.plist
- Request permission before recording

**Android:**
- Add `RECORD_AUDIO` permission to AndroidManifest.xml
- Use `permission_handler` package to request at runtime

---

## Memory Management

```dart
// Unload STT model to free memory
await RunAnywhere.stt.unload();

// Unload TTS voice
await RunAnywhere.tts.unloadVoice();

// Check current loaded models
print('STT loaded: ${RunAnywhere.isSTTModelLoaded}');
print('TTS loaded: ${RunAnywhere.isTTSVoiceLoaded}');
```

---

## Related Packages

- [runanywhere](https://pub.dev/packages/runanywhere) — Core SDK (required)
- [runanywhere_llamacpp](https://pub.dev/packages/runanywhere_llamacpp) — LLM backend
- [runanywhere_onnx](https://pub.dev/packages/runanywhere_onnx) — STT/TTS/VAD backend (this package)

## Resources

- [Flutter Starter Example](https://github.com/RunanywhereAI/flutter-starter-example)
- [Documentation](https://runanywhere.ai/docs)
- [GitHub Issues](https://github.com/RunanywhereAI/runanywhere-sdks/issues)

---

## License

This software is licensed under the RunAnywhere License, which is based on Apache 2.0 with additional terms for commercial use. See [LICENSE](https://github.com/RunanywhereAI/runanywhere-sdks/blob/main/LICENSE) for details.

For commercial licensing inquiries, contact: san@runanywhere.ai
