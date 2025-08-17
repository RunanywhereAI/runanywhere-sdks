# RunAnywhere SDKs

<p align="center">
  <img src="examples/logo.svg" alt="RunAnywhere Logo" width="200"/>
</p>

[![License](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](https://opensource.org/licenses/Apache-2.0)
[![iOS SDK](https://img.shields.io/badge/iOS%20SDK-Available-brightgreen.svg)](sdk/runanywhere-swift/)
[![Android SDK](https://img.shields.io/badge/Android%20SDK-Coming%20Soon-yellow.svg)](sdk/runanywhere-android/)

**Privacy-first, on-device AI SDKs** that bring powerful language models directly to your iOS and Android applications. RunAnywhere enables intelligent AI execution with automatic optimization for performance, privacy, and user experience.

## 🚀 Current Status

### ✅ iOS SDK - **Available**
The iOS SDK provides on-device text generation, voice AI capabilities, and structured outputs for privacy-first AI applications. [View iOS SDK →](sdk/runanywhere-swift/)

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
  <img src="docs/screenshots/main-screenshot.jpg" alt="RunAnywhere SDK in Action" width="600"/>
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
- **🎙️ Voice AI Workflow** - Real-time voice conversations with transcription and synthesis (Experimental)
- **📋 Structured Outputs** - Type-safe JSON generation with schema validation (Experimental)
- **🏗️ Model Management** - Automatic model downloading, caching, and lifecycle management
- **📊 Performance Analytics** - Real-time metrics for latency, throughput, and resource usage

### Technical Highlights
- **🔒 Privacy-First Architecture** - All processing happens on-device by default
- **🚀 Multi-Framework Support** - GGUF models via llama.cpp, Apple Foundation Models (iOS 18+)
- **⚡ Native Performance** - Optimized for Apple Silicon with Metal acceleration
- **🧠 Smart Memory Management** - Automatic memory optimization and cleanup
- **📱 Cross-Platform** - iOS 13.0+, macOS 10.15+, tvOS 13.0+, watchOS 6.0+

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

// Initialize the SDK
let sdk = RunAnywhereSDK.shared
try await sdk.initialize(
    apiKey: "your-api-key",
    configuration: SDKConfiguration(
        privacyMode: .strict,  // On-device only
        debugMode: true
    )
)

// Generate text
let result = try await sdk.generateText(
    "Explain quantum computing in simple terms",
    options: GenerationOptions(
        maxTokens: 100,
        temperature: 0.7,
        stream: true
    )
)

print("Generated: \(result.text)")
print("Tokens/sec: \(result.performance.tokensPerSecond)")
```

[View full iOS documentation →](sdk/runanywhere-swift/)

### Android SDK (Coming Soon)

```kotlin
// Android SDK is under active development
// Check back soon for updates
```

## 📋 System Requirements

### iOS SDK
- **Platforms**: iOS 13.0+ / macOS 10.15+ / tvOS 13.0+ / watchOS 6.0+
- **Development**: Xcode 15.0+, Swift 5.9+
- **Recommended**: iOS 17.0+ for full feature support
- **Foundation Models**: iOS 26.0+ with Apple Intelligence

### Android SDK (Coming Soon)
- **Minimum SDK**: 24 (Android 7.0)
- **Target SDK**: 36
- **Kotlin**: 2.0.21+
- **Gradle**: 8.11.1+

## 🛠️ Installation

### iOS SDK

#### Swift Package Manager (Recommended)

Add RunAnywhere to your project:

1. In Xcode, select **File > Add Package Dependencies**
2. Enter the repository URL: `https://github.com/RunanywhereAI/runanywhere-sdks`
3. Select the latest version

Or add to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/RunanywhereAI/runanywhere-sdks", from: "0.13.0")
]
```

#### CocoaPods

```ruby
pod 'RunAnywhere', '~> 0.13'
```

### Android SDK (Coming Soon)

```gradle
// Coming soon
dependencies {
    implementation 'ai.runanywhere:sdk:0.13.0'
}
```

## 💡 Example Use Cases

### Privacy-First Chat Application
```swift
// All processing stays on-device
let sdk = RunAnywhereSDK.shared
let result = try await sdk.generateText(
    userMessage,
    options: GenerationOptions(privacyMode: .strict)
)
```

### Voice Assistant
```swift
// Real-time voice conversations (Experimental)
let voiceSession = try await sdk.startVoiceSession()
voiceSession.delegate = self
try await voiceSession.startListening()
```

### Structured Data Generation
```swift
// Type-safe JSON generation (Experimental)
struct QuizQuestion: Generatable {
    let question: String
    let options: [String]
    let correctAnswer: Int
}

let quiz: QuizQuestion = try await sdk.generateStructuredOutput(
    prompt: "Create a quiz question about space",
    type: QuizQuestion.self
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

- **Discord**: [Join our community](https://discord.gg/runanywhere)
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
