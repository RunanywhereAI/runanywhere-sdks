# LlamaCPPRuntime Module

> LLM text generation backend using llama.cpp with GGUF models and Metal GPU acceleration.

<p align="center">
  <img src="https://img.shields.io/badge/Swift-5.9+-FA7343?style=flat-square&logo=swift&logoColor=white" alt="Swift 5.9+" />
  <img src="https://img.shields.io/badge/Metal-GPU%20Accelerated-8A2BE2?style=flat-square" alt="Metal GPU" />
  <img src="https://img.shields.io/badge/Models-GGUF-green?style=flat-square" alt="GGUF Models" />
</p>

---

## Overview

The **LlamaCPPRuntime** module provides large language model (LLM) capabilities to the RunAnywhere SDK using [llama.cpp](https://github.com/ggerganov/llama.cpp) as the inference engine. It supports GGUF-format models with Metal GPU acceleration on Apple Silicon devices.

### Key Features

- **On-device LLM inference** — Run models locally with no internet required
- **Metal GPU acceleration** — 3-5x faster inference on Apple Silicon
- **GGUF model support** — Works with any GGUF-quantized model
- **Streaming generation** — Real-time token-by-token output
- **Structured output** — JSON schema-constrained generation
- **Thinking models** — Support for `<think>...</think>` reasoning tags

---

## Installation

The LlamaCPPRuntime module is included with the RunAnywhere Swift SDK:

```swift
// Package.swift
dependencies: [
    .package(url: "https://github.com/RunanywhereAI/runanywhere-sdks", from: "0.16.0")
],
targets: [
    .target(
        name: "YourApp",
        dependencies: [
            .product(name: "RunAnywhere", package: "runanywhere-sdks"),
            .product(name: "RunAnywhereLlamaCPP", package: "runanywhere-sdks"),
        ]
    )
]
```

---

## Quick Start

### 1. Register the Module

```swift
import RunAnywhere
import LlamaCPPRuntime

@MainActor
func setupSDK() async {
    // Initialize SDK
    try RunAnywhere.initialize()

    // Register LlamaCPP backend
    LlamaCPP.register()
}
```

### 2. Load a Model

```swift
// Download model if needed
for try await progress in RunAnywhere.downloadModel("smollm2-360m-q8_0") {
    print("Progress: \(Int(progress.overallProgress * 100))%")
}

// Load into memory
try await RunAnywhere.loadModel("smollm2-360m-q8_0")
```

### 3. Generate Text

```swift
// Simple chat
let response = try await RunAnywhere.chat("What is Swift?")
print(response)

// Streaming generation
let result = try await RunAnywhere.generateStream(
    "Explain machine learning",
    options: LLMGenerationOptions(maxTokens: 200, temperature: 0.7)
)

for try await token in result.stream {
    print(token, terminator: "")
}
```

---

## Supported Models

LlamaCPPRuntime supports any GGUF-format model. Common options include:

| Model | Size | Memory | Use Case |
|-------|------|--------|----------|
| SmolLM2 360M Q8_0 | ~400MB | 500MB | Fast, lightweight chat |
| Qwen 2.5 0.5B Q6_K | ~500MB | 600MB | Multilingual, efficient |
| LFM2 350M Q4_K_M | ~200MB | 250MB | Ultra-compact |
| Llama 2 7B Q4_K_M | ~4GB | 4GB | High quality |
| Mistral 7B Instruct Q4_K_M | ~4GB | 4GB | Instruction following |
| Llama 3.2 1B Q4_K_M | ~700MB | 1GB | Latest Llama, compact |
| Phi-3 Mini Q4_K_M | ~2GB | 2.5GB | Microsoft, reasoning |

### Quantization Levels

| Quantization | Quality | Speed | Size |
|--------------|---------|-------|------|
| Q8_0 | Highest | Slower | Largest |
| Q6_K | High | Medium | Medium |
| Q5_K_M | Good | Medium | Medium |
| Q4_K_M | Good | Fast | Small |
| Q4_0 | Acceptable | Fastest | Smallest |

---

## Configuration

### Generation Options

```swift
let options = LLMGenerationOptions(
    maxTokens: 256,           // Maximum output length
    temperature: 0.7,         // Randomness (0.0–2.0)
    topP: 0.95,              // Nucleus sampling
    topK: 40,                // Top-K filtering
    stopSequences: ["</s>"], // Stop generation triggers
    systemPrompt: "You are a helpful assistant."
)

let result = try await RunAnywhere.generate(prompt, options: options)
```

### Temperature Guide

| Temperature | Behavior |
|-------------|----------|
| 0.0–0.3 | Deterministic, factual |
| 0.4–0.7 | Balanced creativity |
| 0.8–1.0 | More creative, varied |
| 1.0–2.0 | Highly random |

---

## Architecture

The LlamaCPPRuntime module is a thin Swift wrapper around the C++ backend:

```
┌─────────────────────────────────────────────────┐
│              Your Application                    │
├─────────────────────────────────────────────────┤
│         RunAnywhere Public API                   │
│    (RunAnywhere.generate(), .chat(), etc.)      │
├─────────────────────────────────────────────────┤
│          LlamaCPPRuntime Module                  │
│    ┌─────────────────────────────────────────┐  │
│    │  LlamaCPP.swift (registration)          │  │
│    └─────────────────────────────────────────┘  │
├─────────────────────────────────────────────────┤
│           C Bridge (LlamaCPPBackend)             │
│    rac_backend_llamacpp_register()              │
│    rac_text_generate() / rac_text_load_model()  │
├─────────────────────────────────────────────────┤
│         RABackendLLAMACPP.xcframework           │
│    (Native C++ llama.cpp with Metal)            │
└─────────────────────────────────────────────────┘
```

### Binary Dependencies

| Framework | Size | Description |
|-----------|------|-------------|
| `RABackendLLAMACPP.xcframework` | ~15-25MB | llama.cpp with Metal acceleration |
| `RACommons.xcframework` | ~2MB | Shared C++ infrastructure |

---

## Performance

### Benchmarks (Apple Silicon)

| Device | Model | Tokens/sec |
|--------|-------|------------|
| M1 MacBook | SmolLM2 360M Q8 | ~45 tok/s |
| M1 MacBook | Llama 2 7B Q4 | ~12 tok/s |
| iPhone 15 Pro | SmolLM2 360M Q8 | ~35 tok/s |
| iPhone 15 Pro | Mistral 7B Q4 | ~8 tok/s |
| iPad Pro M2 | Llama 3.2 1B Q4 | ~30 tok/s |

### Optimization Tips

1. **Use Metal** — Ensure you're on Apple Silicon for GPU acceleration
2. **Choose appropriate quantization** — Q4_K_M is often the best balance
3. **Limit context length** — Shorter contexts = faster inference
4. **Preload models** — Load during app startup, not on-demand

---

## Error Handling

```swift
do {
    let result = try await RunAnywhere.generate(prompt)
} catch let error as SDKError {
    switch error.code {
    case .modelNotFound:
        print("Model not downloaded. Download it first.")
    case .modelLoadFailed:
        print("Failed to load model. Check file integrity.")
    case .insufficientMemory:
        print("Not enough RAM. Try a smaller model.")
    case .generationFailed:
        print("Generation failed: \(error.message)")
    case .generationTimeout:
        print("Generation timed out.")
    default:
        print("Error: \(error.localizedDescription)")
    }
}
```

---

## API Reference

### `LlamaCPP` Module

```swift
public enum LlamaCPP: RunAnywhereModule {
    /// Module identifier
    static let moduleId: String = "llamacpp"

    /// Human-readable name
    static let moduleName: String = "LlamaCPP"

    /// Supported capabilities
    static let capabilities: Set<SDKComponent> = [.llm]

    /// Inference framework identifier
    static let inferenceFramework: InferenceFramework = .llamaCpp

    /// Current module version
    static let version: String = "2.0.0"

    /// Underlying llama.cpp library version
    static let llamaCppVersion: String = "b7199"

    /// Register the module with the SDK
    @MainActor
    static func register(priority: Int = 100)

    /// Unregister the module
    static func unregister()

    /// Check if this module can handle a model
    static func canHandle(modelId: String?) -> Bool
}
```

### Auto-Registration

```swift
// Trigger registration automatically when module is imported
_ = LlamaCPP.autoRegister
```

---

## Troubleshooting

### Model Won't Load

**Symptoms:** `modelLoadFailed` error

**Solutions:**
1. Verify model file exists and isn't corrupted
2. Check available memory (need ~1.5x model size)
3. Ensure model is GGUF format
4. Try re-downloading the model

### Slow Generation

**Symptoms:** < 5 tokens/second

**Solutions:**
1. Verify Metal is being used (Apple Silicon only)
2. Use smaller quantization (Q4_K_M instead of Q8)
3. Reduce `maxTokens`
4. Close other memory-intensive apps

### Out of Memory

**Symptoms:** App crashes or `insufficientMemory` error

**Solutions:**
1. Use a smaller model
2. Unload other models first
3. Reduce context length
4. Test on device with more RAM

---

## Version History

| Version | llama.cpp | Changes |
|---------|-----------|---------|
| 2.0.0 | b7199 | Modular architecture, C++ backend |
| 1.0.0 | b6000 | Initial release |

---

## See Also

- [RunAnywhere SDK](../../README.md) — Main SDK documentation
- [API Reference](../../Docs/Documentation.md) — Complete API documentation
- [ONNX Runtime Module](../ONNXRuntime/README.md) — STT/TTS backend
- [llama.cpp](https://github.com/ggerganov/llama.cpp) — Upstream project

---

## License

Copyright © 2025 RunAnywhere AI. All rights reserved.
