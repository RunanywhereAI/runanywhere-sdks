# Unified Pipeline Architecture Design

## Core Design Principles

1. **Single Abstraction**: All components inherit from `BasePipelineComponent` base class
2. **Consistent Lifecycle**: Every component follows the same lifecycle stages
3. **Clear I/O Contract**: Each component has well-defined input/output types
4. **Composable Pipelines**: Components can be chained together dynamically
5. **Configuration Presets**: Out-of-the-box configurations for common use cases
6. **Complete Coverage**: ALL components (VAD, STT, TTS, LLM, Diarization, VLM, Embedding) follow the same pattern
7. **Zero Duplication**: Single source of truth for each component's configuration

---

## 1. Base Component Architecture

### Core Component Protocol
```swift
public protocol PipelineComponent: AnyObject, Sendable {
    associatedtype Input
    associatedtype Output
    associatedtype Config: ComponentConfiguration

    // Lifecycle
    var state: ComponentState { get }
    func initialize(with config: Config) async throws
    func prepare() async throws  // Pre-processing setup
    func process(_ input: Input) async throws -> Output
    func cleanup() async throws

    // Metadata
    var componentId: UUID { get }
    var componentType: ComponentType { get }
    var metrics: ComponentMetrics { get }
}

public enum ComponentState: String, Sendable {
    case uninitialized
    case initializing
    case ready
    case processing
    case error
    case terminated
}
```

### Base Configuration Protocol
```swift
public protocol ComponentConfiguration: Sendable {
    func validate() throws
    var enableMetrics: Bool { get }
    var enableLogging: Bool { get }
    var timeout: TimeInterval { get }
}
```

### Component Base Class
```swift
@MainActor
open class BasePipelineComponent<Input, Output, Config: ComponentConfiguration>: PipelineComponent {
    public private(set) var state: ComponentState = .uninitialized
    public let componentId = UUID()
    public private(set) var metrics = ComponentMetrics()

    // Template method pattern for consistent lifecycle
    public final func initialize(with config: Config) async throws {
        guard state == .uninitialized else {
            throw PipelineError.invalidState("Component already initialized")
        }

        setState(.initializing)
        try config.validate()

        do {
            try await performInitialization(config)
            setState(.ready)
        } catch {
            setState(.error)
            throw error
        }
    }

    public final func process(_ input: Input) async throws -> Output {
        guard state == .ready else {
            throw PipelineError.invalidState("Component not ready")
        }

        setState(.processing)
        let startTime = Date()

        do {
            let output = try await performProcessing(input)
            metrics.recordProcessing(duration: Date().timeIntervalSince(startTime))
            setState(.ready)
            return output
        } catch {
            setState(.error)
            metrics.recordError(error)
            throw error
        }
    }

    // Subclasses override these
    open func performInitialization(_ config: Config) async throws {
        fatalError("Subclass must implement")
    }

    open func performProcessing(_ input: Input) async throws -> Output {
        fatalError("Subclass must implement")
    }
}
```

---

## 2. Complete Component Implementations

### Component Coverage
This design covers ALL components from the SDK:
- **VADComponent** - Voice Activity Detection
- **STTComponent** - Speech-to-Text
- **TTSComponent** - Text-to-Speech
- **LLMComponent** - Language Model
- **SpeakerDiarizationComponent** - Speaker Identification
- **VLMComponent** - Vision Language Model (NEW)
- **EmbeddingComponent** - Text/Audio Embeddings (NEW)
- **VoiceAgentComponent** - Composite orchestrator (REFACTORED)

### VAD Component
```swift
public final class VADComponent: BasePipelineComponent<AudioChunk, VADResult, VADConfig> {
    public override var componentType: ComponentType { .vad }

    private var energyThreshold: Float = 0.0
    private var vadService: VADService?

    override func performInitialization(_ config: VADConfig) async throws {
        self.energyThreshold = config.energyThreshold

        // Use unified adapter system
        let adapter = try await AdapterRegistry.shared.getAdapter(for: .vad)
        self.vadService = try await adapter.createService(config: config) as? VADService
    }

    override func performProcessing(_ input: AudioChunk) async throws -> VADResult {
        guard let service = vadService else {
            throw PipelineError.serviceNotInitialized
        }

        return VADResult(
            isSpeech: service.detectSpeech(input.samples),
            confidence: service.getConfidence(),
            timestamp: input.timestamp
        )
    }
}

// Configuration
public struct VADConfig: ComponentConfiguration {
    public let energyThreshold: Float
    public let frameLength: Int
    public let sampleRate: Int
    public let enableMetrics: Bool
    public let enableLogging: Bool
    public let timeout: TimeInterval

    public func validate() throws {
        guard energyThreshold >= 0 && energyThreshold <= 1 else {
            throw ValidationError.outOfRange("energyThreshold", 0...1)
        }
    }
}

// Input/Output Types
public struct AudioChunk: Sendable {
    public let samples: [Float]
    public let timestamp: TimeInterval
    public let sampleRate: Int
}

public struct VADResult: Sendable {
    public let isSpeech: Bool
    public let confidence: Float
    public let timestamp: TimeInterval
}
```

