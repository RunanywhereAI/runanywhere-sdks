# RunAnywhere Flutter SDK

A privacy-first, on-device AI SDK for Flutter that brings powerful AI models directly to your applications.

## Architecture

This SDK uses a **multi-package architecture** for modularity and smaller app sizes:

```text
runanywhere-flutter/
├── packages/
│   ├── runanywhere/           # Core SDK (required)
│   ├── runanywhere_onnx/      # ONNX backend (STT, TTS, VAD, LLM)
│   └── runanywhere_llamacpp/  # LlamaCpp backend (LLM)
├── melos.yaml                 # Multi-package management
└── analysis_options.yaml      # Shared lint rules
```

## Features

- **On-Device AI**: Run language models directly on user devices
- **Privacy-First**: All processing happens locally, no data leaves the device
- **Modular Backends**: Only include the backends you need
- **Speech-to-Text (STT)**: Streaming and batch transcription via ONNX
- **Text-to-Speech (TTS)**: Neural voice synthesis via ONNX
- **Voice Activity Detection (VAD)**: Real-time speech detection
- **LLM Inference**: Text generation via LlamaCpp or ONNX

## Installation

Add the packages you need to your `pubspec.yaml`:

### Core + ONNX (STT/TTS/VAD)

```yaml
dependencies:
  runanywhere:
    path: ../path/to/runanywhere-flutter/packages/runanywhere
  runanywhere_onnx:
    path: ../path/to/runanywhere-flutter/packages/runanywhere_onnx
```

### Core + LlamaCpp (LLM)

```yaml
dependencies:
  runanywhere:
    path: ../path/to/runanywhere-flutter/packages/runanywhere
  runanywhere_llamacpp:
    path: ../path/to/runanywhere-flutter/packages/runanywhere_llamacpp
```

### All Backends

```yaml
dependencies:
  runanywhere:
    path: ../path/to/runanywhere-flutter/packages/runanywhere
  runanywhere_onnx:
    path: ../path/to/runanywhere-flutter/packages/runanywhere_onnx
  runanywhere_llamacpp:
    path: ../path/to/runanywhere-flutter/packages/runanywhere_llamacpp
```

## Quick Start

### 1. Initialize SDK and Register Backends

```dart
import 'package:runanywhere/runanywhere.dart';
import 'package:runanywhere_onnx/runanywhere_onnx.dart';
import 'package:runanywhere_llamacpp/runanywhere_llamacpp.dart';

void main() async {
  // Initialize the SDK
  await RunAnywhere.initialize();

  // Register backends (only include what you need)
  await Onnx.register();       // For STT, TTS, VAD
  await LlamaCpp.register();   // For LLM
}
```

### 2. Add Models

```dart
// Add an ONNX model for STT
Onnx.addModel(
  name: 'Whisper Tiny',
  url: 'https://...',
  modality: ModelCategory.speechRecognition,
);

// Add a LlamaCpp model for LLM
LlamaCpp.addModel(
  name: 'SmolLM2 360M',
  url: 'https://...',
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
```

## Development

### Prerequisites

- Flutter SDK >= 3.10.0
- Dart SDK >= 3.0.0
- [Melos](https://melos.invertase.dev/) for multi-package management

### Setup

```bash
# Install melos globally
dart pub global activate melos

# Bootstrap all packages
melos bootstrap

# Run analysis on all packages
melos analyze

# Run tests on all packages
melos test
```

### Native Libraries

The native AI inference libraries are provided by `runanywhere-core`. Run the setup script to download them:

```bash
./scripts/setup_native.sh
```

## Packages

| Package | Description |
|---------|-------------|
| `runanywhere` | Core SDK with interfaces, models, and infrastructure |
| `runanywhere_onnx` | ONNX Runtime backend for STT, TTS, VAD, and LLM |
| `runanywhere_llamacpp` | LlamaCpp backend for high-performance LLM inference |

## Requirements

- Flutter SDK >= 3.10.0
- Dart SDK >= 3.0.0
- iOS 13.0+ / Android API 24+

## Example App

See the [Flutter example app](../../examples/flutter/RunAnywhereAI/) for a complete implementation demonstrating all SDK features including chat, voice, and model management.

## Contributing

See [CONTRIBUTING.md](../../CONTRIBUTING.md) for development guidelines.

## License

Apache License 2.0 - See [LICENSE](../../LICENSE)
