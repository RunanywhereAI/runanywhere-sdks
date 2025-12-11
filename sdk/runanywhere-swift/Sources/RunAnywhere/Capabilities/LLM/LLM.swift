// swiftlint:disable file_length
//
//  LLM.swift
//  RunAnywhere SDK
//
//  Public entry point for the LLM (Language Model) capability
//

import Foundation

/// Public entry point for the LLM (Language Model) capability
/// Provides simplified access to text generation operations
public final class LLM {

    // MARK: - Shared Instance

    /// Shared singleton instance for convenient access
    public static let shared = LLM()

    // MARK: - Properties

    private let logger = SDKLogger(category: "LLM")

    // MARK: - Initialization

    /// Initialize with default settings
    public init() {
        logger.debug("LLM capability initialized")
    }

    // MARK: - Component Creation

    /// Create an LLM component with the specified configuration
    /// - Parameter configuration: The LLM configuration
    /// - Returns: An LLMComponent ready for initialization
    @MainActor
    public func createComponent(configuration: LLMConfiguration) -> LLMComponent {
        logger.info("Creating LLM component with model: \(configuration.modelId ?? "default")")
        return LLMComponent(configuration: configuration)
    }

    /// Create an LLM component with a model ID
    /// - Parameter modelId: The model identifier
    /// - Returns: An LLMComponent ready for initialization
    @MainActor
    public func createComponent(modelId: String) -> LLMComponent {
        let configuration = LLMConfiguration(modelId: modelId)
        return createComponent(configuration: configuration)
    }

    // MARK: - Quick Generation (using ServiceContainer)

    /// Generate text using the currently loaded model
    /// - Parameters:
    ///   - prompt: The input prompt
    ///   - options: Generation options (optional)
    /// - Returns: Generation result
    public func generate(
        prompt: String,
        options: LLMGenerationOptions? = nil
    ) async throws -> LLMGenerationResult {
        logger.info("Generating text with prompt length: \(prompt.count)")

        let generationService = RunAnywhere.serviceContainer.generationService
        let resolvedOptions = options ?? LLMGenerationOptions()

        return try await generationService.generate(
            prompt: prompt,
            options: resolvedOptions
        )
    }

    /// Generate streaming text using the currently loaded model
    /// - Parameters:
    ///   - prompt: The input prompt
    ///   - options: Generation options (optional)
    /// - Returns: Streaming result with token stream and final metrics
    public func generateStream(
        prompt: String,
        options: LLMGenerationOptions? = nil
    ) -> LLMStreamingResult {
        logger.info("Starting streaming generation with prompt length: \(prompt.count)")

        let streamingService = RunAnywhere.serviceContainer.streamingService
        let resolvedOptions = options ?? LLMGenerationOptions()

        return streamingService.generateStreamWithMetrics(
            prompt: prompt,
            options: resolvedOptions
        )
    }

    /// Generate streaming text with token-level granularity
    /// - Parameters:
    ///   - prompt: The input prompt
    ///   - options: Generation options (optional)
    /// - Returns: Stream of streaming tokens
    public func generateTokenStream(
        prompt: String,
        options: LLMGenerationOptions? = nil
    ) -> AsyncThrowingStream<StreamingToken, Error> {
        logger.info("Starting token stream generation with prompt length: \(prompt.count)")

        let streamingService = RunAnywhere.serviceContainer.streamingService
        let resolvedOptions = options ?? LLMGenerationOptions()

        return streamingService.generateTokenStream(
            prompt: prompt,
            options: resolvedOptions
        )
    }

    // MARK: - Structured Output

    /// Generate structured output of a specific type
    /// - Parameters:
    ///   - type: The type to generate (must conform to Generatable)
    ///   - prompt: The input prompt
    ///   - options: Generation options (optional)
    /// - Returns: Parsed instance of the requested type
    public func generate<T: Generatable>(
        _ type: T.Type,
        prompt: String,
        options: LLMGenerationOptions? = nil
    ) async throws -> T {
        logger.info("Generating structured output of type: \(T.self)")

        // Create options with structured output config
        let structuredConfig = StructuredOutputConfig(type: type)
        var resolvedOptions = options ?? LLMGenerationOptions()
        resolvedOptions = LLMGenerationOptions(
            maxTokens: resolvedOptions.maxTokens,
            temperature: resolvedOptions.temperature,
            topP: resolvedOptions.topP,
            stopSequences: resolvedOptions.stopSequences,
            streamingEnabled: resolvedOptions.streamingEnabled,
            preferredFramework: resolvedOptions.preferredFramework,
            structuredOutput: structuredConfig,
            systemPrompt: resolvedOptions.systemPrompt
        )

        let result = try await generate(prompt: prompt, options: resolvedOptions)

        // Parse the structured output
        let handler = StructuredOutputHandler()
        return try handler.parseStructuredOutput(from: result.text, type: type)
    }

