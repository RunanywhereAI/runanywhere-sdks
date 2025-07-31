# Model Management Documentation

This directory contains comprehensive guides for managing ML models in the RunAnywhereAI iOS app.

## 📚 Documentation Overview

### Core Guides

1. **[Model Download Guide](download-guide.md)**
   - Comprehensive guide for downloading models on-demand
   - Covers all supported frameworks and model formats
   - Includes authentication setup for providers

2. **[Bundled Models Guide](bundled-models.md)**
   - How to include models directly in your app bundle
   - Best practices for model size and distribution
   - Step-by-step Xcode integration

3. **[Model Integration Guide](integration-guide.md)**
   - Technical details for model integration
   - Production distribution strategies
   - Security and optimization considerations

### Provider-Specific Guides

- **[HuggingFace Models](providers/huggingface.md)** - Authentication, downloads, and directory handling
- **[Kaggle Models](providers/kaggle.md)** - API setup and TensorFlow Lite models

## 🚀 Quick Start

### Option 1: Download Models On-Demand
Best for large models or when you want to minimize app size.

1. Check available models in the app's Models tab
2. Follow the [Download Guide](download-guide.md) for setup
3. Provider-specific setup:
   - [HuggingFace](providers/huggingface.md) - No auth required for public models
   - [Kaggle](providers/kaggle.md) - Requires API credentials

### Option 2: Bundle Models with App
Best for small models or offline-first apps.

1. Download your model files
2. Follow the [Bundled Models Guide](bundled-models.md)
3. Register models in `BundledModelsService.swift`

## 📦 Supported Model Formats

| Framework | Model Format | Typical Size | Download Method |
|-----------|-------------|--------------|-----------------|
| Core ML | .mlpackage, .mlmodel | 200MB-2GB | HuggingFace, Direct |
| MLX | Directory with .safetensors | 1GB-8GB | HuggingFace |
| ONNX Runtime | .onnx, .ort | 500MB-4GB | Direct URLs |
| TensorFlow Lite | .tflite | 200MB-2GB | Kaggle, Direct |
| Swift Transformers | .mlpackage | 1GB-12GB | HuggingFace |
| llama.cpp | .gguf | 500MB-8GB | HuggingFace, Direct |

## 🔍 Model Sources

### Pre-converted Models Ready to Use

**Swift Transformers Models (No Auth Required):**
- OpenELM-270M-Instruct (~1GB)
- OpenELM-450M-Instruct (~1.7GB)
- OpenELM-1.1B-Instruct (~4GB)
- OpenELM-3B-Instruct (~11GB)

**GGUF Models (Direct Download):**
- TinyLlama 1.1B
- Phi-3 Mini
- Llama 3.2 3B
- Mistral 7B

**TensorFlow Lite Models (Kaggle Auth Required):**
- Gemma 2B (GPU INT4)
- Gemma 2B (CPU INT8)

## 🛠️ Model Management Features

The RunAnywhereAI app provides:

1. **Download Manager**
   - Progress tracking with speed/time remaining
   - Pause/Resume support
   - Background downloads
   - Automatic retry on failure

2. **Model Storage**
   - Organized by framework
   - Automatic cleanup options
   - Storage usage tracking

3. **Model Registry**
   - Central URL management
   - Custom model URL support
   - Import/Export configurations

## 📋 Model Integration Workflow

1. **Choose Distribution Method**
   - On-demand download for large/optional models
   - Bundle for essential/small models

2. **Select Model Source**
   - HuggingFace for most models
   - Kaggle for TensorFlow Lite
   - Direct URLs for GGUF

3. **Configure Authentication** (if needed)
   - HuggingFace: Optional for better rate limits
   - Kaggle: Required for all models

4. **Test Integration**
   - Verify model loads correctly
   - Check performance metrics
   - Validate output quality

## 🔒 Security Considerations

- All downloads use HTTPS
- Optional SHA256 verification
- Models sandboxed in app container
- No code execution from models

## 📱 Platform Considerations

### Storage Requirements
- Ensure 2x model size in free space
- Models stored in Documents/Models/
- Automatic cleanup available

### Network Requirements
- WiFi recommended for large models
- Background download support
- Resumable downloads

### Device Compatibility
- Check framework requirements
- Verify available memory
- Consider thermal constraints

---

*For technical implementation details, see the [Model Integration Guide](integration-guide.md)*
