# @runanywhere/llamacpp

LlamaCPP backend for the RunAnywhere React Native SDK. Provides on-device LLM text generation with GGUF models powered by llama.cpp.

---

## Overview

`@runanywhere/llamacpp` provides the LlamaCPP backend for on-device Large Language Model (LLM) inference. It enables:

- **Text Generation** — Generate text responses from prompts
- **Streaming** — Real-time token-by-token output
- **Tool Calling** — Let models invoke registered tools during generation
- **Structured Output** — Generate type-safe JSON responses
- **GGUF Support** — Run any GGUF-format model (Llama, Mistral, Qwen, SmolLM, etc.)
- **Metal GPU Acceleration** — 3-5x faster inference on Apple Silicon (iOS)
- **CPU Inference** — Works on all devices without GPU requirements
- **Memory Efficient** — Quantized models (Q4, Q6, Q8) for reduced memory usage

---

## Requirements

- `@runanywhere/core` (peer dependency)
- React Native 0.74+
- iOS 15.1+ / Android API 24+

---

## Installation

```bash
npm install @runanywhere/core @runanywhere/llamacpp
# or
yarn add @runanywhere/core @runanywhere/llamacpp
```

### iOS Setup

```bash
cd ios && pod install && cd ..
```

### Android Setup

No additional setup required. Native libraries are downloaded automatically.

---

## Quick Start

```typescript
import { RunAnywhere, SDKEnvironment, ModelCategory } from '@runanywhere/core';
import { LlamaCPP } from '@runanywhere/llamacpp';

// 1. Initialize SDK
await RunAnywhere.initialize({
  environment: SDKEnvironment.Development,
});

// 2. Register LlamaCPP backend
LlamaCPP.register();

// 3. Add a model
await LlamaCPP.addModel({
  id: 'smollm2-360m-q8_0',
  name: 'SmolLM2 360M Q8_0',
  url: 'https://huggingface.co/prithivMLmods/SmolLM2-360M-GGUF/resolve/main/SmolLM2-360M.Q8_0.gguf',
  memoryRequirement: 500_000_000,
});

// 4. Download model
await RunAnywhere.downloadModel('smollm2-360m-q8_0', (progress) => {
  console.log(`Downloading: ${(progress.progress * 100).toFixed(1)}%`);
});

// 5. Load model
const modelInfo = await RunAnywhere.getModelInfo('smollm2-360m-q8_0');
await RunAnywhere.loadModel(modelInfo.localPath);

// 6. Generate text
const response = await RunAnywhere.chat('What is the capital of France?');
console.log(response);
```

---

## API Reference

### LlamaCPP Module

```typescript
import { LlamaCPP } from '@runanywhere/llamacpp';
```

#### `LlamaCPP.register()`

Register the LlamaCPP backend with the SDK. Must be called before using LLM features.

```typescript
LlamaCPP.register(): void
```

**Example:**

```typescript
await RunAnywhere.initialize({ ... });
LlamaCPP.register();  // Now LLM features are available
```

---

#### `LlamaCPP.addModel(options)`

Add a GGUF model to the model registry.

```typescript
await LlamaCPP.addModel(options: LlamaCPPModelOptions): Promise<ModelInfo>
```

**Parameters:**

```typescript
interface LlamaCPPModelOptions {
  /**
   * Unique model ID.
   * If not provided, generated from the URL filename.
   */
  id?: string;

  /** Display name for the model */
  name: string;

  /** Download URL for the model (GGUF format) */
  url: string;

  /**
   * Model category.
   * Default: ModelCategory.Language
   */
  modality?: ModelCategory;

  /**
   * Memory requirement in bytes.
   * Used for device capability checks.
   */
  memoryRequirement?: number;

  /**
   * Whether model supports reasoning/thinking tokens.
   * If true, thinking content is extracted from responses.
   */
  supportsThinking?: boolean;
}
```

**Returns:** `Promise<ModelInfo>` — The registered model info

**Example:**

```typescript
// Basic model
await LlamaCPP.addModel({
  id: 'smollm2-360m-q8_0',
  name: 'SmolLM2 360M Q8_0',
  url: 'https://huggingface.co/prithivMLmods/SmolLM2-360M-GGUF/resolve/main/SmolLM2-360M.Q8_0.gguf',
  memoryRequirement: 500_000_000,
});

// Larger model
await LlamaCPP.addModel({
  id: 'llama-2-7b-chat-q4_k_m',
  name: 'Llama 2 7B Chat Q4_K_M',
  url: 'https://huggingface.co/TheBloke/Llama-2-7B-Chat-GGUF/resolve/main/llama-2-7b-chat.Q4_K_M.gguf',
  memoryRequirement: 4_000_000_000,
});

// Model with thinking support (e.g., DeepSeek-R1)
await LlamaCPP.addModel({
  id: 'deepseek-r1-distill-qwen-1.5b',
  name: 'DeepSeek R1 Distill Qwen 1.5B',
  url: 'https://huggingface.co/.../deepseek-r1-distill-qwen-1.5b-q8_0.gguf',
  memoryRequirement: 2_000_000_000,
  supportsThinking: true,
});
```

