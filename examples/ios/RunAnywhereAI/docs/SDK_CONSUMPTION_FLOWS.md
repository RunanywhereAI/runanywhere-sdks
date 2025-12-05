# RunAnywhere SDK Consumption Flows in iOS Sample App

This document details all the places where the RunAnywhere SDK is consumed in the iOS sample app, explaining what each integration does, how it works, and why it's implemented.

## Overview

The iOS sample app demonstrates comprehensive integration with the RunAnywhere SDK for on-device AI model management and execution. The SDK provides intelligent routing between on-device and cloud models, optimizing for cost and privacy.

## Current Directory Structure

The app has been organized into a clean, feature-based architecture:

```
RunAnywhereAI/
├── App/                          # App entry point and navigation
│   ├── RunAnywhereAIApp.swift  # SDK initialization
│   └── ContentView.swift        # Main tab navigation
├── Core/                        # Core functionality
│   ├── Models/                  # Data models
│   │   ├── AppTypes.swift      # App-specific types
│   │   └── ChatMessage.swift   # Message model
│   ├── Services/               # SDK adapters and services
│   │   ├── ConversationStore.swift
│   │   ├── DeviceInfoService.swift
│   │   ├── KeychainService.swift
│   │   ├── ModelDownloadManager.swift
│   │   ├── ModelManager.swift
│   │   ├── ModelURLRegistry.swift
│   │   ├── Foundation/         # Foundation Models adapter
│   │   └── LlamaCPP/          # LlamaCPP adapter
├── Features/                    # Feature modules
│   ├── AnalyticsView.swift    # Analytics dashboard
│   ├── Chat/                   # Chat functionality
│   │   ├── ChatViewModel.swift
│   │   └── Chat/              # Chat UI components
│   ├── Models/                 # Model management
│   │   ├── AddModelFromURLView.swift
│   │   ├── ModelListViewModel.swift
│   │   └── SimplifiedModelsView.swift
│   ├── Quiz/                   # Quiz feature
│   │   ├── QuizViewModel.swift
│   │   └── Quiz/              # Quiz UI components
│   ├── Storage/                # Storage management
│   │   ├── StorageView.swift
│   │   └── StorageViewModel.swift
│   └── Settings/               # App settings
│       └── SimplifiedSettingsView.swift
└── Resources/                  # Assets and configuration
    ├── Assets.xcassets
    ├── RunAnywhereConfig-Debug.plist
    └── RunAnywhereConfig-Release.plist
```

## Core SDK Integration Points

### 1. App Initialization (`App/RunAnywhereAIApp.swift`)

**What**: SDK initialization and adapter registration
**Where**: Lines 30-50
**How**:
```swift
// Initialize SDK with configuration
let config = SDKConfiguration(
    apiKey: apiKey,
    enableAnalytics: true,
    enableLiveMetrics: true,
    routingPolicy: .balanced
)
RunAnywhereSDK.shared.initialize(apiKey: apiKey, configuration: config)

// Register framework adapters
RunAnywhereSDK.shared.registerAdapter(LlamaCPPCoreAdapter())
RunAnywhereSDK.shared.registerAdapter(FoundationModelsAdapter())
```
**Why**: Essential setup to enable all SDK functionality throughout the app

### 2. Chat Generation (`Features/Chat/ChatViewModel.swift`)

**What**: Text generation and conversation management
**Where**: Primary methods around lines 150-350
**How**:
- `sendMessage()` - Initiates text generation with SDK
- Uses `RunAnywhereSDK.shared.generateStream()` for streaming responses
- Tracks generation metrics and analytics
- Manages conversation context and history

**Key SDK interactions**:
```swift
// Streaming generation
for try await chunk in RunAnywhereSDK.shared.generateStream(
    messages: messages,
    options: generationOptions
) {
    // Process streaming chunks
}

// Analytics tracking
await RunAnywhereSDK.shared.getSessionAnalytics(sessionId)
```

### 3. Model Management (`Core/Services/ModelManager.swift`)

**What**: Model lifecycle management
**Where**: Throughout the service class
**How**:
```swift
// Load model
try await RunAnywhereSDK.shared.loadModel(modelInfo.id)

// Unload model
try await RunAnywhereSDK.shared.unloadModel()

// List available models
try await RunAnywhereSDK.shared.listAvailableModels()
```
**Why**: Provides abstraction layer for model operations

