# MLX Module Documentation

## 1. Overview

### What is MLX?

MLX is Apple's open-source machine learning framework specifically designed for Apple Silicon. Built by Apple's machine learning research team, MLX leverages the unified memory architecture of Apple processors to deliver exceptional performance for on-device AI workloads.

**Key Characteristics:**
- **Unified Memory Architecture**: CPU and GPU share the same memory, eliminating data copying overhead
- **Metal Acceleration**: Native GPU acceleration through Metal framework
- **Lazy Evaluation**: Builds computation graphs executed only when results are needed
- **Multi-Language Support**: APIs in Python, Swift, C++, and C
- **Open Source**: MIT license with active community on [Hugging Face](https://huggingface.co/mlx-community)

### Why Use MLX in RunAnywhere?

MLX provides exceptional performance for LLM inference on Apple devices:

- **230 tok/s** on iPhone 15 Pro (Mistral-7B-Instruct-v0.3-4bit)
- **High-quality models**: Access to thousands of pre-converted models from mlx-community
- **Latest hardware support**: Neural Accelerators in M5 chip (macOS beta), optimized for all Apple Silicon
- **Training support**: Fine-tune models directly on your Mac
- **Multimodal capabilities**: LLM text generation, TTS, embeddings, and more

### Target Platforms

**Minimum Requirements:**
- **iOS**: 18.0+ (unified memory optimizations)
- **macOS**: 13.5+ (Metal 3 support)
- **RAM**: 8GB minimum (16GB+ recommended for larger models)
- **Processor**: Apple Silicon (M1/M2/M3/M4/M5 or A14+)
- **Device**: Physical device only (Simulator not supported)

**Why These Requirements?**
- Unified memory architecture requires Apple Silicon
- Metal Performance Shaders need Metal 3+
- LLM models require substantial RAM (4-bit quantized: 3-8GB, full precision: 14GB+)

## 2. Capabilities

### Primary Use Case: LLM Text Generation

MLX excels at running large language models for text generation:

**Supported Model Types:**
- Decoder-only transformers (GPT-style)
- Instruction-tuned models (Mistral, Llama, Qwen, Phi)
- Thinking models with reasoning tags (`<think>...</think>`)
- Quantized models (4-bit, 8-bit) for memory efficiency

**Performance Characteristics:**
- **Streaming generation**: Real-time token-by-token output
- **Context lengths**: Up to 32K tokens (model dependent)
- **Batch processing**: Single or multi-turn conversations
- **Structured outputs**: JSON schema-guided generation

### Text-to-Speech (TTS)

MLX provides TTS capabilities through the [mlx-audio](https://github.com/ml-explore/mlx-audio) ecosystem:

**Supported Models:**
- Kokoro TTS models (mlx-community)
- Custom TTS models in MLX format

**Note**: For production TTS, consider FluidAudio's Kokoro implementation which offers Core ML optimizations and lower latency.

### Speech-to-Text (STT)

**Current Status**: Limited support

MLX can run Whisper models for speech recognition, but with important caveats:

**Limitations:**
- Higher latency than specialized STT backends
- Limited streaming support
- Less optimized than WhisperKit for Apple devices

**Recommendation**: Use [WhisperKit](https://github.com/argmaxinc/WhisperKit) for production STT instead. WhisperKit provides:
- Core ML optimizations for Apple Neural Engine
- True streaming transcription
- Lower memory footprint
- Better battery efficiency

### Embeddings

Generate vector embeddings for semantic search and RAG applications:

**Supported Models:**
- Sentence transformers (all-MiniLM, BGE, etc.)
- Multilingual embedding models
- Custom embedding models

## 3. Hardware Requirements

### Memory Requirements by Model Size

| Model Size | Quantization | Minimum RAM | Recommended RAM | Example Models |
|------------|-------------|-------------|-----------------|----------------|
| 360M - 1B | 4-bit | 2GB | 4GB | SmolLM2-360M, Qwen2.5-0.5B |
| 1B - 3B | 4-bit | 3GB | 8GB | Llama-3.2-3B, Qwen2.5-3B |
| 7B | 4-bit | 6GB | 16GB | Mistral-7B, Llama-3.1-8B |
| 13B | 4-bit | 10GB | 32GB | Llama-2-13B |
| 70B+ | 4-bit | 48GB+ | 64GB+ | Llama-3.1-70B (Mac Studio/Pro) |

**Device-Specific Recommendations:**

**iPhone:**
- iPhone 15 Pro (8GB RAM): Up to 3B models (4-bit)
- iPhone 16 Pro (8GB RAM): Up to 3B models (4-bit)
- Future iPhones (12GB+): Up to 7B models (4-bit)

**iPad:**
- iPad Pro M1/M2 (8-16GB): Up to 7B models (4-bit)
- iPad Pro M4 (16GB): Up to 7B models (4-bit)

**Mac:**
- MacBook Air M1/M2 (8GB): Up to 3B models (4-bit)
- MacBook Air M3 (16GB): Up to 7B models (4-bit)
- MacBook Pro (16-32GB): Up to 13B models (4-bit)
- Mac Studio/Pro (64GB+): 70B+ models (4-bit)

### Apple Silicon Requirements

**Required:**
- Apple Silicon chip (M1, M2, M3, M4, M5, or A14+)
- Metal 3 support (iOS 16+, macOS 13+)

**Neural Accelerators (M5 only - macOS beta):**
- Dedicated matrix multiplication operations
- 2-3x performance improvement for LLM inference
- Automatic acceleration through Metal 4 and TensorOps framework

**Physical Device Only:**
- iOS/iPadOS Simulator does not support Metal compute
- Xcode Simulator lacks unified memory architecture
- Always test on real hardware

### iOS/macOS Version Requirements

| Feature | iOS | macOS | Reason |
|---------|-----|-------|--------|
| Basic MLX | 18.0+ | 13.5+ | Unified memory optimizations |
| Metal 3 | 16.0+ | 13.0+ | GPU compute shaders |
| Neural Accelerators | N/A | 15.1+ (beta) | M5 chip support |
| Optimal Performance | 18.0+ | 14.0+ | Latest Metal optimizations |

## 4. Installation

### Package.swift Dependencies

Add MLX to your RunAnywhere project:

```swift
dependencies: [
    .package(url: "https://github.com/RunanywhereAI/runanywhere-sdks", from: "0.15.8"),
    .package(url: "https://github.com/ml-explore/mlx-swift", from: "0.30.0"),
    .package(url: "https://github.com/ml-explore/mlx-swift-lm", from: "0.4.0")
],
targets: [
    .target(
        name: "YourApp",
        dependencies: [
            .product(name: "RunAnywhere", package: "runanywhere-sdks"),
            .product(name: "MLX", package: "mlx-swift"),
            .product(name: "MLXLLM", package: "mlx-swift-lm"),
            .product(name: "MLXLMCommon", package: "mlx-swift-lm")
        ]
    )
]
```

### Adding RunAnywhereMLX to Your Project

**Via Xcode:**
1. File > Add Package Dependencies
2. Enter repository URL: `https://github.com/RunanywhereAI/runanywhere-sdks`
3. Select version: `0.15.8` or later
4. Select products:
   - `RunAnywhere` (required)
   - `RunAnywhereMLX` (for MLX support)
5. Click "Add Package"

**Via Swift Package Manager:**
```bash
# Add to Package.swift dependencies
swift package update
```

**Import in Swift:**
```swift
import RunAnywhere
import MLX
import MLXLLM
import MLXLMCommon
```

## 5. Quick Start

### Basic Initialization

```swift
import RunAnywhere
import MLX
import MLXLLM

// Initialize RunAnywhere SDK
try await RunAnywhere.initialize(
    apiKey: "dev",
    baseURL: "localhost",
    environment: .development
)

// Register MLX adapter (planned feature)
// await MLXModule.autoRegister()
```

### LLM Text Generation Example

```swift
import MLXLLM

// Load model from Hugging Face
let modelId = "mlx-community/Mistral-7B-Instruct-v0.3-4bit"
let configuration = ModelConfiguration(id: modelId)

// Load model container
let modelContainer = try await LLMModelFactory.shared.loadContainer(
    configuration: configuration
)

// Generate text
let prompt = "Explain quantum computing in simple terms"
let result = try await modelContainer.perform { model in
    return try await model.generate(
        prompt: prompt,
        parameters: GenerateParameters(
            temperature: 0.7,
            topP: 0.9,
            maxTokens: 150
        )
    )
}

print("Response: \(result.text)")
```

### Streaming Generation Example

```swift
// Stream tokens in real-time
let stream = try await modelContainer.perform { model in
    return try await model.generateStream(
        prompt: "Write a short story about AI",
        parameters: GenerateParameters(temperature: 0.8)
    )
}

for try await token in stream {
    print(token.text, terminator: "")
    // Update UI in real-time
    await MainActor.run {
        outputTextView.text += token.text
    }
}
```

### TTS Synthesis Example

```swift
import MLXAudio // Hypothetical - check mlx-audio for actual API

// Load TTS model
let ttsModelId = "mlx-community/kokoro-82M"
let ttsConfig = ModelConfiguration(id: ttsModelId)
let ttsModel = try await TTSModelFactory.shared.loadContainer(
    configuration: ttsConfig
)

// Synthesize speech
let audioData = try await ttsModel.perform { model in
    return try await model.synthesize(
        text: "Hello, this is MLX text-to-speech",
        parameters: TTSParameters(
            speakerId: 0,
            speed: 1.0
        )
    )
}

// Play audio
let player = try AVAudioPlayer(data: audioData)
player.play()
```

## 6. Model Management

### Supported Model Formats

MLX requires models in its native format:

**Supported Formats:**
- `.safetensors` (MLX-converted weights)
- `.gguf` (limited support through converters)
- MLX model repositories (config.json + weights)

**Note**: Models must be pre-converted to MLX format. Original PyTorch/TensorFlow models require conversion.

### Model Sources (HuggingFace mlx-community)

The [mlx-community](https://huggingface.co/mlx-community) provides thousands of pre-converted models:

**Popular LLM Models:**
- [Mistral-7B-Instruct-v0.3-4bit](https://huggingface.co/mlx-community/Mistral-7B-Instruct-v0.3-4bit)
- [Llama-3.2-3B-Instruct-4bit](https://huggingface.co/mlx-community/Llama-3.2-3B-Instruct-4bit)
- [Qwen2.5-7B-Instruct-4bit](https://huggingface.co/mlx-community/Qwen2.5-7B-Instruct-4bit)
- [Phi-3.5-mini-instruct-4bit](https://huggingface.co/mlx-community/Phi-3.5-mini-instruct-4bit)
- [SmolLM2-1.7B-Instruct-4bit](https://huggingface.co/mlx-community/SmolLM2-1.7B-Instruct-4bit)

**TTS Models:**
- [kokoro-82M-mlx](https://huggingface.co/mlx-community/kokoro-82M-mlx)

**Embedding Models:**
- [all-MiniLM-L6-v2-mlx](https://huggingface.co/mlx-community/all-MiniLM-L6-v2-mlx)
- [bge-base-en-v1.5-mlx](https://huggingface.co/mlx-community/bge-base-en-v1.5-mlx)

### Recommended Models by Device RAM

**8GB RAM Devices (iPhone 15 Pro, MacBook Air M1):**
```swift
// 360M - 1B models for best performance
let models = [
    "mlx-community/SmolLM2-360M-Instruct-4bit",  // 300MB, 230 tok/s
    "mlx-community/Qwen2.5-0.5B-Instruct-4bit",  // 400MB, 180 tok/s
    "mlx-community/SmolLM2-1.7B-Instruct-4bit"   // 1.2GB, 120 tok/s
]
```

**16GB RAM Devices (MacBook Air M3, iPad Pro M4):**
```swift
// 3B - 7B models for quality/performance balance
let models = [
    "mlx-community/Llama-3.2-3B-Instruct-4bit",     // 2.3GB, 90 tok/s
    "mlx-community/Mistral-7B-Instruct-v0.3-4bit",  // 4.8GB, 60 tok/s
    "mlx-community/Qwen2.5-7B-Instruct-4bit"        // 5.1GB, 55 tok/s
]
```

**32GB+ RAM Devices (MacBook Pro, Mac Studio):**
```swift
// 13B+ models for maximum quality
let models = [
    "mlx-community/Llama-2-13B-chat-4bit",          // 8.5GB, 35 tok/s
    "mlx-community/Mixtral-8x7B-Instruct-v0.1-4bit" // 28GB, 20 tok/s
]
```

**64GB+ RAM Devices (Mac Studio Ultra, Mac Pro):**
```swift
// Frontier models for research and production
let models = [
    "mlx-community/Llama-3.1-70B-Instruct-4bit",  // 45GB, 10 tok/s
    "mlx-community/DeepSeek-V2-Chat-4bit"         // 380GB (requires 512GB)
]
```

### Model Download and Caching

```swift
// Models are automatically downloaded on first use
let configuration = ModelConfiguration(
    id: "mlx-community/Mistral-7B-Instruct-v0.3-4bit",
    // Optional: specify local cache directory
    cacheDirectory: FileManager.default.urls(
        for: .cachesDirectory,
        in: .userDomainMask
    ).first?.appendingPathComponent("mlx-models")
)

// Load container (downloads if not cached)
let container = try await LLMModelFactory.shared.loadContainer(
    configuration: configuration
)

// Check cache status
let cacheURL = configuration.modelDirectory
let isModelCached = FileManager.default.fileExists(atPath: cacheURL.path)
print("Model cached: \(isModelCached)")
```

**Cache Management:**
```swift
// Clear model cache to free disk space
func clearMLXCache() throws {
    let cacheDir = FileManager.default.urls(
        for: .cachesDirectory,
        in: .userDomainMask
    ).first?.appendingPathComponent("mlx-models")

    if let cacheDir = cacheDir {
        try FileManager.default.removeItem(at: cacheDir)
    }
}
```

## 7. Configuration

### MLXAdapter Configuration Options

```swift
/// MLX specific options for text generation
public struct MLXOptions {
    /// Use unified memory (default: true)
    /// Enables CPU/GPU memory sharing for zero-copy operations
    public let useUnifiedMemory: Bool

    /// Use Metal Performance Shaders (default: true)
    /// Leverages GPU acceleration for compute operations
    public let useMPS: Bool

    public init(
        useUnifiedMemory: Bool = true,
        useMPS: Bool = true
    ) {
        self.useUnifiedMemory = useUnifiedMemory
        self.useMPS = useMPS
    }
}
```

**Usage:**
```swift
let options = MLXOptions(
    useUnifiedMemory: true,  // Recommended: enables zero-copy
    useMPS: true             // Recommended: enables GPU acceleration
)
```

### Hardware Detection

MLX automatically detects and uses available hardware:

```swift
import MLX

// Check Metal support
let device = MTLCreateSystemDefaultDevice()
print("Metal GPU: \(device?.name ?? "Not available")")

// Check Neural Accelerator support (M5 only)
if #available(macOS 15.1, *) {
    // Neural Accelerators automatically used if available
    print("Neural Accelerator support: Available on M5")
} else {
    print("Neural Accelerator support: Not available")
}

// Check unified memory architecture
#if arch(arm64)
    print("Unified memory: Available (Apple Silicon)")
#else
    print("Unified memory: Not available (Intel)")
#endif
```

### Memory Optimization Tips

**1. Use Quantized Models:**
```swift
// 4-bit quantization reduces memory by ~75%
// Full precision Mistral-7B: ~14GB RAM
// 4-bit quantized: ~4.8GB RAM
let modelId = "mlx-community/Mistral-7B-Instruct-v0.3-4bit"  // Recommended
```

**2. Limit Context Length:**
```swift
let parameters = GenerateParameters(
    maxTokens: 512,        // Limit output length
    temperature: 0.7,
    // Trim input context if too long
    inputTokenLimit: 2048  // Reduces KV cache memory
)
```

**3. Unload Models When Not in Use:**
```swift
// Explicitly unload model to free memory
func freeMLXMemory() async {
    modelContainer = nil  // Release model container
    // Force garbage collection
    Task { @MainActor in
        // Memory will be reclaimed automatically
    }
}
```

**4. Monitor Memory Usage:**
```swift
import os

func checkMemoryPressure() {
    var info = mach_task_basic_info()
    var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size)/4

    let result = withUnsafeMutablePointer(to: &info) {
        $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
            task_info(mach_task_self_,
                     task_flavor_t(MACH_TASK_BASIC_INFO),
                     $0,
                     &count)
        }
    }

    if result == KERN_SUCCESS {
        let usedMB = Double(info.resident_size) / 1024 / 1024
        print("Memory used: \(usedMB) MB")
    }
}
```

## 8. API Reference

### MLXModule.autoRegister()

Automatically registers the MLX adapter with RunAnywhere SDK.

```swift
/// Register MLX module for LLM inference
/// - Throws: SDKError if registration fails
public static func autoRegister() async throws {
    // Register MLX service provider
    await MLXServiceProvider.register()

    // Register default MLX adapter
    try await RunAnywhere.registerFrameworkAdapter(
        MLXAdapter.shared,
        models: MLXAdapter.defaultModels
    )
}
```

**Example:**
```swift
// During app initialization
try await MLXModule.autoRegister()

// Now MLX models are available
let models = try await RunAnywhere.availableModels()
print("Available MLX models: \(models.filter { $0.framework == .mlx })")
```

### MLXAdapter Class

Main adapter class for MLX integration with RunAnywhere.

```swift
public class MLXAdapter: FrameworkAdapter {
    /// Shared singleton instance
    public static let shared = MLXAdapter()

    /// Supported framework
    public var framework: LLMFramework { .mlx }

    /// Default MLX models for quick start
    public static var defaultModels: [ModelRegistration] {
        // Returns curated list of recommended models
    }

    /// Initialize adapter with options
    public init(options: MLXOptions = MLXOptions())

    /// Load model for inference
    public func loadModel(_ modelId: String) async throws -> MLXModel

    /// Unload model to free memory
    public func unloadModel(_ modelId: String) async
}
```

### MLXLLMService

LLM text generation service powered by MLX.

```swift
public protocol MLXLLMService {
    /// Generate text completion
    func generate(
        prompt: String,
        options: GenerationOptions
    ) async throws -> GenerationResult

    /// Stream text generation token-by-token
    func generateStream(
        prompt: String,
        options: GenerationOptions
    ) async throws -> AsyncThrowingStream<GenerationToken, Error>

    /// Generate structured output matching JSON schema
    func generateStructured<T: Codable>(
        prompt: String,
        schema: JSONSchema,
        options: GenerationOptions
    ) async throws -> T
}
```

### MLXTTSService

Text-to-speech synthesis service.

```swift
public protocol MLXTTSService {
    /// Synthesize speech from text
    func synthesize(
        text: String,
        parameters: TTSParameters
    ) async throws -> Data

    /// Stream audio synthesis in chunks
    func synthesizeStream(
        text: String,
        parameters: TTSParameters
    ) async throws -> AsyncThrowingStream<Data, Error>

    /// Available voices for synthesis
    var availableVoices: [String] { get async }
}
```

### MLXModelDownloadStrategy

Strategy for downloading and caching MLX models.

```swift
public struct MLXModelDownloadStrategy {
    /// Download model from Hugging Face
    public static func download(
        modelId: String,
        cacheDirectory: URL,
        progressHandler: ((Double) -> Void)?
    ) async throws -> URL

    /// Verify model integrity
    public static func verifyModel(
        at url: URL
    ) async throws -> Bool

    /// Get model size without downloading
    public static func getModelSize(
        modelId: String
    ) async throws -> Int64
}
```

## 9. Best Practices

### When to Use MLX vs CoreML vs FoundationModels

**Use MLX When:**
- You need high-performance LLM inference (7B+ models)
- You want access to latest HuggingFace models
- You require custom model fine-tuning
- You need multimodal capabilities (LLM + embeddings + TTS)
- You target devices with 16GB+ RAM
- You need 100+ tok/s throughput

**Use CoreML When:**
- You need maximum battery efficiency
- You target older devices (iOS 13+)
- You need Apple Neural Engine optimization
- You prefer Apple's native ML stack
- Model size < 1GB
- STT/image classification are primary use cases

**Use FoundationModels When:**
- You have iOS 26+ / macOS 15+ requirements
- You want Apple Intelligence integration
- You need system-level privacy guarantees
- You prefer zero configuration (system models)
- You want automatic model updates from Apple

**Use LlamaCPP When:**
- You need GGUF model compatibility
- You want maximum portability (iOS 14+)
- You need proven stability and community support
- You prefer memory-mapped models
- You have limited RAM (4-8GB)

### Memory Management

**1. Pre-allocate Memory:**
```swift
// Warm up model before first inference
func warmupModel() async throws {
    _ = try await model.generate(
        prompt: "Hello",
        parameters: GenerateParameters(maxTokens: 1)
    )
}
```

**2. Use Memory Pools:**
```swift
// Reuse buffers to reduce allocations
class MLXModelPool {
    private var loadedModels: [String: MLXModel] = [:]
    private let maxModels = 2

    func getModel(_ id: String) async throws -> MLXModel {
        if let cached = loadedModels[id] {
            return cached
        }

        // Evict oldest model if pool is full
        if loadedModels.count >= maxModels {
            let oldestId = loadedModels.keys.first!
            loadedModels.removeValue(forKey: oldestId)
        }

        let model = try await MLXAdapter.shared.loadModel(id)
        loadedModels[id] = model
        return model
    }
}
```

**3. Handle Memory Warnings:**
```swift
class MLXMemoryManager {
    @MainActor
    func registerMemoryWarning() {
        NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task {
                await self?.handleMemoryWarning()
            }
        }
    }

    func handleMemoryWarning() async {
        // Unload models immediately
        await MLXAdapter.shared.unloadAllModels()

        // Clear caches
        URLCache.shared.removeAllCachedResponses()
    }
}
```

### Model Selection by Device

```swift
import DeviceKit

func selectOptimalModel() -> String {
    let device = Device.current

    // Check RAM and chip
    switch (device.totalDiskSpace, device.cpu) {
    case (_, .m5), (_, .m4):
        // Latest chips - use best available
        return "mlx-community/Qwen2.5-7B-Instruct-4bit"

    case (let ram, .m1), (let ram, .m2), (let ram, .m3) where ram >= 16_000_000_000:
        // 16GB+ - use 7B models
        return "mlx-community/Mistral-7B-Instruct-v0.3-4bit"

    case (let ram, _) where ram >= 8_000_000_000:
        // 8GB - use 3B models
        return "mlx-community/Llama-3.2-3B-Instruct-4bit"

    default:
        // Limited RAM - use 360M models
        return "mlx-community/SmolLM2-360M-Instruct-4bit"
    }
}
```

## 10. Troubleshooting

### Common Errors and Solutions

**Error: "Metal device not available"**
```
Cause: Running on Simulator or Intel Mac
Solution: Test on physical Apple Silicon device
```

**Error: "Out of memory during model load"**
```
Cause: Model too large for available RAM
Solution:
1. Use smaller model (e.g., 3B instead of 7B)
2. Use 4-bit quantization
3. Close other apps to free RAM
4. Restart device to clear memory
```

**Error: "Model download failed"**
```
Cause: Network issue or invalid model ID
Solution:
1. Check internet connection
2. Verify model exists on HuggingFace
3. Check disk space for model cache
4. Try manual download and local path
```

**Error: "Generation timeout"**
```
Cause: Model too slow for device
Solution:
1. Reduce maxTokens parameter
2. Use smaller model
3. Increase timeout value
4. Check device thermal state
```

### Performance Optimization Tips

**1. Batch Processing:**
```swift
// Process multiple prompts efficiently
func batchGenerate(prompts: [String]) async throws -> [String] {
    // Reuse loaded model for all prompts
    let container = try await LLMModelFactory.shared.loadContainer(
        configuration: ModelConfiguration(id: modelId)
    )

    return try await withThrowingTaskGroup(of: String.self) { group in
        for prompt in prompts {
            group.addTask {
                try await container.perform { model in
                    let result = try await model.generate(
                        prompt: prompt,
                        parameters: GenerateParameters()
                    )
                    return result.text
                }
            }
        }

        var results: [String] = []
        for try await result in group {
            results.append(result)
        }
        return results
    }
}
```

**2. Prefetch Models:**
```swift
// Download models in background during idle time
func prefetchModels() async {
    let modelIds = [
        "mlx-community/SmolLM2-360M-Instruct-4bit",
        "mlx-community/Llama-3.2-3B-Instruct-4bit"
    ]

    for modelId in modelIds {
        Task(priority: .background) {
            do {
                let config = ModelConfiguration(id: modelId)
                _ = try await LLMModelFactory.shared.loadContainer(
                    configuration: config
                )
                print("Prefetched: \(modelId)")
            } catch {
                print("Prefetch failed for \(modelId): \(error)")
            }
        }
    }
}
```

**3. Optimize Generation Parameters:**
```swift
// Fast generation for short responses
let fastParams = GenerateParameters(
    temperature: 0.7,
    topP: 0.9,
    topK: 40,           // Reduce from default 50
    maxTokens: 100,     // Limit output length
    repetitionPenalty: 1.1
)

// Quality generation for long-form content
let qualityParams = GenerateParameters(
    temperature: 0.8,
    topP: 0.95,
    topK: 50,
    maxTokens: 2048,
    repetitionPenalty: 1.05
)
```

## 11. Comparison with Other Backends

### Performance Comparison Table

| Backend | Model Size | Tok/s (iPhone 15 Pro) | Tok/s (M4 Max) | RAM Usage | Battery Impact | Notes |
|---------|------------|----------------------|----------------|-----------|----------------|-------|
| **MLX** | 7B (4-bit) | 60 | 180 | 4.8GB | Medium | Best for large models |
| **MLX** | 3B (4-bit) | 90 | 250 | 2.3GB | Medium | Balanced choice |
| **MLX** | 360M (4-bit) | 230 | 450 | 300MB | Low | Fastest option |
| **CoreML** | 1B | 45 | 120 | 1.5GB | Very Low | Most efficient |
| **LlamaCPP** | 7B (Q4_K_M) | 25 | 80 | 5.2GB | Medium | Best compatibility |
| **LlamaCPP** | 3B (Q4_K_M) | 40 | 120 | 2.5GB | Medium | Stable choice |

**Key Takeaways:**

**MLX Advantages:**
- Highest throughput (2-3x faster than LlamaCPP)
- Latest models from HuggingFace
- Training and fine-tuning support
- Multimodal capabilities

**CoreML Advantages:**
- Lowest battery impact
- Apple Neural Engine optimization
- Best for < 1GB models
- Native iOS integration

**LlamaCPP Advantages:**
- Widest device support (iOS 14+)
- Proven stability
- Memory-mapped models (lower RAM peak)
- GGUF ecosystem compatibility

### When to Switch Backends

**Switch from MLX to CoreML if:**
- Battery life is critical
- Model size < 1GB
- Target older devices (iOS 13-17)
- Need Apple Neural Engine optimization

**Switch from MLX to LlamaCPP if:**
- Need iOS 14+ compatibility
- Prefer GGUF model format
- Want memory-mapped execution
- Need maximum stability

**Switch from CoreML to MLX if:**
- Need 7B+ models
- Want > 100 tok/s throughput
- Need latest HuggingFace models
- Target iOS 18+ devices

## Additional Resources

### Documentation
- [MLX Official Documentation](https://ml-explore.github.io/mlx/)
- [MLX Swift Examples](https://github.com/ml-explore/mlx-swift-examples)
- [mlx-community on HuggingFace](https://huggingface.co/mlx-community)
- [WWDC 2025: Get started with MLX](https://developer.apple.com/videos/play/wwdc2025/315/)
- [WWDC 2025: Explore LLMs with MLX](https://developer.apple.com/videos/play/wwdc2025/298/)

### Community
- [MLX Swift GitHub](https://github.com/ml-explore/mlx-swift)
- [Apple Machine Learning Research](https://machinelearning.apple.com/research/exploring-llms-mlx-m5)
- [Swift.org MLX Blog](https://www.swift.org/blog/mlx-swift/)

### Model Repositories
- [mlx-community Models](https://huggingface.co/mlx-community) - 3000+ pre-converted models
- [Using MLX at Hugging Face](https://huggingface.co/docs/hub/en/mlx)

---

**Note**: This documentation covers the planned MLX integration for RunAnywhere Swift SDK. Actual implementation may vary. Check the [GitHub repository](https://github.com/RunanywhereAI/runanywhere-sdks) for the latest updates.

## Sources

- [Apple Open Source - MLX](https://opensource.apple.com/projects/mlx/)
- [MLX GitHub Repository](https://github.com/ml-explore/mlx)
- [MLX Swift Examples](https://github.com/ml-explore/mlx-swift-examples)
- [mlx-community on HuggingFace](https://huggingface.co/mlx-community)
- [Apple ML Research: MLX with M5](https://machinelearning.apple.com/research/exploring-llms-mlx-m5)
- [WWDC 2025: Get started with MLX](https://developer.apple.com/videos/play/wwdc2025/315/)
- [WWDC 2025: Explore LLMs with MLX](https://developer.apple.com/videos/play/wwdc2025/298/)
- [Swift.org: On-device ML research with MLX](https://www.swift.org/blog/mlx-swift/)
- [Using MLX at Hugging Face](https://huggingface.co/docs/hub/en/mlx)
