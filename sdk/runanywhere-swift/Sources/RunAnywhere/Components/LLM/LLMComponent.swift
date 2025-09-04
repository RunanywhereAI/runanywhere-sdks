import Foundation

// MARK: - LLM Service Protocol

/// Protocol for language model services
public protocol LLMService: AnyObject {
    /// Initialize the LLM service with optional model path
    func initialize(modelPath: String?) async throws

    /// Generate text from prompt
    func generate(prompt: String, options: RunAnywhereGenerationOptions) async throws -> String

    /// Stream generation token by token
    func streamGenerate(
        prompt: String,
        options: RunAnywhereGenerationOptions,
        onToken: @escaping (String) -> Void
    ) async throws

    /// Check if service is ready
    var isReady: Bool { get }

    /// Get current model identifier
    var currentModel: String? { get }

    /// Cleanup resources
    func cleanup() async
}

/// Errors for LLM services
public enum LLMServiceError: LocalizedError {
    case notInitialized
    case modelNotFound(String)
    case generationFailed(Error)
    case streamingNotSupported
    case contextLengthExceeded
    case invalidOptions

    public var errorDescription: String? {
        switch self {
        case .notInitialized:
            return "LLM service is not initialized"
        case .modelNotFound(let model):
            return "Model not found: \(model)"
        case .generationFailed(let error):
            return "Generation failed: \(error.localizedDescription)"
        case .streamingNotSupported:
            return "Streaming generation is not supported"
        case .contextLengthExceeded:
            return "Context length exceeded"
        case .invalidOptions:
            return "Invalid generation options"
        }
    }
}

// MARK: - LLM Configuration

/// Configuration for LLM component (conforms to ComponentConfiguration and ComponentInitParameters protocols)
public struct LLMConfiguration: ComponentConfiguration, ComponentInitParameters {
    /// Component type
    public var componentType: SDKComponent { .llm }

    /// Model ID
    public let modelId: String?

    // Model loading parameters
    public let contextLength: Int
    public let useGPUIfAvailable: Bool
    public let quantizationLevel: QuantizationLevel?
    public let cacheSize: Int // Token cache size in MB
    public let preloadContext: String? // Optional system prompt to preload

    // Default generation parameters
    public let temperature: Double
    public let maxTokens: Int
    public let systemPrompt: String?
    public let streamingEnabled: Bool

    public enum QuantizationLevel: String, Sendable {
        case q4v0 = "Q4_0"
        case q4KM = "Q4_K_M"
        case q5KM = "Q5_K_M"
        case q6K = "Q6_K"
        case q8v0 = "Q8_0"
        case f16 = "F16"
        case f32 = "F32"
    }

    public init(
        modelId: String? = nil,
        contextLength: Int = 2048,
        useGPUIfAvailable: Bool = true,
        quantizationLevel: QuantizationLevel? = nil,
        cacheSize: Int = 100,
        preloadContext: String? = nil,
        temperature: Double = 0.7,
        maxTokens: Int = 100,
        systemPrompt: String? = nil,
        streamingEnabled: Bool = true
    ) {
        self.modelId = modelId
        self.contextLength = contextLength
        self.useGPUIfAvailable = useGPUIfAvailable
        self.quantizationLevel = quantizationLevel
        self.cacheSize = cacheSize
        self.preloadContext = preloadContext
        self.temperature = temperature
        self.maxTokens = maxTokens
        self.systemPrompt = systemPrompt ?? preloadContext
        self.streamingEnabled = streamingEnabled
    }

    public func validate() throws {
        guard contextLength > 0 && contextLength <= 32768 else {
            throw SDKError.validationFailed("Context length must be between 1 and 32768")
        }
        guard cacheSize >= 0 && cacheSize <= 1000 else {
            throw SDKError.validationFailed("Cache size must be between 0 and 1000 MB")
        }
        guard temperature >= 0 && temperature <= 2.0 else {
            throw SDKError.validationFailed("Temperature must be between 0 and 2.0")
        }
        guard maxTokens > 0 && maxTokens <= contextLength else {
            throw SDKError.validationFailed("Max tokens must be between 1 and context length")
        }
    }
}

// MARK: - LLM Input/Output Models

/// Input for Language Model generation (conforms to ComponentInput protocol)
public struct LLMInput: ComponentInput {
    /// Messages in the conversation
    public let messages: [Message]

    /// Optional system prompt override
    public let systemPrompt: String?

    /// Optional context for conversation
    public let context: Context?

    /// Optional generation options override
    public let options: RunAnywhereGenerationOptions?

    public init(
        messages: [Message],
        systemPrompt: String? = nil,
        context: Context? = nil,
        options: RunAnywhereGenerationOptions? = nil
    ) {
        self.messages = messages
        self.systemPrompt = systemPrompt
        self.context = context
        self.options = options
    }

