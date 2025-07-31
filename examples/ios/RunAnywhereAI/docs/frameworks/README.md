# iOS LLM Frameworks Overview

This directory contains detailed documentation for each LLM framework supported by RunAnywhereAI.

## Framework Comparison Matrix

| Framework | Best For | Min iOS | Device Requirements | Model Formats | Production Ready |
|-----------|----------|---------|-------------------|---------------|------------------|
| **[Foundation Models](../setup/foundation-models.md)** | iOS 26+ native apps | iOS 26.0 | iPhone 15 Pro+ (A17 Pro) | System-managed | 🔶 Beta |
| **[Core ML](ios-llm-frameworks-guide.md#2-core-ml)** | Apple ecosystem | iOS 13.0 | All iOS devices | .mlpackage, .mlmodel | ✅ Yes |
| **[MLX](ios-llm-frameworks-guide.md#3-mlx-framework)** | Performance-critical | iOS 14.0 | A14+ recommended | .safetensors | ✅ Yes |
| **[ONNX Runtime](ios-llm-frameworks-guide.md#5-onnx-runtime)** | Cross-platform models | iOS 13.0 | All iOS devices | .onnx, .ort | ✅ Yes |
| **[TensorFlow Lite](tensorflow-lite.md)** | TensorFlow models | iOS 12.0 | All iOS devices | .tflite | ✅ Yes |
| **[Swift Transformers](swift-transformers.md)** | HuggingFace models | iOS 15.0 | All iOS devices | .mlpackage | ✅ Yes |
| **[MLC-LLM](ios-llm-frameworks-guide.md#4-mlc-llm)** | Universal deployment | iOS 14.0 | All iOS devices | Pre-compiled | 🔄 Coming Soon |
| **[ExecuTorch](ios-llm-frameworks-guide.md#6-executorch)** | PyTorch models | iOS 13.0 | All iOS devices | .pte | 🔄 Coming Soon |
| **[llama.cpp](ios-llm-frameworks-guide.md#7-llamacpp-gguf)** | GGUF models | iOS 12.0 | All iOS devices | .gguf | 🔄 Coming Soon |
| **[picoLLM](ios-llm-frameworks-guide.md#9-picollm)** | Commercial apps | iOS 13.0 | All iOS devices | Compressed | 🔄 Coming Soon |

## Quick Selection Guide

### Choose Foundation Models if:
- You're targeting iOS 26+ exclusively
- You want Apple's native optimizations
- You need built-in safety features
- Model size/management isn't a concern

### Choose Core ML if:
- You need broad iOS device support
- You have Core ML models available
- You want Apple's Neural Engine optimization
- You're already in the Apple ecosystem

### Choose MLX if:
- Performance is critical
- You have Apple Silicon devices (A14+)
- You need unified memory architecture
- You're comfortable with newer APIs

### Choose ONNX Runtime if:
- You have ONNX models from other platforms
- You need cross-platform compatibility
- You want flexibility in model sources
- You need specific ONNX operators

### Choose TensorFlow Lite if:
- You have TensorFlow models
- You need quantization options
- You want mature, stable framework
- You need Android compatibility

### Choose Swift Transformers if:
- You want HuggingFace model compatibility
- You prefer Swift-native implementation
- You need transformer architectures
- You want easy model discovery

## Performance Characteristics

| Framework | Inference Speed | Memory Usage | Battery Impact | Startup Time |
|-----------|----------------|--------------|----------------|--------------|
| Foundation Models | ⚡⚡⚡⚡⚡ | ⭐⭐⭐ | ⭐⭐⭐⭐ | ⚡⚡⚡⚡⚡ |
| Core ML | ⚡⚡⚡⚡ | ⭐⭐⭐⭐ | ⭐⭐⭐⭐⭐ | ⚡⚡⚡⚡ |
| MLX | ⚡⚡⚡⚡⚡ | ⭐⭐⭐⭐⭐ | ⭐⭐⭐⭐ | ⚡⚡⚡ |
| ONNX Runtime | ⚡⚡⚡ | ⭐⭐⭐ | ⭐⭐⭐ | ⚡⚡⚡ |
| TensorFlow Lite | ⚡⚡⚡ | ⭐⭐⭐ | ⭐⭐⭐ | ⚡⚡ |
| Swift Transformers | ⚡⚡⚡⚡ | ⭐⭐⭐⭐ | ⭐⭐⭐⭐ | ⚡⚡⚡ |

*⚡ = Speed (more is faster), ⭐ = Efficiency (more is better)*

## Model Availability

| Framework | Model Sources | Pre-converted Models | Model Conversion |
|-----------|--------------|---------------------|------------------|
| Foundation Models | Built-in only | N/A | Not needed |
| Core ML | [Apple Models](https://developer.apple.com/machine-learning/models/), HuggingFace | Many available | coremltools |
| MLX | [MLX Community](https://huggingface.co/mlx-community) | Growing library | From PyTorch |
| ONNX Runtime | [ONNX Model Zoo](https://github.com/onnx/models) | Extensive | From any framework |
| TensorFlow Lite | [TF Hub](https://tfhub.dev), Kaggle | Many available | TF Lite Converter |
| Swift Transformers | [HuggingFace](https://huggingface.co) | Limited | From Transformers |

## Documentation

- **[Complete Framework Guide](ios-llm-frameworks-guide.md)** - Detailed guide for all frameworks
- **[Swift Transformers Guide](swift-transformers.md)** - Swift Transformers specific documentation
- **[TensorFlow Lite Guide](tensorflow-lite.md)** - TFLite implementation details

## Implementation Status in RunAnywhereAI

| Framework | Implementation | Features | Notes |
|-----------|---------------|----------|-------|
| Foundation Models | ✅ Complete | Streaming, structured output | Requires iOS 26 beta |
| Core ML | ✅ Complete | Model loading, tokenization | Supports .mlpackage |
| MLX | ✅ Complete | GPU acceleration, lazy eval | Best on A14+ |
| ONNX Runtime | ✅ Complete | CoreML provider | Cross-platform models |
| TensorFlow Lite | ✅ Complete | Metal delegate | Via CocoaPods |
| Swift Transformers | ✅ Complete | HF compatibility | Directory downloads |
| Others | 🔄 Planned | - | Coming in future updates |

---

*For detailed implementation of each framework, see the [Complete iOS LLM Frameworks Guide](ios-llm-frameworks-guide.md)*