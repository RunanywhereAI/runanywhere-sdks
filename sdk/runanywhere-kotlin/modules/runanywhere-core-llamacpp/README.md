# RunAnywhere Core LlamaCPP Module

**LLM inference backend for the RunAnywhere Kotlin SDK** — powered by [llama.cpp](https://github.com/ggerganov/llama.cpp) for on-device text generation.

[![Maven Central](https://img.shields.io/maven-central/v/com.runanywhere.sdk/runanywhere-core-llamacpp?label=Maven%20Central)](https://search.maven.org/artifact/com.runanywhere.sdk/runanywhere-core-llamacpp)
[![License: Apache 2.0](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](https://opensource.org/licenses/Apache-2.0)
[![Platform: Android](https://img.shields.io/badge/Platform-Android%207.0%2B-green)](https://developer.android.com)

---

## Features

This module provides the **LLM (Large Language Model)** backend, enabling on-device text generation using the industry-standard llama.cpp library. It's optimized for mobile devices with support for quantized models (GGUF format).

**This module is optional.** Only include it if your app needs LLM/text generation capabilities.

- **On-Device LLM Inference** — Run language models locally without network
- **GGUF Model Support** — Compatible with quantized models from HuggingFace
- **Streaming Generation** — Token-by-token output for responsive UX
- **Multiple Quantization Levels** — Q4, Q5, Q8 for memory/quality tradeoffs
- **Thinking/Reasoning Models** — Support for models with reasoning capabilities
- **ARM64 Optimized** — Native performance on modern Android devices

---

## Installation

Add to your module's `build.gradle.kts`:

```kotlin
dependencies {
    // Core SDK (required)
    implementation("com.runanywhere.sdk:runanywhere-kotlin:0.1.4")

    // LlamaCPP backend (this module)
    implementation("com.runanywhere.sdk:runanywhere-core-llamacpp:0.1.4")
}
```

---

## Usage

Once included, the module automatically registers the `LLAMA_CPP` framework with the SDK.

### Register a Model

```kotlin
import com.runanywhere.sdk.public.RunAnywhere
import com.runanywhere.sdk.public.extensions.*
import com.runanywhere.sdk.core.types.InferenceFramework

val model = RunAnywhere.registerModel(
    name = "Qwen 0.5B Instruct",
    url = "https://huggingface.co/Qwen/Qwen2.5-0.5B-Instruct-GGUF/resolve/main/qwen2.5-0.5b-instruct-q8_0.gguf",
    framework = InferenceFramework.LLAMA_CPP
)
```

### Download & Load

```kotlin
// Download model
RunAnywhere.downloadModel(model.id).collect { progress ->
    println("Download: ${(progress.progress * 100).toInt()}%")
}

// Load into memory
RunAnywhere.loadLLMModel(model.id)
```

### Generate Text

```kotlin
// Simple chat
val response = RunAnywhere.chat("What is 2+2?")
println(response)

// With options
val result = RunAnywhere.generate(
    prompt = "Write a haiku about code",
    options = LLMGenerationOptions(
        maxTokens = 100,
        temperature = 0.8f
    )
)
println("Response: ${result.text}")
println("Speed: ${result.tokensPerSecond} tok/s")
```

### Streaming

```kotlin
RunAnywhere.generateStream("Tell me a story")
    .collect { token ->
        print(token) // Display tokens in real-time
    }
```

---

## Supported Models

Any GGUF-format model compatible with llama.cpp. Popular options:

| Model | Size | Quantization | Use Case |
|-------|------|--------------|----------|
| Qwen2.5-0.5B | ~300MB | Q8_0 | General chat, fast inference |
| Qwen2.5-0.5B | ~200MB | Q4_0 | Memory-constrained devices |
| Qwen2.5-1.5B | ~900MB | Q8_0 | Higher quality responses |
| Llama-3.2-1B | ~600MB | Q8_0 | Meta's latest small model |
| Phi-3-mini | ~2.2GB | Q4_K_M | Microsoft's reasoning model |
| DeepSeek-R1-Distill | ~1.5GB | Q4_K_M | Reasoning/thinking model |

### HuggingFace URLs

Models can be downloaded directly from HuggingFace using the `resolve/main` URL pattern:

```
https://huggingface.co/{org}/{repo}/resolve/main/{filename}.gguf
```

---

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                  RunAnywhere SDK (Kotlin)                    │
│                                                              │
│  RunAnywhere.generate() / chat() / generateStream()          │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                   runanywhere-core-llamacpp                  │
│                                                              │
│  ┌────────────────────────────────────────────────────────┐ │
│  │                 JNI Bridge (Kotlin ↔ C++)               │ │
│  │           librac_backend_llamacpp_jni.so                │ │
│  └────────────────────────────────────────────────────────┘ │
│                              │                               │
│  ┌────────────────────────────────────────────────────────┐ │
│  │                 librunanywhere_llamacpp.so              │ │
│  │              RunAnywhere llama.cpp wrapper              │ │
│  └────────────────────────────────────────────────────────┘ │
│                              │                               │
│  ┌────────────────────────────────────────────────────────┐ │
│  │                    llama.cpp core                       │ │
│  │             libllama.so + libcommon.so                  │ │
│  └────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────┘
```

---

## Native Libraries

This module bundles the following native libraries (~34MB total for ARM64):

| Library | Size | Description |
|---------|------|-------------|
| `librac_backend_llamacpp_jni.so` | ~2MB | JNI bridge |
| `librunanywhere_llamacpp.so` | ~15MB | RunAnywhere llama.cpp wrapper |
| `libllama.so` | ~15MB | llama.cpp core inference |
| `libcommon.so` | ~2MB | llama.cpp utilities |

### Supported ABIs

- `arm64-v8a` — Primary target (modern Android devices)

---

## Build Configuration

### Remote Mode (Default)

Native libraries are automatically downloaded from GitHub releases:

```kotlin
// gradle.properties
runanywhere.testLocal=false  // Downloads from releases
runanywhere.coreVersion=0.1.4
```

### Local Development

For developing with local C++ builds:

```kotlin
// gradle.properties
runanywhere.testLocal=true   // Uses local jniLibs/
```

Then build the native libraries:

```bash
cd ../../  # SDK root
./scripts/build-kotlin.sh --setup
```

---

## Performance

### Typical Benchmarks (Pixel 7, 8GB RAM)

| Model | Load Time | Tokens/sec | Memory |
|-------|-----------|------------|--------|
| Qwen2.5-0.5B Q8 | ~500ms | 15-25 tok/s | ~500MB |
| Qwen2.5-0.5B Q4 | ~400ms | 20-30 tok/s | ~300MB |
| Qwen2.5-1.5B Q8 | ~800ms | 10-15 tok/s | ~1.5GB |

### Optimization Tips

1. **Use quantized models** — Q4 uses ~40% less memory than Q8
2. **Limit context length** — Reduce `contextLength` for faster inference
3. **Monitor thermal state** — Throttle if device is hot
4. **Unload when done** — Call `unloadLLMModel()` to free memory

---

## Requirements

- **Android**: API 24+ (Android 7.0+)
- **Architecture**: ARM64 (arm64-v8a)
- **Memory**: 1GB+ free RAM recommended
- **RunAnywhere SDK**: 0.1.4+

---

## Troubleshooting

### Model fails to load

```
SDKError: MODEL_LOAD_FAILED - Insufficient memory
```

**Solution:** Use a smaller quantized model (Q4 instead of Q8) or ensure sufficient free RAM.

### Slow inference

Check the result metrics:
```kotlin
val result = RunAnywhere.generate(prompt)
if (result.tokensPerSecond < 5) {
    // Consider a smaller model or check device state
}
```

### Model not recognized

Ensure the model is GGUF format and framework is set correctly:
```kotlin
RunAnywhere.registerModel(
    framework = InferenceFramework.LLAMA_CPP  // Must be LLAMA_CPP for this module
)
```

---

## License

Apache 2.0. See [LICENSE](../../../../LICENSE).

This module includes:
- **llama.cpp** — MIT License
- **ggml** — MIT License

---

## See Also

- [RunAnywhere Kotlin SDK](../../README.md) — Main SDK documentation
- [llama.cpp](https://github.com/ggerganov/llama.cpp) — Upstream project
- [GGUF Models on HuggingFace](https://huggingface.co/models?library=gguf) — Model repository