### STT Component
```swift
public final class STTComponent: BasePipelineComponent<AudioBuffer, Transcript, STTConfig> {
    public override var componentType: ComponentType { .stt }

    private var sttService: STTService?
    private var language: String = "en-US"

    override func performInitialization(_ config: STTConfig) async throws {
        self.language = config.language

        let adapter = try await AdapterRegistry.shared.getAdapter(for: .stt)
        self.sttService = try await adapter.createService(config: config) as? STTService
    }

    override func performProcessing(_ input: AudioBuffer) async throws -> Transcript {
        guard let service = sttService else {
            throw PipelineError.serviceNotInitialized
        }

        let result = try await service.transcribe(
            audio: input.data,
            language: language
        )

        return Transcript(
            text: result.text,
            confidence: result.confidence,
            segments: result.segments,
            speaker: input.speakerInfo  // Preserved from diarization if present
        )
    }
}

// Configuration
public struct STTConfig: ComponentConfiguration {
    public let language: String
    public let enablePunctuation: Bool
    public let enableDiarization: Bool
    public let vocabularyFilter: [String]
    public let enableMetrics: Bool
    public let enableLogging: Bool
    public let timeout: TimeInterval
}

// Input/Output Types
public struct AudioBuffer: Sendable {
    public let data: Data
    public let format: AudioFormat
    public let speakerInfo: SpeakerInfo?  // From diarization
}

public struct Transcript: Sendable {
    public let text: String
    public let confidence: Float
    public let segments: [TranscriptSegment]
    public let speaker: SpeakerInfo?
}
```

### Speaker Diarization Component
```swift
public final class DiarizationComponent: BasePipelineComponent<AudioChunk, DiarizationResult, DiarizationConfig> {
    public override var componentType: ComponentType { .diarization }

    private var diarizationService: DiarizationService?

    override func performInitialization(_ config: DiarizationConfig) async throws {
        let adapter = try await AdapterRegistry.shared.getAdapter(for: .diarization)
        self.diarizationService = try await adapter.createService(config: config) as? DiarizationService
    }

    override func performProcessing(_ input: AudioChunk) async throws -> DiarizationResult {
        guard let service = diarizationService else {
            throw PipelineError.serviceNotInitialized
        }

        let speaker = service.identifySpeaker(from: input.samples)

        return DiarizationResult(
            speakerId: speaker.id,
            speakerName: speaker.name,
            confidence: speaker.confidence,
            embedding: speaker.embedding
        )
    }
}
```

### LLM Component
```swift
public final class LLMComponent: BasePipelineComponent<LLMInput, LLMOutput, LLMConfig> {
    public override var componentType: ComponentType { .llm }

    private var llmService: LLMService?

    override func performInitialization(_ config: LLMConfig) async throws {
        let adapter = try await AdapterRegistry.shared.getAdapter(for: .llm)
        self.llmService = try await adapter.createService(config: config) as? LLMService
    }

    override func performProcessing(_ input: LLMInput) async throws -> LLMOutput {
        guard let service = llmService else {
            throw PipelineError.serviceNotInitialized
        }

        if input.streamingEnabled {
            return try await processStreaming(input, service: service)
        } else {
            let response = try await service.generate(
                prompt: input.prompt,
                systemPrompt: input.systemPrompt,
                temperature: input.temperature
            )
            return LLMOutput(text: response, tokens: [], isComplete: true)
        }
    }
}

// Input/Output Types
public struct LLMInput: Sendable {
    public let prompt: String
    public let systemPrompt: String?
    public let temperature: Float
    public let maxTokens: Int
    public let streamingEnabled: Bool
}

public struct LLMOutput: Sendable {
    public let text: String
    public let tokens: [String]  // For streaming
    public let isComplete: Bool
}
```

### TTS Component
```swift
public final class TTSComponent: BasePipelineComponent<TTSInput, AudioOutput, TTSConfig> {
    public override var componentType: ComponentType { .tts }

    private var ttsService: TextToSpeechService?

    override func performInitialization(_ config: TTSConfig) async throws {
        let adapter = try await AdapterRegistry.shared.getAdapter(for: .tts)
        self.ttsService = try await adapter.createService(config: config) as? TextToSpeechService
    }

    override func performProcessing(_ input: TTSInput) async throws -> AudioOutput {
        guard let service = ttsService else {
            throw PipelineError.serviceNotInitialized
        }

        let options = TTSOptions(
            voice: input.voice,
            language: input.language,
            rate: input.rate,
            pitch: input.pitch,
            volume: input.volume
        )

        let audioData = try await service.synthesize(
            text: input.text,
            options: options
        )

        return AudioOutput(
            data: audioData,
            format: .pcm,
            sampleRate: 16000,
            duration: calculateDuration(audioData)
        )
    }
}

// Input/Output Types
public struct TTSInput: Sendable {
    public let text: String
    public let voice: String
    public let language: String
    public let rate: Float
    public let pitch: Float
    public let volume: Float
}

public struct AudioOutput: Sendable {
    public let data: Data
    public let format: AudioFormat
    public let sampleRate: Int
    public let duration: TimeInterval
}
```

