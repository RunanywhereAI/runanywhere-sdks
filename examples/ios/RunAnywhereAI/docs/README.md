# RunAnywhereAI iOS Documentation

Welcome to the RunAnywhereAI iOS sample app documentation. This guide helps you understand, implement, and use various on-device LLM frameworks.

## 📚 Documentation Structure

### 🚀 [Getting Started](implementation/quickstart.md)
Quick guide to get the app running with pre-built models.

### 🛠️ [Frameworks](frameworks/)
Detailed guides for each supported LLM framework:
- [Framework Overview & Comparison](frameworks/README.md)
- [Complete iOS LLM Frameworks Guide](frameworks/ios-llm-frameworks-guide.md)
- [Swift Transformers Guide](frameworks/swift-transformers.md)
- [TensorFlow Lite Implementation](frameworks/tensorflow-lite.md)

### 📦 [Model Management](models/)
Everything about managing ML models:
- [Model Management Overview](models/README.md)
- [Downloading Models](models/download-guide.md)
- [Bundling Models in App](models/bundled-models.md)
- Provider-specific guides:
  - [HuggingFace Models](models/providers/huggingface.md)
  - [Kaggle Models](models/providers/kaggle.md)

### 🏗️ [Implementation](implementation/)
Technical implementation details:
- [Current Implementation Status](implementation/README.md)
- [Quick Start Guide](implementation/quickstart.md)
- [Architecture & Design](implementation/architecture.md)

### ⚙️ [Setup & Configuration](setup/)
Framework-specific setup guides:
- [Foundation Models (iOS 26+)](setup/foundation-models.md)
- [Troubleshooting Common Issues](setup/troubleshooting.md)

## 🎯 Quick Links

### For New Users
1. Start with the [Quick Start Guide](implementation/quickstart.md)
2. Review [Framework Overview](frameworks/README.md) to choose your framework
3. Follow [Model Download Guide](models/download-guide.md) to get models

### For Developers
1. Check [Implementation Status](implementation/README.md) for current progress
2. Review [Architecture Guide](implementation/architecture.md) for technical details
3. See framework-specific guides in [Frameworks](frameworks/) directory

### For Model Integration
1. [Download Models](models/download-guide.md) for on-demand downloads
2. [Bundle Models](models/bundled-models.md) for including models in app
3. Provider guides for [HuggingFace](models/providers/huggingface.md) and [Kaggle](models/providers/kaggle.md)

## 📱 Supported Frameworks

| Framework | Status | Documentation |
|-----------|--------|---------------|
| Foundation Models | ✅ Ready (iOS 26+) | [Setup Guide](setup/foundation-models.md) |
| Core ML | ✅ Implemented | [Framework Guide](frameworks/ios-llm-frameworks-guide.md#2-core-ml) |
| MLX | ✅ Implemented | [Framework Guide](frameworks/ios-llm-frameworks-guide.md#3-mlx-framework) |
| ONNX Runtime | ✅ Implemented | [Framework Guide](frameworks/ios-llm-frameworks-guide.md#5-onnx-runtime) |
| TensorFlow Lite | ✅ Implemented | [TFLite Guide](frameworks/tensorflow-lite.md) |
| Swift Transformers | ✅ Implemented | [Swift Transformers Guide](frameworks/swift-transformers.md) |
| MLC-LLM | 🔄 Coming Soon | [Framework Guide](frameworks/ios-llm-frameworks-guide.md#4-mlc-llm) |
| ExecuTorch | 🔄 Coming Soon | [Framework Guide](frameworks/ios-llm-frameworks-guide.md#6-executorch) |
| llama.cpp | 🔄 Coming Soon | [Framework Guide](frameworks/ios-llm-frameworks-guide.md#7-llamacpp-gguf) |
| picoLLM | 🔄 Coming Soon | [Framework Guide](frameworks/ios-llm-frameworks-guide.md#9-picollm) |

## 🔧 Development Status

The RunAnywhereAI app demonstrates real implementations of multiple on-device LLM frameworks. See [Implementation Status](implementation/README.md) for detailed progress.

## 📝 Contributing

When adding new documentation:
1. Place framework-specific docs in `frameworks/`
2. Model-related docs go in `models/`
3. Implementation guides in `implementation/`
4. Keep this README updated with new links

---

*Last Updated: July 2025*
