# RunAnywhere Swift SDK

**Privacy-first, on-device AI SDK for iOS** that brings powerful language models directly to your applications. RunAnywhere enables high-performance text generation, voice AI workflows, and structured outputs - all while keeping user data private and secure on-device with intelligent cloud routing.

<p align="center">
  <a href="https://www.youtube.com/watch?v=GG100ijJHl4">
    <img src="https://img.shields.io/badge/▶️_Watch_Demo-red?style=for-the-badge&logo=youtube&logoColor=white" alt="Watch Demo" />
  </a>
  <a href="https://testflight.apple.com/join/xc4HVVJE">
    <img src="https://img.shields.io/badge/📱_Try_iOS_App-blue?style=for-the-badge&logo=apple&logoColor=white" alt="Try on TestFlight" />
  </a>
  <a href="https://runanywhere.ai">
    <img src="https://img.shields.io/badge/🌐_Visit_Website-green?style=for-the-badge" alt="Visit Website" />
  </a>
</p>

## ✨ Features

### Core Capabilities
- 💬 **Text Generation** - High-performance on-device text generation with streaming support
- 🎙️ **Voice AI Pipeline** - Complete voice workflow with VAD, STT, LLM, and TTS components
- 📋 **Structured Outputs** - Type-safe JSON generation with schema validation using `Generatable` protocol
- 🧠 **Thinking Models** - Support for models with thinking tags (`<think>...</think>`)
- 🏗️ **Model Management** - Automatic model discovery, downloading, and lifecycle management
- 📊 **Performance Analytics** - Real-time metrics with comprehensive event system
- 🎯 **Intelligent Routing** - Automatic on-device vs cloud decision making

### Technical Highlights
- 🔒 **Privacy-First** - All processing happens on-device by default with intelligent cloud routing
- 🚀 **Multi-Framework** - GGUF (llama.cpp), Apple Foundation Models, WhisperKit, Core ML, MLX, TensorFlow Lite
- ⚡ **Native Performance** - Optimized for Apple Silicon with Metal and Neural Engine acceleration
- 🧠 **Smart Memory** - Automatic memory optimization, cleanup, and pressure handling
- 📱 **Cross-Platform** - iOS 14.0+, macOS 12.0+, tvOS 14.0+, watchOS 7.0+
- 🎛️ **Component Architecture** - Modular components for flexible AI pipeline construction

## Requirements

- iOS 14.0+ / macOS 12.0+ / tvOS 14.0+ / watchOS 7.0+
- Xcode 15.0+
- Swift 5.9+

## Installation

### Swift Package Manager (GitHub-based Distribution)

Add RunAnywhere to your project directly from GitHub - no package registry needed.

