# RunAnywhere SDKs

<p align="center">
  <img src="examples/logo.svg" alt="RunAnywhere Logo" width="200"/>
</p>

[![License](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](https://opensource.org/licenses/Apache-2.0)
[![Android SDK CI](https://github.com/your-org/runanywhere-sdks/actions/workflows/android-sdk.yml/badge.svg)](https://github.com/your-org/runanywhere-sdks/actions/workflows/android-sdk.yml)
[![iOS SDK CI](https://github.com/your-org/runanywhere-sdks/actions/workflows/ios-sdk.yml/badge.svg)](https://github.com/your-org/runanywhere-sdks/actions/workflows/ios-sdk.yml)

Cross-platform SDKs for the RunAnywhere on-device AI platform. RunAnywhere provides intelligent routing between on-device and cloud AI models to optimize for cost, privacy, and performance.

## 🏗️ Repository Components

This repository contains four main components:

### 📱 SDKs
- **[Android SDK](sdk/runanywhere-android/)** - Kotlin-based SDK for Android applications
- **[iOS SDK](sdk/runanywhere-swift/)** - Swift Package Manager-based SDK for iOS/macOS/tvOS/watchOS

### 🚀 Sample Applications
- **[Android Demo App](examples/android/RunAnywhereAI/)** - Sample Android app demonstrating SDK usage
- **[iOS Demo App](examples/ios/RunAnywhereAI/)** - Sample iOS app demonstrating SDK usage

## ✨ Key Features

- **🤖 Intelligent Routing**: Automatically decides between on-device and cloud AI models
- **💰 Cost Optimization**: Real-time cost and savings tracking
- **🔒 Privacy-First**: Keep sensitive data on-device when possible
- **🔄 Universal Model Support**: GGUF, ONNX, Core ML, MLX, TensorFlow Lite
- **⚡ Modern APIs**: Async/await patterns with Kotlin coroutines and Swift concurrency
- **📊 Performance Metrics**: Detailed execution statistics and model performance data

## 🚀 Quick Start

### Android SDK

```kotlin
// Initialize the SDK
val sdk = RunAnywhereSDK.getInstance()
sdk.initialize(apiKey = "your-api-key")

// Generate text
val options = GenerationOptions(
    maxTokens = 100,
    temperature = 0.7f
)

val result = sdk.generateText("Hello, world!", options)
println("Generated: ${result.text}")
println("Cost: $${result.cost}")
```

### iOS SDK

```swift
// Initialize the SDK
let sdk = RunAnywhereSDK.shared
await sdk.initialize(apiKey: "your-api-key")

// Generate text
let options = GenerationOptions(
    maxTokens: 100,
    temperature: 0.7
)

let result = await sdk.generateText("Hello, world!", options: options)
print("Generated: \(result.text)")
print("Cost: $\(result.cost)")
```

## 📋 Requirements

### Android SDK
- **Minimum SDK**: 24 (Android 7.0)
- **Target SDK**: 36
- **Kotlin**: 2.0.21+
- **Gradle**: 8.11.1+

### iOS SDK
- **iOS**: 13.0+ / **macOS**: 10.15+ / **tvOS**: 13.0+ / **watchOS**: 6.0+
- **Swift**: 5.9+
- **Xcode**: 15.0+

## 🛠️ Development

### Building the Android SDK

```bash
cd sdk/runanywhere-android/
./gradlew build
./gradlew test
./gradlew lint
```

### Building the iOS SDK

```bash
cd sdk/runanywhere-swift/
swift build
swift test
swiftlint
```

### Running Example Apps

#### Android Example
```bash
cd examples/android/RunAnywhereAI/
./gradlew installDebug
```

#### iOS Example
```bash
cd examples/ios/RunAnywhereAI/
open RunAnywhereAI.xcodeproj
```

## 🧪 Testing

Both SDKs include comprehensive test suites:

```bash
# Android
./gradlew test

# iOS
swift test --enable-code-coverage
```

## 🔍 Code Quality & Linting

We enforce strict code quality standards including mandatory GitHub issue references for all TODO comments.

### Running Lint Checks

```bash
# Run all lint checks (iOS + Android)
./scripts/lint-all.sh

# iOS-specific lint checks
./scripts/lint-ios.sh

# Android-specific lint checks
./scripts/lint-android.sh

# Find TODOs without issue references
./scripts/fix-todos.sh
```

### TODO Policy

All TODO-style comments must reference a GitHub issue:
- ✅ Correct: `// TODO: #123 - Implement error handling`
- ❌ Wrong: `// TODO: Implement error handling`

See [TODO Policy](docs/TODO_POLICY.md) for details.

### Pre-commit Hooks

Install pre-commit hooks to catch issues before committing:
```bash
pre-commit install
```

## 📖 Documentation

- [Android SDK Documentation](sdk/runanywhere-android/README.md)
- [iOS SDK Documentation](sdk/runanywhere-swift/README.md)
- [Android Example Documentation](examples/android/RunAnywhereAI/README.md)
- [iOS Example Documentation](examples/ios/RunAnywhereAI/README.md)

## 🤝 Contributing

We welcome contributions! Please see our [Contributing Guidelines](CONTRIBUTING.md) for details on how to:

- Report bugs
- Suggest features
- Submit pull requests
- Set up your development environment

## 📄 License

This project is licensed under the Apache License 2.0 - see the [LICENSE](LICENSE) file for details.

## 🏢 About RunAnywhere

RunAnywhere is building the future of on-device AI, providing developers with intelligent routing capabilities that balance cost, privacy, and performance. Our platform automatically decides when to run AI models locally versus in the cloud, optimizing for your specific use case.

---

**Questions?** Feel free to open an issue or reach out to our team.
