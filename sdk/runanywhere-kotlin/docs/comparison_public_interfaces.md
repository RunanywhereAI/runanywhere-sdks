# RunAnywhere SDK: iOS vs Kotlin Public Interface Comparison

## Executive Summary

This document provides a comprehensive comparison between the iOS SDK (Swift) and Kotlin Multiplatform SDK public interfaces for the RunAnywhere AI platform. Both SDKs share similar architectural patterns but differ significantly in their implementation approaches, with iOS using extension-based modular design and Kotlin employing expect/actual multiplatform patterns.

---

## 1. iOS SDK Public Interface Analysis

### 1.1 Main Entry Point (`RunAnywhere.swift`)

**Architecture:** Enum-based singleton with static methods
- **Entry Point:** `public enum RunAnywhere`
- **Pattern:** Clean, event-driven API with async/await support
- **Initialization:** Comprehensive 8-step atomic initialization process
- **Event System:** Built-in EventBus for reactive programming (`RunAnywhere.events`)

**Core Public Methods:**
```swift
// Initialization
public static func initialize(apiKey: String, baseURL: URL, environment: SDKEnvironment = .production) async throws

// Text Generation
public static func chat(_ prompt: String) async throws -> String
public static func generate(_ prompt: String, options: RunAnywhereGenerationOptions? = nil) async throws -> String
public static func generateStream(_ prompt: String, options: RunAnywhereGenerationOptions? = nil) -> AsyncThrowingStream<String, Error>
public static func generateStructured<T: Generatable>(_ type: T.Type, prompt: String) async throws -> T

// Voice Operations
public static func transcribe(_ audioData: Data) async throws -> String

// Model Management
public static func loadModel(_ modelId: String) async throws
public static func availableModels() async throws -> [ModelInfo]
public static var currentModel: ModelInfo?

// State Management
public static var isInitialized: Bool
public static var events: EventBus
```

### 1.2 Extension-Based Modular Design

**Extensions:**
1. **`RunAnywhere+Configuration.swift`** - Configuration management
   - `getCurrentGenerationSettings() async -> DefaultGenerationSettings?`
   - `getCurrentRoutingPolicy() async -> RoutingPolicy`
   - `syncUserPreferences() async throws`

2. **`RunAnywhere+Voice.swift`** - Voice operations
   - `transcribe(audio: Data, modelId: String, options: STTOptions) async throws -> STTResult`
   - `createVoiceConversation(sttModelId: String, llmModelId: String, ttsVoice: String) -> AsyncThrowingStream<VoiceConversationEvent, Error>`
   - `processVoiceTurn(audio: Data, ...) async throws -> Data`

3. **`RunAnywhere+ModelManagement.swift`** - Model operations
   - `loadModelWithInfo(_ modelIdentifier: String) async throws -> ModelInfo`
   - `unloadModel() async throws`
   - `listAvailableModels() async throws -> [ModelInfo]`
   - `downloadModel(_ modelIdentifier: String) async throws`
   - `deleteModel(_ modelIdentifier: String) async throws`
   - `addModelFromURL(_ url: URL, name: String, type: String) async -> ModelInfo`

4. **`RunAnywhere+Components.swift`** - Component initialization
   - Component-based initialization with priority levels
   - LLM, STT, TTS, VAD component management
   - Unified component configuration

5. **`RunAnywhere+Pipelines.swift`** - Pipeline management
   - End-to-end voice conversation pipelines
   - Multi-modal pipeline orchestration

### 1.3 Type System

**Structured Types:**
- **`RunAnywhereGenerationOptions`** - Comprehensive generation configuration
  ```swift
  public struct RunAnywhereGenerationOptions {
      public let maxTokens: Int
      public let temperature: Float
      public let topP: Float
      public let enableRealTimeTracking: Bool
      public let stopSequences: [String]
      public let streamingEnabled: Bool
      public let preferredExecutionTarget: ExecutionTarget?
      public let structuredOutput: StructuredOutputConfig?
      public let systemPrompt: String?
  }
  ```

- **Event Types:** Rich event system with typed events
  - `SDKInitializationEvent`
  - `SDKGenerationEvent`
  - `SDKVoiceEvent`
  - `SDKModelEvent`

### 1.4 Component Architecture

**Component Types:**
- **STTComponent** - Speech-to-text
- **LLMComponent** - Language model
- **TTSComponent** - Text-to-speech
- **VADComponent** - Voice activity detection

**Factory Pattern:** `RunAnywhere.conversation()` creates conversation instances

---

## 2. Kotlin SDK Public Interface Analysis

### 2.1 Main Entry Point (`RunAnywhere.kt`)

**Architecture:** Multiplatform expect/actual pattern
- **Interface:** `interface RunAnywhereSDK`
- **Base Class:** `abstract class BaseRunAnywhereSDK`
- **Platform Objects:** `expect object RunAnywhere : BaseRunAnywhereSDK`
- **Pattern:** Object-oriented with shared logic in base class

