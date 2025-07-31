# RunAnywhere Swift SDK

RunAnywhere is a powerful Swift SDK that enables intelligent AI model execution with automatic routing between on-device and cloud models. It optimizes for cost, privacy, and performance while providing a unified interface for various AI model formats.

## Features

- 🚀 **Intelligent Routing**: Automatically decides between on-device and cloud execution based on device capabilities, model requirements, and user preferences
- 🔒 **Privacy-First**: Prioritizes on-device execution for sensitive data with configurable privacy policies
- 💰 **Cost Optimization**: Real-time cost tracking and savings calculations
- 🎯 **Multi-Format Support**: Seamlessly works with GGUF, ONNX, Core ML, MLX, and TensorFlow Lite models
- 📱 **Cross-Platform**: Supports iOS 13.0+, macOS 10.15+, tvOS 13.0+, and watchOS 6.0+
- 🔄 **Automatic Model Management**: Handles model downloading, caching, and memory management
- 📊 **Performance Monitoring**: Built-in metrics for latency, token throughput, and resource usage

## Requirements

- iOS 13.0+ / macOS 10.15+ / tvOS 13.0+ / watchOS 6.0+
- Xcode 15.0+
- Swift 5.9+

## Installation

### Swift Package Manager

Add RunAnywhere to your project using Swift Package Manager:

1. In Xcode, select **File > Add Package Dependencies**
2. Enter the repository URL: `https://github.com/yourusername/runanywhere-swift`
3. Select the version you want to use

Or add it to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/yourusername/runanywhere-swift", from: "1.0.0")
]
```

## Quick Start

### 1. Initialize the SDK

```swift
import RunAnywhere

// Initialize with your API key
try await RunAnywhereSDK.shared.initialize(
    apiKey: "your-api-key",
    configuration: Configuration(
        allowCloudFallback: true,
        privacyMode: .balanced,
        debugMode: true
    )
)
```

### 2. Load a Model

```swift
// Load a model by name (automatic format detection)
let model = try await RunAnywhereSDK.shared.loadModel("llama-3.2-1b")

// Or load with specific options
let model = try await RunAnywhereSDK.shared.loadModel(
    "llama-3.2-1b",
    options: ModelLoadOptions(
        preferredExecution: .onDevice,
        maxMemoryUsage: 2_000_000_000 // 2GB
    )
)
```

### 3. Generate Text

```swift
// Simple generation
let result = try await model.generate(
    prompt: "Explain quantum computing in simple terms",
    options: GenerationOptions(
        maxTokens: 100,
        temperature: 0.7
    )
)

print(result.text)
print("Cost: $\(result.estimatedCost)")
print("Tokens/sec: \(result.tokensPerSecond)")
```

### 4. Chat Conversations

```swift
// Create a conversation context
let context = RunAnywhereSDK.shared.createContext()

// Add messages
context.addMessage(Message(role: .user, content: "What is Swift?"))
context.addMessage(Message(role: .assistant, content: "Swift is a modern programming language..."))
context.addMessage(Message(role: .user, content: "What are its main features?"))

// Generate with context
let result = try await model.generate(
    context: context,
    options: GenerationOptions(maxTokens: 200)
)
```

## Basic Usage Examples

### Privacy-Focused Generation

```swift
// Configure for maximum privacy
let configuration = Configuration(
    allowCloudFallback: false,  // Never use cloud
    privacyMode: .strict,        // Strictest privacy settings
    localModelPath: "/path/to/models"
)

try await RunAnywhereSDK.shared.initialize(apiKey: apiKey, configuration: configuration)
```

### Cost-Optimized Generation

```swift
// Set cost thresholds
let options = GenerationOptions(
    maxTokens: 100,
    costThreshold: 0.001,  // Switch to cheaper option if cost exceeds $0.001
    preferredExecution: .auto
)

let result = try await model.generate(prompt: prompt, options: options)
print("Actual cost: $\(result.estimatedCost)")
print("Savings: $\(result.estimatedSavings)")
```

### Streaming Responses

```swift
// Stream tokens as they're generated
let stream = try await model.generateStream(
    prompt: "Write a story about a robot",
    options: GenerationOptions(maxTokens: 500)
)

for try await token in stream {
    print(token, terminator: "")
}
```

## Model Support

RunAnywhere supports various model formats out of the box:

- **GGUF**: Llama, Mistral, and other popular models
- **Core ML**: Apple's optimized format for iOS/macOS
- **MLX**: Apple's new ML framework models
- **ONNX**: Cross-platform neural network models
- **TensorFlow Lite**: Lightweight TensorFlow models

## Error Handling

```swift
do {
    let result = try await model.generate(prompt: "Hello")
} catch RunAnywhereError.modelNotFound {
    print("Model not available")
} catch RunAnywhereError.insufficientMemory {
    print("Not enough memory for on-device execution")
} catch RunAnywhereError.networkError(let error) {
    print("Network error: \(error)")
} catch {
    print("Unexpected error: \(error)")
}
```

## Advanced Configuration

### Custom Hardware Detection

```swift
// Implement custom hardware capability detection
class MyHardwareDetector: HardwareDetector {
    func detectCapabilities() -> HardwareCapabilities {
        // Custom detection logic
    }
}

RunAnywhereSDK.shared.setHardwareDetector(MyHardwareDetector())
```

### Authentication Provider

```swift
// Implement custom authentication
class MyAuthProvider: AuthProvider {
    func getAuthToken() async throws -> String {
        // Custom auth logic
        return "bearer-token"
    }
}

RunAnywhereSDK.shared.setAuthProvider(MyAuthProvider())
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

## Documentation

- [Architecture Overview](docs/ARCHITECTURE.md) - Detailed SDK architecture and design
- [API Reference](docs/API_REFERENCE.md) - Complete API documentation
- [Migration Guide](docs/MIGRATION.md) - Upgrading from previous versions
- [Examples](examples/) - Sample applications and code snippets

## Contributing

We welcome contributions! Please see our [Contributing Guidelines](CONTRIBUTING.md) for details.

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Support

- 📧 Email: support@runanywhere.ai
- 💬 Discord: [Join our community](https://discord.gg/runanywhere)
- 📚 Documentation: [docs.runanywhere.ai](https://docs.runanywhere.ai)
- 🐛 Issues: [GitHub Issues](https://github.com/yourusername/runanywhere-swift/issues)

## Acknowledgments

Built with ❤️ by the RunAnywhere team. Special thanks to all our contributors and the open-source community.