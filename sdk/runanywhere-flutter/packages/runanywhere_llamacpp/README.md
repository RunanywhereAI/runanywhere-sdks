# RunAnywhere LlamaCpp Backend

[![pub package](https://img.shields.io/pub/v/runanywhere_llamacpp.svg)](https://pub.dev/packages/runanywhere_llamacpp)
[![License](https://img.shields.io/badge/License-RunAnywhere-blue.svg)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/main/LICENSE)

LlamaCpp backend for the RunAnywhere Flutter SDK. Provides high-performance on-device LLM text generation capabilities.

## Features

- **On-Device LLM Inference**: Run large language models directly on device
- **Streaming Generation**: Real-time token-by-token output
- **GGUF Model Support**: Compatible with all GGUF quantized models
- **Memory Efficient**: Optimized for mobile devices
- **Privacy-First**: All processing happens locally

## Installation

Add both the core SDK and this backend to your `pubspec.yaml`:

```yaml
dependencies:
  runanywhere: ^0.15.8
  runanywhere_llamacpp: ^0.15.8
```

## Quick Start

### 1. Initialize and Register

```dart
import 'package:runanywhere/runanywhere.dart';
import 'package:runanywhere_llamacpp/runanywhere_llamacpp.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize the SDK
  await RunAnywhere.initialize();

  // Register the LlamaCpp backend
  await LlamaCpp.register();

  runApp(MyApp());
}
```

### 2. Add a Model

```dart
// Add a GGUF model for text generation
LlamaCpp.addModel(
  name: 'SmolLM2 360M',
  url: 'https://your-model-url.com/smollm2-360m-q4.gguf',
  memoryRequirement: 500000000, // ~500MB
);
```

### 3. Generate Text

```dart
// Streaming generation
final stream = RunAnywhere.generateStream(
  'Explain quantum computing in simple terms',
  options: RunAnywhereGenerationOptions(
    maxTokens: 256,
    temperature: 0.7,
  ),
);

await for (final token in stream) {
  print(token); // Print each token as it's generated
}

// Non-streaming generation
final response = await RunAnywhere.generate(
  'What is 2 + 2?',
  options: RunAnywhereGenerationOptions(),
);
print(response.text);
```

## Supported Model Formats

This backend supports GGUF models, which are quantized versions of large language models optimized for efficient inference. Popular model sources include:

- [Hugging Face](https://huggingface.co/models?search=gguf)
- [TheBloke's GGUF Models](https://huggingface.co/TheBloke)

## Platform Support

| Platform | Minimum Version |
|----------|-----------------|
| iOS      | 13.0+           |
| Android  | API 24+         |

## Requirements

- `runanywhere` core SDK package

## License

This software is licensed under the RunAnywhere License, which is based on Apache 2.0 with additional terms for commercial use. See [LICENSE](https://github.com/RunanywhereAI/runanywhere-sdks/blob/main/LICENSE) for details.

For commercial licensing inquiries, contact: san@runanywhere.ai

## Support

- [GitHub Issues](https://github.com/RunanywhereAI/runanywhere-sdks/issues)
- Email: san@runanywhere.ai