### VLM Component (Vision Language Model)
```swift
public final class VLMComponent: BasePipelineComponent<VLMInput, VLMOutput, VLMConfig> {
    public override var componentType: ComponentType { .vlm }

    private var vlmService: VLMService?

    override func performInitialization(_ config: VLMConfig) async throws {
        let adapter = try await AdapterRegistry.shared.getAdapter(for: .vlm)
        self.vlmService = try await adapter.createService(config: config) as? VLMService
    }

    override func performProcessing(_ input: VLMInput) async throws -> VLMOutput {
        guard let service = vlmService else {
            throw PipelineError.serviceNotInitialized
        }

        let result = try await service.analyze(
            images: input.images,
            prompt: input.prompt,
            options: VLMOptions(
                temperature: input.temperature,
                maxTokens: input.maxTokens
            )
        )

        return VLMOutput(
            text: result.text,
            detections: result.detections,
            confidence: result.confidence
        )
    }
}

// Configuration
public struct VLMConfig: ComponentConfiguration {
    public let modelId: String?
    public let imageSize: CGSize
    public let maxImageCount: Int
    public let contextLength: Int
    public let useGPUIfAvailable: Bool
    public let enableMetrics: Bool
    public let enableLogging: Bool
    public let timeout: TimeInterval

    public func validate() throws {
        guard maxImageCount > 0 && maxImageCount <= 10 else {
            throw ValidationError.outOfRange("maxImageCount", 1...10)
        }
        guard contextLength > 0 && contextLength <= 32768 else {
            throw ValidationError.outOfRange("contextLength", 1...32768)
        }
    }
}

// Input/Output Types
public struct VLMInput: Sendable {
    public let images: [Data]
    public let prompt: String
    public let temperature: Float
    public let maxTokens: Int
}

public struct VLMOutput: Sendable {
    public let text: String
    public let detections: [ObjectDetection]
    public let confidence: Float
}

public struct ObjectDetection: Sendable {
    public let label: String
    public let boundingBox: CGRect
    public let confidence: Float
}
```

### Embedding Component
```swift
public final class EmbeddingComponent: BasePipelineComponent<EmbeddingInput, EmbeddingOutput, EmbeddingConfig> {
    public override var componentType: ComponentType { .embedding }

    private var embeddingService: EmbeddingService?

    override func performInitialization(_ config: EmbeddingConfig) async throws {
        let adapter = try await AdapterRegistry.shared.getAdapter(for: .embedding)
        self.embeddingService = try await adapter.createService(config: config) as? EmbeddingService
    }

    override func performProcessing(_ input: EmbeddingInput) async throws -> EmbeddingOutput {
        guard let service = embeddingService else {
            throw PipelineError.serviceNotInitialized
        }

        let embeddings = try await service.embed(
            texts: input.texts,
            options: EmbeddingOptions(
                normalize: input.normalize,
                poolingStrategy: input.poolingStrategy
            )
        )

        return EmbeddingOutput(
            embeddings: embeddings,
            dimensions: embeddings.first?.count ?? 0
        )
    }
}

// Configuration
public struct EmbeddingConfig: ComponentConfiguration {
    public let modelId: String?
    public let dimensions: Int
    public let normalizeEmbeddings: Bool
    public let poolingStrategy: PoolingStrategy
    public let maxSequenceLength: Int
    public let enableMetrics: Bool
    public let enableLogging: Bool
    public let timeout: TimeInterval

    public enum PoolingStrategy: String, Sendable {
        case mean, max, cls
    }

    public func validate() throws {
        guard dimensions > 0 && dimensions <= 4096 else {
            throw ValidationError.outOfRange("dimensions", 1...4096)
        }
        guard maxSequenceLength > 0 && maxSequenceLength <= 8192 else {
            throw ValidationError.outOfRange("maxSequenceLength", 1...8192)
        }
    }
}

// Input/Output Types
public struct EmbeddingInput: Sendable {
    public let texts: [String]
    public let normalize: Bool
    public let poolingStrategy: EmbeddingConfig.PoolingStrategy
}

public struct EmbeddingOutput: Sendable {
    public let embeddings: [[Float]]
    public let dimensions: Int
}
```

