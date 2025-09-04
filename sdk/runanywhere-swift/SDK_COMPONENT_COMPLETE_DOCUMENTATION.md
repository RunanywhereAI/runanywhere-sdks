# RunAnywhere SDK - Complete Component Architecture Documentation

## Table of Contents
1. [Architecture Overview](#architecture-overview)
2. [Core Infrastructure](#core-infrastructure)
3. [Component Deep Dive](#component-deep-dive)
   - [WakeWordComponent](#1-wakewordcomponent)
   - [VADComponent](#2-vadcomponent)
   - [STTComponent](#3-sttcomponent)
   - [TTSComponent](#4-ttscomponent)
   - [LLMComponent](#5-llmcomponent)
   - [SpeakerDiarizationComponent](#6-speakerdiarizationcomponent)
   - [VLMComponent](#7-vlmcomponent)
4. [Pipeline Architecture](#pipeline-architecture)
5. [Integration Patterns](#integration-patterns)
6. [Event Flow](#event-flow)

---

## Architecture Overview

The RunAnywhere SDK implements a clean, three-layer architecture with a plugin-based module system:

```
┌─────────────────────────────────────────────────────────┐
│                    APPLICATION LAYER                      │
│         (PipelineBuilder, RunAnywhere SDK API)           │
└─────────────────────────────────────────────────────────┘
                            │
┌─────────────────────────────────────────────────────────┐
│                    COMPONENT LAYER                        │
│   WakeWord → VAD → STT → LLM → TTS → Speaker Diarization│
└─────────────────────────────────────────────────────────┘
                            │
┌─────────────────────────────────────────────────────────┐
│                     SERVICE LAYER                         │
│         (Protocol Definitions & Abstractions)            │
└─────────────────────────────────────────────────────────┘
                            │
┌─────────────────────────────────────────────────────────┐
│                 IMPLEMENTATION LAYER                      │
│    (External: WhisperCPP, llama.cpp, FluidAudio, etc)    │
│    (Built-in: SystemTTS, DefaultVAD, etc)               │
└─────────────────────────────────────────────────────────┘
```

## Core Infrastructure

### BaseComponent<TService>

The foundation of all components, providing:
- Lifecycle management (notInitialized → initializing → ready → failed)
- Event publishing through EventBus
- Service container integration
- Thread safety with @MainActor
- Generic type safety with TService constraint

```swift
@MainActor
public class BaseComponent<TService: AnyObject>: Component, @unchecked Sendable {
    // Lifecycle states and management
    private(set) var currentState: ComponentState = .notInitialized

    // Service management
    private(set) var service: TService?

    // Event publishing
    let eventBus = EventBus.shared
}
```

### ModuleRegistry

Central registration system for external implementations:

```swift
@MainActor
public final class ModuleRegistry {
    public static let shared = ModuleRegistry()

    // Provider registration
    private var sttProviders: [STTServiceProvider] = []
    private var llmProviders: [LLMServiceProvider] = []
    // ... other providers

    // Provider access with model matching
    public func sttProvider(for modelId: String?) -> STTServiceProvider?
}
```

---

## Component Deep Dive

### 1. WakeWordComponent

**Purpose**: Detects wake words in audio streams to trigger voice interactions.

#### Service Protocol
```swift
public protocol WakeWordService: AnyObject {
    func initialize() async throws
    func startListening()
    func stopListening()
    func processAudioBuffer(_ buffer: [Float]) -> Bool
    var isListening: Bool { get }
    func cleanup() async
}
```

#### Configuration
```swift
public struct WakeWordConfiguration {
    let modelId: String?              // Optional ML model
    let wakeWords: [String]           // Words to detect
    let sensitivity: Float            // 0.0-1.0
    let bufferSize: Int              // Audio buffer size
    let sampleRate: Int              // Audio sample rate
    let confidenceThreshold: Float   // Detection threshold
    let continuousListening: Bool    // Continue after detection
}
```

#### Input/Output Models
```swift
public struct WakeWordInput {
    let audioBuffer: [Float]         // Audio samples
    let timestamp: TimeInterval?     // Optional timing
}

public struct WakeWordOutput {
    let detected: Bool               // Detection result
    let wakeWord: String?           // Detected word
    let confidence: Float           // Confidence score
    let metadata: WakeWordMetadata  // Processing details
}
```

#### Implementation Details
- **Default**: `DefaultWakeWordService` (returns false, placeholder)
- **External**: Supports external wake word engines via `WakeWordServiceProvider`
- **Events**: Publishes component lifecycle events
- **Pipeline Position**: First in voice pipeline, triggers downstream processing

---

### 2. VADComponent

**Purpose**: Detects voice activity in audio streams to segment speech.

#### Service Protocol
```swift
public protocol VADService: AnyObject {
    func initialize(config: VADConfiguration) async throws
    func processAudio(_ samples: [Float]) async -> VADDecision
    func reset() async
    var isActive: Bool { get }
    func updateThreshold(_ threshold: Float) async
    func getStatistics() async -> VADStatistics
    func cleanup() async
}
```

#### Configuration
```swift
public struct VADConfiguration {
    let modelId: String?
    let energyThreshold: Float      // Energy threshold
    let silenceDuration: TimeInterval // Silence to end speech
    let minSpeechDuration: TimeInterval // Minimum speech length
    let sampleRate: Int
    let frameSize: Int
    let enableNoiseSuppression: Bool
    let adaptiveThreshold: Bool
}
```

#### Input/Output Models
```swift
public struct VADInput {
    let audioBuffer: [Float]
    let timestamp: TimeInterval
    let metadata: VADInputMetadata?
}

public struct VADOutput {
    let decision: VADDecision        // .speech, .silence, .uncertain
    let confidence: Float
    let energy: Float
    let metadata: VADMetadata
}
```

#### Implementation Details
- **Default**: `SimpleEnergyVAD` - Energy-based detection with adaptive thresholds
- **Adapter**: `DefaultVADAdapter` bridges to VADService protocol
- **Features**:
  - Adaptive threshold adjustment
  - Noise floor estimation
  - Speech segment buffering
- **Pipeline Position**: After wake word, before STT

---

### 3. STTComponent

**Purpose**: Converts speech audio to text transcription.

#### Service Protocol
```swift
public protocol STTService: AnyObject {
    func initialize(modelPath: String?) async throws
    func transcribe(audioData: Data, options: STTOptions) async throws -> STTTranscriptionResult
    func streamTranscribe<S: AsyncSequence>(
        audioStream: S,
        options: STTOptions,
        onPartial: @escaping (String) -> Void
    ) async throws -> STTTranscriptionResult where S.Element == Data
    var isReady: Bool { get }
    var currentModel: String? { get }
    func cleanup() async
}
```

#### Configuration
```swift
public struct STTConfiguration {
    let modelId: String?
    let language: String
    let sampleRate: Int
    let enablePunctuation: Bool
    let enableDiarization: Bool
    let maxAlternatives: Int
    let vocabularyFilter: [String]?
    let acousticModelPath: String?
    let languageModelPath: String?
}
```

#### Input/Output Models
```swift
public struct STTInput {
    let audioData: Data              // Audio bytes
    let language: String?            // Target language
    let options: STTOptions?         // Override options
}

public struct STTOutput {
    let text: String                 // Transcribed text
    let confidence: Float            // Overall confidence
    let wordTimestamps: [WordTimestamp]? // Word timings
    let detectedLanguage: String?   // Auto-detected language
    let alternatives: [TranscriptionAlternative]? // Alternative transcriptions
    let metadata: TranscriptionMetadata
}
```

#### Implementation Details
- **External**: WhisperCPP via `STTServiceProvider`
- **Features**:
  - Multi-language support
  - Word-level timestamps
  - Alternative transcriptions
  - Streaming support with partial results
- **Events**: Download progress for model files
- **Pipeline Position**: After VAD, before LLM

---

### 4. TTSComponent

**Purpose**: Converts text to synthesized speech audio.

#### Service Protocol
```swift
public protocol TTSService: AnyObject {
    func initialize() async throws
    func synthesize(text: String, options: TTSOptions) async throws -> Data
    func synthesizeStream(
        text: String,
        options: TTSOptions,
        onChunk: @escaping (Data) -> Void
    ) async throws
    func stop()
    var isSynthesizing: Bool { get }
    var availableVoices: [String] { get }
    func cleanup() async
}
```

#### Configuration
```swift
public struct TTSConfiguration {
    let modelId: String?
    let voice: String?               // Voice selection
    let language: String
    let speakingRate: Float         // Speed (0.5-2.0)
    let pitch: Float                // Pitch adjustment
    let volume: Float               // Volume (0.0-1.0)
    let audioFormat: AudioFormat
    let enableSSML: Bool            // SSML support
}
```

#### Input/Output Models
```swift
public struct TTSInput {
    let text: String                // Text to synthesize
    let voice: String?              // Override voice
    let options: TTSOptions?        // Override options
}

public struct TTSOutput {
    let audioData: Data             // Synthesized audio
    let duration: TimeInterval      // Audio duration
    let metadata: TTSMetadata       // Synthesis details
}
```

#### Implementation Details
- **Built-in**: `SystemTTSService` using AVSpeechSynthesizer
- **Features**:
  - Multiple voice support
  - Rate/pitch/volume control
  - SSML parsing (if enabled)
  - Streaming synthesis
- **Pipeline Position**: After LLM, final output stage

---

### 5. LLMComponent

**Purpose**: Generates text responses using language models.

#### Service Protocol
```swift
public protocol LLMService: AnyObject {
    func initialize(modelPath: String?) async throws
    func generate(prompt: String, options: RunAnywhereGenerationOptions) async throws -> String
    func streamGenerate(
        prompt: String,
        options: RunAnywhereGenerationOptions,
        onToken: @escaping (String) -> Void
    ) async throws
    var isReady: Bool { get }
    var currentModel: String? { get }
    func cleanup() async
}
```

#### Configuration
```swift
public struct LLMConfiguration {
    let modelId: String?
    let contextLength: Int          // Max context tokens
    let useGPUIfAvailable: Bool
    let quantizationLevel: QuantizationLevel?
    let cacheSize: Int              // Token cache size
    let preloadContext: String?     // System prompt
    let temperature: Double
    let maxTokens: Int
    let systemPrompt: String?
    let streamingEnabled: Bool
}
```

#### Input/Output Models
```swift
public struct LLMInput {
    let messages: [Message]         // Conversation history
    let systemPrompt: String?       // Override system prompt
    let context: Context?           // Additional context
    let options: RunAnywhereGenerationOptions?
}

public struct LLMOutput {
    let text: String                // Generated text
    let tokenUsage: TokenUsage      // Token statistics
    let metadata: GenerationMetadata
    let finishReason: FinishReason // Why generation stopped
}
```

#### Implementation Details
- **External**: llama.cpp via `LLMServiceProvider`
- **Features**:
  - Context management
  - Token streaming
  - Multiple quantization levels
  - GPU acceleration support
- **Model Loading**: Download progress tracking
- **Pipeline Position**: After STT, before TTS

---

### 6. SpeakerDiarizationComponent

**Purpose**: Identifies and tracks different speakers in audio.

#### Service Protocol
```swift
public protocol SpeakerDiarizationService: AnyObject {
    func initialize() async throws
    func processAudio(_ samples: [Float]) -> SpeakerInfo
    func getAllSpeakers() -> [SpeakerInfo]
    func reset()
    var isReady: Bool { get }
    func cleanup() async
}
```

#### Configuration
```swift
public struct SpeakerDiarizationConfiguration {
    let modelId: String?
    let maxSpeakers: Int            // Max speakers to track
    let minSegmentLength: TimeInterval
    let embeddingDimension: Int
    let clusteringThreshold: Float
}
```

#### Input/Output Models
```swift
public struct SpeakerDiarizationInput {
    let audioBuffer: [Float]
    let timestamp: TimeInterval?
}

public struct SpeakerDiarizationOutput {
    let speakerId: String           // Speaker identifier
    let confidence: Float
    let embedding: [Float]?         // Speaker embedding
    let metadata: DiarizationMetadata
}
```

#### Implementation Details
- **Default**: `DefaultSpeakerDiarization` - Simple energy-based speaker tracking
- **External**: FluidAudioDiarization via provider
- **Features**:
  - Speaker embedding extraction
  - Cosine similarity matching
  - Dynamic speaker discovery
  - Speaker profile management
- **Pipeline Position**: Parallel with STT, enriches transcription

---

### 7. VLMComponent

**Purpose**: Processes images with language models for vision tasks.

#### Service Protocol
```swift
public protocol VLMService: AnyObject {
    func initialize(modelPath: String?) async throws
    func processImage(
        imageData: Data,
        prompt: String,
        options: VLMOptions
    ) async throws -> VLMResult
    var isReady: Bool { get }
    var currentModel: String? { get }
    func cleanup() async
}
```

#### Configuration
```swift
public struct VLMConfiguration {
    let modelId: String?
    let imageSize: CGSize
    let maxImageDimension: Int
    let compressionQuality: Float
    let enableOCR: Bool
    let temperature: Float
    let maxTokens: Int
}
```

#### Input/Output Models
```swift
public struct VLMInput {
    let image: VLMImage             // Image data
    let prompt: String              // Query about image
    let options: VLMOptions?
}

public struct VLMOutput {
    let text: String                // Generated description
    let boundingBoxes: [BoundingBox]? // Object locations
    let labels: [Label]?            // Detected labels
    let metadata: VLMMetadata
}
```

#### Implementation Details
- **Placeholder**: `UnavailableVLMService` - Throws not available
- **External**: Future VLM providers
- **Features**:
  - Image preprocessing
  - OCR support
  - Object detection
  - Scene understanding
- **Pipeline Position**: Alternative to text pipeline for vision tasks

---

## Pipeline Architecture

### Voice Agent Pipeline Flow

```
[Microphone Input]
        ↓
[WakeWordComponent] → Detects activation phrase
        ↓
[VADComponent] → Segments speech from silence
        ↓
[STTComponent] → Transcribes speech to text
        ↓                    ↓
        ↓          [SpeakerDiarization] → Identifies speaker
        ↓                    ↓
[LLMComponent] → Generates response
        ↓
[TTSComponent] → Synthesizes speech
        ↓
[Audio Output]
```

### Pipeline Builder

```swift
public final class PipelineBuilder {
    // Preset pipelines
    func buildTranscriptionPipeline(enableDiarization: Bool) -> TranscriptionPipeline
    func buildVoiceAgentPipeline(llmModel: String) -> VoiceAgentPipeline

    // Custom pipeline composition
    func buildCustomPipeline(components: [SDKComponent]) -> CustomPipeline
}
```

### Pipeline Coordination

- **Event-Driven**: Components communicate through EventBus
- **Stream Processing**: AsyncSequence/AsyncStream for real-time data
- **Error Propagation**: Errors bubble up through pipeline
- **State Management**: Each component tracks its own state

---

## Integration Patterns

### External Module Integration

1. **Implement Service Protocol**
```swift
class WhisperSTTService: STTService {
    // Implement all protocol requirements
}
```

2. **Create Provider**
```swift
struct WhisperSTTProvider: STTServiceProvider {
    func createSTTService(configuration: STTConfiguration) async throws -> STTService {
        return WhisperSTTService(config: configuration)
    }
}
```

3. **Register with ModuleRegistry**
```swift
ModuleRegistry.shared.registerSTT(WhisperSTTProvider())
```

### Component Usage Pattern

```swift
// Configure
let config = STTConfiguration(language: "en-US")

// Create component
let sttComponent = STTComponent(configuration: config)

// Initialize
try await sttComponent.initialize()

// Process
let input = STTInput(audioData: audioData)
let output = try await sttComponent.process(input)
```

---

## Event Flow

### Component Lifecycle Events

```swift
public enum ComponentInitializationEvent {
    case componentChecking(component: SDKComponent, modelId: String?)
    case componentDownloadRequired(component: SDKComponent, modelId: String, sizeBytes: Int64)
    case componentDownloadStarted(component: SDKComponent, modelId: String)
    case componentDownloadProgress(component: SDKComponent, modelId: String, progress: Double)
    case componentDownloadCompleted(component: SDKComponent, modelId: String)
    case componentInitializing(component: SDKComponent, modelId: String?)
    case componentInitialized(component: SDKComponent)
    case componentFailed(component: SDKComponent, error: Error)
}
```

### Pipeline Events

```swift
public enum ModularPipelineEvent {
    // VAD events
    case vadSpeechStart
    case vadSpeechEnd

    // STT events
    case sttPartialResult(String)
    case sttFinalResult(String)
    case sttSpeakerChanged(from: SpeakerInfo?, to: SpeakerInfo)

    // TTS events
    case ttsStarted
    case ttsCompleted

    // LLM events
    case llmProcessingStarted
    case llmTokenGenerated(String)
    case llmProcessingCompleted
}
```

### Event Subscription

```swift
// Subscribe to events
EventBus.shared.subscribe(to: ComponentInitializationEvent.self) { event in
    switch event {
    case .componentInitialized(let component):
        print("\(component) ready")
    case .componentFailed(let component, let error):
        print("\(component) failed: \(error)")
    default:
        break
    }
}
```

---

## Best Practices

### Component Development

1. **Always inherit from BaseComponent<TService>**
2. **Define clear service protocols**
3. **Provide sensible defaults in configurations**
4. **Validate inputs in ComponentInput.validate()**
5. **Publish lifecycle events consistently**
6. **Handle cleanup in performCleanup()**

### Pipeline Construction

1. **Check component readiness before processing**
2. **Handle errors at each stage**
3. **Use streaming APIs for real-time processing**
4. **Monitor events for pipeline health**
5. **Clean up resources when done**

### External Integration

1. **Implement full service protocol**
2. **Support model downloading if needed**
3. **Provide clear provider naming**
4. **Handle initialization failures gracefully**
5. **Support cleanup and resource management**

---

## Conclusion

The RunAnywhere SDK architecture provides a robust, extensible foundation for building AI-powered applications. The component-based design with plugin support enables:

- **Flexibility**: Choose and swap AI implementations
- **Scalability**: Add new components without affecting others
- **Testability**: Mock services for unit testing
- **Maintainability**: Clear separation of concerns
- **Reusability**: Components work independently or in pipelines

The architecture successfully balances simplicity for basic use cases with power for advanced scenarios, making it suitable for a wide range of AI applications.
