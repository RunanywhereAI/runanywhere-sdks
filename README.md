# RunAnywhere SDKs

<p align="center">
  <img src="examples/logo.svg" alt="RunAnywhere Logo" width="200"/>
</p>

[![License](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](https://opensource.org/licenses/Apache-2.0)
[![iOS SDK](https://img.shields.io/badge/iOS%20SDK-Available-brightgreen.svg)](sdk/runanywhere-swift/)
[![Android SDK](https://img.shields.io/badge/Android%20SDK-Coming%20Soon-yellow.svg)](sdk/runanywhere-android/)
[![GitHub stars](https://img.shields.io/github/stars/RunanywhereAI/runanywhere-sdks?style=social)](https://github.com/RunanywhereAI/runanywhere-sdks)

**Privacy-first, on-device AI SDKs** that bring powerful language models directly to your iOS and Android applications. RunAnywhere enables intelligent AI execution with automatic optimization for performance, privacy, and user experience.

## 🚀 Current Status

### ✅ iOS SDK - **Available**
The iOS SDK provides high-performance on-device text generation, complete voice AI pipeline with VAD/STT/LLM/TTS, structured outputs with type-safe JSON generation, and thinking model support for privacy-first AI applications. [View iOS SDK →](sdk/runanywhere-swift/)

### 🏗️ Android SDK - **Coming Soon**
The Android SDK is under active development. We're bringing the same powerful on-device AI capabilities to Android.

## 🎯 See It In Action

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

<p align="center">
  <img src="docs/screenshots/main-screenshot.jpg" alt="Chat with RunAnywhere" width="200"/>
  <img src="examples/ios/RunAnywhereAI/docs/screenshots/chat-interface.png" alt="Chat Analytics" width="200"/>
  <img src="examples/ios/RunAnywhereAI/docs/screenshots/quiz-flow.png" alt="Structured Output" width="200"/>
  <img src="examples/ios/RunAnywhereAI/docs/screenshots/voice-ai.png" alt="Voice AI" width="200"/>
</p>

## 📦 What's Included

### iOS Components (Available Now)
- **[iOS SDK](sdk/runanywhere-swift/)** - Swift Package with comprehensive on-device AI capabilities
- **[iOS Demo App](examples/ios/RunAnywhereAI/)** - Full-featured sample app showcasing all SDK features

### Android Components (Coming Soon)
- **[Android SDK](sdk/runanywhere-android/)** - Kotlin-based SDK (in development)
- **[Android Demo App](examples/android/RunAnywhereAI/)** - Sample app (in development)

## ✨ iOS SDK Features

### Core Capabilities
- **💬 Text Generation** - High-performance on-device text generation with streaming support
- **🎙️ Voice AI Pipeline** - Complete voice workflow with VAD, STT, LLM, and TTS components
- **📋 Structured Outputs** - Type-safe JSON generation with schema validation using `Generatable` protocol
- **🧠 Thinking Models** - Support for models with thinking tags (`<think>...</think>`)
- **🏗️ Model Management** - Automatic model discovery, downloading, and lifecycle management
- **📊 Performance Analytics** - Real-time metrics with comprehensive event system
- **🎯 Intelligent Routing** - Automatic on-device vs cloud decision making

### Technical Highlights
- **🔒 Privacy-First** - All processing happens on-device by default with intelligent cloud routing
- **🚀 Multi-Framework** - GGUF (llama.cpp), Apple Foundation Models, WhisperKit, Core ML, MLX, TensorFlow Lite
- **⚡ Native Performance** - Optimized for Apple Silicon with Metal and Neural Engine acceleration
- **🧠 Smart Memory** - Automatic memory optimization, cleanup, and pressure handling
- **📱 Cross-Platform** - iOS 14.0+, macOS 12.0+, tvOS 14.0+, watchOS 7.0+
- **🎛️ Component Architecture** - Modular components for flexible AI pipeline construction

## 🗺️ Roadmap

### Next Release
- [ ] **Android SDK** - Full parity with iOS features
- [ ] **Hybrid Routing** - Intelligent on-device + cloud execution
- [ ] **Advanced Analytics** - Usage insights and performance dashboards

### Upcoming Features
- [ ] **Remote Configuration** - Dynamic model and routing updates
- [ ] **Enterprise Features** - Team management and usage controls
- [ ] **Extended Model Support** - ONNX, TensorFlow Lite, Core ML optimizations

### Future Vision
- [ ] **Multi-Modal Support** - Image and audio understanding

## 🚀 Quick Start

### iOS SDK (Available Now)

```swift
import RunAnywhere
import LLMSwift
import WhisperKitTranscription

// 1. Initialize the SDK
try await RunAnywhere.initialize(
    apiKey: "dev",           // Any string works in dev mode
    baseURL: "localhost",    // Not used in dev mode
    environment: .development
)

// 2. Register framework adapters
await LLMSwiftServiceProvider.register()
try await RunAnywhere.registerFrameworkAdapter(
    LLMSwiftAdapter(),
    models: [
        try! ModelRegistration(
            url: "https://huggingface.co/prithivMLmods/SmolLM2-360M-GGUF/resolve/main/SmolLM2-360M.Q8_0.gguf",
            framework: .llamaCpp,
            id: "smollm2-360m",
            name: "SmolLM2 360M",
            memoryRequirement: 500_000_000
        )
    ]
)

// 3. Download and load model
try await RunAnywhere.downloadModel("smollm2-360m")
try await RunAnywhere.loadModel("smollm2-360m")

// 4. Generate text
let result = try await RunAnywhere.generate(
    "Explain quantum computing in simple terms",
    options: RunAnywhereGenerationOptions(
        maxTokens: 100,
        temperature: 0.7
    )
)

print("Generated: \(result.text)")
```

[View full iOS documentation →](sdk/runanywhere-swift/)

### Android SDK (Coming Soon)

```kotlin
// Android SDK is under active development
// Check back soon for updates
```

## 📋 System Requirements

### iOS SDK
- **Platforms**: iOS 14.0+ / macOS 12.0+ / tvOS 14.0+ / watchOS 7.0+
- **Development**: Xcode 15.0+, Swift 5.9+
- **Recommended**: iOS 17.0+ for full feature support

### Android SDK (Coming Soon)
- **Minimum SDK**: 24 (Android 7.0)
- **Target SDK**: 36
- **Kotlin**: 2.0.21+
- **Gradle**: 8.11.1+

## 🛠️ Installation

### iOS SDK

#### Swift Package Manager (Recommended)

Add RunAnywhere to your project:

#### Via Xcode (Recommended)
1. In Xcode, select **File > Add Package Dependencies**
2. Enter the repository URL: `https://github.com/RunanywhereAI/runanywhere-sdks`
3. **Select version rule:**
   - **Latest Release (Recommended)**: Choose **Up to Next Major** from `0.13.0`
   - **Specific Version**: Choose **Exact** and enter `0.13.0`
   - **Development Branch**: Choose **Branch** and enter `main`
4. Select the `runanywhere-swift` product
5. Click **Add Package**

#### Via Package.swift

**Latest Release (Recommended):**
```swift
dependencies: [
    .package(url: "https://github.com/RunanywhereAI/runanywhere-sdks", from: "0.13.0")
]
```

**Specific Version:**
```swift
dependencies: [
    .package(url: "https://github.com/RunanywhereAI/runanywhere-sdks", exact: "0.13.0")
]
```

**Development Branch:**
```swift
dependencies: [
    .package(url: "https://github.com/RunanywhereAI/runanywhere-sdks", .branch("main"))
]
```


#### CocoaPods

**Latest Release (Recommended):**
```ruby
pod 'RunAnywhere', '~> 0.13'
```

**Specific Version:**
```ruby
pod 'RunAnywhere', '0.13.0'
```

### Android SDK (Coming Soon)

```gradle
// Coming soon - Latest release will be available here
dependencies {
    implementation 'ai.runanywhere:sdk:0.13.0'
}
```

## 💡 Example Use Cases

### Privacy-First Chat Application
```swift
// All processing stays on-device
let result = try await RunAnywhere.generate(
    userMessage,
    options: RunAnywhereGenerationOptions(maxTokens: 150)
)
```

### Voice Assistant
```swift
// Voice pipeline with VAD, STT, LLM, TTS
let config = ModularPipelineConfig(
    components: [.vad, .stt, .llm, .tts],
    stt: VoiceSTTConfig(modelId: "whisper-base"),
    llm: VoiceLLMConfig(modelId: "default", maxTokens: 100)
)

let pipeline = try await RunAnywhere.createVoicePipeline(config: config)
for try await event in pipeline.process(audioStream: audioStream) {
    // Handle voice events
}
```

### Structured Data Generation
```swift
// Type-safe JSON generation with Generatable protocol
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

let quiz = try await RunAnywhere.generateStructured(
    Quiz.self,
    prompt: "Create a quiz about Swift programming",
    options: options
)
```

## 📖 Documentation

### iOS SDK
- **[iOS SDK Documentation](sdk/runanywhere-swift/)** - Complete API reference and guides
- **[iOS Sample App](examples/ios/RunAnywhereAI/)** - Full-featured demo application
- **[Architecture Overview](sdk/runanywhere-swift/docs/ARCHITECTURE_V2.md)** - Technical deep dive

### Android SDK
- **[Android SDK](sdk/runanywhere-android/)** - Coming soon
- **[Android Sample App](examples/android/RunAnywhereAI/)** - Coming soon

## 🤝 Contributing

We welcome contributions from the community! Here's how you can help:

### Ways to Contribute
- 🐛 **Report bugs** - Help us identify and fix issues
- 💡 **Suggest features** - Share your ideas for improvements
- 📝 **Improve documentation** - Help make our docs clearer
- 🔧 **Submit pull requests** - Contribute code directly

### Getting Started
1. Fork the repository
2. Create your feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

See our [Contributing Guidelines](CONTRIBUTING.md) for detailed instructions.

## 📄 License

This project is licensed under the Apache License 2.0 - see the [LICENSE](LICENSE) file for details.

## 💬 Community & Support

- **Discord**: [Join our community](https://discord.gg/pxRkYmWh)
- **GitHub Issues**: [Report bugs or request features](https://github.com/RunanywhereAI/runanywhere-sdks/issues)
- **Email**: founders@runanywhere.ai
- **Twitter**: [@RunanywhereAI](https://twitter.com/RunanywhereAI)

## 🙏 Acknowledgments

Built with ❤️ by the RunAnywhere team. Special thanks to:
- The open-source community for inspiring this project
- Our early adopters and beta testers
- Contributors who help make this SDK better

---

**Ready to build privacy-first AI apps?** [Get started with our iOS SDK →](sdk/runanywhere-swift/)