---

#### Module Properties

```typescript
LlamaCPP.moduleId        // 'llamacpp'
LlamaCPP.moduleName      // 'LlamaCPP'
LlamaCPP.inferenceFramework  // LLMFramework.LlamaCpp
LlamaCPP.capabilities    // ['llm']
LlamaCPP.defaultPriority // 100
```

---

### Text Generation

Once a model is registered and loaded, use the `RunAnywhere` API for generation:

#### Simple Chat

```typescript
const response = await RunAnywhere.chat('Hello!');
console.log(response);
```

#### Generation with Options

```typescript
const result = await RunAnywhere.generate(
  'Explain machine learning in simple terms',
  {
    maxTokens: 256,
    temperature: 0.7,
    topP: 0.95,
    systemPrompt: 'You are a helpful teacher.',
    stopSequences: ['\n\n'],
  }
);

console.log('Response:', result.text);
console.log('Tokens:', result.tokensUsed);
console.log('Speed:', result.performanceMetrics.tokensPerSecond, 'tok/s');
console.log('TTFT:', result.performanceMetrics.timeToFirstTokenMs, 'ms');
```

#### Streaming Generation

```typescript
const streamResult = await RunAnywhere.generateStream(
  'Write a story about a robot',
  { maxTokens: 500 }
);

// Display tokens as they're generated
for await (const token of streamResult.stream) {
  process.stdout.write(token);
}

// Get final metrics
const result = await streamResult.result;
console.log('\nSpeed:', result.performanceMetrics.tokensPerSecond, 'tok/s');
```

#### Tool Calling

Register tools and let the LLM call them during generation. Tool calling parsing and prompt formatting is handled entirely in C++ for consistency across platforms.

```typescript
import { RunAnywhere } from '@runanywhere/core';
import { LlamaCPP } from '@runanywhere/llamacpp';

// Register a tool
RunAnywhere.registerTool(
  {
    name: 'calculate',
    description: 'Perform a math calculation',
    parameters: [
      { name: 'expression', type: 'string', description: 'Math expression', required: true },
    ],
  },
  async (args) => {
    const result = eval(args.expression as string); // simplified example
    return { result };
  }
);

// Generate with tools
const result = await RunAnywhere.generateWithTools(
  'What is 42 * 17?',
  {
    autoExecute: true,
    maxToolCalls: 3,
    temperature: 0.7,
    format: 'default', // 'default' for most models, 'lfm2' for Liquid AI models
  }
);
console.log(result.text); // "42 * 17 = 714"
```

**Supported tool calling formats:**

| Format | Tag Pattern | Models |
|--------|-------------|--------|
| `default` | `<tool_call>{"tool":"name","arguments":{}}</tool_call>` | Llama, Qwen, Mistral, SmolLM, most GGUF models |
| `lfm2` | `<\|tool_call_start\|>[func(arg="val")]<\|tool_call_end\|>` | Liquid AI LFM2-Tool models |

---

#### Model Management

```typescript
// Load model
await RunAnywhere.loadModel('/path/to/model.gguf');

// Check if loaded
const isLoaded = await RunAnywhere.isModelLoaded();

// Unload to free memory
await RunAnywhere.unloadModel();

// Cancel ongoing generation
await RunAnywhere.cancelGeneration();
```

---

## Supported Models

Any GGUF-format model works with this backend. Recommended models:

### Small Models (< 1GB RAM)

| Model | Size | Memory | Tool Calling | Description |
|-------|------|--------|:------------:|-------------|
| SmolLM2 360M Q8_0 | ~400MB | 500MB | - | Fast, lightweight |
| Qwen 2.5 0.5B Q6_K | ~500MB | 600MB | Yes | Multilingual |
| LFM2 350M Q4_K_M | ~200MB | 250MB | Yes (lfm2) | Ultra-compact, Liquid AI |

### Medium Models (1-3GB RAM)

| Model | Size | Memory | Tool Calling | Description |
|-------|------|--------|:------------:|-------------|
| Phi-3 Mini Q4_K_M | ~2GB | 2.5GB | - | Microsoft |
| Gemma 2B Q4_K_M | ~1.5GB | 2GB | - | Google |
| LFM2 1.2B Q4_K_M | ~800MB | 1GB | Yes (lfm2) | Liquid AI tool-calling |
| Qwen 2.5 1.5B Instruct Q4_K_M | ~1GB | 1.5GB | Yes | Alibaba, multilingual |
| TinyLlama 1.1B Q4_K_M | ~700MB | 1GB | - | Fast chat |

