# RunAnywhere ONNX Backend

[![pub package](https://img.shields.io/pub/v/runanywhere_onnx.svg)](https://pub.dev/packages/runanywhere_onnx)
[![License](https://img.shields.io/badge/License-RunAnywhere-blue.svg)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/main/LICENSE)

ONNX Runtime backend for the RunAnywhere Flutter SDK. Provides on-device Speech-to-Text (STT), Text-to-Speech (TTS), and Voice Activity Detection (VAD) capabilities.

## Features

- **Speech-to-Text (STT)**: Transcribe audio using Whisper models
- **Text-to-Speech (TTS)**: Neural voice synthesis with natural-sounding output
- **Voice Activity Detection (VAD)**: Real-time speech detection
- **Streaming Support**: Real-time transcription and synthesis
- **Privacy-First**: All processing happens locally on device

## Installation

Add both the core SDK and this backend to your `pubspec.yaml`:

```yaml
dependencies:
  runanywhere: ^0.15.8
  runanywhere_onnx: ^0.15.8
```

## Quick Start

### 1. Initialize and Register

```dart
import 'package:runanywhere/runanywhere.dart';
import 'package:runanywhere_onnx/runanywhere_onnx.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize the SDK
  await RunAnywhere.initialize();

  // Register the ONNX backend
  await Onnx.register();

  runApp(MyApp());
}
```

### 2. Add Models

```dart
// Add a Whisper model for STT
Onnx.addModel(
  name: 'Whisper Tiny',
  url: 'https://your-model-url.com/whisper-tiny.tar.bz2',
  modality: ModelCategory.speechRecognition,
);

// Add a VAD model
Onnx.addModel(
  name: 'Silero VAD',
  url: 'https://your-model-url.com/silero-vad.tar.bz2',
  modality: ModelCategory.voiceActivityDetection,
);

// Add a TTS model
Onnx.addModel(
  name: 'Kokoro TTS',
  url: 'https://your-model-url.com/kokoro-tts.tar.bz2',
  modality: ModelCategory.textToSpeech,
);
```

### 3. Use Capabilities

#### Speech-to-Text

```dart
// Request microphone permission first
await Permission.microphone.request();

// Transcribe audio data
final transcription = await RunAnywhere.transcribe(audioData);
print(transcription.text);
```

#### Text-to-Speech

```dart
// Generate speech from text
final audioData = await RunAnywhere.synthesize('Hello, world!');

// Play the audio
await audioPlayer.play(BytesSource(audioData));
```

#### Voice Activity Detection

```dart
// Check if audio contains speech
final hasSpeech = await RunAnywhere.detectVoiceActivity(audioChunk);
```

## Supported Models

### Speech-to-Text
- Whisper (tiny, base, small, medium)
- Faster-Whisper variants

### Text-to-Speech
- Kokoro TTS
- Other ONNX-compatible TTS models

### Voice Activity Detection
- Silero VAD

## Platform Support

| Platform | Minimum Version |
|----------|-----------------|
| iOS      | 13.0+           |
| Android  | API 24+         |

## Requirements

- `runanywhere` core SDK package
- Microphone permission for STT

## License

This software is licensed under the RunAnywhere License, which is based on Apache 2.0 with additional terms for commercial use. See [LICENSE](https://github.com/RunanywhereAI/runanywhere-sdks/blob/main/LICENSE) for details.

For commercial licensing inquiries, contact: san@runanywhere.ai

## Support

- [GitHub Issues](https://github.com/RunanywhereAI/runanywhere-sdks/issues)
- Email: san@runanywhere.ai
