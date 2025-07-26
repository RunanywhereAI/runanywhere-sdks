# RunAnywhere iOS SDK

On-device AI with intelligent routing and cost optimization for iOS applications.

## Features

- **3-line integration** - Get started in minutes
- **Universal model loader** - Automatic detection of GGUF, ONNX, Core ML, MLX, and TFLite formats
- **Intelligent routing** - <1ms decisions for 90% cost savings
- **Real-time cost tracking** - Live dashboard integration
- **Privacy-first** - Sensitive data never leaves the device
- **Offline ready** - Works without internet for 7+ days

## Requirements

- iOS 13.0+ / macOS 10.15+ / tvOS 13.0+ / watchOS 6.0+
- Xcode 15.0+
- Swift 5.9+

## Installation

### Swift Package Manager

Add the following to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/runanywhere/ios-sdk", from: "1.0.0")
]
```

Or in Xcode:
1. File > Add Package Dependencies
2. Enter: `https://github.com/runanywhere/ios-sdk`
3. Click Add Package

### CocoaPods

Add to your `Podfile`:

```ruby
pod 'RunAnywhereSDK', '~> 1.0'
```

## Quick Start

```swift
import RunAnywhereSDK

// 1. Initialize
let config = Configuration(apiKey: "your-api-key")
try await RunAnywhereSDK.shared.initialize(with: config)

// 2. Load model
try await RunAnywhereSDK.shared.loadModel("llama-3.2-1b")

// 3. Generate
let result = try await RunAnywhereSDK.shared.generate("Hello, world!")
print(result.text)
print("Saved: $\(result.savedAmount)")
```

## Configuration

### Basic Configuration

```swift
let config = Configuration(
    apiKey: "your-api-key",
    enableRealTimeDashboard: true,
    telemetryConsent: .granted
)
```

### Advanced Options

```swift
var config = Configuration(apiKey: "your-api-key")
config.routingPolicy = .preferDevice  // Always use on-device when possible
config.privacyMode = .strict          // Enhanced PII detection
config.debugMode = true               // Enable debug logging
```

## Generation Options

```swift
let options = GenerationOptions(
    maxTokens: 200,
    temperature: 0.8,
    topP: 0.95,
    stopSequences: ["\n\n"],
    seed: 42  // For reproducible outputs
)

let result = try await sdk.generate(prompt, options: options)
```

## Context Management

Maintain conversation history:

```swift
let context = Context(messages: [
    Message(role: .user, content: "What is Swift?"),
    Message(role: .assistant, content: "Swift is a programming language...")
])

let options = GenerationOptions(context: context)
let result = try await sdk.generate("Tell me more", options: options)
```

## Real-time Cost Tracking

Track savings in real-time:

```swift
let result = try await sdk.generate(prompt)

// Access cost information
print("Model used: \(result.modelUsed)")
print("Execution: \(result.executionTarget)")
print("Tokens: \(result.tokensUsed)")
print("Latency: \(result.latencyMs)ms")
print("Saved: $\(result.savedAmount)")
```

## Testing

Run tests:

```bash
swift test
```

Run with coverage:

```bash
swift test --enable-code-coverage
```

## License

MIT License - see LICENSE file for details.