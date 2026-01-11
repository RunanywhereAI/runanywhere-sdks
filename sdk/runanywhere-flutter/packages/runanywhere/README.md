# RunAnywhere Flutter SDK

[![pub package](https://img.shields.io/pub/v/runanywhere.svg)](https://pub.dev/packages/runanywhere)
[![License](https://img.shields.io/badge/License-RunAnywhere-blue.svg)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/main/LICENSE)

A privacy-first, on-device AI SDK for Flutter. Run powerful AI models directly on your users' devices with no data leaving the device.

## Features

- **On-Device AI**: Run language models directly on user devices
- **Privacy-First**: All processing happens locally, no data leaves the device
- **Modular Backends**: Only include the backends you need (ONNX, LlamaCpp)
- **Speech-to-Text (STT)**: Streaming and batch transcription
- **Text-to-Speech (TTS)**: Neural voice synthesis
- **Voice Activity Detection (VAD)**: Real-time speech detection
- **LLM Inference**: Text generation with streaming support
- **Voice Agent**: Complete voice AI pipeline orchestration

## Installation

Add `runanywhere` to your `pubspec.yaml`:

```yaml
dependencies:
  runanywhere: ^0.15.8
```

For AI capabilities, add one or more backend packages:

```yaml
dependencies:
  runanywhere: ^0.15.8
  runanywhere_onnx: ^0.15.8      # For STT, TTS, VAD
  runanywhere_llamacpp: ^0.15.8  # For LLM text generation
```

## Quick Start

### 1. Initialize the SDK

```dart
import 'package:runanywhere/runanywhere.dart';
import 'package:runanywhere_onnx/runanywhere_onnx.dart';
import 'package:runanywhere_llamacpp/runanywhere_llamacpp.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize the SDK
  await RunAnywhere.initialize();

  // Register backends (only include what you need)
  await Onnx.register();       // For STT, TTS, VAD
  await LlamaCpp.register();   // For LLM

  runApp(MyApp());
}
```

### 2. Add Models

```dart
// Add an ONNX model for STT
Onnx.addModel(
  name: 'Whisper Tiny',
  url: 'https://your-model-url.com/whisper-tiny.tar.bz2',
  modality: ModelCategory.speechRecognition,
);

// Add a LlamaCpp model for LLM
LlamaCpp.addModel(
  name: 'SmolLM2 360M',
  url: 'https://your-model-url.com/smollm2-360m.gguf',
  memoryRequirement: 500000000,
);
```

### 3. Use AI Capabilities

```dart
// Text generation with streaming
final stream = RunAnywhere.generateStream(
  'Tell me a joke',
  options: RunAnywhereGenerationOptions(),
);

await for (final token in stream) {
  print(token);
}

// Speech-to-text
final transcription = await RunAnywhere.transcribe(audioData);
print(transcription.text);
```

## Platform Support

| Platform | Minimum Version |
|----------|-----------------|
| iOS      | 13.0+           |
| Android  | API 24+         |

## Architecture

This SDK uses a multi-package architecture for modularity:

- **runanywhere** (this package): Core SDK with interfaces, models, and infrastructure
- **runanywhere_onnx**: ONNX Runtime backend for STT, TTS, VAD
- **runanywhere_llamacpp**: LlamaCpp backend for high-performance LLM inference

## Documentation

For comprehensive documentation, visit [runanywhere.ai](https://runanywhere.ai).

## License

This software is licensed under the RunAnywhere License, which is based on Apache 2.0 with additional terms for commercial use. See [LICENSE](https://github.com/RunanywhereAI/runanywhere-sdks/blob/main/LICENSE) for details.

For commercial licensing inquiries, contact: san@runanywhere.ai

## Support

- [GitHub Issues](https://github.com/RunanywhereAI/runanywhere-sdks/issues)
- Email: san@runanywhere.ai