    /// Convenience initializer for single prompt
    public init(prompt: String, systemPrompt: String? = nil) {
        self.messages = [Message(role: .user, content: prompt)]
        self.systemPrompt = systemPrompt
        self.context = nil
        self.options = nil
    }

    public func validate() throws {
        guard !messages.isEmpty else {
            throw SDKError.validationFailed("LLMInput must contain at least one message")
        }
    }
}

/// Output from Language Model generation (conforms to ComponentOutput protocol)
public struct LLMOutput: ComponentOutput {
    /// Generated text
    public let text: String

    /// Token usage statistics
    public let tokenUsage: TokenUsage

    /// Generation metadata
    public let metadata: GenerationMetadata

    /// Finish reason
    public let finishReason: FinishReason

    /// Timestamp (required by ComponentOutput)
    public let timestamp: Date

    public init(
        text: String,
        tokenUsage: TokenUsage,
        metadata: GenerationMetadata,
        finishReason: FinishReason,
        timestamp: Date = Date()
    ) {
        self.text = text
        self.tokenUsage = tokenUsage
        self.metadata = metadata
        self.finishReason = finishReason
        self.timestamp = timestamp
    }
}

/// Token usage information
public struct TokenUsage: Sendable {
    public let promptTokens: Int
    public let completionTokens: Int

    public var totalTokens: Int {
        promptTokens + completionTokens
    }

    public init(promptTokens: Int, completionTokens: Int) {
        self.promptTokens = promptTokens
        self.completionTokens = completionTokens
    }
}

/// Generation metadata
public struct GenerationMetadata: Sendable {
    public let modelId: String
    public let temperature: Float
    public let generationTime: TimeInterval
    public let tokensPerSecond: Double?

    public init(
        modelId: String,
        temperature: Float,
        generationTime: TimeInterval,
        tokensPerSecond: Double? = nil
    ) {
        self.modelId = modelId
        self.temperature = temperature
        self.generationTime = generationTime
        self.tokensPerSecond = tokensPerSecond
    }
}

/// Reason for generation completion
public enum FinishReason: String, Sendable {
    case completed = "completed"
    case maxTokens = "max_tokens"
    case stopSequence = "stop_sequence"
    case contentFilter = "content_filter"
    case error = "error"
}

// MARK: - LLM Service Registration

/// Protocol for registering external LLM implementations
public protocol LLMServiceProvider {
    /// Create an LLM service for the given configuration
    func createLLMService(configuration: LLMConfiguration) async throws -> LLMService

    /// Check if this provider can handle the given model
    func canHandle(modelId: String?) -> Bool

    /// Provider name for identification
    var name: String { get }
}

// MARK: - LLM Service Wrapper

/// Wrapper class to allow protocol-based LLM service to work with BaseComponent
public final class LLMServiceWrapper: ServiceWrapper {
    public typealias ServiceProtocol = any LLMService
    public var wrappedService: (any LLMService)?

    public init(_ service: (any LLMService)? = nil) {
        self.wrappedService = service
    }
}

// MARK: - LLM Component

/// Language Model component following the clean architecture
@MainActor
public final class LLMComponent: BaseComponent<LLMServiceWrapper>, @unchecked Sendable {

    // MARK: - Properties

    public override class var componentType: SDKComponent { .llm }

    private let llmConfiguration: LLMConfiguration
    private var conversationContext: Context?
    private var isModelLoaded = false

    // Model lifecycle tracking
    private var modelPath: String?
    private var modelLoadProgress: Double = 0.0

    // MARK: - Initialization

    public init(configuration: LLMConfiguration) {
        self.llmConfiguration = configuration

        // Preload context if provided
        if let preloadContext = configuration.preloadContext {
            self.conversationContext = Context(systemPrompt: preloadContext)
        }

        super.init(configuration: configuration)
    }

    // MARK: - Service Creation

    public override func createService() async throws -> LLMServiceWrapper {
        // Check if model needs downloading
        if let modelId = llmConfiguration.modelId {
            modelPath = modelId // In real implementation, check if model exists

            // Simulate download check
            let needsDownload = false // In real implementation, check model store

            if needsDownload {
                // Emit download required event
                eventBus.publish(ComponentInitializationEvent.componentDownloadRequired(
                    component: Self.componentType,
                    modelId: modelId,
                    sizeBytes: 1_000_000_000 // 1GB example
                ))

                // Download model
                try await downloadModel(modelId: modelId)
            }
        }

        // Try to get a registered LLM provider from central registry
        guard let provider = ModuleRegistry.shared.llmProvider(for: llmConfiguration.modelId) else {
            throw SDKError.componentNotInitialized(
                "No LLM service provider registered. Please add llama.cpp or another LLM implementation as a dependency and register it with ModuleRegistry.shared.registerLLM(provider)."
            )
        }

        // Create service through provider
        let llmService = try await provider.createLLMService(configuration: llmConfiguration)

        // Initialize the service
        try await llmService.initialize(modelPath: modelPath)
        isModelLoaded = true

        // Wrap and return the service
        return LLMServiceWrapper(llmService)
    }

