# iOS Sample App - RunAnywhere SDK Usage Documentation

## Overview

This document provides a comprehensive overview of how the iOS sample application (`examples/ios/RunAnywhereAI`) consumes the RunAnywhere SDK and demonstrates all the SDK's capabilities.

## Table of Contents

1. [App Launch & SDK Initialization](#app-launch--sdk-initialization)
2. [Core SDK Management](#core-sdk-management)
3. [Feature-Specific SDK Usage](#feature-specific-sdk-usage)
4. [Data Management & Analytics](#data-management--analytics)
5. [Storage Management](#storage-management)
6. [Error Handling](#error-handling)
7. [SDK API Reference](#sdk-api-reference)

---

## App Launch & SDK Initialization

### Entry Point: `RunAnywhereAIApp.swift`

The app's main entry point handles complete SDK initialization and framework registration.

#### Key SDK Integration Points:

1. **Framework Registration** (Lines 78-95):
   ```swift
   // Register WhisperKit for Speech-to-Text
   WhisperKitServiceProvider.register()
   RunAnywhere.registerFrameworkAdapter(WhisperKitAdapter.shared)

   // Register LLMSwift for Language Models
   LLMSwiftServiceProvider.register()
   RunAnywhere.registerFrameworkAdapter(LLMSwiftAdapter())

   // Register FluidAudioDiarization for Speaker Diarization
   FluidAudioDiarizationProvider.register()

   // Register Foundation Models adapter for iOS 26+
   if #available(iOS 26.0, macOS 26.0, *) {
       RunAnywhere.registerFrameworkAdapter(FoundationModelsAdapter())
   }
   ```

2. **SDK Initialization** (Lines 102-106):
   ```swift
   try await RunAnywhere.initialize(
       apiKey: "demo-api-key",
       baseURL: "https://api.runanywhere.ai",
       environment: .development
   )
   ```

3. **Auto Model Loading** (Lines 149-182):
   - Automatically loads the first available model after SDK initialization
   - Prefers LLama CPP compatible models
   - Updates the ModelListViewModel with the loaded model
   - Posts notifications for UI updates

#### State Management:
- `@State private var isSDKInitialized = false`: Tracks SDK initialization status
- `@State private var initializationError: Error?`: Handles initialization errors
- Loading states with proper error handling and retry functionality

---

## Core SDK Management

### ModelManager.swift

**Purpose**: Centralized model lifecycle management

#### SDK API Usage:
- `RunAnywhere.loadModel(modelInfo.id)`: Load specific models
- `RunAnywhere.unloadModel()`: Unload current model
- `RunAnywhere.listAvailableModels()`: Get available models
- `RunAnywhere.currentModel`: Access currently loaded model

#### Key Methods:
```swift
func loadModel(_ modelInfo: ModelInfo) async throws {
    try await RunAnywhere.loadModel(modelInfo.id)
}

func getAvailableModels() async -> [ModelInfo] {
    return try await RunAnywhere.listAvailableModels()
}
```

### ModelListViewModel.swift

**Purpose**: UI-focused model management with registry integration

#### SDK Integration:
- **Model Discovery** (Line 46): `try await RunAnywhere.availableModels()`
- **Model Downloads** (Line 93): `try await RunAnywhere.downloadModel(model.id)`
- **Model Deletion** (Line 97): `try await RunAnywhere.deleteModel(model.id)`
- **Model Loading** (Line 103): `try await RunAnywhere.loadModelWithInfo(model.id)`
- **Custom Model Addition** (Lines 110-114): `RunAnywhere.addModelFromURL()`

#### Platform Filtering:
```swift
// Filter out Foundation Models for older iOS versions
if #unavailable(iOS 26.0) {
    filteredModels = allModels.filter { $0.preferredFramework != .foundationModels }
}
```

---

## Feature-Specific SDK Usage

### 1. Chat Interface (`ChatViewModel.swift`)

**Primary SDK Usage**: Text generation with advanced analytics

#### Key SDK Integrations:

1. **Streaming Generation** (Lines 335-404):
   ```swift
   let stream = RunAnywhere.generateStream(fullPrompt, options: options)
   for try await token in stream {
       // Process streaming tokens
       fullResponse += token
   }
   ```

2. **Non-Streaming Generation** (Line 535):
   ```swift
   let resultText = try await RunAnywhere.generate(fullPrompt, options: options)
   ```

3. **Generation Options** (Lines 308-312):
   ```swift
   let options = RunAnywhereGenerationOptions(
       maxTokens: effectiveSettings.maxTokens,
       temperature: Float(effectiveSettings.temperature)
   )
   ```

#### Advanced Features:
- **Thinking Mode Support**: Handles `<think>` and `</think>` tags in responses
- **Real-time Analytics**: Tracks tokens per second, timing metrics, interruptions
- **Context Management**: Builds conversation history for model context
- **Error Recovery**: Graceful handling of generation failures

#### Analytics Collection:
- Message-level analytics with timing, token counts, performance metrics
- Conversation-level analytics aggregation
- Real-time token speed tracking

### 2. Voice Assistant (`VoiceAssistantViewModel.swift`)

**Primary SDK Usage**: Modular voice pipeline for real-time conversations

#### Pipeline Creation (Lines 152-160):
```swift
let config = ModularPipelineConfig(
    components: [.vad, .stt, .llm, .tts],
    vad: VADConfig(),
    stt: VoiceSTTConfig(modelId: whisperModelName),
    llm: VoiceLLMConfig(modelId: "default", systemPrompt: "..."),
    tts: VoiceTTSConfig(voice: "system")
)

voicePipeline = try await RunAnywhere.createVoicePipeline(config: config)
```

#### Pipeline Processing (Lines 194-205):
```swift
for try await event in voicePipeline!.process(audioStream: audioStream) {
    await handlePipelineEvent(event)
}
```

#### Event Handling:
- **VAD Events**: Speech start/end detection
- **STT Events**: Partial and final transcriptions
- **LLM Events**: Thinking mode and response generation
- **TTS Events**: Speech synthesis status

### 3. Quiz Generation (`QuizViewModel.swift`)

**Primary SDK Usage**: Structured data generation with custom types

#### Structured Generation (Lines 317-320):
```swift
let jsonText = try await RunAnywhere.generate(
    quizPrompt + "\n\nProvide the response as valid JSON matching the quiz schema.",
    options: options
)
```

#### Custom Generation Options (Lines 294-299):
```swift
let options = RunAnywhereGenerationOptions(
    maxTokens: maxTokens,
    temperature: Float(temperature),
    topP: 0.9,
    preferredExecutionTarget: .onDevice  // Force on-device execution
)
```

#### Schema Definition:
- Implements `Generatable` protocol
- Defines JSON schema for structured output
- Includes generation hints for optimal results

### 4. Storage Management (`StorageViewModel.swift`)

**Primary SDK Usage**: Storage and cleanup operations

#### Storage Information (Line 29):
```swift
let storageInfo = await RunAnywhere.getStorageInfo()
```

#### Storage Operations:
- **Cache Clearing** (Line 48): `try await RunAnywhere.clearCache()`
- **Temp File Cleanup** (Line 57): `try await RunAnywhere.cleanTempFiles()`
- **Model Deletion** (Line 66): `try await RunAnywhere.deleteStoredModel(modelId)`

---

## Data Management & Analytics

### ConversationStore.swift

**Purpose**: Persistent conversation storage with analytics integration

#### Key Features:
- **Message Analytics**: Stores detailed performance metrics with each message
- **Conversation Analytics**: Aggregated metrics across conversations
- **Performance Summaries**: Quick access to key metrics
- **File-based Persistence**: JSON encoding/decoding with error handling

#### Analytics Integration:
```swift
// Message with analytics
let updatedMessage = Message(
    id: currentMessage.id,
    role: currentMessage.role,
    content: currentMessage.content,
    thinkingContent: currentMessage.thinkingContent,
    timestamp: currentMessage.timestamp,
    analytics: analytics,  // Full analytics data
    modelInfo: modelInfo   // Model information
)
```

#### Analytics Data Structures:
- **MessageAnalytics**: Timing, tokens, performance, completion status
- **ConversationAnalytics**: Aggregated metrics across messages
- **PerformanceSummary**: Quick overview for UI display

---

## Storage Management

### Storage Information Structure:
```swift
// SDK provides StorageInfo with:
storageInfo.appStorage.totalSize      // Total app storage
storageInfo.deviceStorage.freeSpace   // Available device space
storageInfo.modelStorage.totalSize    // Space used by models
storageInfo.storedModels              // List of stored models
```

### Cleanup Operations:
- **Cache Management**: Clears temporary inference data
- **Model Management**: Delete unused models
- **Temp File Cleanup**: Removes temporary downloads and processing files

---

## Error Handling

### SDK Error Patterns:

1. **Initialization Errors**: Network issues, invalid API keys, framework registration failures
2. **Model Loading Errors**: Missing models, insufficient memory, framework incompatibility
3. **Generation Errors**: Context overflow, model failures, timeout issues
4. **Storage Errors**: Disk space, file permissions, corruption

### Error Recovery Strategies:
- **Retry Logic**: Automatic retries for transient errors
- **Graceful Degradation**: Fallback to alternative models or modes
- **User Feedback**: Clear error messages with actionable suggestions
- **State Recovery**: Maintains app state during error conditions

---

## SDK API Reference

### Core Initialization:
- `RunAnywhere.initialize(apiKey:baseURL:environment:)`
- `RunAnywhere.registerFrameworkAdapter(_:)`

### Model Management:
- `RunAnywhere.availableModels()` → `[ModelInfo]`
- `RunAnywhere.loadModel(_:)` → `ModelInfo`
- `RunAnywhere.unloadModel()`
- `RunAnywhere.downloadModel(_:)`
- `RunAnywhere.deleteModel(_:)`
- `RunAnywhere.addModelFromURL(_:name:type:)`

### Text Generation:
- `RunAnywhere.generate(_:options:)` → `String`
- `RunAnywhere.generateStream(_:options:)` → `AsyncStream<String>`

### Voice Pipeline:
- `RunAnywhere.createVoicePipeline(config:)` → `ModularVoicePipeline`
- Pipeline events: VAD, STT, LLM, TTS status and results

### Storage Management:
- `RunAnywhere.getStorageInfo()` → `StorageInfo`
- `RunAnywhere.clearCache()`
- `RunAnywhere.cleanTempFiles()`
- `RunAnywhere.deleteStoredModel(_:)`

### Framework Adapters:
- `WhisperKitAdapter`: Speech-to-text processing
- `LLMSwiftAdapter`: LLama.cpp model execution
- `FoundationModelsAdapter`: iOS/macOS native AI models
- `FluidAudioDiarizationProvider`: Speaker separation

---

## Summary

The iOS sample app demonstrates comprehensive SDK usage across:
- **5 major features**: Chat, Voice, Quiz, Storage, Models
- **4 framework integrations**: WhisperKit, LLMSwift, FoundationModels, FluidAudio
- **Advanced capabilities**: Streaming, analytics, structured generation, voice pipelines
- **Production patterns**: Error handling, state management, data persistence

The app serves as both a functional demo and a reference implementation for integrating the RunAnywhere SDK into iOS applications.
