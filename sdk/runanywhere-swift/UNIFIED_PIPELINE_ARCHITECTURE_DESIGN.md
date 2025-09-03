# Unified Pipeline Architecture Design

## Core Design Principles

1. **Single Abstraction**: All components inherit from `PipelineComponent` base class
2. **Consistent Lifecycle**: Every component follows the same lifecycle stages
3. **Clear I/O Contract**: Each component has well-defined input/output types
4. **Composable Pipelines**: Components can be chained together dynamically
5. **Configuration Presets**: Out-of-the-box configurations for common use cases

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

## 2. Component Implementations

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

    private var ttsService: TTSService?

    override func performInitialization(_ config: TTSConfig) async throws {
        let adapter = try await AdapterRegistry.shared.getAdapter(for: .tts)
        self.ttsService = try await adapter.createService(config: config) as? TTSService
    }

    override func performProcessing(_ input: TTSInput) async throws -> AudioOutput {
        guard let service = ttsService else {
            throw PipelineError.serviceNotInitialized
        }

        let audioData = try await service.synthesize(
            text: input.text,
            voice: input.voice,
            rate: input.rate
        )

        return AudioOutput(
            data: audioData,
            format: .pcm,
            sampleRate: 16000,
            duration: calculateDuration(audioData)
        )
    }
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

## 8. Migration Plan

### Phase 1: Core Infrastructure
1. Implement `BasePipelineComponent` class
2. Create `ComponentConfiguration` protocol
3. Set up `AdapterRegistry` system
4. Implement `Pipeline` and `PipelineBuilder`

### Phase 2: Component Migration
1. **VADComponent**: Migrate to new base class
2. **STTComponent**: Update to use consistent pattern
3. **DiarizationComponent**: Convert to adapter system
4. **LLMComponent**: Already correct, just inherit new base
5. **TTSComponent**: Update to new pattern

### Phase 3: Cleanup
1. Remove old component implementations
2. Delete duplicate configuration types
3. Update all pipelines to use new system
4. Deprecate old APIs

### Phase 4: Testing & Documentation
1. Unit tests for each component
2. Integration tests for pipelines
3. Update documentation
4. Migration guide for users

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

## 10. Next Steps

1. **Review & Approve Design**: Ensure this meets all requirements
2. **Start with VADComponent**: Implement as reference
3. **Create Tests**: TDD for each component
4. **Incremental Migration**: One component at a time
5. **Documentation**: Update as we go

This design provides:
- ✅ Single abstraction (BasePipelineComponent)
- ✅ Consistent lifecycle management
- ✅ Clear input/output contracts
- ✅ Preset configurations (STT, Voice Agent, LLM)
- ✅ Composable pipelines
- ✅ Clean public APIs
- ✅ Extensibility for custom components
