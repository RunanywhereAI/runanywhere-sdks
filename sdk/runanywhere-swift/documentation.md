# RunAnywhere Swift SDK – Developer Documentation

> **SDK Version**: 0.16.0
> **Minimum Platform**: iOS 17+ / macOS 14+
> **Swift Version**: 5.9+

---

## 1. Introduction

### 1.1 What is RunAnywhere?

The **RunAnywhere Swift SDK** is a production-grade, on-device AI platform for iOS and macOS applications. It provides a unified API for running AI models locally on Apple devices, offering:

- **LLM (Large Language Model)** – Text generation with streaming support
- **STT (Speech-to-Text)** – Audio transcription with multiple backends
- **TTS (Text-to-Speech)** – Neural and system voice synthesis
- **VAD (Voice Activity Detection)** – Real-time speech detection
- **Speaker Diarization** – Multi-speaker identification
- **Voice Agent** – Complete voice pipeline orchestration

### 1.2 Core Philosophy

1. **On-Device First**: All AI inference runs locally on the device, ensuring low latency and data privacy.
2. **Plugin Architecture**: Backend engines (ONNX, LlamaCPP) are optional modules—include only what you need.
3. **Privacy by Design**: Audio and text data never leaves the device unless explicitly configured.
4. **Framework Agnostic**: Unified API abstracts away backend complexity; swap engines without changing app code.
5. **Event-Driven**: Subscribe to SDK events for reactive UI updates and observability.

### 1.3 When to Use RunAnywhere

RunAnywhere is ideal for applications that require:

- **Offline AI capabilities** – Voice assistants, transcription, and chat that work without internet
- **Low-latency inference** – Real-time voice interactions and streaming text generation
- **Privacy-sensitive AI** – Healthcare, finance, and enterprise apps where data cannot leave the device
- **Multi-modal AI** – Apps combining speech recognition, language models, and speech synthesis
- **Voice-first experiences** – Conversational interfaces with VAD-triggered interactions

---

## 2. Core Concepts

### 2.1 SDK Entry Point: `RunAnywhere`

The `RunAnywhere` enum is the primary public API. All SDK operations are accessed through static methods:

```swift
import RunAnywhere

// Initialize once at app launch
try RunAnywhere.initialize(
    apiKey: "your-api-key",
    baseURL: "https://api.runanywhere.ai",
    environment: .production
)

// Generate text
let response = try await RunAnywhere.chat("Hello, world!")

// Subscribe to events
RunAnywhere.events.on(.llm) { event in
    print("LLM Event: \(event.type)")
}
```

### 2.2 Module Registry & Plugins

The SDK uses a **plugin architecture** where AI backends register as modules:

```swift
import RunAnywhere
import LlamaCPPRuntime
import ONNXRuntime

// Register modules at app startup
await ModuleRegistry.shared.register(LlamaCPP.self)  // LLM via llama.cpp
await ModuleRegistry.shared.register(ONNX.self)      // STT/TTS via ONNX Runtime
```

Each module declares its capabilities:

| Module | Capabilities | Priority |
|--------|--------------|----------|
| `LlamaCPP` | LLM | 100 |
| `ONNX` | STT, TTS | 100 |
| `AppleAI` | LLM (iOS 26+) | 50 |
| `FluidAudioDiarization` | Speaker Diarization | 100 |

Higher priority modules are preferred when multiple can handle a request.

### 2.3 Capabilities & Services

Each AI capability follows a consistent pattern:

1. **Capability Protocol** – Defines the public interface (`LLMCapability`, `STTCapability`, etc.)
2. **Service Protocol** – Backend-agnostic service interface (`LLMService`, `STTService`, etc.)
3. **Service Provider** – Factory that creates services for specific models

```
┌─────────────────────────────────────────────────────────────────┐
│                      RunAnywhere API                             │
├─────────────────────────────────────────────────────────────────┤
│  STT Capability │ TTS Capability │ LLM Capability │ VAD Cap.    │
├─────────────────────────────────────────────────────────────────┤
│     ONNX STT    │   ONNX TTS    │  LlamaCPP LLM  │ Energy VAD  │
│                 │   System TTS  │   Apple AI     │             │
└─────────────────────────────────────────────────────────────────┘
```

### 2.4 Event Bus

The SDK emits events for all significant operations via `EventBus`:

```swift
// Subscribe to all events
let subscription = RunAnywhere.events.on { event in
    print("[\(event.category)] \(event.type)")
}

// Subscribe to specific category
RunAnywhere.events.on(.model) { event in
    if case ModelEvent.downloadProgress(let modelId, let progress, _, _) = event {
        updateProgressUI(modelId: modelId, progress: progress)
    }
}
```

