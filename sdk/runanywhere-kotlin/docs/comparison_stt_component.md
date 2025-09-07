# Speech-to-Text (STT) Component Architecture Comparison: iOS vs Kotlin SDKs

## Executive Summary

This document compares the STT component architectures between iOS and Kotlin SDKs, identifying areas of duplication, architectural differences, and opportunities for consolidation. The investigation reveals significant architectural overlap and multiple STT implementations that create complexity and potential maintenance burden.

## Key Findings

### 1. **Multiple STT Component Implementations Identified**

The analysis confirms the user's observation of "duplicate STT components" across different architectural layers:

#### iOS STT Architecture:
- **Generic STT Component**: `/sdk/runanywhere-swift/Sources/RunAnywhere/Components/STT/STTComponent.swift`
- **WhisperKit Adapter**: `/sdk/runanywhere-swift/Modules/WhisperKitTranscription/Sources/WhisperKitTranscription/WhisperKitAdapter.swift`
- **WhisperKit Service**: `/sdk/runanywhere-swift/Modules/WhisperKitTranscription/Sources/WhisperKitTranscription/WhisperKitService.swift`
- **WhisperKit Provider**: `/sdk/runanywhere-swift/Modules/WhisperKitTranscription/Sources/WhisperKitTranscription/WhisperKitServiceProvider.swift`

#### Kotlin STT Architecture:
- **Generic STT Component**: `/sdk/runanywhere-kotlin/src/commonMain/kotlin/com/runanywhere/sdk/components/stt/STTComponent.kt`
- **Generic STT Models**: `/sdk/runanywhere-kotlin/src/commonMain/kotlin/com/runanywhere/sdk/components/stt/STTModels.kt`
- **Legacy Voice Models**: `/sdk/runanywhere-kotlin/src/commonMain/kotlin/com/runanywhere/sdk/voice/models/STTModels.kt`
- **STT Handler**: `/sdk/runanywhere-kotlin/src/commonMain/kotlin/com/runanywhere/sdk/voice/handlers/STTHandler.kt`
- **WhisperKit Module**: `/sdk/runanywhere-kotlin/modules/runanywhere-whisperkit/src/commonMain/kotlin/com/runanywhere/whisperkit/`
- **Platform Implementations**: JVM and Android specific STT services

### 2. **Architectural Differences**

#### iOS: Clean Separation of Concerns
```swift
STTComponent (Generic)
    └── STTServiceProvider (Registry)
        └── WhisperKitServiceProvider (Implementation)
            └── WhisperKitService (Concrete Service)
                └── WhisperKitAdapter (Framework Adapter)
```

#### Kotlin: Multiple Overlapping Architectures
```kotlin
// Architecture 1: Component-based
STTComponent (Generic)
    └── STTService (Interface)
        └── WhisperSTTService (expect/actual)

// Architecture 2: WhisperKit Module
WhisperKitService (Abstract)
    └── Platform implementations (JVM/Android)
        └── WhisperKitFactory (expect object)

// Architecture 3: Legacy Voice System
STTHandler
    └── Uses STTComponent directly
    └── Separate STTModels in voice package
```

## Detailed Comparison

### Generic STT Interfaces

#### iOS Implementation
- **Single STTService protocol** with clear interface boundaries
- **Unified configuration system** through STTConfiguration
- **Consistent error handling** via STTError enum
- **Service wrapper pattern** for protocol-based services

#### Kotlin Implementation
- **Multiple STT interfaces** across different packages:
  - `com.runanywhere.sdk.components.stt.STTService`
  - Legacy models in `com.runanywhere.sdk.voice.models`
- **Inconsistent configuration** between different layers
- **Multiple error handling approaches** (sealed classes vs exceptions)

### WhisperKit-Specific Extensions

#### iOS WhisperKit Module
```swift
// Clean separation: Generic protocols + Whisper implementation
public protocol STTService: AnyObject {
    func initialize(modelPath: String?) async throws
    func transcribe(audioData: Data, options: STTOptions) async throws -> STTTranscriptionResult
    // ... other methods
}

// WhisperKit implementation
public class WhisperKitService: STTService {
    // Implements generic protocol with WhisperKit specifics
}
```

#### Kotlin WhisperKit Module
```kotlin
// Mixed approach: Abstract class extending interface
abstract class WhisperKitService : STTService {
    // WhisperKit-specific functionality
    suspend fun initializeWithWhisperModel(modelType: WhisperModelType)
    suspend fun transcribeWithWhisperOptions(options: WhisperTranscriptionOptions)
    // Generic STTService methods
}

// Separate factory pattern
expect object WhisperKitFactory {
    fun createService(): WhisperKitService
}
```

