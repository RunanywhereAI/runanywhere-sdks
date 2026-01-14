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
  runanywhere: ^0.15.11
  runanywhere_onnx: ^0.15.11
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
| iOS      | 14.0+           | Microphone permission |
| Android  | API 24+         | RECORD_AUDIO permission |

---

## Platform Setup

### iOS

Update `ios/Podfile`:

```ruby
platform :ios, '14.0'

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

  // Register ONNX backend
  await Onnx.register();

  runApp(MyApp());
}
```

### 2. Add Models

```dart
// STT Model (Whisper)
Onnx.addModel(
  id: 'whisper-tiny-en',
  name: 'Whisper Tiny English',
  url: 'https://github.com/RunanywhereAI/sherpa-onnx/releases/download/runanywhere-models-v1/sherpa-onnx-whisper-tiny.en.tar.gz',
  modality: ModelCategory.speechRecognition,
  memoryRequirement: 75000000,  // ~75MB
);

// TTS Model (Piper)
Onnx.addModel(
  id: 'piper-amy-medium',
  name: 'Piper Amy (English)',
  url: 'https://github.com/RunanywhereAI/sherpa-onnx/releases/download/runanywhere-models-v1/vits-piper-en_US-amy-medium.tar.gz',
  modality: ModelCategory.speechSynthesis,
  memoryRequirement: 50000000,  // ~50MB
);
```

### 3. Speech-to-Text

```dart
// Download and load STT model
await for (final p in RunAnywhere.downloadModel('whisper-tiny-en')) {
  if (p.state.isCompleted) break;
}
await RunAnywhere.loadSTTModel('whisper-tiny-en');

// Transcribe audio (PCM16 @ 16kHz mono)
final text = await RunAnywhere.transcribe(audioData);
print('Transcription: $text');

// With detailed result
final result = await RunAnywhere.transcribeWithResult(audioData);
print('Text: ${result.text}');
print('Confidence: ${result.confidence}');
print('Language: ${result.language}');
```

### 4. Text-to-Speech

```dart
// Download and load TTS model
await for (final p in RunAnywhere.downloadModel('piper-amy-medium')) {
  if (p.state.isCompleted) break;
}
await RunAnywhere.loadTTSVoice('piper-amy-medium');

// Synthesize speech
final result = await RunAnywhere.synthesize(
  'Hello! Welcome to RunAnywhere.',
  rate: 1.0,   // Speech rate
  pitch: 1.0,  // Speech pitch
);

print('Duration: ${result.durationSeconds}s');
print('Sample rate: ${result.sampleRate} Hz');
print('Samples: ${result.samples.length}');

// Play with audioplayers package
// await audioPlayer.play(BytesSource(wavBytes));
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

#### `addModel()`

Add an ONNX model to the registry.

```dart
static void addModel({
  required String id,
  required String name,
  required String url,
  required ModelCategory modality,
  int memoryRequirement = 0,
})
```

**Parameters:**
- `id` – Unique model identifier
- `name` – Human-readable model name
- `url` – Download URL (supports .tar.gz, .tar.bz2, .zip)
- `modality` – Model category (`speechRecognition`, `speechSynthesis`)
- `memoryRequirement` – Estimated memory usage in bytes

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
await RunAnywhere.loadSTTModel('whisper-tiny-en');
await RunAnywhere.loadModel('smollm2-360m');
await RunAnywhere.loadTTSVoice('piper-amy-medium');

// Check voice agent readiness
print('Voice agent ready: ${RunAnywhere.isVoiceAgentReady}');

// Start voice session
if (RunAnywhere.isVoiceAgentReady) {
  final session = await RunAnywhere.startVoiceSession();

  session.events.listen((event) {
    if (event is VoiceSessionTranscribed) {
      print('User: ${event.text}');
    } else if (event is VoiceSessionResponded) {
      print('AI: ${event.text}');
    }
  });
}
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
await RunAnywhere.unloadSTTModel();

// Unload TTS voice
await RunAnywhere.unloadTTSVoice();

// Check current loaded models
print('STT loaded: ${RunAnywhere.isSTTModelLoaded}');
print('TTS loaded: ${RunAnywhere.isTTSVoiceLoaded}');
```

---

## License

This software is licensed under the RunAnywhere License, which is based on Apache 2.0 with additional terms for commercial use. See [LICENSE](https://github.com/RunanywhereAI/runanywhere-sdks/blob/main/LICENSE) for details.

For commercial licensing inquiries, contact: san@runanywhere.ai

---

## Support

- [GitHub Issues](https://github.com/RunanywhereAI/runanywhere-sdks/issues)
- [Documentation](https://runanywhere.ai/docs)
- Email: san@runanywhere.ai
