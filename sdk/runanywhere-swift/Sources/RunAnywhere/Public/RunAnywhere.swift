import Foundation
import Combine

/// The clean, event-based RunAnywhere SDK
/// Single entry point with both event-driven and async/await patterns
public enum RunAnywhere {

    // MARK: - Internal State Management

    /// Internal configuration storage
    internal static var _configuration: Configuration?
    private static var _isInitialized = false

    /// Access to service container (through the shared instance for now)
    internal static var serviceContainer: ServiceContainer {
        ServiceContainer.shared
    }

    /// Check if SDK is initialized
    public static var isInitialized: Bool {
        _isInitialized
    }

    // MARK: - Event Access

    /// Access to all SDK events for subscription-based patterns
    public static var events: EventBus {
        EventBus.shared
    }

    // MARK: - Simple Initialization

    /// Initialize the SDK with just an API key
    /// - Parameter apiKey: Your RunAnywhere API key
    public static func initialize(apiKey: String) async throws {
        EventBus.shared.publish(SDKInitializationEvent.started)

        do {
            // Validate API key first
            guard !apiKey.isEmpty else {
                throw SDKError.invalidAPIKey("API key cannot be empty")
            }

            // Create configuration
            let config = Configuration(apiKey: apiKey)
            _configuration = config

            // Bootstrap services directly
            try await serviceContainer.bootstrap(with: config)

            // Initialize device information collection
            await initializeDeviceInfo()

            // Get current configuration from configuration service
            let configService = await serviceContainer.configurationService
            let currentConfig = await configService.getConfiguration()
            EventBus.shared.publish(SDKConfigurationEvent.loaded(configuration: currentConfig))

            // Get model information from model info service
            let modelInfoService = await serviceContainer.modelInfoService
            let storedModels = try await modelInfoService.loadStoredModels()
            EventBus.shared.publish(SDKModelEvent.catalogLoaded(models: storedModels))

            // Mark as initialized
            _isInitialized = true

            EventBus.shared.publish(SDKInitializationEvent.completed)
        } catch {
            _configuration = nil
            _isInitialized = false
            EventBus.shared.publish(SDKInitializationEvent.failed(error))
            throw error
        }
    }

    /// Initialize device information collection during SDK startup
    private static func initializeDeviceInfo() async {
        let deviceInfoService = await serviceContainer.deviceInfoService

        // Load current device information
        if let deviceInfo = await deviceInfoService.loadCurrentDeviceInfo() {
            EventBus.shared.publish(SDKDeviceEvent.deviceInfoCollected(deviceInfo: deviceInfo))

            // Log device summary for debugging
            let summary = await deviceInfoService.getDeviceInfoSummary()
            print("RunAnywhere SDK - Device Info:\n\(summary)")
        } else {
            print("RunAnywhere SDK - Warning: Could not collect device information")
        }
    }

    // MARK: - Text Generation (Clean Async/Await Interface)

    /// Simple text generation with automatic event publishing
    /// - Parameter prompt: The text prompt
    /// - Returns: Generated response
    public static func chat(_ prompt: String) async throws -> String {
        return try await generate(prompt, options: nil)
    }

    /// Text generation with options
    /// - Parameters:
    ///   - prompt: The text prompt
    ///   - options: Generation options (optional)
    /// - Returns: Generated response
    public static func generate(
        _ prompt: String,
        options: RunAnywhereGenerationOptions? = nil
    ) async throws -> String {
        await EventBus.shared.publish(SDKGenerationEvent.started(prompt: prompt))

        do {
            // Ensure initialized
            guard _isInitialized else {
                throw SDKError.notInitialized
            }

            // Use options directly or defaults
            let result = try await serviceContainer.generationService.generate(
                prompt: prompt,
                options: options ?? RunAnywhereGenerationOptions()
            )

            await EventBus.shared.publish(SDKGenerationEvent.completed(
                response: result.text,
                tokensUsed: result.tokensUsed,
                latencyMs: result.latencyMs
            ))

            if result.savedAmount > 0 {
                await EventBus.shared.publish(SDKGenerationEvent.costCalculated(
                    amount: 0,
                    savedAmount: result.savedAmount
                ))
            }

            return result.text
        } catch {
            await EventBus.shared.publish(SDKGenerationEvent.failed(error))
            throw error
        }
    }