### Service Initialization Patterns

#### iOS: Provider-Based Registration
```swift
// Simple, centralized registration
WhisperKitServiceProvider.register()

// Automatic service discovery
guard let provider = ModuleRegistry.shared.sttProvider(for: configuration.modelId)
```

#### Kotlin: Multiple Initialization Paths
```kotlin
// Path 1: Component creation
STTComponent(STTConfiguration())

// Path 2: Service provider
WhisperServiceProvider.register()

// Path 3: WhisperKit factory
WhisperKitFactory.createService()

// Path 4: Direct instantiation
WhisperSTTService() // expect/actual
```

### Audio Processing Workflows

#### iOS: Unified Processing Pipeline
- Single audio format handling through `AudioFormat` enum
- Consistent buffer conversion utilities
- Unified streaming support via `AsyncSequence`

#### Kotlin: Multiple Processing Approaches
- Different audio handling in each layer:
  - `ByteArray` in STT components
  - `FloatArray` in WhisperKit module
  - Platform-specific conversion utilities
- Inconsistent streaming implementations using Kotlin `Flow`

### State Management

#### iOS: Protocol-Driven States
```swift
// Simple boolean state
public var isReady: Bool { get }

// WhisperKit adds detailed states without breaking generic interface
private let _whisperState = MutableStateFlow(WhisperServiceState.UNINITIALIZED)
```

#### Kotlin: Multiple State Systems
```kotlin
// Component state
enum class ComponentState { NOT_INITIALIZED, INITIALIZING, READY, ERROR }

// WhisperKit state (separate enum)
enum class WhisperServiceState { UNINITIALIZED, INITIALIZING, DOWNLOADING_MODEL, READY... }

// Legacy STT state (third enum)
enum class STTState { IDLE, INITIALIZING, READY, PROCESSING, ERROR }
```

### Error Handling Approaches

#### iOS: Consistent Error Types
```swift
// Single, comprehensive error enum
public enum STTError: LocalizedError {
    case serviceNotInitialized
    case transcriptionFailed(Error)
    case streamingNotSupported
    // ...
}
```

#### Kotlin: Multiple Error Patterns
```kotlin
// Pattern 1: Sealed class hierarchy
sealed class STTError : Exception() {
    object ServiceNotInitialized : STTError()
    data class TranscriptionFailed(override val cause: Throwable) : STTError()
}

// Pattern 2: WhisperKit-specific errors
sealed class WhisperError : Exception() {
    data class ModelNotFound(override val message: String) : WhisperError()
    data class InitializationFailed(override val message: String) : WhisperError()
}

// Pattern 3: Legacy voice errors (different structure)
sealed class STTError : Exception() {
    data class ModelNotFound(override val message: String) : STTError()
    data class TranscriptionError(override val message: String) : STTError()
}
```

## Identified Duplications

### 1. **Model Definition Duplication**

#### Data Classes/Structs
- **iOS**: Single set of data structures in STTComponent.swift
- **Kotlin**: Multiple definitions:
  - `STTInput/STTOutput` in `components.stt.STTModels`
  - `STTInput/STTOutput` in `voice.models.STTModels` (different structure)
  - `WhisperTranscriptionOptions` in WhisperKit module
  - Platform-specific data types

#### Transcription Results
```kotlin
// Duplication 1: Component layer
data class STTTranscriptionResult(
    val transcript: String,
    val confidence: Float?,
    val timestamps: List<TimestampInfo>?
)

// Duplication 2: WhisperKit layer
data class WhisperTranscriptionResult(
    val text: String,
    val segments: List<TranscriptionSegment>,
    val confidence: Float
)

// Duplication 3: Legacy voice layer
data class STTOutput(
    val text: String,
    val confidence: Float,
    val segments: List<TranscriptionSegment>
)
```

### 2. **Service Interface Duplication**

#### Multiple Service Contracts
- **Generic STTService interface** in components package
- **WhisperKitService abstract class** in WhisperKit module
- **Legacy STT interfaces** in voice package

### 3. **Configuration Duplication**