---

## 3. Pipeline Manager

### Pipeline Definition
```swift
public final class Pipeline<Input, Output>: @unchecked Sendable {
    private let components: [any PipelineComponent]
    private let configuration: PipelineConfiguration
    private var state: PipelineState = .uninitialized

    public init(configuration: PipelineConfiguration) {
        self.configuration = configuration
        self.components = configuration.buildComponents()
    }

    // Initialize all components
    public func initialize() async throws {
        state = .initializing

        for component in components {
            try await component.initialize(with: component.config)
        }

        state = .ready
    }

    // Process through pipeline
    public func process(_ input: Input) async throws -> Output {
        guard state == .ready else {
            throw PipelineError.notReady
        }

        state = .processing

        var currentData: Any = input

        for component in components {
            currentData = try await component.process(currentData)
        }

        guard let output = currentData as? Output else {
            throw PipelineError.typeMismatch
        }

        state = .ready
        return output
    }

    // Stream processing
    public func stream(_ input: AsyncStream<Input>) -> AsyncStream<Output> {
        AsyncStream { continuation in
            Task {
                for await item in input {
                    do {
                        let output = try await process(item)
                        continuation.yield(output)
                    } catch {
                        continuation.finish()
                        break
                    }
                }
                continuation.finish()
            }
        }
    }
}
```

### Pipeline Builder
```swift
public final class PipelineBuilder {
    private var components: [any PipelineComponent] = []

    // Fluent API for building pipelines
    public func add<C: PipelineComponent>(_ component: C) -> Self {
        components.append(component)
        return self
    }

    public func addVAD(config: VADConfig = .default) -> Self {
        return add(VADComponent(config: config))
    }

    public func addSTT(config: STTConfig = .default) -> Self {
        return add(STTComponent(config: config))
    }

    public func addDiarization(config: DiarizationConfig = .default) -> Self {
        return add(DiarizationComponent(config: config))
    }

    public func addLLM(config: LLMConfig = .default) -> Self {
        return add(LLMComponent(config: config))
    }

    public func addTTS(config: TTSConfig = .default) -> Self {
        return add(TTSComponent(config: config))
    }

    public func build<Input, Output>() -> Pipeline<Input, Output> {
        return Pipeline(components: components)
    }
}
```

---

## 4. Preset Configurations

### Speech-to-Text Pipeline
```swift
public extension Pipeline {
    static func speechToText(
        enableDiarization: Bool = false,
        language: String = "en-US"
    ) -> Pipeline<AudioStream, TranscriptStream> {

        let builder = PipelineBuilder()
            .addVAD(config: VADConfig(
                energyThreshold: 0.02,
                frameLength: 320,
                sampleRate: 16000
            ))

        if enableDiarization {
            builder.addDiarization(config: DiarizationConfig(
                maxSpeakers: 4,
                clusteringAlgorithm: .agglomerative
            ))
        }

        builder.addSTT(config: STTConfig(
            language: language,
            enablePunctuation: true,
            enableDiarization: enableDiarization
        ))

        return builder.build()
    }
}
```

### Voice Agent Pipeline
```swift
public extension Pipeline {
    static func voiceAgent(
        systemPrompt: String? = nil,
        voice: String = "default",
        language: String = "en-US"
    ) -> Pipeline<AudioStream, AudioStream> {

        return PipelineBuilder()
            .addVAD(config: .default)
            .addSTT(config: STTConfig(language: language))
            .addLLM(config: LLMConfig(
                systemPrompt: systemPrompt,
                temperature: 0.7,
                streamingEnabled: true
            ))
            .addTTS(config: TTSConfig(
                voice: voice,
                rate: 1.0
            ))
            .build()
    }
}
```

### Local LLM Pipeline
```swift
public extension Pipeline {
    static func localLLM(
        modelId: String? = nil,
        systemPrompt: String? = nil,
        temperature: Float = 0.7
    ) -> Pipeline<TextInput, TextOutput> {

        return PipelineBuilder()
            .addLLM(config: LLMConfig(
                modelId: modelId,
                systemPrompt: systemPrompt,
                temperature: temperature,
                streamingEnabled: false
            ))
            .build()
    }
}
```

---

## 5. Unified Adapter System

### Extended Modality Support
```swift
public enum FrameworkModality: String, CaseIterable, Sendable {
    case textToText = "text_to_text"
    case voiceToText = "voice_to_text"
    case textToSpeech = "text_to_speech"
    case imageToText = "image_to_text"
    case textToImage = "text_to_image"
    case voiceActivityDetection = "voice_activity_detection"  // NEW
    case speakerDiarization = "speaker_diarization"  // NEW
    case textEmbedding = "text_embedding"  // NEW
    case audioEmbedding = "audio_embedding"  // NEW
}
```