**Core Public Methods:**
```kotlin
interface RunAnywhereSDK {
    val isInitialized: Boolean
    val currentEnvironment: SDKEnvironment
    val events: EventBus

    suspend fun initialize(apiKey: String, baseURL: String? = null, environment: SDKEnvironment)
    suspend fun availableModels(): List<ModelInfo>
    suspend fun downloadModel(modelId: String): Flow<Float>
    suspend fun loadModel(modelId: String): Boolean
    suspend fun generate(prompt: String, options: Map<String, Any>? = null): String
    fun generateStream(prompt: String, options: Map<String, Any>? = null): Flow<String>
    suspend fun transcribe(audioData: ByteArray): String
    suspend fun cleanup()
}
```

### 2.2 Platform-Specific Implementations

**JVM Implementation (`jvmMain/RunAnywhere.kt`):**
```kotlin
actual object RunAnywhere : BaseRunAnywhereSDK() {
    // JVM-specific implementations
    // File-based storage and database
    // STTComponent and VADComponent management
}
```

**Android Implementation (`androidMain/RunAnywhereAndroid.kt`):**
```kotlin
actual object RunAnywhere : BaseRunAnywhereSDK() {
    suspend fun initialize(context: Context, apiKey: String, baseURL: String?, environment: SDKEnvironment)
    // Android-specific implementations
    // Room database, EncryptedSharedPreferences
    // Context-aware initialization
}
```

### 2.3 Type System

**Generation Options:**
```kotlin
data class GenerationOptions(
    val model: String? = null,
    val temperature: Float = 0.7f,
    val maxTokens: Int = 1000,
    val topP: Float = 0.9f,
    val topK: Int = 40,
    val stopSequences: List<String> = emptyList(),
    val streaming: Boolean = false,
    val seed: Int? = null
)
```

**Components:**
- **LLMComponent** - Language model component
- **STTComponent** - Speech-to-text component
- **TTSComponent** - Text-to-speech component
- **VADComponent** - Voice activity detection component

### 2.4 Service Architecture

**Service Container Pattern:**
- **ServiceContainer** - Central dependency injection
- **GenerationService** - Text generation
- **StreamingService** - Streaming generation
- **ModelInfoService** - Model information management

---

## 3. Detailed Comparison

### 3.1 Architecture Patterns

| Aspect | iOS SDK | Kotlin SDK |
|--------|---------|------------|
| **Main Pattern** | Enum-based singleton with extensions | Interface + expect/actual multiplatform |
| **Entry Point** | `enum RunAnywhere` | `expect object RunAnywhere : BaseRunAnywhereSDK` |
| **Modularity** | Extension-based (`RunAnywhere+Feature.swift`) | Package-based modular architecture |
| **State Management** | Static properties with internal backing | Object properties with protected backing |
| **Concurrency** | async/await + Combine | Coroutines + Flow |

### 3.2 Initialization Approach

**iOS SDK:**
- **Method:** Single comprehensive `initialize()` method
- **Steps:** 8-step atomic process with detailed logging
- **Rollback:** Automatic rollback on failure
- **Events:** Rich event publishing throughout process

**Kotlin SDK:**
- **Method:** Platform-aware initialization in base class
- **Steps:** Same 8-step process with abstract platform methods
- **Context:** Android requires Context parameter
- **Flexibility:** Platform-specific credential storage (keychain vs encrypted preferences)

### 3.3 Generation Options

| Feature | iOS `RunAnywhereGenerationOptions` | Kotlin `GenerationOptions` |
|---------|-----------------------------------|---------------------------|
| **maxTokens** | ✅ Int (default: 100) | ✅ Int (default: 1000) |
| **temperature** | ✅ Float (default: 0.7) | ✅ Float (default: 0.7) |
| **topP** | ✅ Float (default: 1.0) | ✅ Float (default: 0.9) |
| **topK** | ❌ Missing | ✅ Int (default: 40) |
| **stopSequences** | ✅ [String] | ✅ List<String> |
| **streaming** | ✅ streamingEnabled: Bool | ✅ streaming: Bool |
| **realTimeTracking** | ✅ enableRealTimeTracking: Bool | ❌ Missing |
| **structuredOutput** | ✅ StructuredOutputConfig? | ❌ Missing |
| **systemPrompt** | ✅ String? | ❌ Missing |
| **executionTarget** | ✅ preferredExecutionTarget: ExecutionTarget? | ❌ Missing |
| **seed** | ❌ Missing | ✅ Int? |

### 3.4 API Surface Differences

#### iOS SDK Advantages:
1. **Rich Extensions:** Specialized extensions for different use cases
2. **Component System:** Advanced component initialization with priorities
3. **Pipeline Management:** Built-in pipeline orchestration
4. **Structured Output:** Native support for structured data generation
5. **Event-Driven:** Comprehensive event bus with typed events
6. **Conversation Factory:** `RunAnywhere.conversation()` factory method
7. **Real-time Tracking:** Built-in cost and performance tracking