    // MARK: - Utility Methods

    /// Estimate token count for a given text
    /// - Parameter text: The text to estimate
    /// - Returns: Estimated token count
    public func estimateTokenCount(_ text: String) -> Int {
        return TokenCounter.estimateTokenCount(text)
    }

    /// Parse thinking content from generated text
    /// - Parameters:
    ///   - text: The generated text
    ///   - pattern: The thinking tag pattern (defaults to standard pattern)
    /// - Returns: Parse result with content and thinking
    public func parseThinking(
        from text: String,
        pattern: ThinkingTagPattern = .defaultPattern
    ) -> ThinkingParser.ParseResult {
        return ThinkingParser.parse(text: text, pattern: pattern)
    }
}

// MARK: - LLM Component

/// Language Model component following the clean architecture
@MainActor
public final class LLMComponent: BaseComponent<LLMServiceWrapper>, @unchecked Sendable {

    // MARK: - Properties

    public override static var componentType: SDKComponent { .llm }

    private let llmConfiguration: LLMConfiguration
    private var isModelLoaded = false
    private let logger = SDKLogger(category: "LLMComponent")

    // MARK: - Initialization

    public init(configuration: LLMConfiguration) {
        self.llmConfiguration = configuration
        super.init(configuration: configuration)
    }

    // MARK: - Service Creation

    public override func createService() async throws -> LLMServiceWrapper {
        let modelId = llmConfiguration.modelId ?? "unknown"

        // Check if we already have a cached service via the lifecycle tracker
        if let cachedService = await ModelLifecycleTracker.shared.llmService(for: modelId) {
            logger.info("✅ Reusing cached LLM service for model: \(modelId)")
            isModelLoaded = true
            return LLMServiceWrapper(cachedService)
        }

        // Try to get a registered LLM provider from central registry
        let provider = await MainActor.run {
            ModuleRegistry.shared.llmProvider(for: llmConfiguration.modelId)
        }

        guard let provider = provider else {
            let message = """
                No LLM service provider registered. Please add llama.cpp or another LLM implementation \
                as a dependency and register it with ModuleRegistry.shared.registerLLM(provider).
                """
            throw RunAnywhereError.componentNotInitialized(message)
        }

        // Create service through provider
        let llmService = try await provider.createLLMService(configuration: llmConfiguration)
        isModelLoaded = true

        // Store service in lifecycle tracker for reuse
        await MainActor.run {
            ModelLifecycleTracker.shared.modelDidLoad(
                modelId: modelId,
                modelName: modelId,
                framework: llmConfiguration.preferredFramework ?? .llamaCpp,
                modality: .llm,
                llmService: llmService
            )
        }

        // Wrap and return the service
        return LLMServiceWrapper(llmService)
    }

    public override func performCleanup() async throws {
        await service?.wrappedService?.cleanup()
        isModelLoaded = false
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
            throw RunAnywhereError.componentNotReady("LLM service not available")
        }

        // Validate input
        try input.validate()

        // Use provided options or create from configuration
        let options = input.options ?? LLMGenerationOptions(
            maxTokens: llmConfiguration.maxTokens,
            temperature: Float(llmConfiguration.temperature),
            streamingEnabled: llmConfiguration.streamingEnabled,
            preferredFramework: llmConfiguration.preferredFramework
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
                        continuation.finish(throwing: RunAnywhereError.componentNotReady("LLM service not available"))
                        return
                    }

                    let options = LLMGenerationOptions(
                        maxTokens: llmConfiguration.maxTokens,
                        temperature: Float(llmConfiguration.temperature),
                        streamingEnabled: true,
                        preferredFramework: llmConfiguration.preferredFramework
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

        // Add system prompt first if available
        if let system = systemPrompt {
            prompt += "\(system)\n\n"
        }

        // Add messages without role markers - let LLM service handle formatting
        for message in messages {
            prompt += "\(message.content)\n"
        }

        return prompt.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