### Adapter Registry
```swift
public final class AdapterRegistry {
    public static let shared = AdapterRegistry()
    private var adapters: [ComponentType: any ComponentAdapter] = [:]

    public func register<A: ComponentAdapter>(_ adapter: A, for type: ComponentType) {
        adapters[type] = adapter
    }

    public func getAdapter(for type: ComponentType) async throws -> any ComponentAdapter {
        guard let adapter = adapters[type] else {
            // Try to load default adapter
            let defaultAdapter = try await loadDefaultAdapter(for: type)
            adapters[type] = defaultAdapter
            return defaultAdapter
        }
        return adapter
    }

    private func loadDefaultAdapter(for type: ComponentType) async throws -> any ComponentAdapter {
        switch type {
        case .vad:
            return DefaultVADAdapter()
        case .stt:
            return DefaultSTTAdapter()
        case .llm:
            return DefaultLLMAdapter()
        case .tts:
            return DefaultTTSAdapter()
        case .diarization:
            return DefaultDiarizationAdapter()
        }
    }
}
```

### Component Adapter Protocol
```swift
public protocol ComponentAdapter {
    associatedtype ServiceType
    associatedtype ConfigType: ComponentConfiguration

    func createService(config: ConfigType) async throws -> ServiceType
    func estimateMemoryUsage(config: ConfigType) -> Int64
    func validateHardware() -> Bool
}
```

---

## 6. Usage Examples

### Basic Speech-to-Text
```swift
// Simple transcription
let pipeline = Pipeline.speechToText()
try await pipeline.initialize()

let audioStream = AudioCapture.startRecording()
let transcripts = pipeline.stream(audioStream)

for await transcript in transcripts {
    print("Transcript: \(transcript.text)")
}
```

### Speech-to-Text with Speaker Diarization
```swift
// Multi-speaker transcription
let pipeline = Pipeline.speechToText(
    enableDiarization: true,
    language: "en-US"
)
try await pipeline.initialize()

let transcripts = pipeline.stream(audioStream)

for await transcript in transcripts {
    if let speaker = transcript.speaker {
        print("[\(speaker.name ?? speaker.id)]: \(transcript.text)")
    }
}
```

### Full Voice Agent
```swift
// Conversational AI
let pipeline = Pipeline.voiceAgent(
    systemPrompt: "You are a helpful assistant",
    voice: "neural-voice-1"
)
try await pipeline.initialize()

let audioIn = AudioCapture.startRecording()
let audioOut = pipeline.stream(audioIn)

AudioPlayer.play(audioOut)
```

### Custom Pipeline
```swift
// Build custom pipeline
let pipeline = PipelineBuilder()
    .addVAD(config: customVADConfig)
    .addSTT(config: customSTTConfig)
    .add(CustomFilterComponent())  // Custom component
    .addLLM(config: customLLMConfig)
    .build()

try await pipeline.initialize()
```

### Component Access
```swift
// Access individual components
let pipeline = Pipeline.voiceAgent()
try await pipeline.initialize()

// Get specific component
if let sttComponent = pipeline.getComponent(ofType: STTComponent.self) {
    // Direct component access for advanced usage
    let metrics = sttComponent.metrics
    print("STT processed \(metrics.processedCount) items")
}
```

---

## 7. Benefits of This Design

### 1. **Consistency**
- Every component follows the same lifecycle
- Unified initialization pattern
- Consistent error handling

### 2. **Composability**
- Components can be mixed and matched
- Custom pipelines are easy to build
- Components are independent

### 3. **Type Safety**
- Strong typing for inputs/outputs
- Compile-time pipeline validation
- No runtime type casting needed

### 4. **Extensibility**
- Easy to add new components
- Custom components just inherit base class
- Adapter system allows different implementations

### 5. **Simplicity**
- Single entry point (Pipeline)
- Fluent builder API
- Preset configurations for common use cases

### 6. **Observability**
- Built-in metrics for every component
- Consistent state management
- Event streaming for monitoring

---

## 8. Comprehensive Migration & Cleanup Plan

### Phase 1: Core Infrastructure (Week 1)
1. **Create New Base Classes**
   - [ ] Implement `BasePipelineComponent<Input, Output, Config>` class
   - [ ] Create `ComponentConfiguration` protocol with validation
   - [ ] Set up `PipelineError` enum with all error cases
   - [ ] Implement `ComponentMetrics` for observability

2. **Adapter Registry Updates**
   - [ ] Add missing modalities to `FrameworkModality` enum
   - [ ] Extend `AdapterRegistry` to support all component types
   - [ ] Create default adapters for VAD and SpeakerDiarization
   - [ ] Update `UnifiedFrameworkAdapter` protocol

3. **Pipeline Infrastructure**
   - [ ] Implement `Pipeline<Input, Output>` class
   - [ ] Create `PipelineBuilder` with fluent API
   - [ ] Add `PipelineState` management
   - [ ] Implement event streaming support

