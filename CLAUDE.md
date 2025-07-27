# CLAUDE.md

### Before starting work
- Always in plan mode to make a plan refer to `thoughts/shared/plans/{descriptive_name}.md`.
- After get the plan, make sure you Write the plan to the appropriate file as mentioned in the guide that you referred to.
- If the task require external knowledge or certain package, also research to get latest knowledge (Use Task tool for research)
- Don't over plan it, always think MVP.
- Once you write the plan, firstly ask me to review it. Do not continue until I approve the plan.
### While implementing
- You should update the plan as you work - check `thoughts/shared/plans/{descriptive_name}.md` if you're running an already created plan via `thoughts/shared/plans/{descriptive_name}.md`
- After you complete tasks in the plan, you should update and append detailed descriptions of the changes you made, so following tasks can be easily hand over to other engineers.


This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository Overview

This repository contains cross-platform SDKs for the RunAnywhere on-device AI platform. The platform provides intelligent routing between on-device and cloud AI models to optimize for cost and privacy.

### SDK Implementations
- **Android SDK** (`sdk/runanywhere-android/`) - Kotlin-based SDK for Android
- **iOS SDK** (`sdk/runanywhere-swift/`) - Swift Package Manager-based SDK for iOS/macOS/tvOS/watchOS

### Example Applications
- **Android Demo** (`examples/android/RunAnywhereAI/`) - Sample Android app demonstrating SDK usage
- **iOS Demo** (`examples/ios/RunAnywhereAI/`) - Sample iOS app demonstrating SDK usage

## Common Development Commands

### Android SDK Development

```bash
# Navigate to Android SDK
cd sdk/runanywhere-android/

# Build the SDK
./gradlew build

# Run lint checks
./gradlew lint

# Run tests
./gradlew test

# Clean build
./gradlew clean

# Build release AAR
./gradlew assembleRelease
```

### iOS SDK Development

```bash
# Navigate to iOS SDK
cd sdk/runanywhere-swift/

# Build the SDK
swift build

# Run tests
swift test

# Run tests with coverage
swift test --enable-code-coverage

# Run SwiftLint
swiftlint

# Build for specific platform
xcodebuild build -scheme RunAnywhere -destination 'platform=iOS Simulator,name=iPhone 15'
```

### Android Example App

```bash
# Navigate to Android example
cd examples/android/RunAnywhereAI/

# Build the app
./gradlew build

# Run lint
./gradlew :app:lint

# Install on device/emulator
./gradlew installDebug

# Run tests
./gradlew test
```

### iOS Example App

```bash
# Navigate to iOS example
cd examples/ios/RunAnywhereAI/

# Run SwiftLint
./swiftlint.sh

# Build and run (open in Xcode)
open RunAnywhereAI.xcodeproj
```

### Pre-commit Hooks

```bash
# Run all pre-commit checks
pre-commit run --all-files

# Run specific checks
pre-commit run android-sdk-lint --all-files
pre-commit run ios-sdk-swiftlint --all-files
```

## Architecture Overview

### Core SDK Design Patterns

Both SDKs follow similar architectural patterns:

1. **Singleton Pattern**: Main SDK access through `RunAnywhereSDK.shared` (iOS) or `RunAnywhereSDK.getInstance()` (Android)
2. **Configuration-based Initialization**: Initialize with API key and optional settings
3. **Async/Promise-based APIs**: Modern async patterns (Kotlin coroutines for Android, async/await for iOS)
4. **Model Loading**: Universal model loader supporting multiple formats (GGUF, ONNX, Core ML, MLX, TFLite)
5. **Intelligent Routing**: Automatic decision-making for on-device vs cloud execution
6. **Cost Tracking**: Real-time cost and savings tracking

### Key Components

**Android SDK Structure:**
- `RunAnywhereSDK.kt` - Main SDK entry point and singleton
- `Configuration.kt` - SDK configuration options
- `GenerationOptions.kt` - Text generation parameters
- `GenerationResult.kt` - Generation response with metrics
- `Message.kt` & `Context.kt` - Conversation management

**iOS SDK Structure:**
- `RunAnywhereSDK.swift` - Main SDK class with shared instance
- `Configuration.swift` - SDK configuration and policies
- `GenerationOptions.swift` - Generation parameters
- `GenerationResult.swift` - Results with cost tracking
- `Context.swift` & `Message.swift` - Conversation context

### Platform Requirements

**Android:**
- Minimum SDK: 24 (Android 7.0)
- Target SDK: 36
- Kotlin: 2.0.21
- Gradle: 8.11.1

**iOS:**
- iOS 13.0+ / macOS 10.15+ / tvOS 13.0+ / watchOS 6.0+
- Swift: 5.9+
- Xcode: 15.0+

## CI/CD Pipeline

GitHub Actions workflows are configured for automated testing and building:

- **Path-based triggers**: Workflows only run when relevant files change
- **Platform-specific runners**: Ubuntu for Android, macOS for iOS
- **Artifact uploads**: Build outputs and test results are preserved
- **Lint enforcement**: Lint errors fail the build

Workflows are located in `.github/workflows/`:
- `android-sdk.yml` - Android SDK CI
- `ios-sdk.yml` - iOS SDK CI
- `android-app.yml` - Android example app CI
- `ios-app.yml` - iOS example app CI

## Development Notes

- Both SDKs are in early development with placeholder implementations
- The SDKs focus on privacy-first, on-device AI with intelligent routing
- Cost optimization is a key feature with real-time tracking
- Pre-commit hooks are configured for code quality enforcement
- SwiftLint is temporarily disabled in iOS SDK build due to plugin issues