**Event Categories:**
- `.sdk` – Initialization, configuration
- `.model` – Download, load, unload
- `.llm` – Text generation events
- `.stt` – Transcription events
- `.tts` – Synthesis events
- `.voice` – Voice pipeline events
- `.storage` – Cache, cleanup events
- `.error` – Error events

### 2.5 Model Info & Format

Models are described by `ModelInfo`:

```swift
public struct ModelInfo {
    let id: String                           // Unique identifier
    let name: String                         // Human-readable name
    let category: ModelCategory              // .languageModel, .speechRecognition, etc.
    let format: ModelFormat                  // .gguf, .onnx
    let downloadURL: URL?                    // Remote download location
    var localPath: URL?                      // Local file path (when downloaded)
    let downloadSize: Int64?                 // Size in bytes
    let memoryRequired: Int64?               // RAM needed to run
    let compatibleFrameworks: [InferenceFramework]
    let preferredFramework: InferenceFramework?
    let contextLength: Int?                  // For LLMs
    let supportsThinking: Bool               // Reasoning model support
    var isDownloaded: Bool { get }           // Computed: is locally available?
}
```

**Model Categories:**
- `.languageModel` – LLM/chat models
- `.speechRecognition` – STT models (Whisper, Zipformer)
- `.speechSynthesis` – TTS models (Piper, VITS)
- `.voiceActivityDetection` – VAD models
- `.speakerDiarization` – Speaker ID models

**Model Formats:**
- `.gguf` – LlamaCPP (quantized LLMs)
- `.onnx` – ONNX Runtime (STT/TTS)

### 2.6 Error Handling Model

All SDK errors conform to `SDKErrorProtocol` and are exposed as `RunAnywhereError`:

```swift
public enum RunAnywhereError: LocalizedError {
    // Initialization
    case notInitialized
    case alreadyInitialized
    case invalidAPIKey(String?)
    case invalidConfiguration(String)

    // Model
    case modelNotFound(String)
    case modelLoadFailed(String, Error?)
    case modelIncompatible(String, String)

    // Generation
    case generationFailed(String)
    case generationTimeout(String?)
    case contextTooLong(Int, Int)

    // Network
    case networkUnavailable
    case downloadFailed(String, Error?)

    // Storage
    case insufficientStorage(Int64, Int64)
    case storageFull

    // Components
    case componentNotInitialized(String)
    case componentNotReady(String)
}
```

Each error includes:
- `errorDescription` – Human-readable message
- `recoverySuggestion` – Actionable fix guidance
- `category` – For telemetry grouping
- `code` – Machine-readable error code

---

## 3. Getting Started (Swift)

### 3.1 Installation

Add RunAnywhere to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/RunanywhereAI/runanywhere-swift.git", from: "0.16.0")
]
```

Add the products you need:

```swift
.target(
    name: "YourApp",
    dependencies: [
        .product(name: "RunAnywhere", package: "runanywhere-swift"),
        .product(name: "RunAnywhereLlamaCPP", package: "runanywhere-swift"),  // For LLM
        .product(name: "RunAnywhereONNX", package: "runanywhere-swift"),      // For STT/TTS
    ]
)
```

### 3.2 Complete Example: Text Generation

```swift
import RunAnywhere
import LlamaCPPRuntime