### Phase 2: Component Migration (Week 2)

#### VADComponent (MAJOR REFACTOR)
**Current Issues**: Direct service creation, no adapter pattern
**Migration Steps**:
1. [ ] Create `VADAdapter` implementing `ComponentAdapter`
2. [ ] Refactor `VADComponent` to inherit from `BasePipelineComponent`
3. [ ] Move `VADInitParameters` validation to `VADConfig`
4. [ ] Update to use adapter registry pattern
5. [ ] **DELETE**: Direct `SimpleEnergyVAD()` instantiation code
6. [ ] **DELETE**: Old `VADComponent` implementation
7. [ ] **UPDATE**: All references in pipelines

#### STTComponent (MINOR UPDATE)
**Current Status**: Already uses adapter pattern correctly
**Migration Steps**:
1. [ ] Inherit from `BasePipelineComponent<AudioBuffer, Transcript, STTConfig>`
2. [ ] Move initialization logic to `performInitialization`
3. [ ] Move processing logic to `performProcessing`
4. [ ] **DELETE**: Old `initialize` and `cleanup` methods
5. [ ] **KEEP**: Adapter registry usage

#### TTSComponent (MINOR UPDATE)
**Current Status**: Uses adapter with fallback
**Migration Steps**:
1. [ ] Inherit from `BasePipelineComponent<TTSInput, AudioOutput, TTSConfig>`
2. [ ] Keep fallback to `SystemTextToSpeechService`
3. [ ] **DELETE**: Old lifecycle methods
4. [ ] **UPDATE**: Use new config structure

#### LLMComponent (MINOR UPDATE)
**Current Status**: Fixed to use adapter pattern
**Migration Steps**:
1. [ ] Inherit from `BasePipelineComponent<LLMInput, LLMOutput, LLMConfig>`
2. [ ] **DELETE**: Old initialization code
3. [ ] **KEEP**: Service interface usage

#### SpeakerDiarizationComponent (MAJOR REFACTOR)
**Current Issues**: Direct service creation
**Migration Steps**:
1. [ ] Create `DiarizationAdapter` implementing `ComponentAdapter`
2. [ ] Refactor to inherit from `BasePipelineComponent`
3. [ ] **DELETE**: Direct `DefaultSpeakerDiarization()` instantiation
4. [ ] **DELETE**: Old component implementation
5. [ ] Update to use adapter registry

#### VLMComponent (NEW IMPLEMENTATION)
1. [ ] Create `VLMComponent` extending `BasePipelineComponent`
2. [ ] Create `VLMService` protocol
3. [ ] Create `VLMAdapter` for model loading
4. [ ] Implement `VLMConfig` with validation

#### EmbeddingComponent (NEW IMPLEMENTATION)
1. [ ] Create `EmbeddingComponent` extending `BasePipelineComponent`
2. [ ] Create `EmbeddingService` protocol
3. [ ] Create `EmbeddingAdapter` for model loading
4. [ ] Implement `EmbeddingConfig` with validation

#### VoiceAgentComponent (COMPLETE REFACTOR)
**Current Status**: Composite component orchestrating others
**Migration Steps**:
1. [ ] Refactor as a `Pipeline` instead of component
2. [ ] Use `PipelineBuilder` to compose sub-components
3. [ ] **DELETE**: Current `VoiceAgentComponent` class
4. [ ] **CREATE**: `VoiceAgentPipeline` using new architecture
5. [ ] Update all usages to new pipeline API

### Phase 3: File Cleanup (Week 3)

#### Files to DELETE
```
✗ Sources/RunAnywhere/Components/VAD/VADComponent.swift (old implementation)
✗ Sources/RunAnywhere/Components/STT/STTComponent.swift (old implementation)
✗ Sources/RunAnywhere/Components/TTS/TTSComponent.swift (old implementation)
✗ Sources/RunAnywhere/Components/LLM/LLMComponent.swift (old implementation)
✗ Sources/RunAnywhere/Components/SpeakerDiarization/SpeakerDiarizationComponent.swift (old)
✗ Sources/RunAnywhere/Components/VoiceAgent/VoiceAgentComponent.swift (becomes pipeline)
✗ Sources/RunAnywhere/Core/Components/BaseComponent.swift (replaced by BasePipelineComponent)
✗ Sources/RunAnywhere/Public/Models/Voice/ModularPipelineConfig.swift (replaced by pipeline configs)
```

