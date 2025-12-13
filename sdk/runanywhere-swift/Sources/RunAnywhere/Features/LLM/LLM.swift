// swiftlint:disable file_length
//
//  LLM.swift
//  RunAnywhere SDK
//
//  LLM component for advanced use cases
//  For basic generation, use RunAnywhere.generate() or RunAnywhere.generateStream()
//

import Foundation

/// LLM component factory for advanced use cases
/// - Note: For basic generation, use `RunAnywhere.generate()` or `RunAnywhere.generateStream()` directly
public enum LLM {

    // MARK: - Component Creation

    /// Create an LLM component with the specified configuration
    /// - Parameter configuration: The LLM configuration
    /// - Returns: An LLMComponent ready for initialization
    @MainActor
    public static func createComponent(configuration: LLMConfiguration) -> LLMComponent {
        return LLMComponent(configuration: configuration)
    }

    /// Create an LLM component with a model ID
    /// - Parameter modelId: The model identifier
    /// - Returns: An LLMComponent ready for initialization
    @MainActor
    public static func createComponent(modelId: String) -> LLMComponent {
        let configuration = LLMConfiguration(modelId: modelId)
        return createComponent(configuration: configuration)
    }
}

// MARK: - LLM Component

/// Language Model component following the clean architecture
@MainActor
public final class LLMComponent: BaseComponent<any LLMService>, @unchecked Sendable {

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

    public override func createService() async throws -> any LLMService {
        let modelId = llmConfiguration.modelId ?? "unknown"

        // Check if we already have a cached service via the lifecycle tracker
        if let cachedService = await ModelLifecycleTracker.shared.llmService(for: modelId) {
            logger.info("✅ Reusing cached LLM service for model: \(modelId)")
            isModelLoaded = true
            return cachedService
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

        return llmService
    }

    public override func performCleanup() async throws {
        await service?.cleanup()
        isModelLoaded = false
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

        guard let llmService = service else {
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

                    guard let llmService = service else {
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
        return service
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
