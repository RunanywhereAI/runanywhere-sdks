# RunAnywhere LlamaCpp Backend

[![pub package](https://img.shields.io/pub/v/runanywhere_llamacpp.svg)](https://pub.dev/packages/runanywhere_llamacpp)
[![License](https://img.shields.io/badge/License-RunAnywhere-blue.svg)](https://github.com/RunanywhereAI/runanywhere-sdks/blob/main/LICENSE)
[![Platform](https://img.shields.io/badge/platform-iOS%20%7C%20Android-lightgrey.svg)]()

High-performance LLM text generation backend for the RunAnywhere Flutter SDK, powered by [llama.cpp](https://github.com/ggerganov/llama.cpp).

---

## Features

| Feature | Description |
|---------|-------------|
| **GGUF Model Support** | Run any GGUF-quantized model (Q4, Q5, Q8, etc.) |
| **Streaming Generation** | Token-by-token streaming for real-time UI updates |
| **Metal Acceleration** | Hardware acceleration on iOS devices |
| **NEON Acceleration** | ARM NEON optimizations on Android |
| **Privacy-First** | All processing happens locally on device |
| **Memory Efficient** | Quantized models reduce memory footprint |

---

## Installation

Add both the core SDK and this backend to your `pubspec.yaml`:

```yaml
dependencies:
  runanywhere: ^0.15.11
  runanywhere_llamacpp: ^0.15.11
```

Then run:

```bash
flutter pub get
```

> **Note:** This package requires the core `runanywhere` package. It won't work standalone.

---

## Platform Support

| Platform | Minimum Version | Acceleration |
|----------|-----------------|--------------|
| iOS      | 14.0+           | Metal GPU    |
| Android  | API 24+         | NEON SIMD    |

---

## Quick Start

### 1. Initialize & Register

```dart
import 'package:runanywhere/runanywhere.dart';
import 'package:runanywhere_llamacpp/runanywhere_llamacpp.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize SDK
  await RunAnywhere.initialize();

  // Register LlamaCpp backend
  await LlamaCpp.register();

  runApp(MyApp());
}
```

### 2. Add a Model

```dart
LlamaCpp.addModel(
  id: 'smollm2-360m-q8_0',
  name: 'SmolLM2 360M Q8_0',
  url: 'https://huggingface.co/prithivMLmods/SmolLM2-360M-GGUF/resolve/main/SmolLM2-360M.Q8_0.gguf',
  memoryRequirement: 500000000,  // ~500MB
);
```

### 3. Download & Load

```dart
// Download the model
await for (final progress in RunAnywhere.downloadModel('smollm2-360m-q8_0')) {
  print('Progress: ${(progress.percentage * 100).toStringAsFixed(1)}%');
  if (progress.state.isCompleted) break;
}

// Load the model
await RunAnywhere.loadModel('smollm2-360m-q8_0');
print('Model loaded: ${RunAnywhere.isModelLoaded}');
```

### 4. Generate Text

```dart
// Simple chat
final response = await RunAnywhere.chat('Hello! How are you?');
print(response);

// Streaming generation
final result = await RunAnywhere.generateStream(
  'Write a short poem about Flutter',
  options: LLMGenerationOptions(maxTokens: 100, temperature: 0.7),
);

await for (final token in result.stream) {
  stdout.write(token);  // Real-time output
}

// Get metrics after completion
final metrics = await result.result;
print('\nTokens/sec: ${metrics.tokensPerSecond.toStringAsFixed(1)}');
```

---

## API Reference

### LlamaCpp Class

#### `register()`

Register the LlamaCpp backend with the SDK.

```dart
static Future<void> register({int priority = 100})
```

**Parameters:**
- `priority` – Backend priority (higher = preferred). Default: 100.

#### `addModel()`

Add an LLM model to the registry.

```dart
static void addModel({
  required String id,
  required String name,
  required String url,
  int memoryRequirement = 0,
  bool supportsThinking = false,
})
```

**Parameters:**
- `id` – Unique model identifier
- `name` – Human-readable model name
- `url` – Download URL for the GGUF file
- `memoryRequirement` – Estimated memory usage in bytes
- `supportsThinking` – Whether model supports thinking tokens (e.g., DeepSeek R1)

---

## Supported Models

Any GGUF model compatible with llama.cpp:

### Recommended Models

| Model | Size | Memory | Use Case |
|-------|------|--------|----------|
| SmolLM2 360M Q8_0 | ~400MB | ~500MB | Fast responses, mobile |
| Qwen2.5 0.5B Q8_0 | ~600MB | ~700MB | Good quality, small |
| Qwen2.5 1.5B Q4_K_M | ~1GB | ~1.2GB | Better quality |
| Phi-3.5-mini Q4_K_M | ~2GB | ~2.5GB | High quality |
| Llama 3.2 1B Q4_K_M | ~800MB | ~1GB | Balanced |
| DeepSeek R1 1.5B Q4_K_M | ~1.2GB | ~1.5GB | Reasoning, thinking |

### Quantization Guide

| Format | Quality | Size | Speed |
|--------|---------|------|-------|
| Q8_0 | Highest | Largest | Slower |
| Q6_K | Very High | Large | Medium |
| Q5_K_M | High | Medium | Medium |
| Q4_K_M | Good | Small | Fast |
| Q4_0 | Lower | Smallest | Fastest |

> **Tip:** For mobile, Q4_K_M or Q5_K_M offer the best quality/size balance.

---

## Memory Management

### Checking Memory

```dart
// Get available models with their memory requirements
final models = await RunAnywhere.availableModels();
for (final model in models) {
  if (model.downloadSize != null) {
    print('${model.name}: ${(model.downloadSize! / 1e9).toStringAsFixed(1)} GB');
  }
}
```

### Unloading Models

```dart
// Unload to free memory
await RunAnywhere.unloadModel();
```

---

## Generation Options

```dart
final result = await RunAnywhere.generate(
  'Your prompt here',
  options: LLMGenerationOptions(
    maxTokens: 200,           // Maximum tokens to generate
    temperature: 0.7,         // Randomness (0.0 = deterministic, 1.0 = creative)
    topP: 0.9,               // Nucleus sampling
    systemPrompt: 'You are a helpful assistant.',
  ),
);
```

| Option | Default | Range | Description |
|--------|---------|-------|-------------|
| `maxTokens` | 100 | 1-4096 | Maximum tokens to generate |
| `temperature` | 0.8 | 0.0-2.0 | Response randomness |
| `topP` | 1.0 | 0.0-1.0 | Nucleus sampling threshold |
| `systemPrompt` | null | - | System prompt prepended to input |

---

## Troubleshooting

### Model Loading Fails

**Symptom:** `SDKError.modelLoadFailed`

**Solutions:**
1. Verify model is fully downloaded (check `model.isDownloaded`)
2. Ensure sufficient memory available
3. Check model format is GGUF (not GGML or safetensors)

### Slow Generation

**Solutions:**
1. Use smaller quantization (Q4_K_M instead of Q8_0)
2. Use a smaller model
3. Reduce `maxTokens`
4. On iOS, ensure Metal is available (device not in low power mode)

### Out of Memory

**Solutions:**
1. Unload current model before loading new one
2. Use smaller quantization
3. Use a smaller model

---

## License

This software is licensed under the RunAnywhere License, which is based on Apache 2.0 with additional terms for commercial use. See [LICENSE](https://github.com/RunanywhereAI/runanywhere-sdks/blob/main/LICENSE) for details.

For commercial licensing inquiries, contact: san@runanywhere.ai

---

## Support

- [GitHub Issues](https://github.com/RunanywhereAI/runanywhere-sdks/issues)
- [Documentation](https://runanywhere.ai/docs)
- Email: san@runanywhere.ai