### Large Models (4GB+ RAM)

| Model | Size | Memory | Tool Calling | Description |
|-------|------|--------|:------------:|-------------|
| Llama 3.2 3B Instruct Q4_K_M | ~2GB | 3GB | Yes | Meta latest |
| Mistral 7B Instruct Q4_K_M | ~4GB | 5GB | Yes | Mistral AI |
| Qwen 2.5 7B Instruct Q4_K_M | ~4GB | 5GB | Yes | Alibaba |
| Llama 2 7B Chat Q4_K_M | ~4GB | 5GB | - | Meta |

### Tool Calling Model Selection Guide

- **Best for tool calling (small):** LFM2-350M-Tool (use `format: 'lfm2'`) or Qwen 2.5 0.5B
- **Best for tool calling (medium):** LFM2-1.2B-Tool or Qwen 2.5 1.5B Instruct
- **Best for tool calling (large):** Mistral 7B Instruct or Qwen 2.5 7B Instruct
- **Instruct-tuned models** generally perform better at following tool calling instructions
- Use `format: 'lfm2'` only with Liquid AI LFM2-Tool models; all others use `format: 'default'`

---

## Performance Tips

### Device Recommendations

- **Apple Silicon (M1/M2/M3, A14+)**: Metal GPU acceleration provides 3-5x speedup
- **Modern Android**: 6GB+ RAM recommended for 7B models
- **Older devices**: Use smaller models (360M-1B)

### Optimization Strategies

1. **Use quantized models** — Q4_K_M offers best quality/size ratio
2. **Limit maxTokens** — Shorter responses = faster generation
3. **Unload when idle** — Free memory for other apps
4. **Pre-download models** — Better UX during onboarding

### Expected Performance

| Device | Model | Speed |
|--------|-------|-------|
| iPhone 15 Pro | SmolLM2 360M Q8 | 50-80 tok/s |
| iPhone 15 Pro | Llama 3.2 3B Q4 | 15-25 tok/s |
| MacBook M2 | Llama 2 7B Q4 | 20-40 tok/s |
| Pixel 8 | SmolLM2 360M Q8 | 30-50 tok/s |

---

## Native Integration

### iOS

This package uses `RABackendLLAMACPP.xcframework` which includes:
- llama.cpp compiled for iOS (arm64)
- Metal GPU acceleration
- Optimized NEON SIMD

The framework is automatically downloaded during `pod install`.

### Android

Native library `librunanywhere_llamacpp.so` includes:
- llama.cpp compiled for Android (arm64-v8a, armeabi-v7a)
- OpenMP threading support
- Optimized for ARM NEON

Libraries are automatically downloaded during Gradle build.

---

## Package Structure

```
packages/llamacpp/
├── src/
│   ├── index.ts                # Package exports
│   ├── LlamaCPP.ts             # Module API (register, addModel)
│   ├── LlamaCppProvider.ts     # Service provider
│   ├── native/
│   │   └── NativeRunAnywhereLlama.ts
│   └── specs/
│       └── RunAnywhereLlama.nitro.ts
├── cpp/
│   ├── HybridRunAnywhereLlama.cpp
│   ├── HybridRunAnywhereLlama.hpp
│   └── bridges/
├── ios/
│   ├── RunAnywhereLlama.podspec
│   └── Frameworks/
│       └── RABackendLLAMACPP.xcframework
├── android/
│   ├── build.gradle
│   └── src/main/jniLibs/
│       └── arm64-v8a/
│           └── librunanywhere_llamacpp.so
└── nitrogen/
    └── generated/
```

---

## Troubleshooting

### Model fails to load

**Symptoms:** `modelLoadFailed` error

**Solutions:**
1. Check file exists at the path
2. Verify GGUF format (not GGML, SafeTensors, etc.)
3. Ensure sufficient memory (check `memoryRequirement`)
4. Try a smaller model

### Slow generation

**Symptoms:** < 5 tokens/second

**Solutions:**
1. Use a smaller model (360M instead of 7B)
2. Check device isn't thermal throttling
3. Close other apps to free memory
4. On iOS, ensure Metal is enabled

### Out of memory

**Symptoms:** App crash during inference

**Solutions:**
1. Unload model before loading a new one
2. Use a smaller/more quantized model
3. Reduce context length (fewer tokens)

---

## See Also

- [Main SDK README](../../README.md) — Full SDK documentation
- [API Reference](../../Docs/Documentation.md) — Complete API docs
- [@runanywhere/core](../core/README.md) — Core SDK
- [@runanywhere/onnx](../onnx/README.md) — STT/TTS backend
- [llama.cpp](https://github.com/ggerganov/llama.cpp) — Underlying engine

---

## License

MIT License