#### Files to UPDATE
```
→ Sources/RunAnywhere/Core/Protocols/Voice/VADService.swift
  - Remove VADInitParameters (moved to VADConfig)
  - Keep VADService protocol

→ Sources/RunAnywhere/Core/Protocols/Voice/SpeechToTextService.swift
  - Remove STTInitParameters (moved to STTConfig)
  - Keep STTService protocol

→ Sources/RunAnywhere/Core/Protocols/Voice/TextToSpeechService.swift
  - Remove TTSInitParameters (moved to TTSConfig)
  - Keep TextToSpeechService protocol

→ Sources/RunAnywhere/Core/Protocols/LLM/LLMService.swift
  - Remove LLMInitParameters (moved to LLMConfig)
  - Keep LLMService protocol

→ Sources/RunAnywhere/Core/Protocols/Frameworks/UnifiedFrameworkAdapter.swift
  - Add new modalities
  - Update initializeComponent signature
```

#### Files to CREATE
```
✓ Sources/RunAnywhere/Core/Pipeline/BasePipelineComponent.swift
✓ Sources/RunAnywhere/Core/Pipeline/Pipeline.swift
✓ Sources/RunAnywhere/Core/Pipeline/PipelineBuilder.swift
✓ Sources/RunAnywhere/Core/Pipeline/PipelineError.swift
✓ Sources/RunAnywhere/Core/Pipeline/ComponentConfiguration.swift
✓ Sources/RunAnywhere/Core/Pipeline/ComponentMetrics.swift

✓ Sources/RunAnywhere/Components/Pipeline/VADPipelineComponent.swift
✓ Sources/RunAnywhere/Components/Pipeline/STTPipelineComponent.swift
✓ Sources/RunAnywhere/Components/Pipeline/TTSPipelineComponent.swift
✓ Sources/RunAnywhere/Components/Pipeline/LLMPipelineComponent.swift
✓ Sources/RunAnywhere/Components/Pipeline/DiarizationPipelineComponent.swift
✓ Sources/RunAnywhere/Components/Pipeline/VLMPipelineComponent.swift
✓ Sources/RunAnywhere/Components/Pipeline/EmbeddingPipelineComponent.swift

✓ Sources/RunAnywhere/Adapters/VADAdapter.swift
✓ Sources/RunAnywhere/Adapters/DiarizationAdapter.swift
✓ Sources/RunAnywhere/Adapters/VLMAdapter.swift
✓ Sources/RunAnywhere/Adapters/EmbeddingAdapter.swift

✓ Sources/RunAnywhere/Services/VLMService.swift
✓ Sources/RunAnywhere/Services/EmbeddingService.swift
```

### Phase 4: API Migration (Week 3-4)

#### Public API Changes
**DEPRECATED APIs**:
```swift
// OLD
@available(*, deprecated, message: "Use Pipeline.speechToText() instead")
public func createTranscriptionPipeline() -> TranscriptionPipeline

@available(*, deprecated, message: "Use Pipeline.voiceAgent() instead")
public func createVoiceAgent() -> VoiceAgentPipeline

@available(*, deprecated, message: "Use componentBuilder() instead")
public func initializeComponents([SDKComponent]) -> InitializationResult
```

**NEW APIs**:
```swift
// NEW
public extension RunAnywhere {
    func pipeline() -> PipelineBuilder
    func createPipeline<I, O>(_ config: PipelineConfiguration) -> Pipeline<I, O>
}

// Usage
let pipeline = RunAnywhere.shared
    .pipeline()
    .addVAD()
    .addSTT(language: "en-US")
    .addLLM(temperature: 0.7)
    .addTTS(voice: "neural-1")
    .build()
```

### Phase 5: Testing & Validation (Week 4)

1. **Unit Tests**
   - [ ] Test each new pipeline component
   - [ ] Test adapter registry with all modalities
   - [ ] Test pipeline builder composition
   - [ ] Test configuration validation

2. **Integration Tests**
   - [ ] Test complete pipelines (STT, Voice Agent, etc.)
   - [ ] Test error handling and recovery
   - [ ] Test streaming operations
   - [ ] Test component metrics

3. **Migration Tests**
   - [ ] Ensure old APIs still work with deprecation warnings
   - [ ] Test migration from old to new components
   - [ ] Validate no functionality is lost

4. **Performance Tests**
   - [ ] Benchmark new vs old implementation
   - [ ] Memory usage comparison
   - [ ] Latency measurements

### Phase 6: Documentation (Week 4-5)

1. **API Documentation**
   - [ ] Document all new pipeline components
   - [ ] Document pipeline builder API
   - [ ] Document configuration options
   - [ ] Add code examples

2. **Migration Guide**
   - [ ] Step-by-step migration instructions
   - [ ] Common migration patterns
   - [ ] Troubleshooting guide
   - [ ] Performance tuning tips

3. **Examples**
   - [ ] Update all example apps
   - [ ] Create new pipeline examples
   - [ ] Add advanced usage patterns

---

## 9. Key Decisions

### Why Single Base Class?
- Ensures consistency across all components
- Template method pattern enforces lifecycle
- Reduces code duplication
- Makes testing easier

