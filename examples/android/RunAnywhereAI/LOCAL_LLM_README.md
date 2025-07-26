# RunAnywhere AI - Local LLM Implementation

This Android sample app demonstrates on-device Large Language Model (LLM) inference using the RunAnywhere SDK.

## Features

### 🚀 On-Device LLM Inference
- **MediaPipe LLM Inference**: Optimized for Google's models (Gemma, etc.)
- **ONNX Runtime**: Cross-platform support for various model formats
- **Privacy-First**: All processing happens on-device, no data leaves the device

### 💬 Chat Interface
- Real-time streaming responses
- Conversation history
- Customizable generation parameters
- Model selection and management

### 📦 Model Management
- Download models on-demand
- View available and downloaded models
- Delete unused models to save space
- Automatic model recommendations based on device capabilities

## Architecture

```
app/
├── llm/                    # LLM core functionality
│   ├── LLMService.kt      # Base interface for LLM services
│   ├── UnifiedLLMManager.kt # Manager for multiple frameworks
│   └── frameworks/        # Framework implementations
│       ├── MediaPipeService.kt
│       └── ONNXRuntimeService.kt
├── ui/                    # User interface
│   ├── chat/             # Chat screen
│   └── models/           # Model management
├── data/                 # Data layer
│   └── repository/       # Model repository
└── utils/                # Utilities

```

## Supported Models

### MediaPipe Models
- **Gemma 2B**: Google's efficient 2B parameter model (INT4 quantized)
- **Phi-2**: Microsoft's 2.7B model (INT4 quantized)
- **Falcon 1B**: Lightweight model for basic tasks
- **StableLM 3B**: Stability AI's language model

### ONNX Runtime Models
- **TinyLlama 1.1B**: Compact Llama variant (FP16)
- Custom ONNX models can be added

## Setup Instructions

1. **Clone the repository** and open the Android project

2. **Build the project**:
   ```bash
   ./gradlew build
   ```

3. **Run on device/emulator**:
   - Minimum Android 7.0 (API 24)
   - Recommended: 4GB+ RAM device
   - For best performance: Device with GPU/NPU support

4. **Download models**:
   - Launch the app
   - Navigate to the Models tab
   - Download desired models
   - Select a model to use in chat

## Usage

### Basic Chat
1. Select a model from the Models tab
2. Navigate to Chat tab
3. Type your message and send
4. View streaming responses in real-time

### Model Management
1. Go to Models tab
2. View available models with size and requirements
3. Download models with progress tracking
4. Delete unused models to free space

## Performance Optimization

The app includes several optimizations:
- **Large heap enabled** for model loading
- **GPU acceleration** via MediaPipe when available
- **NNAPI support** for hardware acceleration
- **Quantized models** (INT4/INT8) for reduced memory usage

## Adding Custom Models

### MediaPipe Models
1. Place `.bin` model files in app assets or download
2. Update `MediaPipeService.SUPPORTED_MODELS`
3. Ensure model is AI Edge compatible

### ONNX Models
1. Convert model to ONNX format
2. Place `.onnx` file in assets or download
3. Implement proper tokenizer in `ONNXRuntimeService`

## Troubleshooting

### Out of Memory
- Use smaller or more quantized models
- Enable large heap in manifest
- Close other apps
- Use device with more RAM

### Model Load Failures
- Verify model file integrity
- Check model format compatibility
- Ensure sufficient storage space
- Verify framework support

### Slow Performance
- Use quantized models (INT4/INT8)
- Enable GPU acceleration
- Reduce context size
- Use appropriate thread count

## Future Enhancements

- [ ] Additional frameworks (ExecuTorch, MLC-LLM, llama.cpp)
- [ ] More model options
- [ ] Performance monitoring dashboard
- [ ] Model conversion tools
- [ ] Custom model training integration
- [ ] Voice input/output
- [ ] Multi-turn conversation context
- [ ] Model fine-tuning capabilities

## Resources

- [MediaPipe GenAI](https://developers.google.com/mediapipe/solutions/genai)
- [ONNX Runtime Android](https://onnxruntime.ai/docs/get-started/with-android.html)
- [Android Neural Networks API](https://developer.android.com/ndk/guides/neuralnetworks)

## License

This sample is part of the RunAnywhere SDK and follows the same licensing terms.