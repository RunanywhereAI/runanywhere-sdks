# RunAnywhere Swift SDK - API Reference

## Table of Contents

1. [Overview](#overview)
2. [Core Classes](#core-classes)
   - [RunAnywhereSDK](#runanywheresk)
   - [Configuration](#configuration)
   - [LoadedModel](#loadedmodel)
3. [Data Types](#data-types)
   - [GenerationOptions](#generationoptions)
   - [GenerationResult](#generationresult)
   - [Message](#message)
   - [Context](#context)
   - [ModelLoadOptions](#modelloadoptions)
4. [Enumerations](#enumerations)
   - [PrivacyMode](#privacymode)
   - [ExecutionMode](#executionmode)
   - [ModelFormat](#modelformat)
   - [MessageRole](#messagerole)
5. [Protocols](#protocols)
   - [HardwareDetector](#hardwaredetector)
   - [AuthProvider](#authprovider)
   - [ModelProvider](#modelprovider)
6. [Error Handling](#error-handling)
   - [RunAnywhereError](#runanywheerror)
7. [Extensions](#extensions)
8. [Best Practices](#best-practices)

## Overview

The RunAnywhere Swift SDK provides a comprehensive API for integrating on-device and cloud-based AI models into your iOS, macOS, tvOS, and watchOS applications. This reference covers all public APIs, their usage, and best practices.

## Core Classes

### RunAnywhereSDK

The main entry point for the SDK. This is a singleton class that manages the SDK lifecycle.

```swift
public class RunAnywhereSDK {
    /// Shared instance of the SDK
    public static let shared: RunAnywhereSDK
    
    /// Current SDK version
    public static let version: String
    
    /// Whether the SDK has been initialized
    public private(set) var isInitialized: Bool
    
    /// Current configuration
    public private(set) var configuration: Configuration?
}
```

#### Methods

##### initialize(apiKey:configuration:)

Initializes the SDK with your API key and optional configuration.

```swift
public func initialize(
    apiKey: String,
    configuration: Configuration = Configuration()
) async throws
```

**Parameters:**
- `apiKey`: Your RunAnywhere API key
- `configuration`: Optional configuration settings

**Throws:**
- `RunAnywhereError.invalidAPIKey`: If the API key is invalid
- `RunAnywhereError.networkError`: If initialization fails due to network issues

**Example:**
```swift
try await RunAnywhereSDK.shared.initialize(
    apiKey: "your-api-key",
    configuration: Configuration(
        privacyMode: .balanced,
        debugMode: true
    )
)
```

##### loadModel(_:options:)

Loads a model by name or identifier.

```swift
public func loadModel(
    _ identifier: String,
    options: ModelLoadOptions? = nil
) async throws -> LoadedModel
```

**Parameters:**
- `identifier`: Model name or identifier (e.g., "llama-3.2-1b", "gpt-4-mini")
- `options`: Optional loading options

**Returns:**
- `LoadedModel`: A loaded model instance ready for inference

**Throws:**
- `RunAnywhereError.modelNotFound`: If the model doesn't exist
- `RunAnywhereError.insufficientMemory`: If there's not enough memory
- `RunAnywhereError.downloadError`: If model download fails

**Example:**
```swift
let model = try await RunAnywhereSDK.shared.loadModel(
    "llama-3.2-1b",
    options: ModelLoadOptions(
        preferredExecution: .onDevice,
        maxMemoryUsage: 2_000_000_000
    )
)
```

##### createContext()

Creates a new conversation context for multi-turn conversations.

```swift
public func createContext() -> Context
```

**Returns:**
- `Context`: A new conversation context

**Example:**
```swift
let context = RunAnywhereSDK.shared.createContext()
context.addMessage(Message(role: .user, content: "Hello!"))
```

##### listAvailableModels()

Lists all available models that can be loaded.

```swift
public func listAvailableModels() async throws -> [ModelInfo]
```

**Returns:**
- `[ModelInfo]`: Array of available model information

**Example:**
```swift
let models = try await RunAnywhereSDK.shared.listAvailableModels()
for model in models {
    print("\(model.name): \(model.size) bytes")
}
```

##### clearCache()

Clears the model cache to free up disk space.

```swift
public func clearCache() async throws
```

**Example:**
```swift
try await RunAnywhereSDK.shared.clearCache()
```

##### setHardwareDetector(_:)

Sets a custom hardware detector for capability detection.

```swift
public func setHardwareDetector(_ detector: HardwareDetector)
```

**Parameters:**
- `detector`: Custom hardware detector implementation

##### setAuthProvider(_:)

Sets a custom authentication provider.

```swift
public func setAuthProvider(_ provider: AuthProvider)
```

**Parameters:**
- `provider`: Custom authentication provider implementation

### Configuration

Configuration options for SDK initialization.

```swift
public struct Configuration {
    /// Whether to allow cloud execution as fallback
    public var allowCloudFallback: Bool
    
    /// Privacy mode setting
    public var privacyMode: PrivacyMode
    
    /// Local directory for model storage
    public var localModelPath: String?
    
    /// Enable debug logging
    public var debugMode: Bool
    
    /// Maximum memory usage in bytes
    public var maxMemoryUsage: Int?
    
    /// Network timeout in seconds
    public var networkTimeout: TimeInterval
    
    /// Custom headers for API requests
    public var customHeaders: [String: String]
    
    /// Model cache size limit in bytes
    public var cacheSizeLimit: Int
}
```

**Default Values:**
- `allowCloudFallback`: `true`
- `privacyMode`: `.balanced`
- `localModelPath`: `nil` (uses default)
- `debugMode`: `false`
- `maxMemoryUsage`: `nil` (system decides)
- `networkTimeout`: `30.0`
- `customHeaders`: `[:]`
- `cacheSizeLimit`: `10_737_418_240` (10GB)

**Example:**
```swift
let config = Configuration(
    allowCloudFallback: false,
    privacyMode: .strict,
    debugMode: true,
    maxMemoryUsage: 4_000_000_000, // 4GB
    cacheSizeLimit: 20_000_000_000  // 20GB
)
```

### LoadedModel

Represents a loaded model ready for inference.

```swift
public class LoadedModel {
    /// Model identifier
    public let identifier: String
    
    /// Model metadata
    public let metadata: ModelMetadata
    
    /// Current execution mode
    public private(set) var executionMode: ExecutionMode
    
    /// Whether the model is currently loaded in memory
    public var isLoaded: Bool { get }
}
```

#### Methods

##### generate(prompt:options:)

Generates text based on a prompt.

```swift
public func generate(
    prompt: String,
    options: GenerationOptions = GenerationOptions()
) async throws -> GenerationResult
```

**Parameters:**
- `prompt`: The input prompt
- `options`: Generation options

**Returns:**
- `GenerationResult`: The generation result with text and metadata

**Example:**
```swift
let result = try await model.generate(
    prompt: "Explain quantum computing",
    options: GenerationOptions(
        maxTokens: 100,
        temperature: 0.7
    )
)
```

##### generate(context:options:)

Generates text based on a conversation context.

```swift
public func generate(
    context: Context,
    options: GenerationOptions = GenerationOptions()
) async throws -> GenerationResult
```

**Parameters:**
- `context`: Conversation context with message history
- `options`: Generation options

**Returns:**
- `GenerationResult`: The generation result

**Example:**
```swift
let result = try await model.generate(
    context: conversationContext,
    options: GenerationOptions(maxTokens: 200)
)
```

##### generateStream(prompt:options:)

Generates text as a stream of tokens.

```swift
public func generateStream(
    prompt: String,
    options: GenerationOptions = GenerationOptions()
) async throws -> AsyncThrowingStream<String, Error>
```

**Returns:**
- `AsyncThrowingStream<String, Error>`: Stream of generated tokens

**Example:**
```swift
let stream = try await model.generateStream(
    prompt: "Write a story",
    options: GenerationOptions(maxTokens: 500)
)

for try await token in stream {
    print(token, terminator: "")
}
```

##### unload()

Unloads the model from memory.

```swift
public func unload() async
```

**Example:**
```swift
await model.unload()
```

## Data Types

### GenerationOptions

Options for text generation.

```swift
public struct GenerationOptions {
    /// Maximum number of tokens to generate
    public var maxTokens: Int
    
    /// Sampling temperature (0.0 to 2.0)
    public var temperature: Double
    
    /// Top-p sampling parameter
    public var topP: Double
    
    /// Top-k sampling parameter
    public var topK: Int?
    
    /// Frequency penalty (-2.0 to 2.0)
    public var frequencyPenalty: Double
    
    /// Presence penalty (-2.0 to 2.0)
    public var presencePenalty: Double
    
    /// Stop sequences
    public var stopSequences: [String]
    
    /// Preferred execution mode
    public var preferredExecution: ExecutionMode
    
    /// Cost threshold in USD
    public var costThreshold: Decimal?
    
    /// Random seed for reproducibility
    public var seed: Int?
    
    /// System prompt override
    public var systemPrompt: String?
}
```

**Default Values:**
- `maxTokens`: `512`
- `temperature`: `1.0`
- `topP`: `1.0`
- `topK`: `nil`
- `frequencyPenalty`: `0.0`
- `presencePenalty`: `0.0`
- `stopSequences`: `[]`
- `preferredExecution`: `.auto`
- `costThreshold`: `nil`
- `seed`: `nil`
- `systemPrompt`: `nil`

### GenerationResult

Result of a text generation request.

```swift
public struct GenerationResult {
    /// Generated text
    public let text: String
    
    /// Number of tokens generated
    public let tokenCount: Int
    
    /// Time taken in seconds
    public let latency: TimeInterval
    
    /// Tokens per second
    public let tokensPerSecond: Double
    
    /// Estimated cost in USD
    public let estimatedCost: Decimal
    
    /// Estimated savings from on-device execution
    public let estimatedSavings: Decimal
    
    /// Actual execution mode used
    public let executionMode: ExecutionMode
    
    /// Model used for generation
    public let modelUsed: String
    
    /// Finish reason
    public let finishReason: FinishReason
    
    /// Usage statistics
    public let usage: Usage
}
```

#### Nested Types

```swift
public enum FinishReason {
    case stop           // Natural completion
    case length         // Hit max tokens
    case contentFilter  // Content filtered
    case error          // Error occurred
}

public struct Usage {
    public let promptTokens: Int
    public let completionTokens: Int
    public let totalTokens: Int
}
```

### Message

Represents a message in a conversation.

```swift
public struct Message {
    /// Message identifier
    public let id: String
    
    /// Role of the message sender
    public let role: MessageRole
    
    /// Message content
    public let content: String
    
    /// Optional name for the sender
    public let name: String?
    
    /// Timestamp
    public let timestamp: Date
    
    /// Custom metadata
    public var metadata: [String: Any]
    
    public init(
        role: MessageRole,
        content: String,
        name: String? = nil,
        metadata: [String: Any] = [:]
    )
}
```

### Context

Manages conversation context for multi-turn interactions.

```swift
public class Context {
    /// Unique context identifier
    public let id: String
    
    /// All messages in the conversation
    public private(set) var messages: [Message]
    
    /// Maximum context length in tokens
    public var maxLength: Int
    
    /// Add a message to the context
    public func addMessage(_ message: Message)
    
    /// Remove a message by ID
    public func removeMessage(id: String)
    
    /// Clear all messages
    public func clear()
    
    /// Get formatted prompt for model
    public func formattedPrompt() -> String
    
    /// Truncate to fit within token limit
    public func truncate(to maxTokens: Int)
}
```

### ModelLoadOptions

Options for loading a model.

```swift
public struct ModelLoadOptions {
    /// Preferred execution mode
    public var preferredExecution: ExecutionMode
    
    /// Maximum memory to use
    public var maxMemoryUsage: Int?
    
    /// Whether to preload into memory
    public var preload: Bool
    
    /// Custom model path
    public var customPath: String?
    
    /// Model quantization level
    public var quantization: QuantizationLevel?
    
    /// Hardware acceleration options
    public var acceleration: AccelerationOptions
}
```

#### Nested Types

```swift
public enum QuantizationLevel {
    case none
    case int8
    case int4
    case mixed
}

public struct AccelerationOptions {
    public var useGPU: Bool
    public var useNeuralEngine: Bool
    public var useMetal: Bool
}
```

## Enumerations

### PrivacyMode

Controls privacy settings for the SDK.

```swift
public enum PrivacyMode {
    /// No cloud execution, no telemetry, maximum privacy
    case strict
    
    /// Cloud allowed with explicit consent, anonymized telemetry
    case balanced
    
    /// Full cloud integration, detailed telemetry
    case permissive
}
```

### ExecutionMode

Specifies where model execution should occur.

```swift
public enum ExecutionMode {
    /// Automatically choose best option
    case auto
    
    /// Force on-device execution
    case onDevice
    
    /// Force cloud execution
    case cloud
    
    /// Use both for comparison
    case hybrid
}
```

### ModelFormat

Supported model file formats.

```swift
public enum ModelFormat {
    case gguf
    case coreML
    case mlx
    case onnx
    case tensorflowLite
    case custom(String)
}
```

### MessageRole

Role in a conversation.

```swift
public enum MessageRole {
    case system
    case user
    case assistant
    case function
}
```

## Protocols

### HardwareDetector

Protocol for custom hardware capability detection.

```swift
public protocol HardwareDetector {
    /// Detect current hardware capabilities
    func detectCapabilities() -> HardwareCapabilities
    
    /// Check if specific model can run
    func canRunModel(_ model: ModelInfo) -> Bool
    
    /// Get available memory
    func availableMemory() -> Int
    
    /// Get thermal state
    func thermalState() -> ThermalState
}
```

#### Associated Types

```swift
public struct HardwareCapabilities {
    public let deviceModel: String
    public let chipType: String
    public let totalMemory: Int
    public let availableMemory: Int
    public let hasNeuralEngine: Bool
    public let hasGPU: Bool
    public let gpuMemory: Int?
    public let supportedFormats: [ModelFormat]
}

public enum ThermalState {
    case nominal
    case fair
    case serious
    case critical
}
```

### AuthProvider

Protocol for custom authentication.

```swift
public protocol AuthProvider {
    /// Get authentication token
    func getAuthToken() async throws -> String
    
    /// Refresh token if needed
    func refreshToken() async throws -> String
    
    /// Check if token is valid
    func isTokenValid() -> Bool
    
    /// Handle authentication error
    func handleAuthError(_ error: Error) async throws
}
```

### ModelProvider

Protocol for custom model providers.

```swift
public protocol ModelProvider {
    /// Supported model formats
    var supportedFormats: [ModelFormat] { get }
    
    /// Load model from URL
    func loadModel(from url: URL, format: ModelFormat) async throws -> LoadedModelInstance
    
    /// Check if format is supported
    func supports(format: ModelFormat) -> Bool
    
    /// Validate model file
    func validate(modelAt url: URL) async throws -> Bool
    
    /// Get model metadata
    func metadata(for url: URL) async throws -> ModelMetadata
}
```

## Error Handling

### RunAnywhereError

Comprehensive error types for the SDK.

```swift
public enum RunAnywhereError: LocalizedError {
    /// API key is invalid or missing
    case invalidAPIKey(String)
    
    /// Model not found
    case modelNotFound(identifier: String)
    
    /// Insufficient memory for operation
    case insufficientMemory(required: Int, available: Int)
    
    /// Network-related errors
    case networkError(Error)
    
    /// Download failed
    case downloadError(url: URL, underlying: Error)
    
    /// Model validation failed
    case validationError(reason: String)
    
    /// Execution error
    case executionError(model: String, reason: String)
    
    /// Configuration error
    case configurationError(String)
    
    /// Not initialized
    case notInitialized
    
    /// Operation cancelled
    case cancelled
    
    /// Timeout
    case timeout(TimeInterval)
    
    /// Cost threshold exceeded
    case costThresholdExceeded(cost: Decimal, threshold: Decimal)
    
    /// Privacy policy violation
    case privacyPolicyViolation(String)
    
    /// Unsupported platform
    case unsupportedPlatform(String)
    
    /// Model format not supported
    case unsupportedFormat(ModelFormat)
    
    public var errorDescription: String? { get }
    public var recoverySuggestion: String? { get }
}
```

### Error Handling Examples

```swift
do {
    let model = try await RunAnywhereSDK.shared.loadModel("llama-3.2-1b")
    let result = try await model.generate(prompt: "Hello")
} catch RunAnywhereError.modelNotFound(let identifier) {
    print("Model '\(identifier)' not found")
    // Suggest alternative models
} catch RunAnywhereError.insufficientMemory(let required, let available) {
    print("Need \(required) bytes but only \(available) available")
    // Try smaller model or free memory
} catch RunAnywhereError.networkError(let error) {
    print("Network error: \(error)")
    // Retry or use offline model
} catch {
    print("Unexpected error: \(error)")
}
```

## Extensions

### Combine Support

For apps using Combine framework:

```swift
import Combine

extension RunAnywhereSDK {
    /// Publisher for model loading
    public func loadModelPublisher(
        _ identifier: String,
        options: ModelLoadOptions? = nil
    ) -> AnyPublisher<LoadedModel, Error>
    
    /// Publisher for text generation
    public func generatePublisher(
        model: LoadedModel,
        prompt: String,
        options: GenerationOptions
    ) -> AnyPublisher<GenerationResult, Error>
}
```

### SwiftUI Support

Property wrappers and view modifiers:

```swift
import SwiftUI

@propertyWrapper
public struct RunAnywhereModel: DynamicProperty {
    public var wrappedValue: LoadedModel?
    public init(_ identifier: String)
}

extension View {
    /// Show loading indicator while model loads
    public func runAnywhereLoading() -> some View
    
    /// Handle RunAnywhere errors
    public func runAnywhereError(
        _ error: Binding<RunAnywhereError?>,
        retry: @escaping () -> Void
    ) -> some View
}
```

## Best Practices

### 1. Initialization

Always initialize the SDK before using any other methods:

```swift
@main
struct MyApp: App {
    init() {
        Task {
            do {
                try await RunAnywhereSDK.shared.initialize(
                    apiKey: ProcessInfo.processInfo.environment["RUNANYWHERE_API_KEY"] ?? "",
                    configuration: Configuration(debugMode: true)
                )
            } catch {
                print("Failed to initialize SDK: \(error)")
            }
        }
    }
}
```

### 2. Error Handling

Always handle errors appropriately:

```swift
func generateText(prompt: String) async {
    do {
        let model = try await RunAnywhereSDK.shared.loadModel("llama-3.2-1b")
        let result = try await model.generate(prompt: prompt)
        // Use result
    } catch RunAnywhereError.insufficientMemory {
        // Try smaller model
        await generateWithSmallerModel(prompt: prompt)
    } catch RunAnywhereError.networkError {
        // Show offline message
        showOfflineAlert()
    } catch {
        // Generic error handling
        showError(error)
    }
}
```

### 3. Memory Management

Monitor memory usage and unload models when not needed:

```swift
class ModelManager {
    private var loadedModels: [String: LoadedModel] = [:]
    
    func model(for identifier: String) async throws -> LoadedModel {
        if let existing = loadedModels[identifier] {
            return existing
        }
        
        // Check memory before loading
        let memoryAvailable = getAvailableMemory()
        if memoryAvailable < requiredMemory {
            // Unload least recently used
            await unloadLRUModel()
        }
        
        let model = try await RunAnywhereSDK.shared.loadModel(identifier)
        loadedModels[identifier] = model
        return model
    }
}
```

### 4. Cost Optimization

Set cost thresholds to control spending:

```swift
let options = GenerationOptions(
    maxTokens: 1000,
    costThreshold: 0.01, // $0.01 maximum
    preferredExecution: .auto
)

do {
    let result = try await model.generate(prompt: prompt, options: options)
    print("Cost: $\(result.estimatedCost), Saved: $\(result.estimatedSavings)")
} catch RunAnywhereError.costThresholdExceeded(let cost, let threshold) {
    print("Would cost $\(cost), exceeds threshold of $\(threshold)")
}
```

### 5. Privacy First

Configure privacy settings based on your app's requirements:

```swift
// For apps handling sensitive data
let config = Configuration(
    allowCloudFallback: false,
    privacyMode: .strict,
    debugMode: false
)

// For general apps
let config = Configuration(
    allowCloudFallback: true,
    privacyMode: .balanced,
    debugMode: true
)
```

### 6. Streaming for Better UX

Use streaming for long generations:

```swift
@MainActor
class ChatViewModel: ObservableObject {
    @Published var responseText = ""
    
    func generate(prompt: String) async {
        responseText = ""
        
        do {
            let stream = try await model.generateStream(
                prompt: prompt,
                options: GenerationOptions(maxTokens: 500)
            )
            
            for try await token in stream {
                responseText += token
            }
        } catch {
            responseText = "Error: \(error.localizedDescription)"
        }
    }
}
```

### 7. Context Management

Properly manage conversation context:

```swift
class ConversationManager {
    private let context = RunAnywhereSDK.shared.createContext()
    private let maxContextTokens = 4096
    
    func addUserMessage(_ content: String) {
        context.addMessage(Message(role: .user, content: content))
        
        // Truncate if needed
        if context.tokenCount > maxContextTokens {
            context.truncate(to: maxContextTokens - 500) // Leave room
        }
    }
    
    func generateResponse() async throws -> String {
        let result = try await model.generate(
            context: context,
            options: GenerationOptions(maxTokens: 500)
        )
        
        // Add assistant response to context
        context.addMessage(Message(
            role: .assistant,
            content: result.text
        ))
        
        return result.text
    }
}
```

## Migration Guide

### From Version 0.x to 1.0

Key changes:
1. Async/await APIs instead of completion handlers
2. Unified error types
3. Improved cost tracking
4. New streaming APIs

```swift
// Old (0.x)
RunAnywhereSDK.shared.loadModel("llama") { result in
    switch result {
    case .success(let model):
        model.generate("Hello") { response in
            print(response.text)
        }
    case .failure(let error):
        print(error)
    }
}

// New (1.0)
do {
    let model = try await RunAnywhereSDK.shared.loadModel("llama-3.2-1b")
    let result = try await model.generate(prompt: "Hello")
    print(result.text)
} catch {
    print(error)
}
```

## Conclusion

The RunAnywhere Swift SDK provides a powerful yet simple API for integrating AI models into your applications. By following the patterns and best practices outlined in this reference, you can build robust, privacy-focused, and cost-effective AI-powered features.

For more examples and tutorials, visit our [GitHub repository](https://github.com/yourusername/runanywhere-swift) or check out the [sample applications](https://github.com/yourusername/runanywhere-swift/tree/main/examples).