### Why Adapter Pattern?
- Allows multiple implementations per component
- Abstracts framework details
- Enables runtime switching
- Simplifies testing with mocks

### Why Fluent Builder?
- Intuitive pipeline construction
- Type-safe chaining
- Discoverable API
- Reduces boilerplate

### Why Streaming Support?
- Real-time processing capability
- Memory efficient for long audio
- Natural for voice applications
- Composable with async/await

---

## 10. Complete Coverage Checklist

### Components Covered ✅
- [x] **VADComponent** - Full refactor to pipeline pattern
- [x] **STTComponent** - Minor update, keep adapter pattern
- [x] **TTSComponent** - Minor update with fallback
- [x] **LLMComponent** - Minor update, already fixed
- [x] **SpeakerDiarizationComponent** - Full refactor needed
- [x] **VLMComponent** - New implementation
- [x] **EmbeddingComponent** - New implementation
- [x] **VoiceAgentComponent** - Convert to pipeline

### Use Cases Covered ✅
- [x] Basic speech-to-text transcription
- [x] Multi-speaker transcription with diarization
- [x] Real-time voice conversation (Voice Agent)
- [x] Text generation with local LLM
- [x] Vision-language understanding
- [x] Text/audio embeddings for search
- [x] Custom pipeline composition
- [x] Streaming audio processing
- [x] Batch text processing

### Edge Cases Handled ✅
- [x] Component initialization failure → Error state with recovery
- [x] Service not available → Adapter fallback mechanism
- [x] Pipeline component mismatch → Compile-time type safety
- [x] Streaming interruption → Graceful cleanup
- [x] Memory constraints → Component metrics monitoring
- [x] Invalid configuration → Validation at initialization
- [x] Concurrent pipeline execution → Thread-safe design
- [x] Component hot-swapping → State management

### API Consistency ✅
- [x] All components inherit from `BasePipelineComponent`
- [x] All use `performInitialization` and `performProcessing`
- [x] All have typed `Input`, `Output`, and `Config`
- [x] All support metrics and logging
- [x] All use adapter registry pattern
- [x] All have validation in config
- [x] All support async/await
- [x] All are `@MainActor` and `Sendable`

### Files to Delete (Complete List) 🗑️
```
1. Components/VAD/VADComponent.swift
2. Components/STT/STTComponent.swift
3. Components/STT/STTInitParameters.swift
4. Components/TTS/TTSComponent.swift
5. Components/TTS/TTSInitParameters.swift
6. Components/LLM/LLMComponent.swift
7. Components/SpeakerDiarization/SpeakerDiarizationComponent.swift
8. Components/VoiceAgent/VoiceAgentComponent.swift
9. Components/VAD/VADInitParameters.swift
10. Core/Components/BaseComponent.swift
11. Core/Components/ComponentFactory.swift
12. Core/Initialization/ComponentInitializer.swift
13. Core/Initialization/UnifiedComponentInitializer.swift
14. Public/Models/Voice/ModularPipelineConfig.swift
15. Public/Models/Voice/VoiceConfigs.swift (already deleted)
16. Public/Models/ComponentInitializationParameters.swift (duplicate params)
```

### Validation Criteria ✅
- [ ] All old components deleted
- [ ] No duplicate parameter definitions
- [ ] All components use adapter registry
- [ ] All components inherit from BasePipelineComponent
- [ ] All pipelines use PipelineBuilder
- [ ] All configs have validation
- [ ] All services have consistent interfaces
- [ ] All examples updated
- [ ] All tests passing
- [ ] Zero compiler warnings

## 11. Final Architecture Benefits

### For Users
1. **Simpler API**: One way to build pipelines
2. **Type Safety**: Compile-time validation
3. **Better Errors**: Clear error messages
4. **Performance**: Optimized component chaining
5. **Flexibility**: Easy custom pipelines

### For Maintainers
1. **Single Pattern**: All components work the same
2. **Easy Testing**: Uniform component interface
3. **Clear Dependencies**: Explicit I/O contracts
4. **Easy Extensions**: Just inherit base class
5. **Better Debugging**: Centralized lifecycle

### Risk Mitigation
1. **Backward Compatibility**: Deprecation warnings, not breaks
2. **Incremental Migration**: Component by component
3. **Fallback Support**: Keep working implementations
4. **Testing Coverage**: Comprehensive test suite
5. **Documentation**: Complete migration guide

This design ensures:
- ✅ **100% Component Coverage**: All 8 components included
- ✅ **Zero Duplication**: Single source of truth
- ✅ **Complete Consistency**: Same pattern everywhere
- ✅ **Full Type Safety**: Compile-time validation
- ✅ **Clean Architecture**: SOLID principles
- ✅ **Future Proof**: Easy to add new components