> **🏆 Recommended**: Check [releases](https://github.com/RunanywhereAI/runanywhere-sdks/releases) for the most current version.

#### Via Xcode (Recommended)
1. In Xcode, select **File > Add Package Dependencies**
2. Enter the repository URL: `https://github.com/RunanywhereAI/runanywhere-sdks`
3. **Select version rule:**
   - **Latest Release (Recommended)**: Choose **Up to Next Major** from `0.15.0`
   - **Specific Version**: Choose **Exact** and enter `0.15.0`
   - **Development Branch**: Choose **Branch** and enter `main`
4. Select products based on your needs:
   - `RunAnywhere` - Core SDK (required)
   - `LLMSwift` - GGUF/GGML models (optional, iOS 16+)
   - `WhisperKitTranscription` - Speech-to-text (optional, iOS 16+)
   - `FluidAudioDiarization` - Speaker diarization (optional, iOS 17+)
5. Click **Add Package**

#### Via Package.swift

```swift
dependencies: [
    .package(url: "https://github.com/RunanywhereAI/runanywhere-sdks", from: "0.15.0")
],
targets: [
    .target(
        name: "YourApp",
        dependencies: [
            .product(name: "RunAnywhere", package: "runanywhere-sdks"),
            .product(name: "LLMSwift", package: "runanywhere-sdks"),
            .product(name: "WhisperKitTranscription", package: "runanywhere-sdks")
        ]
    )
]
```


#### For Private Repository Access
If the repository is private, configure your GitHub access token:
```bash
# Add to ~/.netrc (or use Xcode's Accounts preferences)
machine github.com
login YOUR_GITHUB_USERNAME
password YOUR_GITHUB_TOKEN
```

## Quick Start

### 1. Initialize the SDK

```swift
import RunAnywhere

// Development mode (recommended for getting started)
try await RunAnywhere.initialize(
    apiKey: "dev",           // Any string works in dev mode
    baseURL: "localhost",    // Not used in dev mode
    environment: .development
)
```

> **For Production**: Contact RunAnywhere team for production API keys and base URLs to enable analytics, observability, OTA model updates, and other additional features available for Production.

### 2. Import Required Modules

Currently, you need to import the adapter modules separately (we'll consolidate this in a future update):

```swift
import RunAnywhere
import LLMSwift
import WhisperKitTranscription
import FluidAudioDiarization
```

> **Note**: We're working on consolidating these into a single `import RunAnywhere` for better developer experience.

### 3. Register Framework Adapters

Before using any AI features, register the required adapters:

```swift
// Register LLM adapter for text generation
await LLMSwiftServiceProvider.register()
try await RunAnywhere.registerFrameworkAdapter(
    LLMSwiftAdapter(),
    models: [
        // Register models you want to use
        try! ModelRegistration(
            url: "https://huggingface.co/prithivMLmods/SmolLM2-360M-GGUF/resolve/main/SmolLM2-360M.Q8_0.gguf",
            framework: .llamaCpp,
            id: "smollm2-360m",           // This becomes your model ID
            name: "SmolLM2 360M",
            memoryRequirement: 500_000_000
        )
    ]
)

// Register WhisperKit for voice features
await WhisperKitServiceProvider.register()
try await RunAnywhere.registerFrameworkAdapter(
    WhisperKitAdapter.shared,
    models: [
        try! ModelRegistration(
            url: "https://huggingface.co/argmaxinc/whisperkit-coreml/tree/main/openai_whisper-base",
            framework: .whisperKit,
            id: "whisper-base",           // This becomes your model ID
            name: "Whisper Base",
            format: .mlmodel,
            memoryRequirement: 74_000_000
        )
    ]
)

// Register FluidAudio for speaker diarization (optional)
await FluidAudioDiarizationProvider.register()
```

### 4. Download and Load Models

After registration, download and load the models:

```swift
// See what models are available (from your registrations)
let models = try await RunAnywhere.availableModels()
print("Available models: \(models.map { $0.name })")

// Download a model (uses the URL from registration)
try await RunAnywhere.downloadModel("smollm2-360m")

// Load the model for use
try await RunAnywhere.loadModel("smollm2-360m")
```

### 5. Generate Text

Now you can use the loaded model:

```swift
// Simple chat
let response = try await RunAnywhere.chat("Hello, how are you?")
print(response)

// Generation with options
let options = RunAnywhereGenerationOptions(
    maxTokens: 150,
    temperature: 0.7
)

let result = try await RunAnywhere.generate(
    "Explain quantum computing in simple terms",
    options: options
)

print("Response: \(result.text)")
```

### 6. Streaming Generation

```swift
// Stream tokens in real-time
let stream = RunAnywhere.generateStream(
    "Write a short story about AI",
    options: options
)

for try await token in stream {
    print(token, terminator: "")
}
```

## Advanced Features

### Voice AI Pipeline

Create voice pipelines using your registered models. The `modelId` refers to the IDs you used during registration:

```swift
// Voice pipeline configuration
let config = ModularPipelineConfig(
    components: [.vad, .stt, .llm, .tts],
    vad: VADConfig(energyThreshold: 0.005),
    stt: VoiceSTTConfig(modelId: "whisper-base"),  // Uses registered whisper-base
    llm: VoiceLLMConfig(
        modelId: "default",  // Uses currently loaded LLM model
        systemPrompt: "You are a helpful voice assistant.",
        maxTokens: 100
    ),
    tts: VoiceTTSConfig(voice: "system")
)

let pipeline = try await RunAnywhere.createVoicePipeline(config: config)

// Process audio with real-time events
for try await event in pipeline.process(audioStream: audioStream) {
    switch event {
    case .vadSpeechStart:
        print("Speech detected")
    case .sttPartialTranscript(let text):
        print("Partial: \(text)")
    case .sttFinalTranscript(let text):
        print("Final transcription: \(text)")
    case .llmFinalResponse(let response):
        print("AI response: \(response)")
    case .ttsCompleted:
        print("Speech synthesis complete")
    }
}
```

### Structured Output Generation

Define structures that conform to `Generatable`:

```swift
struct Quiz: Codable, Generatable {
    let title: String
    let questions: [Question]

    static var jsonSchema: String {
        return """
        {
            "type": "object",
            "properties": {
                "title": {"type": "string"},
                "questions": {"type": "array"}
            }
        }
        """
    }
}

struct Question: Codable {
    let text: String
    let options: [String]
    let correctIndex: Int
}

// Generate structured data
let quiz = try await RunAnywhere.generateStructured(
    Quiz.self,
    prompt: "Create a quiz about Swift programming",
    options: options
)

print("Generated quiz: \(quiz.title)")
print("Number of questions: \(quiz.questions.count)")
```

### Adding Custom Models

Add your own models to the registry:

```swift
// Add a custom model from any URL
let customModel = await RunAnywhere.addModelFromURL(
    URL(string: "https://huggingface.co/microsoft/DialoGPT-medium/resolve/main/model.gguf")!,
    name: "My Custom Model",
    type: "gguf"
)

// Then download and use it
try await RunAnywhere.downloadModel(customModel.id)
try await RunAnywhere.loadModel(customModel.id)
```

### Model Management

```swift
// List all available models
let models = try await RunAnywhere.availableModels()
for model in models {
    print("Model: \(model.name), ID: \(model.id), Size: \(model.memoryRequired)MB")
}

// Delete models to free space
try await RunAnywhere.deleteModel("unused-model-id")
```

## Supported Models & Frameworks

### Currently Implemented
- **GGUF Models** (via llama.cpp/LLM.swift)
  - Llama 3.2 (1B, 3B)
  - Mistral 7B
  - Qwen 2.5 (0.5B, 1.5B, 3B)
  - Gemma 2 (2B)
  - Phi 3.5 Mini
  - All quantization levels (Q2_K to Q8_0)

- **Apple Foundation Models** (iOS 26+ Experimental)
  - System language model
  - Requires Apple Intelligence eligibility

- **WhisperKit** (Voice Transcription)
  - whisper-tiny, base, small, medium models
  - Real-time streaming transcription

### Model Registry
The SDK includes a built-in model registry with metadata for popular models. Models are automatically downloaded and cached on first use.

## Performance & Analytics

### Real-time Monitoring

```swift
// Monitor generation performance
let result = try await RunAnywhereSDK.shared.generateText(
    prompt,
    options: GenerationOptions(collectMetrics: true)
)

print("""
Performance Metrics:
- Tokens/second: \(result.performance.tokensPerSecond)
- First token latency: \(result.performance.firstTokenLatency)ms
- Total duration: \(result.performance.totalDuration)ms
- Memory used: \(result.performance.peakMemoryUsage / 1024 / 1024)MB
""")
```

### Analytics Export

```swift
// Export performance data
let analytics = try await RunAnywhereSDK.shared.exportAnalytics(
    format: .json,
    timeRange: .last24Hours
)
```

## Memory Management

```swift
// Configure memory limits
let config = SDKConfiguration(
    memoryConfiguration: MemoryConfiguration(
        maxMemoryUsage: 2_000_000_000,  // 2GB limit
        lowMemoryThreshold: 0.8,        // Warn at 80% usage
        aggressiveCleanup: true         // Aggressive memory cleanup
    )
)

// Monitor memory usage
let memoryInfo = RunAnywhereSDK.shared.currentMemoryUsage()
print("Current usage: \(memoryInfo.usedMemory / 1024 / 1024)MB")
print("Available: \(memoryInfo.availableMemory / 1024 / 1024)MB")

// Manual cleanup
try await RunAnywhereSDK.shared.clearCache()
```

## Development

### Building from Source

```bash
# Clone the repository
git clone https://github.com/yourusername/runanywhere-swift
cd runanywhere-swift

# Build the SDK
swift build

# Run tests
swift test

# Run with specific platform
xcodebuild build -scheme RunAnywhere -destination 'platform=iOS Simulator,name=iPhone 15'
```

### Running Tests

```bash
# Run all tests
swift test

# Run with coverage
swift test --enable-code-coverage

# Run specific test
swift test --filter RunAnywhereTests.GenerationTests
```

## 📚 Documentation

### Architecture & Guides
- [Architecture Overview](docs/ARCHITECTURE_V2.md) - Detailed SDK architecture
- [Public API Reference](docs/PUBLIC_API_REFERENCE.md) - Complete API documentation
- [Structured Output Guide](docs/STRUCTURED_OUTPUT_GUIDE.md) - Type-safe generation
- [Environment Configuration](docs/ENVIRONMENT_CONFIGURATION.md) - Setup guide

### Sample Code
- [iOS Demo App](../../examples/ios/RunAnywhereAI/) - Full-featured example application
- [Code Examples](../../examples/ios/RunAnywhereAI/docs/) - Common use cases

## 🤝 Contributing

We welcome contributions from the community!

### How to Contribute
1. Fork the repository
2. Create your feature branch (`git checkout -b feature/amazing-feature`)
3. Write tests for your changes
4. Ensure all tests pass (`swift test`)
5. Commit your changes (`git commit -m 'Add amazing feature'`)
6. Push to the branch (`git push origin feature/amazing-feature`)
7. Open a Pull Request

See our [Contributing Guidelines](../../CONTRIBUTING.md) for more details.

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 💬 Community & Support

- **Website**: [runanywhere.ai](https://runanywhere.ai)
- **Discord**: [Join our community](https://discord.gg/runanywhere)
- **GitHub Issues**: [Report bugs or request features](https://github.com/RunanywhereAI/runanywhere-sdks/issues)
- **Email**: founders@runanywhere.ai

## 🙏 Acknowledgments

Built with ❤️ by the RunAnywhere team. Special thanks to:
- The LLM.swift and llama.cpp communities
- WhisperKit contributors
- Our beta testers and early adopters
