# RunAnywhere Swift SDK - Public API Reference

## Overview

The RunAnywhere Swift SDK provides a comprehensive on-device AI platform with privacy-first execution and multi-framework support. Version 2.0+ offers **two complementary approaches**: simple direct methods for common use cases and an optional event-based architecture for advanced scenarios.

### Key Features

- **Privacy-First Design**: Default device-only routing for maximum privacy
- **Simple Direct Methods**: Clean async/await API for 80% of use cases
- **Optional Event System**: Subscribe to events for advanced monitoring and analytics
- **Multi-Framework Support**: Unified API across 15+ ML frameworks
- **Multi-Modal Capabilities**: Text generation, voice transcription, structured output
- **Intelligent Model Management**: Automatic discovery, downloading, validation
- **Performance Monitoring**: Real-time metrics available through events when needed
- **Cost Optimization**: Token budget management and savings tracking
- **Streaming Support**: Real-time token streaming with simple async streams

### Supported Frameworks

- **Text Generation**: Core ML, MLX, llama.cpp, GGUF, ONNX, TensorFlow Lite, ExecuTorch, Swift Transformers, Foundation Models, PicoLLM, MLC, MediaPipe
- **Voice/Audio**: WhisperKit, OpenAI Whisper
- **Custom**: Extensible framework adapter system

## Table of Contents