    /// Streaming text generation
    /// - Parameters:
    ///   - prompt: The text prompt
    ///   - options: Generation options (optional)
    /// - Returns: AsyncStream of generated tokens
    public static func generateStream(
        _ prompt: String,
        options: RunAnywhereGenerationOptions? = nil
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task {
                await EventBus.shared.publish(SDKGenerationEvent.started(prompt: prompt))

                do {
                    // Ensure initialized
                    guard _isInitialized else {
                        throw SDKError.notInitialized
                    }

                    let stream = serviceContainer.streamingService.generateStream(
                        prompt: prompt,
                        options: options ?? RunAnywhereGenerationOptions()
                    )

                    var fullResponse = ""
                    for try await token in stream {
                        await EventBus.shared.publish(SDKGenerationEvent.tokenGenerated(token: token))
                        fullResponse += token
                        continuation.yield(token)
                    }

                    await EventBus.shared.publish(SDKGenerationEvent.completed(
                        response: fullResponse,
                        tokensUsed: fullResponse.count / 4, // Rough estimate
                        latencyMs: 0 // Would need to track properly
                    ))

                    continuation.finish()
                } catch {
                    await EventBus.shared.publish(SDKGenerationEvent.failed(error))
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    /// Structured output generation
    /// - Parameters:
    ///   - type: The type to generate
    ///   - prompt: The text prompt
    /// - Returns: Generated structured data
    public static func generateStructured<T: Generatable>(
        _ type: T.Type,
        prompt: String
    ) async throws -> T {
        await EventBus.shared.publish(SDKGenerationEvent.started(prompt: prompt))

        do {
            // Ensure initialized
            guard _isInitialized else {
                throw SDKError.notInitialized
            }

            // For now, structured output generation is not fully implemented
            // This would need proper JSON schema generation and parsing
            throw SDKError.notImplemented
        } catch {
            await EventBus.shared.publish(SDKGenerationEvent.failed(error))
            throw error
        }
    }

    // MARK: - Voice Operations

    /// Simple voice transcription
    /// - Parameter audioData: Audio data to transcribe
    /// - Returns: Transcribed text
    public static func transcribe(_ audioData: Data) async throws -> String {
        await EventBus.shared.publish(SDKVoiceEvent.transcriptionStarted)

        do {
            // Ensure initialized
            guard _isInitialized else {
                throw SDKError.notInitialized
            }

            // Use voice capability service directly
            // Find voice service and transcribe
            guard let voiceService = serviceContainer.voiceCapabilityService.findVoiceService(for: "whisper-base") else {
                throw STTError.noVoiceServiceAvailable
            }

            try await voiceService.initialize(modelPath: "whisper-base")
            let result = try await voiceService.transcribe(audio: audioData, options: STTOptions())

            await EventBus.shared.publish(SDKVoiceEvent.transcriptionFinal(text: result.text))
            return result.text
        } catch {
            await EventBus.shared.publish(SDKVoiceEvent.pipelineError(error))
            throw error
        }
    }

    // MARK: - Model Management

    /// Load a model by ID
    /// - Parameter modelId: The model identifier
    public static func loadModel(_ modelId: String) async throws {
        await EventBus.shared.publish(SDKModelEvent.loadStarted(modelId: modelId))

        do {
            // Ensure initialized
            guard _isInitialized else {
                throw SDKError.notInitialized
            }

            let loadedModel = try await serviceContainer.modelLoadingService.loadModel(modelId)

            // IMPORTANT: Set the loaded model in the generation service
            serviceContainer.generationService.setCurrentModel(loadedModel)

            await EventBus.shared.publish(SDKModelEvent.loadCompleted(modelId: modelId))
        } catch {
            await EventBus.shared.publish(SDKModelEvent.loadFailed(modelId: modelId, error: error))
            throw error
        }
    }

    /// Get available models
    /// - Returns: Array of available models
    public static func availableModels() async throws -> [ModelInfo] {
        guard _isInitialized else {
            throw SDKError.notInitialized
        }

        // Use model registry to get available models
        let models = await serviceContainer.modelRegistry.discoverModels()
        return models
    }

    /// Get currently loaded model
    /// - Returns: Currently loaded model info
    public static var currentModel: ModelInfo? {
        guard _isInitialized else {
            return nil
        }

        // Get the current model from the generation service
        return serviceContainer.generationService.getCurrentModel()?.model
    }
}


// MARK: - Conversation Management

/// Simple conversation manager
public class Conversation {
    private var messages: [String] = []

    public init() {}

    /// Send a message and get response
    public func send(_ message: String) async throws -> String {
        messages.append("User: \(message)")

        let contextPrompt = messages.joined(separator: "\n") + "\nAssistant:"
        let response = try await RunAnywhere.generate(contextPrompt)

        messages.append("Assistant: \(response)")
        return response
    }

    /// Get conversation history
    public var history: [String] {
        messages
    }

    /// Clear conversation
    public func clear() {
        messages.removeAll()
    }
}

// MARK: - Factory Methods

extension RunAnywhere {
    /// Create a new conversation
    public static func conversation() -> Conversation {
        Conversation()
    }
}