// 1. Initialize SDK at app launch
@main
struct MyApp: App {
    init() {
        do {
            try RunAnywhere.initialize(
                apiKey: "your-api-key",
                baseURL: "https://api.runanywhere.ai",
                environment: .production
            )

            // Register LlamaCPP module
            Task { @MainActor in
                ModuleRegistry.shared.register(LlamaCPP.self)
            }
        } catch {
            print("SDK init failed: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

// 2. Use in a SwiftUI view
struct ContentView: View {
    @State private var response = ""
    @State private var isLoading = false

    var body: some View {
        VStack {
            Text(response)
                .padding()

            Button("Generate") {
                Task {
                    await generateText()
                }
            }
            .disabled(isLoading)
        }
    }

    func generateText() async {
        isLoading = true
        defer { isLoading = false }

        do {
            // Load model if not already loaded
            if await !RunAnywhere.isModelLoaded {
                try await RunAnywhere.loadModel("my-llama-model")
            }

            // Generate text
            let result = try await RunAnywhere.generate(
                "Explain quantum computing in simple terms",
                options: LLMGenerationOptions(
                    maxTokens: 200,
                    temperature: 0.7
                )
            )

            response = result.text
            print("Generated in \(result.latencyMs)ms at \(result.tokensPerSecond) tok/s")

        } catch {
            response = "Error: \(error.localizedDescription)"
        }
    }
}
```

### 3.3 Complete Example: Voice Transcription

```swift
import RunAnywhere
import ONNXRuntime
import AVFoundation

struct TranscriptionView: View {
    @State private var transcription = ""

    var body: some View {
        VStack {
            Text(transcription)
            Button("Transcribe Audio File") {
                Task { await transcribeAudio() }
            }
        }
    }

    func transcribeAudio() async {
        do {
            // Register ONNX module (provides STT)
            await MainActor.run {
                ModuleRegistry.shared.register(ONNX.self)
            }

            // Load STT model
            try await RunAnywhere.loadSTTModel("whisper-base-onnx")

            // Load audio file
            let audioURL = Bundle.main.url(forResource: "sample", withExtension: "wav")!
            let audioData = try Data(contentsOf: audioURL)

            // Transcribe
            let text = try await RunAnywhere.transcribe(audioData)
            transcription = text

        } catch {
            transcription = "Error: \(error.localizedDescription)"
        }
    }
}
```

---

## 4. Configuration Deep Dive

### 4.1 SDK Initialization Parameters

```swift
public struct SDKInitParams {
    let apiKey: String              // Required (can be empty for development)
    let baseURL: URL                // Backend API URL
    let environment: SDKEnvironment // .development | .staging | .production
}
```

**Environment Modes:**

| Environment | Log Level | Telemetry | Mock Data | Backend Sync |
|-------------|-----------|-----------|-----------|--------------|
| `.development` | Debug | Yes (to Supabase) | Yes | No |
| `.staging` | Info | Yes | No | Yes |
| `.production` | Warning | Yes | No | Yes |

```swift
// Development mode (local testing, no real backend)
try RunAnywhere.initialize(
    apiKey: "",  // Can be empty
    baseURL: "https://localhost:8080",
    environment: .development
)

// Production mode
try RunAnywhere.initialize(
    apiKey: "sk-prod-xxxxx",
    baseURL: "https://api.runanywhere.ai",
    environment: .production
)
```

### 4.2 LLM Generation Options

```swift
public struct LLMGenerationOptions: Sendable {
    let maxTokens: Int           // Default: 100
    let temperature: Float       // 0.0-2.0, default: 0.8
    let topP: Float              // 0.0-1.0, default: 1.0
    let stopSequences: [String]  // Stop generation at these strings
    let streamingEnabled: Bool   // Enable token-by-token streaming
    let preferredFramework: InferenceFramework?  // Force specific backend
    let structuredOutput: StructuredOutputConfig? // JSON schema output
    let systemPrompt: String?    // System prompt for behavior
}

// Example with all options
let options = LLMGenerationOptions(
    maxTokens: 500,
    temperature: 0.7,
    topP: 0.9,
    stopSequences: ["###", "END"],
    streamingEnabled: true,
    systemPrompt: "You are a helpful assistant. Be concise."
)
```

### 4.3 STT Options

```swift
public struct STTOptions: Sendable {
    let language: String         // BCP-47 code, default: "en"
    let detectLanguage: Bool     // Auto-detect spoken language
    let enablePunctuation: Bool  // Add punctuation, default: true
    let enableDiarization: Bool  // Identify speakers
    let maxSpeakers: Int?        // Max speakers to identify
    let enableTimestamps: Bool   // Word-level timestamps
    let vocabularyFilter: [String] // Custom vocabulary boost
    let audioFormat: AudioFormat // Input format
    let sampleRate: Int          // Input sample rate (default: 16000)
    let preferredFramework: InferenceFramework?
}

// Example: Multi-language transcription with timestamps
let options = STTOptions(
    language: "auto",
    detectLanguage: true,
    enablePunctuation: true,
    enableTimestamps: true,
    vocabularyFilter: ["RunAnywhere", "LlamaCPP"]
)
```

### 4.4 TTS Options

```swift
public struct TTSOptions: Sendable {
    let voice: String?       // Voice ID (nil = default)
    let language: String     // BCP-47 code, default: "en-US"
    let rate: Float          // 0.0-2.0, default: 1.0
    let pitch: Float         // 0.0-2.0, default: 1.0
    let volume: Float        // 0.0-1.0, default: 1.0
    let audioFormat: AudioFormat  // Output format
    let sampleRate: Int      // Output sample rate
    let useSSML: Bool        // Parse SSML markup
}

// Example: Slow, high-pitched voice
let options = TTSOptions(
    voice: "en-US-Neural2-F",
    rate: 0.8,
    pitch: 1.3
)
```

### 4.5 VAD Configuration

```swift
public struct VADConfiguration: Sendable {
    let energyThreshold: Float      // 0.0-1.0, default: 0.015
    let sampleRate: Int             // Default: 16000
    let frameLength: Float          // Seconds, default: 0.1
    let enableAutoCalibration: Bool // Adapt to ambient noise
    let calibrationMultiplier: Float // 1.5-5.0
}

// Builder pattern
let config = VADConfiguration.builder()
    .energyThreshold(0.02)
    .enableAutoCalibration(true)
    .calibrationMultiplier(2.5)
    .build()
```

---

## 5. Feature Guides

### 5.1 Text Generation (LLM)

The SDK provides both simple and advanced text generation APIs.

#### Simple Chat

```swift
// One-liner for quick responses
let response = try await RunAnywhere.chat("What is the capital of France?")
print(response)  // "The capital of France is Paris."
```

#### Full Generation with Metrics

```swift
let result = try await RunAnywhere.generate(
    "Write a haiku about Swift programming",
    options: LLMGenerationOptions(maxTokens: 50, temperature: 1.0)
)

print("Response: \(result.text)")
print("Model: \(result.modelUsed)")
print("Tokens: \(result.tokensUsed)")
print("Speed: \(result.tokensPerSecond) tok/s")
print("Latency: \(result.latencyMs)ms")

// For reasoning models
if let thinking = result.thinkingContent {
    print("Reasoning: \(thinking)")
}
```

#### Streaming Generation

```swift
let streamResult = try await RunAnywhere.generateStream(
    "Tell me a story",
    options: LLMGenerationOptions(maxTokens: 500)
)

// Display tokens as they arrive
for try await token in streamResult.stream {
    print(token, terminator: "")
    textView.text += token
}

// Get final metrics after streaming completes
let metrics = try await streamResult.result.value
print("\n\nGenerated \(metrics.tokensUsed) tokens")
```

#### System Prompts

```swift
let options = LLMGenerationOptions(
    maxTokens: 200,
    systemPrompt: """
    You are a senior Swift developer.
    Answer questions with code examples.
    Use modern Swift conventions.
    """
)

let result = try await RunAnywhere.generate(
    "How do I parse JSON in Swift?",
    options: options
)
```

### 5.2 Structured Output

Generate type-safe JSON output that conforms to Swift `Codable` types.

#### Define Your Type

```swift
struct Recipe: Generatable {
    let name: String
    let ingredients: [String]
    let steps: [String]
    let cookingTimeMinutes: Int

    static var jsonSchema: String {
        """
        {
          "type": "object",
          "properties": {
            "name": { "type": "string" },
            "ingredients": { "type": "array", "items": { "type": "string" } },
            "steps": { "type": "array", "items": { "type": "string" } },
            "cookingTimeMinutes": { "type": "integer" }
          },
          "required": ["name", "ingredients", "steps", "cookingTimeMinutes"]
        }
        """
    }
}
```

#### Generate Structured Output

```swift
let recipe: Recipe = try await RunAnywhere.generateStructured(
    Recipe.self,
    prompt: "Create a recipe for chocolate chip cookies"
)

print("Recipe: \(recipe.name)")
print("Ingredients: \(recipe.ingredients.joined(separator: ", "))")
print("Time: \(recipe.cookingTimeMinutes) minutes")
```

### 5.3 Speech-to-Text (STT)

#### Basic Transcription

```swift
// From Data
let audioData = try Data(contentsOf: audioFileURL)
let text = try await RunAnywhere.transcribe(audioData)

// With options
let output = try await RunAnywhere.transcribeWithOptions(
    audioData,
    options: STTOptions(
        language: "en",
        enableTimestamps: true,
        enablePunctuation: true
    )
)

print("Text: \(output.text)")
if let segments = output.segments {
    for segment in segments {
        print("[\(segment.startTime)-\(segment.endTime)]: \(segment.text)")
    }
}
```

#### From Audio Buffer

```swift
import AVFoundation

let buffer: AVAudioPCMBuffer = ... // From microphone or file
let output = try await RunAnywhere.transcribeBuffer(buffer, language: "en")
```

#### Streaming Transcription

```swift
// Create audio stream (e.g., from microphone)
let audioStream: AsyncStream<Data> = microphoneManager.audioStream

let transcriptionStream = try await RunAnywhere.transcribeStream(
    audioStream,
    options: STTOptions(language: "en")
)

for try await partialText in transcriptionStream {
    transcriptionLabel.text = partialText
}
```

### 5.4 Text-to-Speech (TTS)

#### Basic Synthesis

```swift
// Load a TTS voice
try await RunAnywhere.loadTTSVoice("piper-en-us-amy")

// Synthesize
let output = try await RunAnywhere.synthesize(
    "Hello, welcome to RunAnywhere!",
    options: TTSOptions(rate: 1.0, pitch: 1.0)
)

// Play audio
let player = try AVAudioPlayer(data: output.audioData)
player.play()
```

#### Available Voices

```swift
let voices = await RunAnywhere.availableTTSVoices
for voice in voices {
    print(voice)
}
```

#### Streaming Synthesis

```swift
let audioStream = await RunAnywhere.synthesizeStream(
    "This is a very long text that will be synthesized in chunks...",
    options: TTSOptions()
)

for try await audioChunk in audioStream {
    // Play chunks as they arrive for lower latency
    audioQueue.enqueue(audioChunk)
}
```

#### Stop Synthesis

```swift
await RunAnywhere.stopSynthesis()
```

### 5.5 Voice Activity Detection (VAD)

VAD detects when speech starts and stops in an audio stream.

#### Initialize VAD

```swift
// With default configuration
try await RunAnywhere.initializeVAD()

// With custom configuration
let config = VADConfiguration(
    energyThreshold: 0.02,
    enableAutoCalibration: true
)
try await RunAnywhere.initializeVAD(config)
```

#### Detect Speech in Audio

```swift
import AVFoundation

let buffer: AVAudioPCMBuffer = ... // From microphone
let result = try await RunAnywhere.detectSpeech(in: buffer)

if result.isSpeech {
    print("Speech detected!")
}
```

#### Speech Activity Callback

```swift
await RunAnywhere.setVADSpeechActivityCallback { event in
    switch event {
    case .speechStarted:
        print("User started speaking")
        startRecording()
    case .speechEnded(let duration):
        print("User stopped speaking after \(duration)s")
        stopRecording()
    }
}

// Start VAD processing
await RunAnywhere.startVAD()
```

#### Cleanup

```swift
await RunAnywhere.stopVAD()
await RunAnywhere.cleanupVAD()
```

### 5.6 Voice Agent (Full Pipeline)

The Voice Agent orchestrates VAD → STT → LLM → TTS for complete voice interactions.

#### Initialize Voice Agent

```swift
try await RunAnywhere.initializeVoiceAgent(
    sttModelId: "whisper-base-onnx",
    llmModelId: "llama-3.2-1b-q4",
    ttsVoice: "piper-en-us-amy"
)
```

#### Process Voice Turn

```swift
// Record audio from user
let audioData = audioRecorder.capturedAudio

// Process complete turn
let result = try await RunAnywhere.processVoiceTurn(audioData)

if result.speechDetected {
    print("User said: \(result.transcription ?? "")")
    print("AI response: \(result.response ?? "")")

    // Play synthesized response
    if let audio = result.synthesizedAudio {
        audioPlayer.play(audio)
    }
}
```

#### Stream Voice Processing

```swift
let audioStream: AsyncStream<Data> = microphoneManager.audioStream

let eventStream = await RunAnywhere.processVoiceStream(audioStream)

for try await event in eventStream {
    switch event {
    case .vadTriggered(let isSpeaking):
        updateMicrophoneUI(isActive: isSpeaking)

    case .transcriptionAvailable(let text):
        transcriptionLabel.text = text

    case .responseGenerated(let response):
        responseLabel.text = response

    case .audioSynthesized(let audio):
        audioPlayer.play(audio)

    case .error(let error):
        showError(error)

    case .processed(let result):
        // Complete turn finished
        break
    }
}
```

### 5.7 Speaker Diarization

Identify and track different speakers in audio.

#### Initialize

```swift
try await RunAnywhere.initializeSpeakerDiarization()
```

#### Identify Speakers

```swift
let samples: [Float] = ... // Audio samples
let speakerInfo = try await RunAnywhere.identifySpeaker(samples)

print("Speaker: \(speakerInfo.speakerId)")
print("Name: \(speakerInfo.name ?? "Unknown")")
print("Confidence: \(speakerInfo.confidence)")
```

#### Manage Speakers

```swift
// Get all identified speakers
let speakers = try await RunAnywhere.getAllSpeakers()

// Update speaker name
try await RunAnywhere.updateSpeakerName(speakerId: "spk_001", name: "Alice")

// Reset speaker tracking
try await RunAnywhere.resetSpeakerDiarization()
```

### 5.8 Model Management

#### Discover Available Models

```swift
let models = try await RunAnywhere.availableModels()

for model in models {
    print("\(model.name) (\(model.id))")
    print("  Category: \(model.category)")
    print("  Format: \(model.format)")
    print("  Downloaded: \(model.isDownloaded)")
    print("  Size: \(ByteCountFormatter().string(fromByteCount: model.downloadSize ?? 0))")
}
```

#### Filter by Category/Framework

```swift
// Get LLM models
let llmModels = try await RunAnywhere.getModelsForCategory(.languageModel)

// Get ONNX-compatible models
let onnxModels = try await RunAnywhere.getModelsForFramework(.onnx)
```

#### Fetch Model Assignments

```swift
// Get models assigned to this device from backend
let assigned = try await RunAnywhere.fetchModelAssignments()
```

#### Load/Unload Models

```swift
// Load LLM
try await RunAnywhere.loadModel("llama-3.2-1b-q4")

// Check if loaded
let isLoaded = await RunAnywhere.isModelLoaded

// Get current model
let currentId = await RunAnywhere.getCurrentModelId()

// Unload to free memory
try await RunAnywhere.unloadModel()
```

#### Storage Management

```swift
// Get storage info
let info = await RunAnywhere.getStorageInfo()
print("Used: \(info.usedBytes) / \(info.totalBytes)")

// Clear cache
try await RunAnywhere.clearCache()

// Delete specific model
try await RunAnywhere.deleteStoredModel("old-model-id")

// Clean temp files
try await RunAnywhere.cleanTempFiles()
```

---

## 6. Error Handling & Debugging

### 6.1 Error Categories

Errors are organized by category for easier handling:

| Category | Examples |
|----------|----------|
| `.initialization` | `notInitialized`, `invalidAPIKey` |
| `.model` | `modelNotFound`, `modelLoadFailed`, `modelIncompatible` |
| `.generation` | `generationFailed`, `generationTimeout`, `contextTooLong` |
| `.network` | `networkUnavailable`, `downloadFailed`, `timeout` |
| `.storage` | `insufficientStorage`, `storageFull` |
| `.component` | `componentNotReady`, `componentNotInitialized` |

### 6.2 Error Handling Pattern

```swift
do {
    try await RunAnywhere.loadModel("my-model")
    let result = try await RunAnywhere.generate("Hello")

} catch RunAnywhereError.notInitialized {
    // SDK not initialized
    showError("Please restart the app")

} catch RunAnywhereError.modelNotFound(let modelId) {
    // Model not available
    showError("Model '\(modelId)' not found. Please download it first.")

} catch RunAnywhereError.modelLoadFailed(let modelId, let underlying) {
    // Model failed to load
    print("Failed to load \(modelId): \(underlying?.localizedDescription ?? "unknown")")

} catch RunAnywhereError.generationTimeout(_) {
    // Generation took too long
    showError("Request timed out. Try a shorter prompt.")

} catch RunAnywhereError.insufficientStorage(let required, let available) {
    // Not enough disk space
    let formatter = ByteCountFormatter()
    showError("Need \(formatter.string(fromByteCount: required)), only \(formatter.string(fromByteCount: available)) available")

} catch {
    // Generic error
    showError(error.localizedDescription)
}
```

### 6.3 Debug Mode

Enable verbose logging for development:

```swift
// Enable debug mode
RunAnywhere.setDebugMode(true)

// Set log level directly
RunAnywhere.setLogLevel(.debug)

// Enable local logging (Pulse)
RunAnywhere.configureLocalLogging(enabled: true)
```

### 6.4 Flush Logs and Analytics

```swift
// Force flush all pending data
await RunAnywhere.flushAll()
```

### 6.5 Common Debugging Tips

1. **Model not loading?**
   - Check `model.isDownloaded` before loading
   - Verify model format matches registered modules
   - Check device storage space

2. **Generation slow?**
   - Reduce `maxTokens`
   - Use smaller/quantized models (Q4 vs Q8)
   - Check if model supports Metal acceleration

3. **Audio not transcribing?**
   - Verify sample rate matches (usually 16kHz for STT)
   - Check audio format (PCM is required)
   - Test with a known-good audio file first

4. **Events not firing?**
   - Ensure EventBus subscription is retained
   - Check event category filter

---

## 7. Performance & Resource Management

### 7.1 Memory Considerations

| Model Type | Typical Memory | Notes |
|------------|----------------|-------|
| LLM Q4 (1B) | 1-2 GB | Suitable for all devices |
| LLM Q4 (3B) | 3-4 GB | iPhone Pro / iPad |
| LLM Q4 (7B) | 6-8 GB | M1+ Macs only |
| STT (Whisper Base) | 150 MB | Universal |
| STT (Whisper Large) | 1.5 GB | Pro devices |
| TTS (Piper) | 50-100 MB | Universal |

**Recommendations:**
- Only load one LLM at a time
- Unload models when switching tasks
- Monitor `ModelInfo.memoryRequired` before loading

### 7.2 Threading & Concurrency

The SDK is designed for Swift concurrency:

```swift
// All public APIs are async
try await RunAnywhere.loadModel(...)
try await RunAnywhere.generate(...)

// Component state is MainActor-isolated
@MainActor
class ViewModel: ObservableObject {
    func load() async {
        try await RunAnywhere.loadModel("model-id")
        // Safe to update UI here
    }
}

// Background operations handled internally
// Analytics and telemetry use Task.detached
```

### 7.3 Recommended Patterns

#### Preload Models at App Launch

```swift
@main
struct MyApp: App {
    init() {
        try? RunAnywhere.initialize(...)

        Task {
            // Preload commonly used model
            try? await RunAnywhere.loadModel("default-llm")
        }
    }
}
```

#### Unload When Backgrounded

```swift
.onReceive(NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)) { _ in
    Task {
        try? await RunAnywhere.unloadModel()
    }
}
```

#### Use Streaming for Long Generations

```swift
// Better UX than waiting for full response
let stream = try await RunAnywhere.generateStream(prompt)
for try await token in stream.stream {
    // Update UI progressively
}
```

### 7.4 Performance Tuning

```swift
// Reduce latency with smaller context
let options = LLMGenerationOptions(
    maxTokens: 100,        // Shorter responses
    temperature: 0.0       // Deterministic (faster)
)

// Use preferred framework for specific models
let options = LLMGenerationOptions(
    preferredFramework: .llamaCpp  // Force Metal acceleration
)
```

---

## 8. Integration Patterns

### 8.1 SwiftUI Integration

```swift
import SwiftUI
import RunAnywhere

@MainActor
class ChatViewModel: ObservableObject {
    @Published var messages: [Message] = []
    @Published var isGenerating = false

    func sendMessage(_ text: String) async {
        messages.append(Message(role: .user, content: text))
        isGenerating = true

        do {
            let result = try await RunAnywhere.generate(text)
            messages.append(Message(role: .assistant, content: result.text))
        } catch {
            messages.append(Message(role: .error, content: error.localizedDescription))
        }

        isGenerating = false
    }
}

struct ChatView: View {
    @StateObject private var viewModel = ChatViewModel()
    @State private var input = ""

    var body: some View {
        VStack {
            ScrollView {
                ForEach(viewModel.messages) { message in
                    MessageView(message: message)
                }
            }

            HStack {
                TextField("Message", text: $input)
                Button("Send") {
                    Task {
                        await viewModel.sendMessage(input)
                        input = ""
                    }
                }
                .disabled(viewModel.isGenerating)
            }
        }
    }
}
```

### 8.2 UIKit Integration

```swift
class TranscriptionViewController: UIViewController {
    private var eventSubscription: AnyCancellable?

    override func viewDidLoad() {
        super.viewDidLoad()

        // Subscribe to STT events
        eventSubscription = RunAnywhere.events.on(.stt) { [weak self] event in
            DispatchQueue.main.async {
                self?.handleSTTEvent(event)
            }
        }
    }

    private func handleSTTEvent(_ event: any SDKEvent) {
        if case STTEvent.transcriptionCompleted(let text, _) = event {
            transcriptionLabel.text = text
        }
    }

    @IBAction func transcribeButtonTapped() {
        Task {
            do {
                let text = try await RunAnywhere.transcribe(audioData)
                transcriptionLabel.text = text
            } catch {
                showAlert(error.localizedDescription)
            }
        }
    }
}
```

### 8.3 MVVM with Combine

```swift
class VoiceAssistantViewModel: ObservableObject {
    @Published var state: AssistantState = .idle
    @Published var transcription = ""
    @Published var response = ""

    private var cancellables = Set<AnyCancellable>()

    init() {
        // React to SDK events
        RunAnywhere.events.events(for: .voice)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] event in
                self?.handleVoiceEvent(event)
            }
            .store(in: &cancellables)
    }

    private func handleVoiceEvent(_ event: any SDKEvent) {
        switch event {
        case VoicePipelineEvent.speechDetected:
            state = .listening
        case VoicePipelineEvent.pipelineCompleted:
            state = .idle
        default:
            break
        }
    }
}
```

---

## 9. Testing & Mocks

### 9.1 Development Mode

Use `.development` environment for testing without a real backend:

```swift
try RunAnywhere.initialize(
    apiKey: "",
    baseURL: "https://localhost",
    environment: .development
)
```

### 9.2 Mocking the SDK

Create protocol abstractions for testability:

```swift
// Define abstraction
protocol AIService {
    func generate(_ prompt: String) async throws -> String
}

// Production implementation
class RunAnywhereAIService: AIService {
    func generate(_ prompt: String) async throws -> String {
        let result = try await RunAnywhere.generate(prompt)
        return result.text
    }
}

// Mock for tests
class MockAIService: AIService {
    var mockResponse = "Mock response"
    var generateCallCount = 0