1. [Getting Started](#getting-started)
2. [SDK Initialization](#sdk-initialization)
3. [Text Generation](#text-generation)
4. [Model Management](#model-management)
5. [Voice & Audio](#voice--audio)
6. [Structured Output](#structured-output)
7. [Configuration Management](#configuration-management)
8. [Storage Management](#storage-management)
9. [Framework Management](#framework-management)
10. [Advanced: Event-Based Architecture](#advanced-event-based-architecture)
11. [Error Handling](#error-handling)
12. [Migration Guide](#migration-guide)
13. [Best Practices](#best-practices)

## Getting Started

### Installation

Add the RunAnywhere SDK to your project using Swift Package Manager:

#### Via Xcode
1. Open your project in Xcode
2. Go to File → Add Package Dependencies
3. Enter the repository URL: `https://github.com/runanywhere/ios-sdk`
4. Select version: "Up to Next Major" from `1.0.0`
5. Click "Add Package"

#### Via Package.swift
```swift
dependencies: [
    // For latest version 1.x
    .package(url: "https://github.com/runanywhere/ios-sdk", from: "1.0.0")

    // Or pin to specific version
    .package(url: "https://github.com/runanywhere/ios-sdk", exact: "1.0.0")

    // For private repo (with GitHub access token configured)
    .package(url: "https://github.com/runanywhere/ios-sdk.git", .branch("main"))
]
```

### Basic Usage

```swift
import RunAnywhere

// Initialize the SDK with just an API key
try await RunAnywhere.initialize(apiKey: "your-api-key")

// Simple text generation
let response = try await RunAnywhere.chat("Hello, how are you?")
print(response)

// Generate with options
let result = try await RunAnywhere.generate(
    "Write a haiku about coding",
    options: RunAnywhereGenerationOptions(
        maxTokens: 50,
        temperature: 0.8
    )
)
print(result)

// Load a model
try await RunAnywhere.loadModel("llama-3.2-1b")

// Stream responses
let stream = RunAnywhere.generateStream("Tell me a story")
for try await chunk in stream {
    print(chunk, terminator: "")
}
```

## API Design Philosophy

### Two Complementary Approaches

The RunAnywhere SDK provides two ways to interact with AI models:

1. **Direct Methods (Primary)** - Simple async/await for common use cases
2. **Event System (Optional)** - Advanced monitoring and reactive programming

### When to Use Each Approach

**Use Direct Methods when you need:**
- Simple request/response operations
- Loading models, generating text, transcribing audio
- Straightforward error handling with try/catch
- Quick integration with minimal code

**Use Event System when you need:**
- Real-time progress monitoring
- Analytics and metrics collection
- Multi-subscriber scenarios
- Building debugging dashboards
- Reactive UI updates

## SDK Initialization

### Simple Initialization

Initialize with just an API key:

```swift
try await RunAnywhere.initialize(apiKey: "your-api-key")
```

### Check Initialization Status

```swift
// Check if SDK is initialized
if RunAnywhere.isInitialized {
    // SDK is ready to use
}
```

### Advanced: Initialization Events

For advanced monitoring, initialization automatically publishes these events:
- `SDKInitializationEvent.started`
- `SDKConfigurationEvent.loaded`
- `SDKModelEvent.catalogLoaded`
- `SDKDeviceEvent.deviceInfoCollected`
- `SDKInitializationEvent.completed` or `.failed`

See [Event-Based Architecture](#advanced-event-based-architecture) for subscription details.

## Text Generation

### Simple Generation

```swift
// Simplest usage - just pass a prompt
let response = try await RunAnywhere.chat("Hello, how are you?")

// With options for more control
let response = try await RunAnywhere.generate(
    "Write a poem about nature",
    options: RunAnywhereGenerationOptions(
        maxTokens: 100,
        temperature: 0.8,
        topP: 0.9
    )
)
```

### Streaming Generation

```swift
// Stream tokens as they're generated
let stream = RunAnywhere.generateStream(
    "Tell me a long story",
    options: RunAnywhereGenerationOptions(maxTokens: 500)
)

for try await chunk in stream {
    print(chunk, terminator: "") // Print each token as it arrives
}
```

### Generation Options

```swift
public struct RunAnywhereGenerationOptions {
    public let maxTokens: Int                     // Default: 100
    public let temperature: Float                 // Default: 0.7
    public let topP: Float                       // Default: 1.0
    public let stopSequences: [String]          // Default: []
    public let seed: Int?                       // For reproducibility
    public let systemPrompt: String?            // System message
    public let structuredOutput: StructuredOutputConfig? // For JSON output
}
```

## Model Management

### Loading Models

```swift
// Load a model by ID
try await RunAnywhere.loadModel("llama-3.2-1b")

// Load and get model info
let modelInfo = try await RunAnywhere.loadModelWithInfo("llama-3.2-1b")
print("Loaded: \(modelInfo.name) (\(modelInfo.size) bytes)")
```

### Model Discovery

```swift
// Get all available models
let models = try await RunAnywhere.availableModels()

// Get stored models
let storedModels = await RunAnywhere.getStoredModels()

// List models (triggers discovery)
let allModels = try await RunAnywhere.listAvailableModels()
```

### Model Operations

```swift
// Download a model
try await RunAnywhere.downloadModel("llama-3.2-1b")

// Delete a model
try await RunAnywhere.deleteModel("model-id")

// Unload current model
try await RunAnywhere.unloadModel()

// Get current model
if let model = RunAnywhere.currentModel {
    print("Current model: \(model.name)")
}
```

### Custom Models

```swift
// Add a custom model from URL
let modelInfo = await RunAnywhere.addModelFromURL(
    URL(string: "https://example.com/model.gguf")!,
    name: "My Custom Model",
    type: "language"
)
```

## Voice & Audio

### Simple Transcription

```swift
// Transcribe audio with default settings
let result = try await RunAnywhere.transcribe(audioData)
print("Transcribed: \(result.text)")
```

### Advanced Transcription

```swift
// Transcribe with specific model and options
let result = try await RunAnywhere.transcribe(
    audio: audioData,
    modelId: "whisper-large",
    options: STTOptions(
        language: "en",
        enableTimestamps: true
    )
)

print("Text: \(result.text)")
print("Confidence: \(result.confidence)")
```

### Voice Pipeline

```swift
// Create a complete voice interaction pipeline
let config = ModularPipelineConfig(
    sttConfig: VoiceSTTConfig(modelId: "whisper-base"),
    llmConfig: VoiceLLMConfig(modelId: "llama-3.2-1b"),
    ttsConfig: VoiceTTSConfig(),
    vadConfig: VADConfig()
)

let pipeline = RunAnywhere.createVoicePipeline(config: config)

// Process audio stream
let audioStream = AsyncStream<VoiceAudioChunk> { /* audio chunks */ }
let eventStream = RunAnywhere.processVoice(
    audioStream: audioStream,
    config: config
)

for try await event in eventStream {
    switch event {
    case .transcriptionResult(let text):
        print("User said: \(text)")
    case .generationResult(let response):
        print("AI response: \(response)")
    case .audioGenerated(let audioData):
        // Play the synthesized audio
        playAudio(audioData)
    }
}
```

## Structured Output

### Type-Safe JSON Generation

```swift
// Define your structure
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

// Generate structured data
let recipe = try await RunAnywhere.generateStructured(
    Recipe.self,
    prompt: "Create a recipe for chocolate chip cookies"
)

print("Recipe: \(recipe.title)")
print("Prep time: \(recipe.prepTime) minutes")
```

### Validation Modes

```swift
// Strict validation - fails if output doesn't match exactly
let strictResult = try await RunAnywhere.generateStructured(
    Recipe.self,
    prompt: "Create a recipe",
    validationMode: .strict
)

// Lenient validation - allows minor deviations
let lenientResult = try await RunAnywhere.generateStructured(
    Recipe.self,
    prompt: "Create a recipe",
    validationMode: .lenient
)
```

## Configuration Management

### Update Settings

```swift
// Update generation settings
await RunAnywhere.requestConfiguration(
    RunAnywhere.ConfigurationRequest(
        temperature: 0.9,
        maxTokens: 200,
        topP: 0.95
    )
)
```

### Get Current Settings

```swift
// Query current configuration
let settings = await RunAnywhere.getCurrentGenerationSettings()
let routingPolicy = await RunAnywhere.getCurrentRoutingPolicy()
let privacyMode = await RunAnywhere.getCurrentPrivacyMode()
```

### Configuration Presets

```swift
// Use built-in presets
await RunAnywhere.requestConfiguration(.creative())         // High temperature
await RunAnywhere.requestConfiguration(.precise())          // Low temperature
await RunAnywhere.requestConfiguration(.balanced())         // Balanced settings
await RunAnywhere.requestConfiguration(.privacyFocused())   // Device-only
```

## Storage Management

### Storage Information

```swift
// Get storage statistics
let info = await RunAnywhere.getStorageInfo()
print("Storage used: \(info.usedSpace) / \(info.totalSpace) bytes")
print("Models: \(info.modelCount)")

// Get stored models
let models = await RunAnywhere.getStoredModels()
for model in models {
    print("\(model.name): \(model.size) bytes")
}
```

### Storage Cleanup

```swift
// Clear cache
try await RunAnywhere.clearCache()

// Clean temporary files
try await RunAnywhere.cleanTempFiles()

// Delete specific model
try await RunAnywhere.deleteStoredModel("model-id")

// Get base directory for custom storage
let baseURL = RunAnywhere.getBaseDirectoryURL()
```

## Framework Management

### Register Custom Framework

```swift
// Register a custom framework adapter
class MyCustomAdapter: UnifiedFrameworkAdapter {
    // Implementation...
}

let adapter = MyCustomAdapter()
RunAnywhere.registerFrameworkAdapter(adapter)
```

### Framework Discovery

```swift
// Get available frameworks
let frameworks = RunAnywhere.getAvailableFrameworks()
// Returns: [.coreML, .mlx, .gguf, .tensorFlowLite, ...]

// Get models for specific framework
let coreMLModels = RunAnywhere.getModelsForFramework(.coreML)

// Check framework support
let supportsTTS = RunAnywhere.frameworkSupports(.whisperKit, modality: .textToVoice)
```

## Advanced: Event-Based Architecture

For advanced use cases requiring real-time monitoring, analytics, or reactive programming, the SDK provides a comprehensive event system.

### When to Use Events

Consider using events for:
- **Progress Monitoring**: Track download/upload progress
- **Analytics Collection**: Gather performance metrics
- **Debug Dashboards**: Build real-time monitoring tools
- **Reactive UI**: Update UI based on SDK state changes
- **Multi-Subscriber Scenarios**: Multiple components need updates

### Accessing the Event Bus

```swift
import Combine

// Access the event bus
let events = RunAnywhere.events

// Store subscriptions
var cancellables = Set<AnyCancellable>()
```

### Event Types

```swift
public enum SDKEventType {
    case initialization  // SDK startup/shutdown
    case configuration  // Settings changes
    case generation     // Text generation lifecycle
    case model         // Model loading/unloading
    case voice         // Voice processing events
    case storage       // Storage operations
    case framework     // Framework management
    case device        // Device information
    case error         // Error events
    case performance   // Performance metrics
    case network       // Network operations
}
```

### Event Subscription Examples

#### Progress Monitoring

```swift
// Monitor model download progress
RunAnywhere.events.modelEvents
    .sink { event in
        switch event {
        case .downloadStarted(let modelId):
            print("Downloading \(modelId)...")
        case .downloadProgress(let modelId, let progress):
            print("\(modelId): \(Int(progress * 100))%")
        case .downloadCompleted(let modelId):
            print("\(modelId) downloaded!")
        default:
            break
        }
    }
    .store(in: &cancellables)

// Then trigger the download
try await RunAnywhere.downloadModel("llama-3.2-1b")
```

#### Analytics Collection

```swift
// Collect generation metrics
RunAnywhere.events.generationEvents
    .sink { event in
        switch event {
        case .completed(let response, let tokens, let latency):
            // Log analytics
            Analytics.track("generation", [
                "tokens": tokens,
                "latency_ms": latency,
                "model": RunAnywhere.currentModel?.id ?? "unknown"
            ])
        case .costCalculated(let amount, let saved):
            // Track costs
            Analytics.track("cost", [
                "amount": amount,
                "saved": saved
            ])
        default:
            break
        }
    }
    .store(in: &cancellables)
```

#### Reactive UI Updates

```swift
class ChatViewModel: ObservableObject {
    @Published var isGenerating = false
    @Published var currentResponse = ""
    private var cancellables = Set<AnyCancellable>()

    init() {
        // Update UI based on generation events
        RunAnywhere.events.generationEvents
            .receive(on: DispatchQueue.main)
            .sink { [weak self] event in
                switch event {
                case .started:
                    self?.isGenerating = true
                    self?.currentResponse = ""
                case .tokenGenerated(let token):
                    self?.currentResponse += token
                case .completed, .failed:
                    self?.isGenerating = false
                default:
                    break
                }
            }
            .store(in: &cancellables)
    }

    func sendMessage(_ prompt: String) async {
        // Just call the method - events update UI automatically
        _ = try? await RunAnywhere.generate(prompt)
    }
}
```

### Complete Event Reference

#### Generation Events

```swift
public enum SDKGenerationEvent: SDKEvent {
    case started(prompt: String, sessionId: String? = nil)
    case firstTokenGenerated(token: String, latencyMs: Double)
    case tokenGenerated(token: String)
    case streamingUpdate(text: String, tokensCount: Int)
    case completed(response: String, tokensUsed: Int, latencyMs: Double)
    case failed(Error)
    case costCalculated(amount: Double, savedAmount: Double)
    case routingDecision(target: String, reason: String)
}
```

#### Model Events

```swift
public enum SDKModelEvent: SDKEvent {
    case loadStarted(modelId: String)
    case loadProgress(modelId: String, progress: Double)
    case loadCompleted(modelId: String)
    case loadFailed(modelId: String, error: Error)
    case downloadStarted(modelId: String)
    case downloadProgress(modelId: String, progress: Double)
    case downloadCompleted(modelId: String)
    case listCompleted(models: [ModelInfo])
    // ... more events
}
```

#### Voice Events

```swift
public enum SDKVoiceEvent: SDKEvent {
    case transcriptionStarted
    case transcriptionPartial(text: String)
    case transcriptionFinal(text: String)
    case pipelineCreated(config: ModularPipelineConfig)
    case pipelineStarted(config: ModularPipelineConfig)
    case pipelineEvent(ModularPipelineEvent)
    case pipelineCompleted
    case pipelineError(Error)
}
```


## Error Handling

### Error Types

```swift
// Primary SDK error type
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

// Structured output errors
public enum StructuredOutputError: LocalizedError {
    case invalidJSON(String)
    case validationFailed(String)
    case extractionFailed(String)
    case schemaGenerationFailed(String)
    case streamingNotSupported
}

// Voice processing errors
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

### Error Handling Patterns

```swift
do {
    let result = try await RunAnywhere.generate("Hello")
} catch SDKError.notInitialized {
    print("SDK not initialized - call RunAnywhere.initialize() first")
} catch SDKError.modelNotFound(let modelId) {
    print("Model not found: \(modelId)")
} catch {
    print("Error: \(error.localizedDescription)")
}
```

### Error Events

All errors are also published as events:

```swift
RunAnywhere.events.generationEvents
    .sink { event in
        if case .failed(let error) = event {
            // Handle generation error
        }
    }
    .store(in: &cancellables)
```

## Migration Guide

### From RunAnywhereSDK (v1.x) to RunAnywhere (v2.0+)

#### Key Changes

1. **Single Entry Point**: `RunAnywhere` enum replaces `RunAnywhereSDK.shared`
2. **Simplified Initialization**: Just provide API key instead of complex configuration
3. **Optional Events**: Events available but not required for basic usage
4. **Cleaner APIs**: Shorter method names, better defaults
5. **Modern Patterns**: Full async/await support throughout

#### Quick Migration Examples

```swift
// ❌ Old (v1.x)
let config = Configuration(
    apiKey: "key",
    routingPolicy: .deviceOnly,
    // ... many more parameters
)
try await RunAnywhereSDK.shared.initialize(configuration: config)
let result = try await RunAnywhereSDK.shared.generate(
    prompt: "Hello",
    options: GenerationOptions(maxTokens: 100)
)

// ✅ New (v2.0+)
try await RunAnywhere.initialize(apiKey: "key")
let result = try await RunAnywhere.generate(
    "Hello",
    options: RunAnywhereGenerationOptions(maxTokens: 100)
)
```

## Best Practices

### 1. Start Simple

```swift
// Start with direct methods for basic functionality
class ChatService {
    func sendMessage(_ prompt: String) async throws -> String {
        try await RunAnywhere.generate(prompt)
    }
}
```

### 2. Add Events When Needed

```swift
// Add event subscriptions only when you need them
class ChatServiceWithProgress {
    @Published var progress: Double = 0
    private var cancellables = Set<AnyCancellable>()

    init() {
        // Only subscribe if you need progress updates
        RunAnywhere.events.modelEvents
            .compactMap { event in
                if case .downloadProgress(_, _, let progress) = event {
                    return progress
                }
                return nil
            }
            .assign(to: &$progress)
    }

    func downloadModel(_ modelId: String) async throws {
        // Direct method call - events update progress automatically
        try await RunAnywhere.downloadModel(modelId)
    }
}
```

### 3. Error Handling

```swift
// Simple error handling with try/catch
do {
    let response = try await RunAnywhere.generate("Hello")
    print(response)
} catch SDKError.notInitialized {
    print("Please initialize the SDK first")
} catch SDKError.modelNotFound(let id) {
    print("Model \(id) not found")
} catch {
    print("Error: \(error)")
}
```

### 4. Memory Management

```swift
// Only store cancellables when using events
class MyService {
    private var cancellables: Set<AnyCancellable>?

    func enableMonitoring() {
        cancellables = Set<AnyCancellable>()
        RunAnywhere.events.performanceEvents
            .sink { /* handle */ }
            .store(in: &cancellables!)
    }

    func disableMonitoring() {
        cancellables = nil // Clean up subscriptions
    }
}
```

### 5. Choose the Right Approach

**Use Direct Methods for:**
- Loading models
- Generating text
- Simple transcription
- Basic operations

**Use Events for:**
- Progress tracking
- Analytics collection
- Debug monitoring
- Multi-component coordination


## Platform Support

- **iOS**: 13.0+
- **macOS**: 10.15+
- **tvOS**: 13.0+
- **watchOS**: 6.0+
- **visionOS**: 1.0+

## Thread Safety

All public APIs are thread-safe and use modern Swift concurrency (async/await). All event publishers are safe to subscribe to from any thread.

## Performance Tips

1. **Use Direct Methods**: Simpler and more efficient for basic operations
2. **Stream for Long Responses**: Use `generateStream()` for better UX
3. **Preload Models**: Load models before they're needed
4. **Monitor Resources**: Check storage before downloading models
5. **Leverage Caching**: SDK caches models and responses automatically

## What's New in 2.0+

### Simplified API Surface
- Single `RunAnywhere` entry point (no more `.shared`)
- Cleaner method names and better defaults
- Simple initialization with just an API key

### Two Complementary Approaches
- **Direct Methods**: Simple async/await for 80% of use cases
- **Optional Events**: Advanced monitoring when you need it

### Modern Swift Patterns
- Full async/await support
- AsyncThrowingStream for streaming
- Combine integration for reactive programming

### Better Developer Experience
- Reduced boilerplate code
- Intuitive method names
- Clear error messages

## Support

- Documentation: https://docs.runanywhere.ai
- Issues: https://github.com/runanywhere/swift-sdk/issues
- Community: https://discord.gg/runanywhere
