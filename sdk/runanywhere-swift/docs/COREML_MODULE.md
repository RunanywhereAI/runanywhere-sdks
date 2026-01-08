# CoreML Module Documentation

## Overview

CoreML (Core Machine Learning) is Apple's unified framework for integrating machine learning models across iOS, macOS, tvOS, and watchOS platforms. In the RunAnywhere Swift SDK, CoreML provides native on-device AI capabilities with direct access to Apple's Neural Engine and optimized hardware acceleration.

### What is CoreML?

CoreML is Apple's foundational ML framework that:
- **Runs models on-device** with zero network latency
- **Optimizes for Apple silicon** (Neural Engine, GPU, CPU)
- **Preserves privacy** by keeping all inference local
- **Minimizes battery impact** through hardware-accelerated inference
- **Supports broad compatibility** across Apple platforms

### Target Platforms

- **iOS**: 16.0+ (recommended), 13.0+ (basic support)
- **macOS**: 13.0+ (recommended), 10.15+ (basic support)
- **tvOS**: 16.0+
- **watchOS**: 9.0+

### Key Benefits

| Feature | Benefit |
|---------|---------|
| **Neural Engine Access** | Up to 15x faster inference on Apple Silicon devices |
| **Broad Compatibility** | Runs on all Apple devices with automatic fallback |
| **Power Efficiency** | 10x more power-efficient than GPU-only inference |
| **Zero Dependencies** | Built into the OS, no external frameworks needed |
| **Automatic Optimization** | CoreML compiler optimizes models for each device |

---

## Capabilities

The CoreML module in RunAnywhere supports multiple AI modalities:

### 1. LLM (Text Generation)

Generate text using CoreML-converted language models.

**Supported Models:**
- TinyLlama (CoreML)
- Phi-2/Phi-3 (CoreML)
- Gemma (CoreML)
- Custom CoreML-converted LLMs

**Use Cases:**
- On-device chatbots
- Text completion
- Code generation
- Summarization

### 2. TTS (Text-to-Speech)

Convert text to natural speech using Kokoro-CoreML or similar models.

**Supported Models:**
- Kokoro-CoreML (high-quality neural TTS)
- Custom CoreML TTS models

**Features:**
- Multiple voices and languages
- Streaming audio generation
- Low latency (<100ms first token)
- Natural prosody and intonation

### 3. Vision (Object Detection & Classification)

Analyze images and videos for objects, scenes, and patterns.

**Supported Models:**
- YOLO (CoreML) - Object detection
- MobileNet (CoreML) - Image classification
- SqueezeNet - Compact classification
- Custom Vision models

**Use Cases:**
- Real-time object detection
- Image classification
- Scene understanding
- Custom vision tasks

### 4. Embeddings (Text/Image)

Generate vector embeddings for semantic search and similarity.

**Supported Models:**
- BERT (CoreML)
- DistilBERT (CoreML)
- Sentence Transformers (CoreML)
- CLIP (text + image embeddings)

**Use Cases:**
- Semantic search
- Document similarity
- Recommendation systems
- RAG (Retrieval-Augmented Generation)

### 5. STT (Speech-to-Text) - Via WhisperKit

**Note:** For speech-to-text, use the dedicated WhisperKit module rather than direct CoreML integration.

WhisperKit provides:
- CoreML-optimized Whisper models
- Streaming transcription
- Multiple languages
- Speaker diarization support

