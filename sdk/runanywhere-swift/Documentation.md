# RunAnywhere Swift SDK - API Documentation

This document provides a complete reference for all public APIs in the RunAnywhere Swift SDK.

## Table of Contents

- [RunAnywhere (Core)](#runanywhere-core)
  - [Initialization](#initialization)
  - [SDK State](#sdk-state)
  - [Text Generation (LLM)](#text-generation-llm)
  - [Model Management](#model-management)
  - [Speech-to-Text (STT)](#speech-to-text-stt)
  - [Text-to-Speech (TTS)](#text-to-speech-tts)
  - [Voice Activity Detection (VAD)](#voice-activity-detection-vad)
  - [Voice Agent](#voice-agent)
  - [Events](#events)
  - [Logging](#logging)
  - [Storage](#storage)
- [Types](#types)
  - [LLM Types](#llm-types)
  - [STT Types](#stt-types)
  - [TTS Types](#tts-types)
  - [VAD Types](#vad-types)
  - [Voice Agent Types](#voice-agent-types)
  - [Model Types](#model-types)
  - [Error Types](#error-types)
- [Modules](#modules)
  - [LlamaCPPRuntime](#llamacppruntime)
  - [ONNXRuntime](#onnxruntime)

---

## RunAnywhere (Core)

The `RunAnywhere` enum is the main entry point for all SDK operations. All methods are static.

### Initialization

#### `initialize(apiKey:baseURL:environment:)`

Initializes the RunAnywhere SDK with the specified configuration.

```swift
public static func initialize(
    apiKey: String? = nil,
    baseURL: String? = nil,
    environment: SDKEnvironment = .development
) throws
```

**Parameters:**
- `apiKey` - API key for authentication. Required for production/staging.
- `baseURL` - Backend API base URL. Required for production/staging.
- `environment` - SDK environment (`.development`, `.staging`, `.production`).

**Throws:** `SDKError` if validation fails.

**Example:**

```swift
try RunAnywhere.initialize(
    apiKey: "your-api-key",
    baseURL: "https://api.runanywhere.ai",
    environment: .production
)
```

#### `completeServicesInitialization()`

Completes services initialization (Phase 2). Called automatically in background by `initialize()`, or can be awaited directly.

```swift
public static func completeServicesInitialization() async throws
```

#### `reset()`

Resets SDK state for testing purposes. Clears all initialization state and cached data.

```swift
public static func reset()
```

---

### SDK State

#### `isSDKInitialized`

Returns whether the SDK is initialized (Phase 1 complete).

```swift
public static var isSDKInitialized: Bool { get }
```

#### `areServicesReady`

Returns whether services are fully ready (Phase 2 complete).

```swift
public static var areServicesReady: Bool { get }
```

#### `isActive`

Returns whether the SDK is active and ready for use.

```swift
public static var isActive: Bool { get }
```

#### `version`

Returns the current SDK version.

```swift
public static var version: String { get }
```

#### `environment`

Returns the current environment (nil if not initialized).

```swift
public static var environment: SDKEnvironment? { get }
```

#### `deviceId`

Returns the device ID (Keychain-persisted, survives reinstalls).

```swift
public static var deviceId: String { get }
```

#### `isAuthenticated`

Returns whether the SDK is currently authenticated.

```swift
public static var isAuthenticated: Bool { get }
```

#### `isDeviceRegistered()`

Returns whether the device is registered with the backend.

```swift
public static func isDeviceRegistered() -> Bool
```

#### `getUserId()`

Returns the current user ID from authentication.

```swift
public static func getUserId() -> String?
```

#### `getOrganizationId()`

Returns the current organization ID from authentication.

```swift
public static func getOrganizationId() -> String?
```

---

### Text Generation (LLM)

#### `chat(_:)`

Simple text generation returning just the text string.

```swift
public static func chat(_ prompt: String) async throws -> String
```

**Parameters:**
- `prompt` - The text prompt.

**Returns:** Generated response text.

**Throws:** `SDKError` if not initialized or generation fails.

**Example:**

```swift
let response = try await RunAnywhere.chat("What is the capital of France?")
print(response) // "The capital of France is Paris."
```

#### `generate(_:options:)`

Text generation with full metrics and analytics.

```swift
public static func generate(
    _ prompt: String,
    options: LLMGenerationOptions? = nil
) async throws -> LLMGenerationResult
```

**Parameters:**
- `prompt` - The text prompt.
- `options` - Generation options (optional).

**Returns:** `LLMGenerationResult` with full metrics.

**Throws:** `SDKError` if not initialized or generation fails.

**Example:**

```swift
let result = try await RunAnywhere.generate(
    "Explain quantum computing",
    options: LLMGenerationOptions(maxTokens: 200, temperature: 0.7)
)
print("Response: \(result.text)")
print("Speed: \(result.tokensPerSecond) tok/s")
```

#### `generateStream(_:options:)`

Streaming text generation with complete analytics.

```swift
public static func generateStream(
    _ prompt: String,
    options: LLMGenerationOptions? = nil
) async throws -> LLMStreamingResult
```

**Parameters:**
- `prompt` - The text prompt.
- `options` - Generation options (optional).

**Returns:** `LLMStreamingResult` containing both the token stream and final metrics task.

**Throws:** `SDKError` if not initialized or generation fails.

**Example:**

```swift
let result = try await RunAnywhere.generateStream(prompt)

for try await token in result.stream {
    print(token, terminator: "")
}

let metrics = try await result.result.value
print("\nSpeed: \(metrics.tokensPerSecond) tok/s")
```

#### `generateStructured(_:prompt:options:)`

Generate structured output conforming to a `Generatable` type.

```swift
public static func generateStructured<T: Generatable>(
    _ type: T.Type,
    prompt: String,
    options: LLMGenerationOptions? = nil
) async throws -> T
```

**Parameters:**
- `type` - The `Generatable` type to generate.
- `prompt` - The text prompt.
- `options` - Generation options (optional).

**Returns:** Instance of the specified type.

**Throws:** `SDKError` if generation or parsing fails.

#### `cancelGeneration()`

Cancels the current text generation.

```swift
public static func cancelGeneration() async
```

#### `supportsLLMStreaming`

Returns whether the currently loaded LLM model supports streaming.

```swift
public static var supportsLLMStreaming: Bool { get async }
```

---

### Model Management

#### `loadModel(_:)`

Loads an LLM model by ID.

```swift
public static func loadModel(_ modelId: String) async throws
```

**Parameters:**
- `modelId` - The model identifier.

**Throws:** `SDKError` if model not found or loading fails.

**Example:**

```swift
try await RunAnywhere.loadModel("llama-3.2-1b-instruct-q4")
```

#### `unloadModel()`

Unloads the currently loaded LLM model.

```swift
public static func unloadModel() async throws
```

#### `isModelLoaded`

Returns whether an LLM model is loaded.

```swift
public static var isModelLoaded: Bool { get async }
```

#### `getCurrentModelId()`

Returns the currently loaded LLM model ID.

```swift
public static func getCurrentModelId() async -> String?
```

#### `currentLLMModel`

Returns the currently loaded LLM model as `ModelInfo`.

```swift
public static var currentLLMModel: ModelInfo? { get async }
```

#### `availableModels()`

Returns all available models.

```swift
public static func availableModels() async throws -> [ModelInfo]
```

**Returns:** Array of `ModelInfo` for all registered models.

---

### Speech-to-Text (STT)

#### `loadSTTModel(_:)`

Loads an STT model by ID.

```swift
public static func loadSTTModel(_ modelId: String) async throws
```

**Parameters:**
- `modelId` - The model identifier (e.g., "whisper-base-onnx").

**Example:**

```swift
try await RunAnywhere.loadSTTModel("whisper-base-onnx")
```

#### `unloadSTTModel()`

Unloads the currently loaded STT model.

```swift
public static func unloadSTTModel() async throws
```

#### `isSTTModelLoaded`

Returns whether an STT model is loaded.

```swift
public static var isSTTModelLoaded: Bool { get async }
```

#### `currentSTTModel`

Returns the currently loaded STT model as `ModelInfo`.

```swift
public static var currentSTTModel: ModelInfo? { get async }
```

#### `transcribe(_:)`

Simple voice transcription using default model.

```swift
public static func transcribe(_ audioData: Data) async throws -> String
```

**Parameters:**
- `audioData` - Audio data to transcribe.

**Returns:** Transcribed text.

**Example:**

```swift
let text = try await RunAnywhere.transcribe(audioData)
```

#### `transcribeWithOptions(_:options:)`

Transcribe audio data with options.

```swift
public static func transcribeWithOptions(
    _ audioData: Data,
    options: STTOptions
) async throws -> STTOutput
```

**Parameters:**
- `audioData` - Raw audio data.
- `options` - Transcription options.

**Returns:** `STTOutput` with text and metadata.

#### `transcribeBuffer(_:language:)`

Transcribe an `AVAudioPCMBuffer`.

```swift
public static func transcribeBuffer(
    _ buffer: AVAudioPCMBuffer,
    language: String? = nil
) async throws -> STTOutput
```

#### `transcribeStream(audioData:options:onPartialResult:)`

Transcribe audio with streaming callbacks.

```swift
public static func transcribeStream(
    audioData: Data,
    options: STTOptions = STTOptions(),
    onPartialResult: @escaping (STTTranscriptionResult) -> Void
) async throws -> STTOutput
```

---

### Text-to-Speech (TTS)

#### `loadTTSModel(_:)` / `loadTTSVoice(_:)`

Loads a TTS voice by ID.

```swift
public static func loadTTSModel(_ voiceId: String) async throws
public static func loadTTSVoice(_ voiceId: String) async throws
```

**Parameters:**
- `voiceId` - The voice identifier.

**Example:**

```swift
try await RunAnywhere.loadTTSVoice("piper-en-us-amy")
```

#### `unloadTTSVoice()`

Unloads the currently loaded TTS voice.

```swift
public static func unloadTTSVoice() async throws
```

#### `isTTSVoiceLoaded`

Returns whether a TTS voice is loaded.

```swift
public static var isTTSVoiceLoaded: Bool { get async }
```

#### `currentTTSVoiceId`

Returns the currently loaded TTS voice ID.

```swift
public static var currentTTSVoiceId: String? { get async }
```

#### `availableTTSVoices`

Returns available TTS voice IDs.

```swift
public static var availableTTSVoices: [String] { get async }
```

#### `synthesize(_:options:)`

Synthesize text to speech.

```swift
public static func synthesize(
    _ text: String,
    options: TTSOptions = TTSOptions()
) async throws -> TTSOutput
```

**Parameters:**
- `text` - Text to synthesize.
- `options` - Synthesis options.

**Returns:** `TTSOutput` with audio data.

**Example:**

```swift
let output = try await RunAnywhere.synthesize(
    "Hello, world!",
    options: TTSOptions(rate: 1.0, pitch: 1.0)
)
```

#### `synthesizeStream(_:options:onAudioChunk:)`

Stream synthesis for long text.

```swift
public static func synthesizeStream(
    _ text: String,
    options: TTSOptions = TTSOptions(),
    onAudioChunk: @escaping (Data) -> Void
) async throws -> TTSOutput
```

#### `speak(_:options:)`

Speak text aloud with automatic playback.

```swift
public static func speak(
    _ text: String,
    options: TTSOptions = TTSOptions()
) async throws -> TTSSpeakResult
```

**Example:**

```swift
try await RunAnywhere.speak("Hello world")
```

#### `stopSpeaking()`

Stop current speech playback.

```swift
public static func stopSpeaking() async
```

#### `stopSynthesis()`

Stop current TTS synthesis.

```swift
public static func stopSynthesis() async
```

#### `isSpeaking`

Returns whether speech is currently playing.

```swift
public static var isSpeaking: Bool { get async }
```

---

### Voice Activity Detection (VAD)

#### `initializeVAD()` / `initializeVAD(_:)`

Initialize VAD with optional configuration.

```swift
public static func initializeVAD() async throws
public static func initializeVAD(_ config: VADConfiguration) async throws
```

#### `isVADReady`

Returns whether VAD is ready.

```swift
public static var isVADReady: Bool { get async }
```

#### `detectSpeech(in:)` - AVAudioPCMBuffer

Detect speech in an audio buffer.

```swift
public static func detectSpeech(in buffer: AVAudioPCMBuffer) async throws -> Bool
```

**Returns:** Whether speech was detected.

#### `detectSpeech(in:)` - [Float]

Detect speech in audio samples.

```swift
public static func detectSpeech(in samples: [Float]) async throws -> Bool
```

#### `startVAD()`

Start VAD processing.

```swift
public static func startVAD() async throws
```

#### `stopVAD()`

Stop VAD processing.

```swift
public static func stopVAD() async throws
```

#### `setVADSpeechActivityCallback(_:)`

Set callback for speech activity events.

```swift
public static func setVADSpeechActivityCallback(
    _ callback: @escaping (SpeechActivityEvent) -> Void
) async
```

#### `setVADAudioBufferCallback(_:)`

Set callback for audio samples.

```swift
public static func setVADAudioBufferCallback(
    _ callback: @escaping ([Float]) -> Void
) async
```

#### `cleanupVAD()`

Cleanup VAD resources.

```swift
public static func cleanupVAD() async
```

---

### Voice Agent

#### `initializeVoiceAgent(_:)`

Initialize voice agent with configuration.

```swift
public static func initializeVoiceAgent(
    _ config: VoiceAgentConfiguration
) async throws
```

#### `initializeVoiceAgentWithLoadedModels()`

Initialize voice agent using already-loaded models.

```swift
public static func initializeVoiceAgentWithLoadedModels() async throws
```

#### `isVoiceAgentReady`

Returns whether voice agent is ready.

```swift
public static var isVoiceAgentReady: Bool { get async }
```

#### `getVoiceAgentComponentStates()`

Get the current state of all voice agent components.

```swift
public static func getVoiceAgentComponentStates() async -> VoiceAgentComponentStates
```

#### `areAllVoiceComponentsReady`

Returns whether all voice components are ready.

```swift
public static var areAllVoiceComponentsReady: Bool { get async }
```

#### `processVoiceTurn(_:)`

Process a complete voice turn: audio -> transcription -> LLM response -> speech.

```swift
public static func processVoiceTurn(
    _ audioData: Data
) async throws -> VoiceAgentResult
```

**Returns:** `VoiceAgentResult` with transcription, response, and synthesized audio.

**Example:**

```swift
let result = try await RunAnywhere.processVoiceTurn(audioData)
print("User said: \(result.transcription)")
print("AI response: \(result.response)")
```

#### `voiceAgentTranscribe(_:)`

Transcribe audio using voice agent.

```swift
public static func voiceAgentTranscribe(_ audioData: Data) async throws -> String
```

#### `voiceAgentGenerateResponse(_:)`

Generate LLM response using voice agent.

```swift
public static func voiceAgentGenerateResponse(_ prompt: String) async throws -> String
```

#### `voiceAgentSynthesizeSpeech(_:)`

Synthesize speech using voice agent.

```swift
public static func voiceAgentSynthesizeSpeech(_ text: String) async throws -> Data
```

#### `cleanupVoiceAgent()`

Cleanup voice agent resources.

```swift
public static func cleanupVoiceAgent() async
```

---

### Events

#### `events`

Access to all SDK events for subscription-based patterns.

```swift
public static var events: EventBus { get }
```

**Example:**

```swift
RunAnywhere.events.events
    .receive(on: DispatchQueue.main)
    .sink { event in
        print("Event: \(event.type)")
    }
    .store(in: &cancellables)
```

---

### Logging

#### `setLogLevel(_:)`

Set the minimum log level.

```swift
public static func setLogLevel(_ level: LogLevel)
```

**Parameters:**
- `level` - One of `.debug`, `.info`, `.warning`, `.error`, `.fault`.

#### `configureLocalLogging(enabled:)`

Enable or disable local logging with Pulse.

```swift
public static func configureLocalLogging(enabled: Bool)
```

#### `setDebugMode(_:)`

Enable or disable verbose debug mode.

```swift
public static func setDebugMode(_ enabled: Bool)
```

#### `flushAll()`

Flush all pending logs.

```swift
public static func flushAll() async
```

---

### Storage

#### `getStorageInfo()`

Get storage information.

```swift
public static func getStorageInfo() async -> StorageInfo
```

#### `cleanTempFiles()`

Clean up temporary files.

```swift
public static func cleanTempFiles() async throws
```

---

## Types

### LLM Types

#### `LLMGenerationOptions`

Options for text generation.

```swift
public struct LLMGenerationOptions: Sendable {
    public let maxTokens: Int
    public let temperature: Float
    public let topP: Float
    public let stopSequences: [String]
    public let streamingEnabled: Bool
    public let preferredFramework: InferenceFramework?
    public let structuredOutput: StructuredOutputConfig?
    public let systemPrompt: String?

    public init(
        maxTokens: Int = 100,
        temperature: Float = 0.8,
        topP: Float = 1.0,
        stopSequences: [String] = [],
        streamingEnabled: Bool = false,
        preferredFramework: InferenceFramework? = nil,
        structuredOutput: StructuredOutputConfig? = nil,
        systemPrompt: String? = nil
    )
}
```

#### `LLMGenerationResult`

Result of a text generation request.

```swift
public struct LLMGenerationResult: Sendable {
    public let text: String
    public let thinkingContent: String?
    public let inputTokens: Int
    public let tokensUsed: Int
    public let modelUsed: String
    public let latencyMs: TimeInterval
    public let framework: String?
    public let tokensPerSecond: Double
    public let timeToFirstTokenMs: Double?
    public var structuredOutputValidation: StructuredOutputValidation?
    public let thinkingTokens: Int?
    public let responseTokens: Int
}
```

#### `LLMStreamingResult`

Container for streaming generation with metrics.

```swift
public struct LLMStreamingResult: Sendable {
    public let stream: AsyncThrowingStream<String, Error>
    public let result: Task<LLMGenerationResult, Error>
}
```

#### `LLMConfiguration`

Configuration for LLM component.

```swift
public struct LLMConfiguration: ComponentConfiguration, Sendable {
    public var componentType: SDKComponent { .llm }
    public let modelId: String?
    public let preferredFramework: InferenceFramework?
    public let contextLength: Int
    public let temperature: Double
    public let maxTokens: Int
    public let systemPrompt: String?
    public let streamingEnabled: Bool
}
```

#### `ThinkingTagPattern`

Pattern for extracting thinking/reasoning content from model output.

```swift
public struct ThinkingTagPattern: Codable, Sendable {
    public let openingTag: String
    public let closingTag: String

    public static let defaultPattern: ThinkingTagPattern
    public static let thinkingPattern: ThinkingTagPattern
    public static func custom(opening: String, closing: String) -> ThinkingTagPattern
}
```

#### `Generatable`

Protocol for types that can be generated as structured output.

```swift
public protocol Generatable: Codable {
    static var jsonSchema: String { get }
}
```

---

### STT Types

#### `STTOptions`

Options for speech-to-text transcription.

```swift
public struct STTOptions: Sendable {
    public let language: String
    public let sampleRate: Int
    public let enableWordTimestamps: Bool
    public let enableVAD: Bool

    public init(
        language: String = "en",
        sampleRate: Int = 16000,
        enableWordTimestamps: Bool = false,
        enableVAD: Bool = true
    )
}
```

#### `STTOutput`

Output from speech-to-text transcription.

```swift
public struct STTOutput: Sendable {
    public let text: String
    public let confidence: Float?
    public let wordTimestamps: [WordTimestamp]?
    public let detectedLanguage: String?
    public let alternatives: [STTAlternative]?
    public let metadata: TranscriptionMetadata?
}
```

#### `STTTranscriptionResult`

Partial transcription result for streaming.

```swift
public struct STTTranscriptionResult: Sendable {
    public let transcript: String
    public let confidence: Float?
    public let timestamps: [WordTimestamp]?
    public let language: String?
    public let alternatives: [STTAlternative]?
}
```

#### `TranscriptionMetadata`

Metadata about a transcription operation.

```swift
public struct TranscriptionMetadata: Sendable {
    public let modelId: String
    public let processingTime: TimeInterval
    public let audioLength: TimeInterval
}
```

---

### TTS Types

#### `TTSOptions`

Options for text-to-speech synthesis.

```swift
public struct TTSOptions: Sendable {
    public let rate: Float
    public let pitch: Float
    public let volume: Float
    public let language: String
    public let sampleRate: Int
    public let audioFormat: AudioFormat

    public init(
        rate: Float = 1.0,
        pitch: Float = 1.0,
        volume: Float = 1.0,
        language: String = "en-US",
        sampleRate: Int = 22050,
        audioFormat: AudioFormat = .wav
    )
}
```

#### `TTSOutput`

Output from text-to-speech synthesis.

```swift
public struct TTSOutput: Sendable {
    public let audioData: Data
    public let format: AudioFormat
    public let duration: TimeInterval
    public let phonemeTimestamps: [PhonemeTimestamp]?
    public let metadata: TTSSynthesisMetadata?
}
```

#### `TTSSpeakResult`

Result from the `speak()` method.

```swift
public struct TTSSpeakResult: Sendable {
    public let duration: TimeInterval
    public let characterCount: Int
    public let voice: String
}
```

#### `TTSSynthesisMetadata`

Metadata about a synthesis operation.

```swift
public struct TTSSynthesisMetadata: Sendable {
    public let voice: String
    public let language: String?
    public let processingTime: TimeInterval
    public let characterCount: Int
}
```

---

### VAD Types

#### `VADConfiguration`

Configuration for voice activity detection.

```swift
public struct VADConfiguration: Sendable {
    public let sampleRate: Int
    public let frameLength: Double
    public let energyThreshold: Double

    public init(
        sampleRate: Int = 16000,
        frameLength: Double = 0.032,
        energyThreshold: Double = 0.5
    )
}
```

#### `SpeechActivityEvent`

Speech activity event type.

```swift
public enum SpeechActivityEvent: Sendable {
    case started
    case ended
}
```

---

### Voice Agent Types

#### `VoiceAgentConfiguration`

Configuration for voice agent.

```swift
public struct VoiceAgentConfiguration: Sendable {
    public let sttModelId: String?
    public let llmModelId: String?
    public let ttsVoice: String?
    public let vadSampleRate: Int
    public let vadFrameLength: Float
    public let vadEnergyThreshold: Float

    public init(
        sttModelId: String? = nil,
        llmModelId: String? = nil,
        ttsVoice: String? = nil,
        vadSampleRate: Int = 16000,
        vadFrameLength: Float = 0.032,
        vadEnergyThreshold: Float = 0.5
    )
}
```

#### `VoiceAgentResult`

Result from processing a voice turn.

```swift
public struct VoiceAgentResult: Sendable {
    public let speechDetected: Bool
    public let transcription: String?
    public let response: String?
    public let synthesizedAudio: Data?
}
```

#### `VoiceAgentComponentStates`

State of all voice agent components.

```swift
public struct VoiceAgentComponentStates: Sendable {
    public let stt: ComponentLoadState
    public let llm: ComponentLoadState
    public let tts: ComponentLoadState

    public var isFullyReady: Bool { get }
}
```

#### `ComponentLoadState`

Load state of a component.

```swift
public enum ComponentLoadState: Sendable {
    case notLoaded
    case loading
    case loaded(modelId: String)
    case failed(Error)
}
```

---

### Model Types

#### `ModelInfo`

Immutable model metadata.

```swift
public struct ModelInfo: Sendable, Identifiable, Codable {
    public let id: String
    public let name: String
    public let description: String?
    public let category: ModelCategory
    public let framework: InferenceFramework
    public let format: ModelFormat
    public let downloadSize: Int64?
    public let diskSize: Int64?
    public let downloadURL: URL?
    public let localPath: URL?
    public let isBuiltIn: Bool
    public let isDownloaded: Bool
    public let version: String?
}
```

#### `ModelCategory`

Category of a model.

```swift
public enum ModelCategory: String, Codable, Sendable {
    case textGeneration
    case speechRecognition
    case speechSynthesis
    case voiceActivityDetection
    case speakerDiarization
}
```

#### `InferenceFramework`

Inference framework used by a model.

```swift
public enum InferenceFramework: String, Codable, Sendable {
    case llamaCpp
    case onnx
    case coreML
    case appleFoundation
    case system
}
```

#### `ModelFormat`

Format of a model file.

```swift
public enum ModelFormat: String, Codable, Sendable {
    case gguf
    case onnx
    case coreML
    case bin
    case safetensors
}
```

---

### Error Types

#### `SDKError`

Unified error type for all SDK errors.

```swift
public struct SDKError: Error, LocalizedError, Sendable {
    public let code: ErrorCode
    public let message: String
    public let category: ErrorCategory
    public let stackTrace: [String]
    public let underlyingError: (any Error)?

    public var errorDescription: String? { get }
    public var failureReason: String? { get }
    public var recoverySuggestion: String? { get }
}
```

**Factory Methods:**

```swift
SDKError.general(_ code: ErrorCode, _ message: String, underlying: (any Error)? = nil)
SDKError.stt(_ code: ErrorCode, _ message: String, underlying: (any Error)? = nil)
SDKError.tts(_ code: ErrorCode, _ message: String, underlying: (any Error)? = nil)
SDKError.llm(_ code: ErrorCode, _ message: String, underlying: (any Error)? = nil)
SDKError.vad(_ code: ErrorCode, _ message: String, underlying: (any Error)? = nil)
SDKError.voiceAgent(_ code: ErrorCode, _ message: String, underlying: (any Error)? = nil)
SDKError.download(_ code: ErrorCode, _ message: String, underlying: (any Error)? = nil)
SDKError.network(_ code: ErrorCode, _ message: String, underlying: (any Error)? = nil)
SDKError.authentication(_ code: ErrorCode, _ message: String, underlying: (any Error)? = nil)
```

#### `ErrorCode`

Error codes used by `SDKError`.

```swift
public enum ErrorCode: String, Sendable {
    case notInitialized
    case invalidConfiguration
    case invalidAPIKey
    case validationFailed
    case modelNotFound
    case modelLoadFailed
    case modelIncompatible
    case generationFailed
    case processingFailed
    case streamingNotSupported
    case emptyAudioBuffer
    case initializationFailed
    case networkUnavailable
    case networkError
    case timeout
    case insufficientStorage
    case insufficientMemory
    case storageError
    case microphonePermissionDenied
    case cancelled
    case invalidState
    case invalidInput
    case notImplemented
    case unknown
}
```

#### `ErrorCategory`

Categories of errors.

```swift
public enum ErrorCategory: String, Sendable {
    case general
    case stt
    case tts
    case llm
    case vad
    case vlm
    case speakerDiarization
    case wakeWord
    case voiceAgent
    case download
    case fileManagement
    case network
    case authentication
    case security
    case runtime
}
```

---

## Modules

### LlamaCPPRuntime

The LlamaCPP module provides LLM text generation capabilities using llama.cpp with GGUF models and Metal acceleration.

#### `LlamaCPP`

```swift
public enum LlamaCPP: RunAnywhereModule {
    public static let moduleId: String
    public static let moduleName: String
    public static let capabilities: Set<SDKComponent>
    public static let defaultPriority: Int
    public static let inferenceFramework: InferenceFramework
    public static let version: String
    public static let llamaCppVersion: String

    @MainActor
    public static func register(priority: Int = 100)
    public static func unregister()
    public static func canHandle(modelId: String?) -> Bool
}
```

**Registration:**

```swift
import LlamaCPPRuntime

@MainActor
func setup() {
    LlamaCPP.register()
}
```

---

### ONNXRuntime

The ONNX module provides STT, TTS, and VAD capabilities using ONNX Runtime with models like Whisper, Piper, and Silero.

#### `ONNX`

```swift
public enum ONNX: RunAnywhereModule {
    public static let moduleId: String
    public static let moduleName: String
    public static let capabilities: Set<SDKComponent>
    public static let defaultPriority: Int
    public static let inferenceFramework: InferenceFramework
    public static let version: String
    public static let onnxRuntimeVersion: String

    @MainActor
    public static func register(priority: Int = 100)
    public static func unregister()
    public static func canHandleSTT(modelId: String?) -> Bool
    public static func canHandleTTS(modelId: String?) -> Bool
    public static func canHandleVAD(modelId: String?) -> Bool
}
```

**Registration:**

```swift
import ONNXRuntime

@MainActor
func setup() {
    ONNX.register()
}
```

---

## EventBus

The `EventBus` provides Combine-based event subscription.

#### Properties

```swift
public var events: AnyPublisher<SDKEvent, Never>
```

#### Methods

```swift
public func events(for category: EventCategory) -> AnyPublisher<SDKEvent, Never>
public func on(_ category: EventCategory, handler: @escaping (SDKEvent) -> Void) -> AnyCancellable
```

**Example:**

```swift
// Subscribe to all events
let cancellable = RunAnywhere.events.events
    .sink { event in
        print("Event: \(event.type) in category: \(event.category)")
    }

// Subscribe to specific category
let llmCancellable = RunAnywhere.events.events(for: .llm)
    .sink { event in
        print("LLM Event: \(event.type)")
    }

// Using closure-based subscription
let subscription = RunAnywhere.events.on(.model) { event in
    print("Model event: \(event.type)")
}
```

---

## SDKEnvironment

Environment configuration for the SDK.

```swift
public enum SDKEnvironment: String, Sendable {
    case development
    case staging
    case production

    public var description: String { get }
}
```

| Environment     | Description                                      |
|-----------------|--------------------------------------------------|
| `.development`  | Verbose logging, mock services, local analytics  |
| `.staging`      | Testing with real services                       |
| `.production`   | Minimal logging, full authentication, telemetry  |
