# RunAnywhere Swift SDK - Public API Reference

## Overview

The RunAnywhere Swift SDK is a comprehensive on-device AI platform providing privacy-first execution with multi-framework support. It offers a unified interface for various ML frameworks including Core ML, MLX, llama.cpp, TensorFlow Lite, ONNX, WhisperKit, and more.

### Key Features

- **Privacy-First Design**: Default device-only routing for maximum privacy
- **Multi-Framework Support**: Unified API across 15+ ML frameworks
- **Multi-Modal Capabilities**: Text generation, voice transcription, structured output
- **Intelligent Model Management**: Automatic discovery, downloading, validation
- **Performance Monitoring**: Real-time analytics, benchmarking, A/B testing
- **Cost Optimization**: Token budget management and savings tracking
- **Thinking/Reasoning Support**: Extract reasoning from models like DeepSeek-R1
- **Streaming Support**: Real-time token streaming for better UX

### Supported Frameworks

- **Text Generation**: Core ML, MLX, llama.cpp, GGUF, ONNX, TensorFlow Lite, ExecuTorch, Swift Transformers, Foundation Models, PicoLLM, MLC, MediaPipe
- **Voice/Audio**: WhisperKit, OpenAI Whisper
- **Custom**: Extensible framework adapter system

## Table of Contents