    func generate(_ prompt: String) async throws -> String {
        generateCallCount += 1
        return mockResponse
    }
}
```

### 9.3 Testing with Dependency Injection

```swift
class ViewModel {
    private let aiService: AIService

    init(aiService: AIService = RunAnywhereAIService()) {
        self.aiService = aiService
    }

    func processInput(_ input: String) async -> String {
        do {
            return try await aiService.generate(input)
        } catch {
            return "Error: \(error.localizedDescription)"
        }
    }
}

// In tests
class ViewModelTests: XCTestCase {
    func testProcessInput() async {
        let mock = MockAIService()
        mock.mockResponse = "Test response"

        let viewModel = ViewModel(aiService: mock)
        let result = await viewModel.processInput("Hello")

        XCTAssertEqual(result, "Test response")
        XCTAssertEqual(mock.generateCallCount, 1)
    }
}
```

### 9.4 Reset SDK State

```swift
// Reset for clean test state
RunAnywhere.reset()
```

---

## 10. Troubleshooting & FAQ

### Q: Why does `RunAnywhereError.notInitialized` occur?

**A:** Call `RunAnywhere.initialize(...)` before any other SDK method. This must happen before the first `loadModel`, `generate`, or `transcribe` call.

### Q: Model download fails with "insufficient storage"

**A:**
1. Check available space: `await RunAnywhere.getStorageInfo()`
2. Clear cache: `try await RunAnywhere.clearCache()`
3. Delete unused models: `try await RunAnywhere.deleteStoredModel("old-model")`

### Q: Why is generation slow?

**A:**
1. Use quantized models (Q4 instead of Q8)
2. Reduce `maxTokens`
3. Ensure Metal is available (check `device.supportsFamily(.metal3)`)
4. Avoid running on simulator—use a real device

### Q: How do I disable telemetry?

**A:** In development mode, telemetry goes to a dev analytics service. For production, telemetry is sent to your configured backend. The SDK does not send data to external third parties. To minimize telemetry, use `.development` environment.

### Q: Can I use multiple models simultaneously?

**A:**
- **LLM**: Only one at a time (memory constraints)
- **STT/TTS**: Can coexist with LLM
- **VAD**: Lightweight, always available

### Q: App crashes with "out of memory"

**A:**
1. Check `ModelInfo.memoryRequired` before loading
2. Unload models when not in use
3. Use smaller quantizations
4. Monitor with Instruments > Allocations

### Q: Audio transcription returns empty text

**A:**
1. Verify audio is 16kHz mono PCM
2. Check audio duration (minimum ~1 second)
3. Test with a known-working audio file
4. Ensure STT model is loaded: `await RunAnywhere.isSTTModelLoaded`

### Q: How do I handle app backgrounding?

**A:**
```swift
NotificationCenter.default.addObserver(
    forName: UIApplication.didEnterBackgroundNotification,
    object: nil,
    queue: .main
) { _ in
    Task {
        await RunAnywhere.stopVAD()
        try? await RunAnywhere.unloadModel()
    }
}
```

### Q: Events aren't being received

**A:**
1. Retain the `AnyCancellable` subscription
2. Check you're subscribing to the correct category
3. Ensure SDK is initialized before subscribing

---

## 11. Limitations

### Current Limitations

1. **Single LLM Model**: Only one LLM can be loaded at a time due to memory constraints.

2. **Apple Intelligence**: Requires iOS 26+ / macOS 26+ (currently in beta).

3. **Resume Downloads**: Partial download resume is not yet implemented.

4. **VLM (Vision-Language Models)**: Architecture defined but not yet fully implemented.

### Platform Requirements

| Module | iOS | macOS | Notes |
|--------|-----|-------|-------|
| RunAnywhere Core | 17+ | 14+ | Base requirement |
| LlamaCPPRuntime | 17+ | 14+ | Metal acceleration |
| ONNXRuntime | 17+ | 14+ | CPU + CoreML |
| FoundationModelsAdapter | 26+ | 26+ | Apple Intelligence |
| FluidAudioDiarization | 17+ | 14+ | Speaker ID |

---

## 12. Links & Next Steps

### Documentation

- [`ARCHITECTURE.md`](./ARCHITECTURE.md) – Technical architecture details
- [`Docs/current-state/`](./Docs/current-state/) – Detailed internal documentation
- [`CHANGELOG.md`](./CHANGELOG.md) – Version history

### Resources

- **Model Downloads**: Models are fetched from your configured `baseURL`
- **Binary Distribution**: XCFrameworks from [runanywhere-binaries](https://github.com/RunanywhereAI/runanywhere-binaries)

### Getting Help

1. Check this documentation first
2. Review error messages—they include recovery suggestions
3. Enable debug mode for verbose logging
4. File issues with logs and reproduction steps

---

© 2025 RunAnywhere AI. All rights reserved.