    public override func performCleanup() async throws {
        await service?.wrappedService?.cleanup()
        isModelLoaded = false
        modelPath = nil
        conversationContext = nil
    }

    // MARK: - Model Management

    private func downloadModel(modelId: String) async throws {
        // Emit download started event
        eventBus.publish(ComponentInitializationEvent.componentDownloadStarted(
            component: Self.componentType,
            modelId: modelId
        ))

        // Simulate download with progress
        for progress in stride(from: 0.0, through: 1.0, by: 0.1) {
            modelLoadProgress = progress
            eventBus.publish(ComponentInitializationEvent.componentDownloadProgress(
                component: Self.componentType,
                modelId: modelId,
                progress: progress
            ))
            try await Task.sleep(nanoseconds: 100_000_000) // 0.1 second
        }

        // Emit download completed event
        eventBus.publish(ComponentInitializationEvent.componentDownloadCompleted(
            component: Self.componentType,
            modelId: modelId
        ))
    }

    // MARK: - Helper Properties

    private var llmService: (any LLMService)? {
        return service?.wrappedService
    }

    // MARK: - Public API

    /// Generate text from a simple prompt
    public func generate(_ prompt: String, systemPrompt: String? = nil) async throws -> LLMOutput {
        try ensureReady()

        let input = LLMInput(
            messages: [Message(role: .user, content: prompt)],
            systemPrompt: systemPrompt
        )
        return try await process(input)
    }

    /// Generate text from prompt (overload for compatibility)
    public func generate(prompt: String) async throws -> LLMOutput {
        return try await generate(prompt, systemPrompt: nil)
    }

    /// Generate with conversation history
    public func generateWithHistory(_ messages: [Message], systemPrompt: String? = nil) async throws -> LLMOutput {
        try ensureReady()

        let input = LLMInput(messages: messages, systemPrompt: systemPrompt)
        return try await process(input)
    }

    /// Process LLM input
    public func process(_ input: LLMInput) async throws -> LLMOutput {
        try ensureReady()

        guard let llmService = llmService else {
            throw SDKError.componentNotReady("LLM service not available")
        }

        // Validate input
        try input.validate()

        // Use provided options or create from configuration
        let options = input.options ?? RunAnywhereGenerationOptions(
            maxTokens: llmConfiguration.maxTokens,
            temperature: Float(llmConfiguration.temperature),
            streamingEnabled: llmConfiguration.streamingEnabled
        )

        // Build prompt
        let prompt = buildPrompt(from: input.messages, systemPrompt: input.systemPrompt ?? llmConfiguration.systemPrompt)

        // Track generation time
        let startTime = Date()

        // Generate response
        let response = try await llmService.generate(prompt: prompt, options: options)

        let generationTime = Date().timeIntervalSince(startTime)

        // Calculate tokens (rough estimate - real implementation would get from service)
        let promptTokens = prompt.count / 4
        let completionTokens = response.count / 4
        let tokensPerSecond = Double(completionTokens) / generationTime

        // Create output
        return LLMOutput(
            text: response,
            tokenUsage: TokenUsage(
                promptTokens: promptTokens,
                completionTokens: completionTokens
            ),
            metadata: GenerationMetadata(
                modelId: llmService.currentModel ?? "unknown",
                temperature: options.temperature,
                generationTime: generationTime,
                tokensPerSecond: tokensPerSecond
            ),
            finishReason: .completed
        )
    }

    /// Stream generation
    public func streamGenerate(
        _ prompt: String,
        systemPrompt: String? = nil
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    try ensureReady()

                    guard let llmService = llmService else {
                        continuation.finish(throwing: SDKError.componentNotReady("LLM service not available"))
                        return
                    }

                    let options = RunAnywhereGenerationOptions(
                        maxTokens: llmConfiguration.maxTokens,
                        temperature: Float(llmConfiguration.temperature),
                        streamingEnabled: true
                    )

                    let fullPrompt = buildPrompt(
                        from: [Message(role: .user, content: prompt)],
                        systemPrompt: systemPrompt ?? llmConfiguration.systemPrompt
                    )

                    try await llmService.streamGenerate(
                        prompt: fullPrompt,
                        options: options
                    ) { token in
                        continuation.yield(token)
                    }

                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    /// Get service for compatibility
    public func getService() -> LLMService? {
        return llmService
    }

    // MARK: - Private Helpers

    private func buildPrompt(from messages: [Message], systemPrompt: String?) -> String {
        var prompt = ""

        if let system = systemPrompt {
            prompt += "System: \(system)\n\n"
        }

        for message in messages {
            switch message.role {
            case .user:
                prompt += "User: \(message.content)\n"
            case .assistant:
                prompt += "Assistant: \(message.content)\n"
            case .system:
                prompt += "System: \(message.content)\n"
            }
        }

        prompt += "Assistant: "
        return prompt
    }
}
