//
//  LLMCapability.swift
//  RunAnywhere SDK
//
//  Actor-based LLM capability that owns model lifecycle and generation
//

import Foundation

/// Actor-based LLM capability that provides a simplified interface for text generation
/// Owns the model lifecycle and provides thread-safe access to LLM operations
public actor LLMCapability: ModelLoadableCapability {
    public typealias Configuration = LLMConfiguration
    public typealias Service = LLMService

    // MARK: - State

    /// Unified model lifecycle manager
    private let lifecycle: ModelLifecycleManager<LLMService>

    /// Current configuration
    private var config: LLMConfiguration?

    // MARK: - Dependencies

    private let logger = SDKLogger(category: "LLMCapability")

    // MARK: - Initialization

    public init() {
        self.lifecycle = ModelLifecycleManager.forLLM()
    }

    // MARK: - Configuration (Capability Protocol)

    public func configure(_ config: LLMConfiguration) {
        self.config = config
        Task { await lifecycle.configure(config) }
    }

    // MARK: - Model Lifecycle (ModelLoadableCapability Protocol)

    public var isModelLoaded: Bool {
        get async { await lifecycle.isLoaded }
    }

    public var currentModelId: String? {
        get async { await lifecycle.currentResourceId }
    }

    public func loadModel(_ modelId: String) async throws {
        try await lifecycle.load(modelId)
    }

    public func unload() async throws {
        await lifecycle.unload()
    }

    public func cleanup() async {
        await lifecycle.reset()
    }

    // MARK: - Generation

    /// Generate text from a prompt
    /// - Parameters:
    ///   - prompt: The input prompt
    ///   - options: Generation options
    /// - Returns: Generation result with text and metrics
    public func generate(
        _ prompt: String,
        options: LLMGenerationOptions = LLMGenerationOptions()
    ) async throws -> LLMGenerationResult {
        let service = try await lifecycle.requireService()
        let modelId = await lifecycle.currentResourceId ?? "unknown"
        let startTime = Date()

        logger.info("Generating with model: \(modelId)")

        // Apply configuration defaults if not specified in options
        let effectiveOptions = mergeOptions(options)

        // Generate text
        let generatedText: String
        do {
            generatedText = try await service.generate(prompt: prompt, options: effectiveOptions)
        } catch {
            logger.error("Generation failed: \(error)")
            throw CapabilityError.operationFailed("Generation", error)
        }

        let latencyMs = Date().timeIntervalSince(startTime) * 1000

        // Simple token estimation (~4 chars per token)
        let outputTokens = max(1, generatedText.count / 4)
        let tokensPerSecond = latencyMs > 0 ? Double(outputTokens) / (latencyMs / 1000.0) : 0

        logger.info("Generation completed: \(outputTokens) tokens in \(Int(latencyMs))ms")

        return LLMGenerationResult(
            text: generatedText,
            thinkingContent: nil,
            tokensUsed: outputTokens,
            modelUsed: modelId,
            latencyMs: latencyMs,
            framework: nil,
            tokensPerSecond: tokensPerSecond,
            thinkingTokens: 0,
            responseTokens: outputTokens
        )
    }

    /// Generate text with streaming
    /// - Parameters:
    ///   - prompt: The input prompt
    ///   - options: Generation options
    /// - Returns: Streaming result with token stream and final metrics
    public func generateStream(
        _ prompt: String,
        options: LLMGenerationOptions = LLMGenerationOptions()
    ) async throws -> LLMStreamingResult {
        let service = try await lifecycle.requireService()
        let modelId = await lifecycle.currentResourceId ?? "unknown"
        let effectiveOptions = mergeOptions(options)

        logger.info("Starting streaming generation with model: \(modelId)")

        // Create metrics collector
        let collector = StreamingMetricsCollector(modelId: modelId)

        // Create the token stream
        let stream = AsyncThrowingStream<String, Error> { continuation in
            Task {
                do {
                    await collector.markStart()

                    try await service.streamGenerate(
                        prompt: prompt,
                        options: effectiveOptions,
                        onToken: { token in
                            Task {
                                await collector.recordToken(token)
                                continuation.yield(token)
                            }
                        }
                    )

                    continuation.finish()
                    await collector.markComplete()
                } catch {
                    continuation.finish(throwing: error)
                    await collector.markFailed(error)
                }
            }
        }

        // Create result task that waits for metrics
        let resultTask = Task<LLMGenerationResult, Error> {
            try await collector.waitForResult()
        }

        return LLMStreamingResult(stream: stream, result: resultTask)
    }

    // MARK: - Private Methods

    private func mergeOptions(_ options: LLMGenerationOptions) -> LLMGenerationOptions {
        guard let config = config else { return options }

        return LLMGenerationOptions(
            maxTokens: options.maxTokens > 0 ? options.maxTokens : config.maxTokens,
            temperature: options.temperature,
            topP: options.topP,
            stopSequences: options.stopSequences,
            streamingEnabled: options.streamingEnabled,
            preferredFramework: options.preferredFramework ?? config.preferredFramework,
            structuredOutput: options.structuredOutput,
            systemPrompt: options.systemPrompt ?? config.systemPrompt
        )
    }
}

// MARK: - Streaming Metrics Collector

/// Internal actor for collecting streaming metrics
private actor StreamingMetricsCollector {
    private let modelId: String
    private var startTime: Date?
    private var fullText = ""
    private var tokenCount = 0
    private var isComplete = false
    private var error: Error?
    private var resultContinuation: CheckedContinuation<LLMGenerationResult, Error>?

    init(modelId: String) {
        self.modelId = modelId
    }

    func markStart() {
        startTime = Date()
    }

    func recordToken(_ token: String) {
        fullText += token
        tokenCount += 1
    }

    func markComplete() {
        isComplete = true
        if let continuation = resultContinuation {
            continuation.resume(returning: buildResult())
            resultContinuation = nil
        }
    }

    func markFailed(_ error: Error) {
        self.error = error
        if let continuation = resultContinuation {
            continuation.resume(throwing: error)
            resultContinuation = nil
        }
    }

    func waitForResult() async throws -> LLMGenerationResult {
        if isComplete {
            return buildResult()
        }

        if let error = error {
            throw error
        }

        return try await withCheckedThrowingContinuation { continuation in
            resultContinuation = continuation
        }
    }

    private func buildResult() -> LLMGenerationResult {
        let endTime = Date()
        let latencyMs = (startTime.map { endTime.timeIntervalSince($0) } ?? 0) * 1000

        // Simple token estimation (~4 chars per token)
        let outputTokens = max(1, fullText.count / 4)
        let tokensPerSecond = latencyMs > 0 ? Double(outputTokens) / (latencyMs / 1000.0) : 0

        return LLMGenerationResult(
            text: fullText,
            thinkingContent: nil,
            tokensUsed: outputTokens,
            modelUsed: modelId,
            latencyMs: latencyMs,
            framework: nil,
            tokensPerSecond: tokensPerSecond,
            thinkingTokens: 0,
            responseTokens: outputTokens
        )
    }
}