### 4. Model Discovery (`Features/Models/ModelListViewModel.swift`)

**What**: Discovering and listing available models
**Where**: `loadModels()` method
**How**:
```swift
let sdkModels = try await RunAnywhereSDK.shared.listAvailableModels()
```
**Why**: Shows users available models from SDK

### 5. Storage Management (`Features/Storage/StorageViewModel.swift`)

**What**: Model storage and cache management
**Where**: Throughout the view model
**How**:
- Monitors model storage usage
- Manages model deletion
- Tracks storage metrics

**SDK interactions**:
```swift
// Get model storage info
let models = try await RunAnywhereSDK.shared.listAvailableModels()
// Calculate storage per model
```

### 6. Analytics Tracking (`Features/AnalyticsView.swift`)

**What**: Real-time usage metrics and cost tracking
**Where**: View implementation
**How**:
- Accesses SDK analytics data
- Displays generation metrics
- Shows cost savings from on-device execution

**SDK interactions**:
```swift
// Access analytics data from SDK
let analytics = RunAnywhereSDK.shared.analytics
```

### 7. Configuration Management (`Features/Settings/SimplifiedSettingsView.swift`)

**What**: SDK configuration and preferences
**Where**: Settings form implementation
**How**:
```swift
// Update SDK configuration
let newConfig = SDKConfiguration(
    apiKey: apiKey,
    routingPolicy: selectedPolicy,
    enableAnalytics: enableAnalytics
)
RunAnywhereSDK.shared.updateConfiguration(newConfig)
```
**Why**: Allows runtime configuration changes

## Framework Adapters

### LlamaCPP Integration (`Core/Services/LlamaCPP/`)
- **LlamaCPPCoreAdapter.swift**: Implements SDK adapter protocol
- **LlamaCPPService.swift**: Handles LlamaCPP-specific operations
- Supports GGUF format models
- Provides streaming generation

### Foundation Models Integration (`Core/Services/Foundation/`)
- **FoundationModelsAdapter.swift**: Implements SDK adapter protocol
- Integrates Apple's on-device models
- Optimized for Apple Silicon

## Key Features Demonstrated

1. **Multi-Framework Support**: Shows how to integrate multiple LLM frameworks
2. **Streaming Generation**: Real-time text generation with progress
3. **Cost Tracking**: Demonstrates cost optimization features
4. **Model Management**: Complete model lifecycle handling
5. **Analytics Integration**: Usage metrics and performance monitoring
6. **Secure Storage**: API key management with KeychainService
7. **Offline Support**: On-device model execution

## SDK Usage Patterns

### 1. Singleton Pattern
```swift
RunAnywhereSDK.shared
```

### 2. Async/Await
```swift
Task {
    do {
        let result = try await RunAnywhereSDK.shared.generate(...)
    } catch {
        // Handle errors
    }
}
```

### 3. Streaming
```swift
for try await chunk in RunAnywhereSDK.shared.generateStream(...) {
    // Process chunks
}
```

### 4. Error Handling
```swift
do {
    try await RunAnywhereSDK.shared.loadModel(modelId)
} catch RunAnywhereError.modelNotFound {
    // Handle specific error
} catch {
    // Handle general error
}
```

## Recent Cleanup Summary

The sample app has undergone significant cleanup:

1. **Removed 20+ unused files** including redundant views, unused services, and test stubs
2. **Reorganized into feature-based structure** for better maintainability
3. **Eliminated debug code** including 36 NSLog statements
4. **Simplified dependencies** by cleaning up Podfile
5. **Removed UI components** that weren't being used

The app now serves as a clean, focused example of SDK integration without unnecessary complexity.

## Best Practices Demonstrated

1. **Proper Initialization**: SDK initialized once at app startup
2. **Error Handling**: Comprehensive error handling for all SDK operations
3. **Resource Management**: Proper model loading/unloading
4. **Security**: API keys stored in Keychain, not hardcoded
5. **Performance**: Efficient streaming and memory management
6. **User Control**: Settings allow customization of SDK behavior

## Summary

This iOS sample app provides a production-ready example of RunAnywhere SDK integration, demonstrating:
- Clean architecture with feature-based organization
- Comprehensive SDK integration across all major features
- Best practices for error handling and resource management
- Real-world usage patterns for on-device AI

The codebase is now minimal yet complete, serving as an excellent reference for developers integrating the RunAnywhere SDK into their iOS applications.