See [WhisperKit Integration](#integration-with-whisperkit) below.

---

## Hardware & Compute Units

CoreML intelligently distributes computation across CPU, GPU, and Neural Engine based on model requirements and device capabilities.

### Compute Unit Options

```swift
public enum ComputeUnits {
    case all                  // Automatic selection (recommended)
    case cpuOnly              // CPU-only execution
    case cpuAndGPU            // CPU + GPU (no Neural Engine)
    case cpuAndNeuralEngine   // CPU + Neural Engine (recommended for A11+)
}
```

### When to Use Each Compute Unit

| Compute Unit | Best For | Device Requirements | Performance |
|--------------|----------|---------------------|-------------|
| **`.all`** | Most scenarios | Any device | Optimal (auto-selected) |
| **`.cpuAndNeuralEngine`** | Neural operations (transformers, CNNs) | A11+ chip | Fastest, most efficient |
| **`.cpuAndGPU`** | Graphics-heavy models (GANs, diffusion) | Any GPU | Fast, moderate power |
| **`.cpuOnly`** | Legacy devices, debugging | Any device | Slowest, highest power |

### Neural Engine Benefits

The Apple Neural Engine (ANE) provides:

- **15x faster** inference vs CPU
- **10x more power efficient** than GPU
- **Optimized for ML operations**: Matrix multiplication, convolutions, activations
- **Available on**: A11 Bionic and later (iPhone 8+, iPad Pro 2017+)

### Neural Engine Limitations

Not all operations run on ANE:
- **Unsupported ops** fall back to CPU/GPU automatically
- **Dynamic shapes** may prevent ANE usage
- **Large models** may not fit in ANE memory (use quantization)

**Solution:** Use quantized models (FP16 or INT8) to maximize ANE compatibility.

---

## Installation

### Package.swift Configuration

CoreML is a **system framework** built into Apple platforms. No external dependencies are required.

```swift
// Package.swift
dependencies: [
    .package(url: "https://github.com/RunanywhereAI/runanywhere-swift", from: "0.1.0")
],
targets: [
    .target(
        name: "YourApp",
        dependencies: [
            .product(name: "RunAnywhere", package: "runanywhere-swift")
            // CoreML module will be included automatically
        ]
    )
]
```

### Adding to Your Xcode Project

1. **Swift Package Manager** (Recommended):
   - File → Add Package Dependencies
   - Enter: `https://github.com/RunanywhereAI/runanywhere-swift`
   - Select: `RunAnywhere` product

2. **Manual Integration**:
   - Link `CoreML.framework` (automatic in modern Xcode)
   - Import `RunAnywhere` in your Swift files

---

## Quick Start

### Basic Initialization

```swift
import RunAnywhere

// Initialize RunAnywhere SDK
let sdk = try await RunAnywhere.initialize(
    apiKey: "your-api-key",
    configuration: .init(
        enableLocalInference: true,
        preferredFramework: .coreML
    )
)

// CoreML module is automatically available
```

### Vision: Object Detection

```swift
import CoreML
import Vision

// Register a CoreML vision model
try await sdk.registerModel(
    modelId: "yolov8n-coreml",
    framework: .coreML,
    category: .vision,
    modelPath: "/path/to/YOLOv8n.mlmodel"
)

// Perform object detection
let image = UIImage(named: "photo.jpg")!
let results = try await sdk.vision.detectObjects(
    image: image,
    modelId: "yolov8n-coreml",
    options: VisionOptions(
        confidenceThreshold: 0.5,
        maxDetections: 10
    )
)

// Process results
for detection in results.detections {
    print("Found \(detection.label) at \(detection.boundingBox) (confidence: \(detection.confidence))")
}
```

### Embeddings: Semantic Search

```swift
// Register a CoreML embeddings model
try await sdk.registerModel(
    modelId: "distilbert-coreml",
    framework: .coreML,
    category: .embeddings,
    modelPath: "/path/to/DistilBERT.mlpackage"
)

// Generate embeddings
let embedding = try await sdk.embeddings.generate(
    text: "The quick brown fox jumps over the lazy dog",
    modelId: "distilbert-coreml"
)

print("Embedding dimension: \(embedding.vector.count)")
// Output: Embedding dimension: 768

// Compute similarity
let similarity = sdk.embeddings.cosineSimilarity(
    embedding1: embedding,
    embedding2: otherEmbedding
)
```

### TTS: Text-to-Speech

```swift
// Register Kokoro-CoreML TTS model
try await sdk.registerModel(
    modelId: "kokoro-coreml-v1",
    framework: .coreML,
    category: .tts,
    modelPath: "/path/to/KokoroCoreML.mlpackage"
)

// Synthesize speech
let audioData = try await sdk.tts.synthesize(
    text: "Hello, this is a CoreML-powered text-to-speech system.",
    voice: "en-US-female",
    modelId: "kokoro-coreml-v1",
    options: TTSOptions(
        sampleRate: 22050,
        streaming: true
    )
)

// Play audio
let audioPlayer = AVAudioPlayer(data: audioData, fileTypeHint: "wav")
audioPlayer.play()
```

---

## Model Management

### Supported Model Formats

CoreML supports three primary model formats:

| Format | Description | Compilation |
|--------|-------------|-------------|
| **`.mlmodel`** | Single-file CoreML model (legacy) | Automatic |
| **`.mlpackage`** | Modern package format (recommended) | Automatic |
| **`.mlmodelc`** | Pre-compiled model (optimized) | Manual |

### Model Compilation

CoreML automatically compiles `.mlmodel` and `.mlpackage` files on first load. For production, pre-compile models:

#### Automatic Compilation (Development)

```swift
// RunAnywhere handles compilation automatically
let model = try await sdk.loadModel(
    modelId: "my-model",
    framework: .coreML,
    modelPath: "/path/to/MyModel.mlpackage"
)
// CoreML compiles the model on first use
```

#### Manual Compilation (Production)

```bash
# Compile CoreML model to .mlmodelc
xcrun coremlcompiler compile MyModel.mlpackage ./

# Results in: MyModel.mlmodelc/
```

```swift
// Load pre-compiled model (faster startup)
let model = try await sdk.loadModel(
    modelId: "my-model",
    framework: .coreML,
    modelPath: "/path/to/MyModel.mlmodelc"
)
```

### Model Sources

#### 1. Hugging Face Hub

Many CoreML models are available on Hugging Face:

```swift
// Download from Hugging Face
let modelPath = try await sdk.downloadModel(
    from: "https://huggingface.co/apple/coreml-models/resolve/main/MobileNetV2.mlpackage.zip",
    modelId: "mobilenet-v2"
)

// Register the model
try await sdk.registerModel(
    modelId: "mobilenet-v2",
    framework: .coreML,
    category: .vision,
    modelPath: modelPath
)
```

#### 2. Custom Conversions

Convert PyTorch, TensorFlow, or ONNX models to CoreML (see [Model Conversion](#model-conversion)).

#### 3. Apple's Model Gallery

Apple provides pre-trained CoreML models:
- [Apple ML Models](https://developer.apple.com/machine-learning/models/)
- Downloadable `.mlmodel` files ready to use

### Download Strategies

```swift
// Configure model download behavior
let config = ModelDownloadConfiguration(
    strategy: .wifiOnly,           // Download only on Wi-Fi
    maxConcurrentDownloads: 2,     // Limit concurrent downloads
    allowCellular: false,          // Prevent cellular downloads
    retryAttempts: 3               // Retry failed downloads
)

// Download with strategy
try await sdk.downloadModel(
    from: modelURL,
    modelId: "my-model",
    configuration: config
)
```

---

## Configuration

### CoreML Compute Configuration

```swift
import RunAnywhere

// Create CoreML configuration
let coreMLConfig = CoreMLOptions(
    useNeuralEngine: true,              // Enable Neural Engine (recommended)
    computeUnits: .cpuAndNeuralEngine   // Prefer ANE over GPU
)

// Apply to generation options
let options = RunAnywhereGenerationOptions(
    maxTokens: 512,
    temperature: 0.7,
    coreMLOptions: coreMLConfig
)

// Generate with CoreML
let response = try await sdk.generate(
    prompt: "Explain quantum computing",
    options: options
)
```

### Automatic vs Manual Compute Unit Selection

#### Automatic Selection (Recommended)

```swift
let config = CoreMLOptions(
    useNeuralEngine: true,
    computeUnits: .all  // Let CoreML choose optimal compute units
)
```

CoreML analyzes:
- Model operations
- Device capabilities
- Battery state
- Thermal state

#### Manual Selection (Advanced)

```swift
// Force Neural Engine (fast, efficient)
let aneConfig = CoreMLOptions(
    useNeuralEngine: true,
    computeUnits: .cpuAndNeuralEngine
)

// Force GPU (graphics-heavy models)
let gpuConfig = CoreMLOptions(
    useNeuralEngine: false,
    computeUnits: .cpuAndGPU
)

// CPU-only (debugging, legacy devices)
let cpuConfig = CoreMLOptions(
    useNeuralEngine: false,
    computeUnits: .cpuOnly
)
```

### Model Compilation Settings

```swift
// Advanced: Control CoreML compilation
let modelConfig = ModelCompilationOptions(
    optimizeForSize: true,          // Reduce model size
    allowLowPrecision: true,        // Enable FP16 (faster, smaller)
    computeUnits: .cpuAndNeuralEngine
)

// Compile with options
let compiledPath = try await sdk.compileModel(
    sourcePath: "/path/to/Model.mlpackage",
    options: modelConfig
)
```

---

## API Reference

### CoreMLModule.autoRegister()

Automatically registers CoreML framework with the RunAnywhere SDK.

```swift
public static func autoRegister()
```

**Usage:**

```swift
// In your app initialization
CoreMLModule.autoRegister()

let sdk = try await RunAnywhere.initialize(apiKey: "key")
// CoreML is now available
```

### CoreMLAdapter

Bridges CoreML models with RunAnywhere's unified interface.

```swift
public class CoreMLAdapter: UnifiedFrameworkAdapter {
    public func loadModel(modelPath: String, config: ModelConfiguration) async throws -> LoadedModel
    public func unloadModel(modelId: String) async throws
    public func predict(input: ModelInput, modelId: String) async throws -> ModelOutput
}
```

**Example:**

```swift
let adapter = CoreMLAdapter()

// Load a CoreML model
let model = try await adapter.loadModel(
    modelPath: "/path/to/Model.mlpackage",
    config: ModelConfiguration(
        computeUnits: .cpuAndNeuralEngine,
        batchSize: 1
    )
)

// Run inference
let output = try await adapter.predict(
    input: .text("Input text"),
    modelId: model.id
)
```

### CoreMLLLMService

Provides text generation using CoreML-based language models.

```swift
public class CoreMLLLMService: LLMService {
    public func generate(prompt: String, options: GenerationOptions) async throws -> String
    public func generateStream(prompt: String, options: GenerationOptions) -> AsyncStream<String>
}
```

**Example:**

```swift
let llmService = CoreMLLLMService(modelId: "tinyllama-coreml")

// Non-streaming generation
let response = try await llmService.generate(
    prompt: "What is the capital of France?",
    options: GenerationOptions(maxTokens: 100, temperature: 0.7)
)

// Streaming generation
for await token in llmService.generateStream(prompt: "Tell me a story", options: options) {
    print(token, terminator: "")
}
```

### CoreMLTTSService

Provides text-to-speech synthesis using CoreML models.

```swift
public class CoreMLTTSService: TTSService {
    public func synthesize(text: String, voice: String, options: TTSOptions) async throws -> Data
    public func synthesizeStream(text: String, voice: String, options: TTSOptions) -> AsyncStream<Data>
}
```

**Example:**

```swift
let ttsService = CoreMLTTSService(modelId: "kokoro-coreml")

// Synthesize complete audio
let audioData = try await ttsService.synthesize(
    text: "Welcome to CoreML text-to-speech.",
    voice: "en-US-female",
    options: TTSOptions(sampleRate: 22050)
)

// Streaming synthesis (low latency)
for await chunk in ttsService.synthesizeStream(text: longText, voice: "en-US-male", options: options) {
    audioPlayer.play(chunk)
}
```

### CoreMLVisionService

Provides computer vision capabilities (detection, classification).

```swift
public class CoreMLVisionService: VisionService {
    public func detectObjects(image: UIImage, options: VisionOptions) async throws -> [Detection]
    public func classify(image: UIImage, options: VisionOptions) async throws -> [Classification]
}
```

**Example:**

```swift
let visionService = CoreMLVisionService(modelId: "yolov8-coreml")

// Object detection
let detections = try await visionService.detectObjects(
    image: inputImage,
    options: VisionOptions(confidenceThreshold: 0.6)
)

// Image classification
let classifications = try await visionService.classify(
    image: inputImage,
    options: VisionOptions(topK: 5)
)
```

### CoreMLEmbeddingsService

Generates vector embeddings for text or images.

```swift
public class CoreMLEmbeddingsService: EmbeddingsService {
    public func generate(text: String) async throws -> Embedding
    public func generate(image: UIImage) async throws -> Embedding
    public func cosineSimilarity(_ a: Embedding, _ b: Embedding) -> Float
}
```

**Example:**

```swift
let embeddingsService = CoreMLEmbeddingsService(modelId: "sentence-bert-coreml")

// Text embeddings
let embedding1 = try await embeddingsService.generate(text: "Machine learning")
let embedding2 = try await embeddingsService.generate(text: "Deep learning")

// Compute similarity
let similarity = embeddingsService.cosineSimilarity(embedding1, embedding2)
print("Similarity: \(similarity)")  // 0.87
```

### CoreMLModelDownloadStrategy

Handles CoreML model downloads with platform-specific optimizations.

```swift
public class CoreMLModelDownloadStrategy: ModelDownloadStrategy {
    public func download(from url: URL, to destination: URL, progress: DownloadProgress?) async throws
    public func validate(modelPath: URL) async throws -> Bool
}
```

**Example:**

```swift
let strategy = CoreMLModelDownloadStrategy()

// Download with progress tracking
try await strategy.download(
    from: URL(string: "https://example.com/model.mlpackage.zip")!,
    to: localPath,
    progress: { progress in
        print("Downloaded \(progress.completedBytes) / \(progress.totalBytes)")
    }
)

// Validate downloaded model
let isValid = try await strategy.validate(modelPath: localPath)
```

---

## Model Conversion

### Converting PyTorch Models to CoreML

Use Apple's `coremltools` to convert PyTorch models:

```python
import torch
import coremltools as ct

# Load PyTorch model
model = torch.load("model.pth")
model.eval()

# Trace the model
example_input = torch.rand(1, 3, 224, 224)
traced_model = torch.jit.trace(model, example_input)

# Convert to CoreML
coreml_model = ct.convert(
    traced_model,
    inputs=[ct.TensorType(shape=(1, 3, 224, 224))],
    compute_units=ct.ComputeUnit.ALL,  # Enable Neural Engine
    minimum_deployment_target=ct.target.iOS16
)

# Save
coreml_model.save("MyModel.mlpackage")
```

### Converting ONNX to CoreML

```python
import coremltools as ct

# Convert ONNX to CoreML
coreml_model = ct.converters.onnx.convert(
    model="model.onnx",
    minimum_ios_deployment_target="16.0",
    compute_units=ct.ComputeUnit.CPU_AND_NE  # Neural Engine
)

# Save
coreml_model.save("ConvertedModel.mlpackage")
```

### Quantization Options

Reduce model size and improve speed with quantization:

#### FP16 Quantization (Recommended)

```python
# Convert with FP16 weights
coreml_model = ct.convert(
    traced_model,
    inputs=[ct.TensorType(shape=(1, 3, 224, 224))],
    compute_precision=ct.precision.FLOAT16,  # FP16 quantization
    compute_units=ct.ComputeUnit.ALL
)
```

**Benefits:**
- 50% smaller model size
- 2x faster inference
- Minimal accuracy loss (~0.1%)

#### INT8 Quantization (Aggressive)

```python
# Convert with INT8 quantization
coreml_model = ct.convert(
    traced_model,
    inputs=[ct.TensorType(shape=(1, 3, 224, 224))],
    compute_precision=ct.precision.INT8,
    compute_units=ct.ComputeUnit.CPU_AND_NE
)
```

**Benefits:**
- 75% smaller model size
- 3-4x faster inference
- Moderate accuracy loss (~1-3%)

---

## Best Practices

### When to Use CoreML vs MLX vs FoundationModels

| Framework | Best For | Platforms | Performance |
|-----------|----------|-----------|-------------|
| **CoreML** | Production apps, broad compatibility | iOS 13+, macOS 10.15+ | Fast, efficient |
| **MLX** | Cutting-edge models, M-series Macs | macOS 13+ (Apple Silicon) | Fastest (M-series) |
| **FoundationModels** | Apple Intelligence features | iOS 18+, macOS 15+ | Optimized, cloud-backed |

**Use CoreML when:**
- You need broad device support (iOS 13+)
- Privacy is critical (100% on-device)
- Model is available in CoreML format
- Battery efficiency is important

**Use MLX when:**
- Targeting M-series Macs exclusively
- Need state-of-the-art model architectures
- Developing research or experimental features

**Use FoundationModels when:**
- Building iOS 18+ exclusive features
- Want Apple-optimized models (Siri, Vision, etc.)
- Need cloud fallback for complex tasks

### Neural Engine Optimization Tips

#### 1. Use FP16 Models

```swift
// Convert models to FP16 for Neural Engine compatibility
// Use coremltools with compute_precision=ct.precision.FLOAT16
```

#### 2. Avoid Dynamic Shapes

```python
# ✅ Good: Fixed input shape
ct.TensorType(shape=(1, 3, 224, 224))

# ❌ Bad: Dynamic shape (may not use ANE)
ct.TensorType(shape=(1, 3, ct.RangeDim(), ct.RangeDim()))
```

#### 3. Batch Size = 1

```swift
// Neural Engine optimized for batch size 1
let config = ModelConfiguration(batchSize: 1)
```

#### 4. Profile Models

```swift
// Use Xcode Instruments to profile CoreML models
// Instruments → Core ML → Performance
```

### Battery and Performance Considerations

#### Monitor Thermal State

```swift
import Foundation

// Check device thermal state
let thermalState = ProcessInfo.processInfo.thermalState

switch thermalState {
case .nominal, .fair:
    // Safe to use Neural Engine
    useComputeUnits(.cpuAndNeuralEngine)
case .serious, .critical:
    // Throttle to CPU-only
    useComputeUnits(.cpuOnly)
@unknown default:
    useComputeUnits(.cpuOnly)
}
```

#### Battery-Aware Inference

```swift
import UIKit

// Check battery level and state
UIDevice.current.isBatteryMonitoringEnabled = true
let batteryLevel = UIDevice.current.batteryLevel
let batteryState = UIDevice.current.batteryState

if batteryLevel < 0.2 && batteryState == .unplugged {
    // Low battery: use CPU-only
    options.coreMLOptions?.computeUnits = .cpuOnly
} else {
    // Normal: use Neural Engine
    options.coreMLOptions?.computeUnits = .cpuAndNeuralEngine
}
```

#### Background Execution

```swift
// Reduce priority for background tasks
if UIApplication.shared.applicationState == .background {
    options.coreMLOptions?.computeUnits = .cpuOnly
    options.priority = .low
}
```

---

## Integration with WhisperKit

### Why STT Uses WhisperKit Instead of CoreML Directly

WhisperKit is a **CoreML-optimized** speech-to-text framework built on top of CoreML. It provides:

1. **Pre-optimized Whisper models** tuned for Apple devices
2. **Streaming transcription** with low latency
3. **Built-in audio processing** (VAD, noise reduction)
4. **Multi-language support** out of the box

**Direct CoreML approach:**
- Requires manual Whisper model conversion
- No built-in streaming support
- Manual audio preprocessing
- More complex integration

**WhisperKit approach:**
- Drop-in solution for STT
- Optimized for real-time use
- Handles audio pipeline automatically

### Using CoreML and WhisperKit Together

```swift
import RunAnywhere

// Initialize SDK with both CoreML and WhisperKit
let sdk = try await RunAnywhere.initialize(
    apiKey: "your-api-key",
    configuration: .init(
        enableLocalInference: true,
        frameworks: [.coreML, .whisperKit]
    )
)

// Use WhisperKit for STT
let transcription = try await sdk.stt.transcribe(
    audioURL: audioFileURL,
    modelId: "whisperkit-base"  // Uses WhisperKit (CoreML backend)
)

// Use CoreML for LLM
let response = try await sdk.generate(
    prompt: "Summarize: \(transcription.text)",
    options: .init(
        framework: .coreML,
        modelId: "tinyllama-coreml"
    )
)

// Use CoreML for TTS
let audioData = try await sdk.tts.synthesize(
    text: response,
    modelId: "kokoro-coreml"
)
```

---

## Troubleshooting

### Common Errors and Solutions

#### Error: "Model failed to load"

**Cause:** Model file not found or incompatible format.

**Solution:**
```swift
// Verify model path exists
let modelURL = URL(fileURLWithPath: modelPath)
guard FileManager.default.fileExists(atPath: modelURL.path) else {
    print("Model not found at \(modelPath)")
    return
}

// Check model format
let modelExtension = modelURL.pathExtension
guard ["mlmodel", "mlpackage", "mlmodelc"].contains(modelExtension) else {
    print("Invalid model format: \(modelExtension)")
    return
}
```

#### Error: "Failed to create MLModel"

**Cause:** Model requires iOS version higher than device.

**Solution:**
```swift
// Check deployment target
if #available(iOS 16, *) {
    let model = try await loadModel(...)
} else {
    print("Model requires iOS 16+, current: \(UIDevice.current.systemVersion)")
    // Fallback to alternative model or framework
}
```

#### Error: "Model compilation failed"

**Cause:** Corrupted model file or incompatible operations.

**Solution:**
```bash
# Validate model with coremltools
python -c "import coremltools as ct; model = ct.models.MLModel('Model.mlpackage'); print('Valid')"

# Re-export from source
# ... (use conversion code from Model Conversion section)
```

### Model Compilation Issues

#### Issue: Compilation takes too long

**Solution:** Pre-compile models during build time.

```bash
# Add to Xcode build phase
xcrun coremlcompiler compile Models/*.mlpackage ./CompiledModels/
```

#### Issue: Compiled model not found

**Solution:** Ensure `.mlmodelc` is included in app bundle.

```swift
// Check for compiled model
let compiledPath = Bundle.main.url(forResource: "Model", withExtension: "mlmodelc")
if compiledPath == nil {
    print("Compiled model not in bundle")
    // Ensure model is in "Copy Bundle Resources" build phase
}
```

### Compute Unit Fallback Behavior

CoreML automatically falls back if preferred compute units are unavailable:

```swift
// Requested: Neural Engine
options.computeUnits = .cpuAndNeuralEngine

// If ANE unavailable (iPhone 7 or older):
// CoreML falls back to: CPU + GPU

// If GPU unavailable (watchOS):
// CoreML falls back to: CPU only
```

**Monitor actual compute units:**

```swift
import CoreML

// Log which compute units are actually used
let modelConfig = MLModelConfiguration()
modelConfig.computeUnits = .all

// Load model and check performance
let model = try MLModel(contentsOf: modelURL, configuration: modelConfig)

// Use Instruments (Core ML template) to see actual compute unit usage
```

### Performance Issues

#### Issue: Slow inference on device

**Solutions:**

1. **Use FP16 quantization:**
   ```python
   # Convert with FP16
   coreml_model = ct.convert(..., compute_precision=ct.precision.FLOAT16)
   ```

2. **Enable Neural Engine:**
   ```swift
   options.coreMLOptions = CoreMLOptions(
       useNeuralEngine: true,
       computeUnits: .cpuAndNeuralEngine
   )
   ```

3. **Reduce model complexity:**
   - Use smaller models (e.g., TinyLlama instead of Llama-7B)
   - Quantize to INT8 if accuracy allows
   - Prune unnecessary layers

4. **Profile with Instruments:**
   - Xcode → Product → Profile
   - Select "Core ML" template
   - Identify bottlenecks

#### Issue: High memory usage

**Solutions:**

1. **Unload models when not in use:**
   ```swift
   try await sdk.unloadModel(modelId: "large-model")
   ```

2. **Use model batching:**
   ```swift
   // Process multiple inputs in batch (if model supports)
   let results = try await model.predict(batch: inputs)
   ```

3. **Enable memory warnings:**
   ```swift
   NotificationCenter.default.addObserver(
       forName: UIApplication.didReceiveMemoryWarningNotification,
       object: nil,
       queue: .main
   ) { _ in
       // Unload non-critical models
       try? await sdk.unloadModel(modelId: "optional-model")
   }
   ```

---

## Additional Resources

### Apple Documentation
- [Core ML Framework](https://developer.apple.com/documentation/coreml)
- [Core ML Tools](https://apple.github.io/coremltools/)
- [Neural Engine Guide](https://developer.apple.com/machine-learning/core-ml/)

### Hugging Face CoreML Models
- [Apple CoreML Models](https://huggingface.co/apple)
- [Community CoreML Models](https://huggingface.co/models?library=coreml)

### Conversion Tools
- [coremltools (Python)](https://github.com/apple/coremltools)
- [ONNX-CoreML](https://github.com/onnx/onnx-coreml)

### Related RunAnywhere Documentation
- [WhisperKit Module](./WHISPERKIT_MODULE.md) - CoreML-based STT
- [Architecture Guide](./ARCHITECTURE.md) - SDK architecture overview
- [Model Management](./MODEL_MANAGEMENT.md) - Loading and managing models

---

## Summary

The CoreML module in RunAnywhere Swift SDK provides:

- **Broad platform support**: iOS 13+, macOS 10.15+, tvOS, watchOS
- **Multiple AI capabilities**: LLM, TTS, Vision, Embeddings
- **Hardware acceleration**: Neural Engine, GPU, CPU
- **Zero dependencies**: Built into Apple platforms
- **Privacy-first**: 100% on-device inference
- **Easy integration**: Unified API with automatic optimization

For speech-to-text, use the dedicated WhisperKit module (built on CoreML) for optimized performance. For all other AI tasks, CoreML provides the best balance of compatibility, performance, and battery efficiency across Apple devices.