1. [Getting Started](#getting-started)
2. [SDK Initialization](#sdk-initialization)
3. [Model Management](#model-management)
4. [Text Generation](#text-generation)
5. [Structured Output](#structured-output)
6. [Voice & Audio](#voice--audio)
7. [Configuration Management](#configuration-management)
8. [Analytics & Monitoring](#analytics--monitoring)
9. [Storage Management](#storage-management)
10. [Framework Management](#framework-management)
11. [Error Handling](#error-handling)
12. [Data Types](#data-types)
13. [Advanced Features](#advanced-features)

## Getting Started

### Installation

Add the RunAnywhere SDK to your project using Swift Package Manager:

```swift
dependencies: [
    .package(url: "https://github.com/runanywhere/swift-sdk", from: "1.0.0")
]
```

### Basic Usage

```swift
import RunAnywhere

// Initialize the SDK
let config = Configuration(apiKey: "your-api-key")
try await RunAnywhereSDK.shared.initialize(configuration: config)

// Load a model
let modelInfo = try await RunAnywhereSDK.shared.loadModel("llama-3.2-1b")

// Generate text
let result = try await RunAnywhereSDK.shared.generate(
    prompt: "Hello, how are you?",
    options: GenerationOptions(maxTokens: 100)
)
print(result.text)
```

## SDK Initialization

### initialize(configuration:)

Initializes the SDK with the provided configuration.

```swift
public func initialize(configuration: Configuration) async throws
```

**Parameters:**
- `configuration`: SDK configuration including API key and settings

**Throws:**
- `SDKError.notInitialized`: If initialization fails
- `RunAnywhereError.alreadyInitialized`: If SDK is already initialized
- `RunAnywhereError.invalidConfiguration`: If configuration is invalid

**Example:**
```swift
let config = Configuration(
    apiKey: "your-api-key",
    routingPolicy: .preferDevice,
    privacyMode: .strict,
    enableRealTimeDashboard: true
)

try await RunAnywhereSDK.shared.initialize(configuration: config)
```

### waitForInitialization()

Waits for SDK initialization to complete.

```swift
public func waitForInitialization() async throws
```

**Throws:**
- `SDKError.notInitialized`: If initialization fails

### isInitialized

Check if SDK is initialized.

```swift
public var isInitialized: Bool { get }
```

### registerDownloadStrategy(_:)

Register a custom download strategy for models.

```swift
public func registerDownloadStrategy(_ strategy: DownloadStrategy)
```

**Parameters:**
- `strategy`: Custom download strategy implementation

### Configuration Options

```swift
public struct Configuration {
    // Required
    public let apiKey: String

    // Optional with defaults
    public var baseURL: URL = URL(string: "https://api.runanywhere.ai")!
    public var enableRealTimeDashboard: Bool = true
    public var routingPolicy: RoutingPolicy = .deviceOnly
    public var telemetryConsent: TelemetryConsent = .limited
    public var privacyMode: PrivacyMode = .standard
    public var debugMode: Bool = false
    public var preferredFrameworks: [LLMFramework] = []
    public var hardwarePreferences: HardwareConfiguration? = nil
    public var modelProviders: [ModelProviderConfig] = []
    public var memoryThreshold: Int64 = 500 * 1024 * 1024 // 500MB
    public var downloadConfiguration: DownloadConfig = .default
    public var defaultGenerationSettings: DefaultGenerationSettings = .default
}
```

#### Routing Policies

```swift
public enum RoutingPolicy {
    case automatic           // Auto-determine best execution
    case preferDevice       // Prefer on-device when possible
    case deviceOnly         // ONLY use on-device (default)
    case preferCloud        // Prefer cloud execution
    case custom(rules: [RoutingRule])
}
```

#### Privacy Modes

```swift
public enum PrivacyMode {
    case standard   // Standard privacy protection
    case strict     // Enhanced privacy with PII detection
    case custom(privacyRules: PrivacyRules)
}
```

## Model Management

### loadModel(_:)

Loads a model by identifier, downloading if necessary.

```swift
public func loadModel(_ modelIdentifier: String) async throws -> ModelInfo
```

**Parameters:**
- `modelIdentifier`: Unique model identifier

**Returns:**
- `ModelInfo`: Loaded model information

**Throws:**
- `RunAnywhereError.modelNotFound`: Model doesn't exist
- `RunAnywhereError.modelLoadFailed`: Loading failed
- `RunAnywhereError.insufficientStorage`: Not enough storage

### unloadModel()

Unloads the currently loaded model.

```swift
public func unloadModel() async throws
```

### listAvailableModels()

Lists all available models.

```swift
public func listAvailableModels() async throws -> [ModelInfo]
```

**Returns:**
- Array of available models

### downloadModel(_:)

Downloads a model without loading it.

```swift
public func downloadModel(_ modelIdentifier: String) async throws -> DownloadTask
```

**Returns:**
- `DownloadTask`: Task for tracking download progress

### deleteModel(_:)

Deletes a downloaded model.

```swift
public func deleteModel(_ modelIdentifier: String) async throws
```

### addModelFromURL(name:url:framework:)

Adds a custom model from a URL.

```swift
public func addModelFromURL(
    name: String,
    url: URL,
    framework: LLMFramework,
    estimatedSize: Int64? = nil,
    supportsThinking: Bool = false,
    thinkingTagPattern: ThinkingTagPattern? = nil
) -> ModelInfo
```

**Parameters:**
- `name`: Display name for the model
- `url`: Download URL
- `framework`: Target framework
- `estimatedSize`: Estimated download size
- `supportsThinking`: Whether model supports reasoning
- `thinkingTagPattern`: Pattern for extracting thinking

### updateModelThinkingSupport(modelId:supportsThinking:thinkingTagPattern:)

Updates thinking/reasoning support for a model.

```swift
public func updateModelThinkingSupport(
    modelId: String,
    supportsThinking: Bool,
    thinkingTagPattern: ThinkingTagPattern? = nil
) async
```

**Parameters:**
- `modelId`: Model identifier
- `supportsThinking`: Whether model supports reasoning
- `thinkingTagPattern`: Pattern for extracting thinking tags

## Text Generation

### generate(prompt:options:)

Generates text from a prompt.

```swift
public func generate(
    prompt: String,
    options: GenerationOptions? = nil
) async throws -> GenerationResult
```

**Parameters:**
- `prompt`: Input prompt
- `options`: Generation parameters

**Returns:**
- `GenerationResult`: Generated text with metrics

**Example:**
```swift
let result = try await RunAnywhereSDK.shared.generate(
    prompt: "Write a haiku about coding",
    options: GenerationOptions(
        maxTokens: 50,
        temperature: 0.7,
        topP: 0.9
    )
)

print("Generated: \(result.text)")
print("Tokens/sec: \(result.metrics.tokensPerSecond)")
print("Cost: $\(result.cost.totalCost)")
```

### generateStream(prompt:options:)

Generates text as a stream.

```swift
public func generateStream(
    prompt: String,
    options: GenerationOptions? = nil
) -> AsyncThrowingStream<String, Error>
```

**Returns:**
- Async stream of text chunks

**Example:**
```swift
let stream = RunAnywhereSDK.shared.generateStream(
    prompt: "Tell me a story",
    options: GenerationOptions(maxTokens: 200)
)

for try await chunk in stream {
    print(chunk, terminator: "")
}
```

### GenerationOptions

```swift
public struct GenerationOptions {
    // Core parameters
    public var maxTokens: Int = 150
    public var temperature: Float = 0.7
    public var topP: Float = 0.95
    public var topK: Int = 40

    // Advanced parameters
    public var context: Context? = nil
    public var stopSequences: [String] = []
    public var seed: Int? = nil
    public var systemMessage: String? = nil

    // Features
    public var enableRealTimeTracking: Bool = true
    public var streamingEnabled: Bool = true
    public var tokenBudget: TokenBudget? = nil

    // Framework-specific
    public var frameworkOptions: FrameworkOptions? = nil
    public var preferredExecutionTarget: ExecutionTarget? = nil

    // Structured output
    public var structuredOutput: StructuredOutputConfig? = nil
}
```

### Context Management

```swift
public struct Context {
    public var messages: [Message]
    public var systemMessage: String?
    public var maxTokens: Int?

    public init(messages: [Message] = [],
                systemMessage: String? = nil,
                maxTokens: Int? = nil)
}

public struct Message {
    public let role: Role
    public let content: String
    public let timestamp: Date

    public enum Role: String, Codable {
        case system
        case user
        case assistant
    }
}
```

## Structured Output

### generateStructured(_:prompt:options:)

Generates structured output conforming to a type.

```swift
public func generateStructured<T: Generatable>(
    _ type: T.Type,
    prompt: String,
    options: GenerationOptions? = nil
) async throws -> T
```

**Parameters:**
- `type`: Target type conforming to `Generatable`
- `prompt`: Input prompt
- `options`: Generation options

### generateStructured(_:prompt:validationMode:options:)

Generates structured output with validation mode.

```swift
public func generateStructured<T: Generatable>(
    _ type: T.Type,
    prompt: String,
    validationMode: SchemaValidationMode,
    options: GenerationOptions? = nil
) async throws -> T
```

### generateWithStructuredOutput(prompt:structuredOutput:options:)

Generates with raw structured output configuration.

```swift
public func generateWithStructuredOutput(
    prompt: String,
    structuredOutput: StructuredOutputConfig,
    options: GenerationOptions? = nil
) async throws -> GenerationResult
```

### generateStructuredStream(_:content:options:)

Generates structured output as a stream.

```swift
public func generateStructuredStream<T: Generatable>(
    _ type: T.Type,
    content: String,
    options: GenerationOptions? = nil
) -> StructuredOutputStreamResult<T>
```

**Returns:**
- `StructuredOutputStreamResult<T>`: Stream result with text stream and final structured result

**Example:**
```swift
struct Recipe: Generatable, Codable {
    let title: String
    let ingredients: [String]
    let instructions: [String]
    let prepTime: Int

    static var jsonSchema: String {
        """
        {
            "type": "object",
            "properties": {
                "title": {"type": "string"},
                "ingredients": {"type": "array", "items": {"type": "string"}},
                "instructions": {"type": "array", "items": {"type": "string"}},
                "prepTime": {"type": "integer"}
            },
            "required": ["title", "ingredients", "instructions", "prepTime"]
        }
        """
    }
}

// Standard generation
let recipe = try await RunAnywhereSDK.shared.generateStructured(
    Recipe.self,
    prompt: "Create a recipe for chocolate chip cookies"
)

// Streaming generation
let streamResult = RunAnywhereSDK.shared.generateStructuredStream(
    Recipe.self,
    content: "Create a recipe for chocolate chip cookies"
)

for try await chunk in streamResult.textStream {
    print(chunk, terminator: "")
}

let recipe = try await streamResult.result
```

### Generatable Protocol

```swift
public protocol Generatable: Codable {
    static var jsonSchema: String { get }
}
```

### Validation Modes

```swift
public enum SchemaValidationMode {
    case strict      // Fail if output doesn't match exactly
    case lenient     // Allow minor deviations
    case bestEffort  // Extract what's possible
}
```

### Structured Output Configuration

```swift
public struct StructuredOutputConfig {
    public let jsonSchema: String
    public let validationMode: SchemaValidationMode
    public let strategy: StructuredOutputStrategy
}

public enum StructuredOutputStrategy {
    case automatic
    case jsonSchemaInPrompt
    case frameworkConstraints
    case postProcessing
}
```

## Voice & Audio

### transcribe(audio:modelId:options:)

Transcribes audio to text using voice models.

```swift
public func transcribe(
    audio: Data,
    modelId: String = "whisper-base",
    options: TranscriptionOptions = TranscriptionOptions()
) async throws -> TranscriptionResult
```

**Parameters:**
- `audio`: Audio data to transcribe
- `modelId`: Voice model identifier (default: "whisper-base")
- `options`: Transcription options

**Returns:**
- `TranscriptionResult`: Transcription with metadata

**Throws:**
- `VoiceError.serviceNotInitialized`: Voice service not initialized
- `VoiceError.transcriptionFailed`: Transcription failed
- `VoiceError.modelNotFound`: Model not found
- `VoiceError.audioFormatNotSupported`: Audio format not supported

### processVoiceQuery(audio:voiceModelId:llmModelId:)

Processes a voice query through transcription and LLM generation.

```swift
public func processVoiceQuery(
    audio: Data,
    voiceModelId: String = "whisper-base",
    llmModelId: String? = nil
) async throws -> VoiceResponse
```

**Parameters:**
- `audio`: Audio data to process
- `voiceModelId`: Voice model for transcription
- `llmModelId`: Optional LLM model for generation

**Returns:**
- `VoiceResponse`: Contains input and output text

### TranscriptionOptions

```swift
public struct TranscriptionOptions {
    public enum Language: String, CaseIterable {
        case auto = "auto"
        case english = "en"
        case spanish = "es"
        case french = "fr"
        case german = "de"
        case chinese = "zh"
        case japanese = "ja"
        // ... more languages
    }

    public enum Task {
        case transcribe  // Transcribe in original language
        case translate   // Translate to English
    }

    public var language: Language = .auto
    public var task: Task = .transcribe
    public var temperature: Float = 0.0
    public var enableTimestamps: Bool = false
    public var maxLength: Int? = nil
}
```

### TranscriptionResult

```swift
public struct TranscriptionResult {
    public let text: String
    public let language: String?
    public let confidence: Float
    public let duration: TimeInterval
    public let segments: [TranscriptionSegment]?
}

public struct TranscriptionSegment {
    public let text: String
    public let start: TimeInterval
    public let end: TimeInterval
    public let confidence: Float
}
```

### VoiceResponse

```swift
public struct VoiceResponse {
    public let inputText: String      // Transcribed text
    public let outputText: String     // LLM response
    public let transcriptionResult: TranscriptionResult
    public let generationResult: GenerationResult?
}
```

### Voice Session Management

```swift
public struct VoiceSession {
    public let id: UUID
    public let startTime: Date
    public var transcriptions: [TranscriptionResult]
    public var generations: [GenerationResult]
}
```

### Audio Chunk Handling

```swift
public struct AudioChunk {
    public let data: Data
    public let timestamp: Date
    public let duration: TimeInterval
}
```

### Voice Error Types

```swift
public enum VoiceError: LocalizedError {
    case serviceNotInitialized
    case transcriptionFailed(Error)
    case streamingNotSupported
    case languageNotSupported(String)
    case modelNotFound(String)
    case audioFormatNotSupported
    case insufficientAudioData
}
```

## Configuration Management

### Dynamic Settings

```swift
// Generation parameters
public func setTemperature(_ value: Float) async
public func setMaxTokens(_ value: Int) async
public func setTopP(_ value: Float) async
public func setTopK(_ value: Int) async

// SDK configuration
public func setCloudRoutingEnabled(_ enabled: Bool) async
public func setPrivacyModeEnabled(_ enabled: Bool) async
public func setRoutingPolicy(_ policy: String) async
public func setApiKey(_ apiKey: String?) async

// Analytics
public func setAnalyticsEnabled(_ enabled: Bool) async
public func setAnalyticsLevel(_ level: String) async
public func setEnableLiveMetrics(_ enabled: Bool) async
```

### Retrieving Settings

```swift
public func getGenerationSettings() async -> DefaultGenerationSettings
public func getCloudRoutingEnabled() async -> Bool
public func getPrivacyModeEnabled() async -> Bool
public func getRoutingPolicy() async -> String
public func getApiKey() async -> String?
public func getAnalyticsEnabled() async -> Bool
public func getAnalyticsLevel() async -> String
public func getEnableLiveMetrics() async -> Bool
```

### Reset Settings

```swift
public func resetGenerationSettings() async
public func syncUserPreferences() async
```

## Analytics & Monitoring

### Performance Monitoring

```swift
// Access performance monitor
let monitor = RunAnywhereSDK.shared.performanceMonitor

// Get current metrics
let metrics = await monitor.getCurrentMetrics()

// Start monitoring
await monitor.startMonitoring()

// Generate report
let report = await monitor.generateReport()
```

### Generation Analytics

```swift
// Get analytics service
let analytics = await RunAnywhereSDK.shared.generationAnalytics

// Get session information
let session = await analytics.getSession(sessionId)
let generations = await analytics.getGenerationsForSession(sessionId)

// Get performance metrics
let avgMetrics = await analytics.getAverageMetrics(
    for: "llama-3.2-1b",
    limit: 100
)

// Observe live metrics
let metricsStream = analytics.observeLiveMetrics(for: generationId)
for await metric in metricsStream {
    print("Tokens/sec: \(metric.tokensPerSecond)")
}
```

### A/B Testing

```swift
let abTesting = RunAnywhereSDK.shared.abTesting

// Create test
let test = await abTesting.createTest(
    name: "Model Comparison",
    variantA: TestVariant(id: "model-a", configuration: configA),
    variantB: TestVariant(id: "model-b", configuration: configB),
    configuration: ABTestConfiguration(sampleSize: 1000)
)

// Get results
let results = await abTesting.analyzeResults(for: test.id)
```

### Benchmarking

```swift
let benchmark = RunAnywhereSDK.shared.benchmarkSuite

// Run benchmark
let result = try await benchmark.runBenchmark(
    prompts: [
        BenchmarkPrompt(text: "Hello world", category: .simple),
        BenchmarkPrompt(text: "Explain quantum computing", category: .complex)
    ],
    options: BenchmarkOptions(iterations: 10)
)

// Compare benchmarks
let comparison = benchmark.compareBenchmarks([result1, result2])
```

## Storage Management

### Storage Information

```swift
// Get storage info
let info = await RunAnywhereSDK.shared.getStorageInfo()
print("Used: \(info.usedSpace) / \(info.totalSpace)")

// Get stored models
let models = await RunAnywhereSDK.shared.getStoredModels()

// Get base directory
let baseURL = RunAnywhereSDK.shared.getBaseDirectoryURL()
```

### Storage Cleanup

```swift
// Clear cache
try await RunAnywhereSDK.shared.clearCache()

// Clean temporary files
try await RunAnywhereSDK.shared.cleanTempFiles()

// Delete specific model
try await RunAnywhereSDK.shared.deleteStoredModel("model-id")
```

### Storage Monitor

```swift
let monitor = RunAnywhereSDK.shared.storageMonitor

// Get recommendations
let recommendations = await monitor.recommendCleanup()

// Perform cleanup
let result = await monitor.cleanupStorage()
print("Freed: \(result.freedSpace) bytes")
```

## Framework Management

### registerFrameworkAdapter(_:)

Register a custom framework adapter.

```swift
public func registerFrameworkAdapter(_ adapter: UnifiedFrameworkAdapter)
```

**Parameters:**
- `adapter`: Unified framework adapter implementation

### Framework Discovery

```swift
// Get registered adapters
public func getRegisteredAdapters() -> [LLMFramework: UnifiedFrameworkAdapter]

// Get available frameworks
public func getAvailableFrameworks() -> [LLMFramework]

// Get detailed availability
public func getFrameworkAvailability() -> [FrameworkAvailability]

// Get models for framework
public func getModelsForFramework(_ framework: LLMFramework) -> [ModelInfo]
```

### Modality-Based Framework Management

```swift
// Get frameworks supporting a specific modality
public func getFrameworks(for modality: FrameworkModality) -> [LLMFramework]

// Get primary modality for a framework
public func getPrimaryModality(for framework: LLMFramework) -> FrameworkModality

// Check if framework supports modality
public func frameworkSupports(_ framework: LLMFramework, modality: FrameworkModality) -> Bool
```

### FrameworkModality

```swift
public enum FrameworkModality: String, CaseIterable {
    case textToText = "text-to-text"       // Traditional LLM
    case voiceToText = "voice-to-text"     // Speech recognition
    case textToVoice = "text-to-voice"     // Text-to-speech
    case imageToText = "image-to-text"     // Vision understanding
    case multimodal = "multimodal"         // Multiple modalities
}
```

### Framework Options

```swift
// Core ML
let coreMLOptions = CoreMLOptions(
    useNeuralEngine: true,
    computeUnits: .all
)

// GGUF (llama.cpp)
let ggufOptions = GGUFOptions(
    gpuLayers: 32,
    useMemoryMap: true,
    batchSize: 512
)

// TensorFlow Lite
let tfliteOptions = TFLiteOptions(
    numThreads: 4,
    useGPUDelegate: true
)

// MLX
let mlxOptions = MLXOptions(
    useUnifiedMemory: true,
    useMPS: true
)
```

## Error Handling

### SDKError

Core SDK error type:

```swift
public enum SDKError: LocalizedError {
    case notInitialized
    case notImplemented
    case modelNotFound(String)
    case loadingFailed(String)
    case generationFailed(String)
    case generationTimeout(String)
    case frameworkNotAvailable(LLMFramework)
    case downloadFailed(Error)
    case validationFailed(ValidationError)
    case routingFailed(String)
    case databaseInitializationFailed(Error)
    case unsupportedModality(String)
}
```

### RunAnywhereError

Primary error type for user-facing errors:

```swift
public enum RunAnywhereError: LocalizedError {
    // Initialization
    case notInitialized
    case alreadyInitialized
    case invalidConfiguration(String)
    case invalidAPIKey

    // Model errors
    case modelNotFound(String)
    case modelLoadFailed(String, Error?)
    case modelValidationFailed(String, [ValidationError])
    case modelIncompatible(String, String)

    // Generation errors
    case generationFailed(String)
    case generationTimeout
    case contextTooLong(provided: Int, maximum: Int)
    case tokenLimitExceeded(generated: Int, limit: Int)
    case costLimitExceeded(cost: Double, limit: Double)

    // Network errors
    case networkUnavailable
    case requestFailed(Error)
    case downloadFailed(String, Error?)

    // Storage errors
    case insufficientStorage(required: Int64, available: Int64)
    case storageFull

    // Hardware errors
    case hardwareUnsupported(String)
    case memoryPressure
    case thermalStateExceeded

    // Feature errors
    case featureNotAvailable(String)
    case notImplemented(String)
}
```

### StructuredOutputError

Structured output validation errors:

```swift
public enum StructuredOutputError: LocalizedError {
    case invalidJSON(String)
    case validationFailed(String)
    case extractionFailed(String)
    case schemaGenerationFailed(String)
    case streamingNotSupported
}
```

### VoiceError

Voice and audio processing errors:

```swift
public enum VoiceError: LocalizedError {
    case serviceNotInitialized
    case transcriptionFailed(Error)
    case streamingNotSupported
    case languageNotSupported(String)
    case modelNotFound(String)
    case audioFormatNotSupported
    case insufficientAudioData
}
```

### Error Handling Example

```swift
do {
    let result = try await RunAnywhereSDK.shared.generate(
        prompt: "Hello",
        options: GenerationOptions(maxTokens: 1000)
    )
} catch RunAnywhereError.tokenLimitExceeded(let generated, let limit) {
    print("Generated \(generated) tokens, but limit is \(limit)")
} catch RunAnywhereError.memoryPressure {
    print("System is under memory pressure")
    // Try with smaller model or reduced context
} catch {
    print("Error: \(error.localizedDescription)")
}
```

## Data Types

### ModelInfo

```swift
public struct ModelInfo: Identifiable, Codable {
    public let id: String
    public let name: String
    public let description: String
    public let version: String
    public let format: ModelFormat
    public let size: Int64
    public let supportedFrameworks: [LLMFramework]
    public let preferredFramework: LLMFramework?
    public let hardwareRequirements: HardwareRequirement
    public let quantizationLevel: QuantizationLevel?
    public let architecture: ModelArchitecture
    public let capabilities: ModelCapabilities
    public let metadata: ModelInfoMetadata
    public let downloadURL: URL?
    public let localPath: URL?
    public let isDownloaded: Bool
    public let supportsThinking: Bool
    public let thinkingTagPattern: ThinkingTagPattern?
}
```

### GenerationResult

```swift
public struct GenerationResult {
    public let text: String
    public let metrics: GenerationMetrics
    public let routingDecision: RoutingDecision
    public let cost: GenerationCost
    public let model: ModelInfo
    public let timestamp: Date
    public let thinking: String?  // Extracted reasoning
    public let sessionId: UUID
    public let messageId: UUID
}
```

### GenerationMetrics

```swift
public struct GenerationMetrics {
    public let latency: TimeInterval
    public let tokensPerSecond: Double
    public let inputTokens: Int
    public let outputTokens: Int
    public let memoryUsage: Int64
    public let energyUsage: Double?
    public let timeToFirstToken: TimeInterval?
    public let averageTokenLatency: TimeInterval
}
```

### LLMFramework

```swift
public enum LLMFramework: String, CaseIterable {
    case coreML = "CoreML"
    case tensorFlowLite = "TensorFlowLite"
    case gguf = "GGUF"
    case onnx = "ONNX"
    case mlx = "MLX"
    case safetensors = "SafeTensors"
    case pytorch = "PyTorch"
    case transformers = "Transformers"
    case llamaCpp = "LlamaCpp"
    case whisper = "Whisper"
    case whisperKit = "WhisperKit"
    case openAIWhisper = "OpenAIWhisper"
    case execuTorch = "ExecuTorch"
    case swiftTransformers = "SwiftTransformers"
    case foundationModels = "FoundationModels"
    case picoLLM = "PicoLLM"
    case mlc = "MLC"
    case mediaPipe = "MediaPipe"
    case custom = "Custom"
}
```

### ThinkingTagPattern

```swift
public struct ThinkingTagPattern: Codable {
    public let startTag: String
    public let endTag: String

    public init(startTag: String, endTag: String) {
        self.startTag = startTag
        self.endTag = endTag
    }
}
```

### StructuredOutputStreamResult

```swift
public struct StructuredOutputStreamResult<T: Generatable> {
    public let textStream: AsyncThrowingStream<String, Error>
    public let result: Task<T, Error>
}
```

## Advanced Features

### Hardware Configuration

```swift
let hwConfig = HardwareConfiguration(
    preferredAccelerator: .neuralEngine,
    memoryMode: .aggressive,
    powerMode: .highPerformance,
    thermalMode: .sustainable,
    threadCount: 8,
    useUnifiedMemory: true,
    quantizationPreference: .int8
)

let config = Configuration(
    apiKey: "key",
    hardwarePreferences: hwConfig
)
```

### Model Providers

```swift
let huggingFaceProvider = ModelProviderConfig(
    type: .huggingFace,
    credentials: ["token": "hf_xxx"],
    searchEnabled: true
)

let config = Configuration(
    apiKey: "key",
    modelProviders: [huggingFaceProvider]
)
```

### Token Budget

```swift
let budget = TokenBudget(
    maxInputTokens: 1000,
    maxOutputTokens: 500,
    maxTotalTokens: 1500,
    maxCost: 0.10  // $0.10
)

let options = GenerationOptions(
    tokenBudget: budget
)
```

### Thinking/Reasoning Support

```swift
// Model with thinking support
let model = RunAnywhereSDK.shared.addModelFromURL(
    name: "DeepSeek-R1",
    url: URL(string: "https://...")!,
    framework: .gguf,
    supportsThinking: true,
    thinkingTagPattern: ThinkingTagPattern(
        startTag: "<think>",
        endTag: "</think>"
    )
)

// Generation extracts thinking automatically
let result = try await RunAnywhereSDK.shared.generate(
    prompt: "Solve this complex problem..."
)

if let thinking = result.thinking {
    print("Model's reasoning: \(thinking)")
}
print("Final answer: \(result.text)")
```

## Best Practices

### 1. Error Handling
Always handle errors appropriately:
```swift
do {
    try await RunAnywhereSDK.shared.loadModel("model-id")
} catch {
    // Handle specific errors
}
```

### 2. Resource Management
Monitor memory usage:
```swift
let memoryStats = await RunAnywhereSDK.shared.performanceMonitor.getCurrentMetrics()
if memoryStats.memoryPressure {
    // Reduce context or switch models
}
```

### 3. Context Management
Trim context for long conversations:
```swift
var context = Context(messages: messages)
if context.messages.count > 20 {
    context.messages = Array(context.messages.suffix(10))
}
```

### 4. Streaming for UX
Use streaming for better user experience:
```swift
for try await chunk in RunAnywhereSDK.shared.generateStream(prompt: prompt) {
    // Update UI with chunk
}
```

### 5. Configuration
Start with sensible defaults:
```swift
let config = Configuration(
    apiKey: apiKey,
    routingPolicy: .deviceOnly,  // Privacy first
    privacyMode: .strict,
    enableRealTimeDashboard: true
)
```

## Platform Support

- **iOS**: 13.0+
- **macOS**: 10.15+
- **tvOS**: 13.0+
- **watchOS**: 6.0+
- **visionOS**: 1.0+

## Thread Safety

All public APIs are thread-safe and can be called from any thread. The SDK uses modern Swift concurrency (async/await) throughout.

## Performance Tips

1. **Preload Models**: Load models before they're needed
2. **Use Appropriate Models**: Smaller models for simple tasks
3. **Monitor Resources**: Check memory and thermal state
4. **Batch Operations**: Process multiple prompts together
5. **Cache Results**: Use SDK's built-in caching when possible

## Migration Guide

For users migrating from v1.x:

1. Replace completion handlers with async/await
2. Update error handling to use new error types
3. Use structured output for JSON generation
4. Adopt new configuration system

## Support

- Documentation: https://docs.runanywhere.ai
- Issues: https://github.com/runanywhere/swift-sdk/issues
- Community: https://discord.gg/runanywhere