#### Multiple Configuration Systems
```kotlin
// Configuration 1: Component level
data class STTConfiguration(
    val modelId: String?,
    val language: String = "en-US",
    val sampleRate: Int = 16000
)

// Configuration 2: WhisperKit level
data class WhisperTranscriptionOptions(
    val language: String = "auto",
    val temperature: Float = 0.0f,
    val suppressBlank: Boolean = true
)

// Configuration 3: Legacy voice level
data class STTOptions(
    val task: STTTask = STTTask.TRANSCRIBE,
    val temperature: Float = 0.0f,
    val wordTimestamps: Boolean = false
)
```

## Platform-Specific Implementation Analysis

### expect/actual Pattern Usage

#### iOS: Native Implementation Approach
- Uses Swift protocols and extensions
- Direct WhisperKit integration
- Platform-specific optimizations handled transparently

#### Kotlin: expect/actual for Platform Abstraction
```kotlin
// Common: Interface definition
expect class WhisperSTTService() : STTService

// JVM: Uses whisper-jni library
actual class WhisperSTTService : STTService {
    private var whisperJNI: WhisperJNI? = null
    private var whisperContext: WhisperContext? = null
    // JVM-specific implementation
}

// Android: Uses different whisper library
actual class WhisperSTTService : STTService {
    private val whisperService = WhisperService()
    // Android-specific implementation
}
```

### Model Management Integration

#### iOS: Unified Model System
- Single model registry
- Consistent download strategies
- Integrated storage management

#### Kotlin: Fragmented Model Handling
- Multiple model type enums (`WhisperModelType`, `STTModelType`, `ModelSize`)
- Separate storage strategies per module
- Inconsistent model lifecycle management

## Recommendations for Consolidation

### 1. **Unify STT Interfaces**

**Problem**: Multiple STT service interfaces across different packages create confusion and maintenance overhead.

**Solution**: Consolidate to single generic interface with extension points:
```kotlin
// Unified generic interface
interface STTService {
    suspend fun initialize(modelPath: String?)
    suspend fun transcribe(audioData: ByteArray, options: STTOptions): STTResult
    // ... standard methods
}

// Extension interface for Whisper-specific features
interface WhisperSTTExtensions {
    suspend fun transcribeWithWhisperOptions(audioData: ByteArray, options: WhisperOptions): WhisperResult
    suspend fun switchModel(modelType: WhisperModelType)
}
```

### 2. **Consolidate Data Models**

**Problem**: Multiple representations of the same concepts.

**Solution**: Create shared data model hierarchy:
```kotlin
// Base transcription result
sealed interface TranscriptionResult {
    val text: String
    val confidence: Float
}

// Generic implementation
data class STTResult(...) : TranscriptionResult

// Whisper-specific extension
data class WhisperResult(...) : TranscriptionResult {
    val segments: List<WhisperSegment>
    val languageProbabilities: Map<String, Float>
}
```

### 3. **Standardize Configuration**

**Problem**: Multiple configuration systems with overlapping concerns.

**Solution**: Hierarchical configuration with inheritance:
```kotlin
// Base configuration
open class STTConfiguration(
    val modelId: String?,
    val language: String = "auto"
)

// Whisper-specific configuration extends base
class WhisperConfiguration(
    modelId: String?,
    language: String = "auto",
    val temperature: Float = 0.0f,
    val modelType: WhisperModelType = WhisperModelType.BASE
) : STTConfiguration(modelId, language)
```

### 4. **Remove Legacy Components**

**Problem**: Legacy voice package creates confusion and duplication.

**Recommendation**:
- Migrate functionality from `voice.handlers.STTHandler` to main `STTComponent`
- Remove duplicate models in `voice.models.STTModels`
- Consolidate error types to single hierarchy

### 5. **Align with iOS Architecture**

**Problem**: Kotlin architecture is more complex than necessary.

**Solution**: Adopt iOS pattern:
- Single generic component with service provider registration
- Clean separation between generic and implementation-specific concerns
- Unified error handling and state management

## Conclusion

The analysis reveals significant architectural duplication between iOS and Kotlin STT implementations, with the Kotlin side being more complex due to multiple overlapping systems. The main issues are:

1. **Multiple STT interfaces** across different packages
2. **Duplicate data models** with similar but incompatible structures
3. **Fragmented configuration systems**
4. **Inconsistent error handling patterns**
5. **Legacy components** that duplicate newer functionality

The iOS architecture demonstrates a cleaner approach with better separation of concerns. The Kotlin implementation would benefit from consolidation to reduce complexity and improve maintainability.

The user's observation of "duplicate STT components" is accurate - there are indeed multiple competing implementations that should be unified into a single, coherent architecture following the successful iOS patterns.