#### Kotlin SDK Advantages:
1. **Multiplatform:** True cross-platform code sharing
2. **Type Safety:** Strong typing with data classes
3. **Context Awareness:** Android-specific context handling
4. **Flow Integration:** Native Kotlin Flow support
5. **Progressive Download:** Progress tracking with `Flow<Float>`
6. **Platform Abstractions:** Clear platform-specific implementations

### 3.5 Missing Interfaces

#### Missing in iOS SDK:
1. **Progress Tracking:** No progress indication for model downloads
2. **topK Parameter:** Missing topK sampling parameter
3. **Seed Parameter:** Missing seed for reproducible generation
4. **Platform Context:** No explicit platform context handling
5. **Cleanup Method:** No explicit cleanup method

#### Missing in Kotlin SDK:
1. **Extension Methods:** No extension-based API organization
2. **Real-time Tracking:** No built-in cost tracking
3. **Structured Output:** No structured data generation support
4. **System Prompts:** No system prompt configuration
5. **Execution Targets:** No execution target preferences
6. **Pipeline Management:** No high-level pipeline APIs
7. **Conversation Factory:** No conversation factory methods
8. **Component Priorities:** No component initialization priorities

### 3.6 Event Systems

**iOS SDK:**
```swift
// Rich typed events
RunAnywhere.events.subscribe(to: SDKGenerationEvent.self) { event in
    switch event {
    case .started(let prompt): // ...
    case .completed(let response, let tokensUsed, let latencyMs): // ...
    case .failed(let error): // ...
    }
}
```

**Kotlin SDK:**
```kotlin
// Basic event bus
EventBus.shared.publish(SDKInitializationEvent.Started)
EventBus.shared.subscribe<SDKInitializationEvent> { event ->
    // Handle event
}
```

---

## 4. Multiplatform Patterns Analysis

### 4.1 Kotlin's expect/actual Pattern

**Strengths:**
- **Code Sharing:** Maximum code reuse between platforms
- **Type Safety:** Compile-time verification of platform implementations
- **Consistency:** Same API surface across platforms
- **Maintenance:** Single source of truth for shared logic

**Implementation:**
```kotlin
// commonMain
expect object RunAnywhere : BaseRunAnywhereSDK

// jvmMain
actual object RunAnywhere : BaseRunAnywhereSDK() {
    // JVM-specific implementation
}

// androidMain
actual object RunAnywhere : BaseRunAnywhereSDK() {
    // Android-specific implementation
}
```

### 4.2 iOS Native Approach

**Strengths:**
- **Platform Optimization:** Full utilization of iOS capabilities
- **Native Patterns:** Uses familiar iOS architectural patterns
- **Performance:** No multiplatform overhead
- **Rich APIs:** Access to full iOS SDK capabilities

**Considerations:**
- **Maintenance Overhead:** Separate codebase maintenance
- **Consistency Challenges:** Ensuring API parity requires discipline
- **Feature Parity:** Manual synchronization of features

---

## 5. Recommendations

### 5.1 API Unification Opportunities

1. **Generation Options Harmonization:**
   - Add missing parameters to achieve parity
   - Kotlin SDK should add: `realTimeTracking`, `structuredOutput`, `systemPrompt`, `executionTarget`
   - iOS SDK should add: `topK`, `seed`

2. **Method Naming Consistency:**
   - Standardize method names across platforms
   - Align parameter naming conventions

3. **Event System Enhancement:**
   - Kotlin SDK should adopt iOS's rich typed event system
   - Consider event categorization similar to iOS

### 5.2 Architecture Improvements

1. **Kotlin SDK:**
   - Add extension-style API organization for better discoverability
   - Implement conversation factory methods
   - Add pipeline management APIs
   - Enhance component initialization with priorities

2. **iOS SDK:**
   - Add progress tracking for downloads
   - Implement explicit cleanup methods
   - Consider platform context abstractions

### 5.3 Feature Parity Goals

1. **Essential Missing Features:**
   - Kotlin: Structured output generation
   - Kotlin: Real-time cost tracking
   - iOS: Download progress indication
   - iOS: Reproducible generation (seed parameter)

2. **Advanced Features:**
   - Pipeline management consistency
   - Component lifecycle management
   - Configuration synchronization

---

## 6. Conclusion

Both SDKs demonstrate strong architectural foundations but serve different strategic purposes:

- **iOS SDK** prioritizes rich, platform-native APIs with advanced features like structured output and pipeline management
- **Kotlin SDK** focuses on multiplatform code sharing and type safety with clean abstractions

The key opportunity lies in achieving feature parity while maintaining each platform's architectural strengths. The iOS extension pattern could inspire better API organization in Kotlin, while Kotlin's multiplatform approach offers valuable lessons for code sharing strategies.

**Priority Actions:**
1. Harmonize generation options for consistent developer experience
2. Implement missing core features (structured output in Kotlin, progress tracking in iOS)
3. Standardize event systems for reactive programming consistency
4. Develop cross-platform API documentation highlighting differences and migration paths

This analysis reveals that both SDKs are well-architected for their target use cases, with clear opportunities for convergence in developer experience while maintaining platform-specific optimizations.
