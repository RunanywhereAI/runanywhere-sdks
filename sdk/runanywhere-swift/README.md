# RunAnywhere Swift SDK

**Privacy-first, on-device AI SDK for iOS** that brings powerful language models directly to your applications. RunAnywhere enables high-performance text generation, voice AI capabilities, and structured outputs - all while keeping user data private and secure on-device.

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
- 🎙️ **Voice AI Workflow** - Real-time voice conversations with WhisperKit transcription (Experimental)
- 📋 **Structured Outputs** - Type-safe JSON generation with schema validation (Experimental)
- 🧠 **Thinking Models** - Support for models with thinking tags (`<think>...</think>`)
- 🏗️ **Model Management** - Automatic downloading, caching, and lifecycle management
- 📊 **Performance Analytics** - Real-time metrics for latency, throughput, and resource usage

### Technical Highlights
- 🔒 **Privacy-First** - All processing happens on-device by default
- 🚀 **Multi-Framework** - GGUF models via llama.cpp, Apple Foundation Models (iOS 18+)
- ⚡ **Native Performance** - Optimized for Apple Silicon with Metal acceleration
- 🧠 **Smart Memory** - Automatic memory optimization and cleanup
- 📱 **Cross-Platform** - iOS 13.0+, macOS 10.15+, tvOS 13.0+, watchOS 6.0+

## Requirements

- iOS 13.0+ / macOS 10.15+ / tvOS 13.0+ / watchOS 6.0+
- Xcode 15.0+
- Swift 5.9+

## Installation

### Swift Package Manager (GitHub-based Distribution)

Add RunAnywhere to your project directly from GitHub - no package registry needed:

#### Via Xcode (Recommended)
1. In Xcode, select **File > Add Package Dependencies**
2. Enter the repository URL: `https://github.com/runanywhere/ios-sdk`
3. Select version rule: **Up to Next Major** from `1.0.0`
4. Click **Add Package**

#### Via Package.swift
```swift
dependencies: [
    // Latest stable version (recommended)
    .package(url: "https://github.com/runanywhere/ios-sdk", from: "1.0.0")

    // Or pin to specific version
    .package(url: "https://github.com/runanywhere/ios-sdk", exact: "1.0.0")

    // For beta/pre-release versions
    .package(url: "https://github.com/runanywhere/ios-sdk", .branch("main"))
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

// Initialize with your API key
try await RunAnywhereSDK.shared.initialize(
    apiKey: "your-api-key",
    configuration: SDKConfiguration(
        privacyMode: .strict,      // On-device only
        debugMode: true,
        telemetryLevel: .minimal   // Privacy-conscious telemetry
    )
)
```

### 2. Load a Model

```swift
// Load a model from the registry
try await RunAnywhereSDK.shared.loadModel(
    "llama-3.2-1b-instruct",
    framework: .llmSwift  // Uses llama.cpp under the hood
)

// Or use Apple's Foundation Models (iOS 18+)
try await RunAnywhereSDK.shared.loadModel(
    "system",
    framework: .foundationModels
)
```

### 3. Generate Text

```swift
// Simple generation
let result = try await RunAnywhereSDK.shared.generateText(
    "Explain quantum computing in simple terms",
    options: GenerationOptions(
        maxTokens: 100,
        temperature: 0.7,
        stream: false
    )
)

print(result.text)
print("Tokens/sec: \(result.performance.tokensPerSecond)")
print("Latency: \(result.performance.firstTokenLatency)ms")
```

### 4. Streaming Generation

```swift
// Stream tokens as they're generated
for try await chunk in RunAnywhereSDK.shared.generateTextStream(
    "Write a short story about AI",
    options: GenerationOptions(maxTokens: 500)
) {
    print(chunk.text, terminator: "")
    // Update UI with partial results
}
```

## Advanced Features

### Voice AI Conversations (Experimental)

```swift
// Start a voice session with real-time transcription
let voiceSession = try await RunAnywhereSDK.shared.startVoiceSession(
    delegate: self
)

// Start listening
try await voiceSession.startListening()

// Handle voice session events
func voiceSession(_ session: VoiceSession, didTranscribe text: String) {
    print("User said: \(text)")
}

func voiceSession(_ session: VoiceSession, didGenerate response: String) {
    print("AI response: \(response)")
}
```

### Structured Output Generation (Experimental)

```swift
// Define your output structure
struct QuizQuestion: Generatable {
    let question: String
    let options: [String]
    let correctAnswer: Int
    let explanation: String
}

// Generate structured data
let quiz: QuizQuestion = try await RunAnywhereSDK.shared.generateStructuredOutput(
    prompt: "Create a quiz question about Swift programming",
    type: QuizQuestion.self,
    options: StructuredOutputOptions(
        validationMode: .strict,
        maxRetries: 3
    )
)

print("Question: \(quiz.question)")
print("Options: \(quiz.options)")
```

### Thinking Models Support

```swift
// Use models with thinking capabilities
let result = try await RunAnywhereSDK.shared.generateText(
    "Solve this step by step: What is 15% of 240?",
    options: GenerationOptions(
        parseThinking: true  // Separates thinking from final answer
    )
)

if let thinking = result.thinking {
    print("Model's thought process: \(thinking)")
}
print("Final answer: \(result.text)")
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
