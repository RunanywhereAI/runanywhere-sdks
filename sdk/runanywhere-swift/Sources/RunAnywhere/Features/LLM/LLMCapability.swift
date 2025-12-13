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
    private let analyticsService: GenerationAnalyticsService

    // MARK: - Initialization

    public init(analyticsService: GenerationAnalyticsService = GenerationAnalyticsService()) {
        self.lifecycle = ModelLifecycleManager.forLLM()
        self.analyticsService = analyticsService
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
        let startTime = Date()

        do {
            try await lifecycle.load(modelId)
            let loadTime = Date().timeIntervalSince(startTime)
            await analyticsService.trackModelLoading(modelId: modelId, loadTime: loadTime, success: true)
        } catch {
            let loadTime = Date().timeIntervalSince(startTime)
            await analyticsService.trackModelLoading(modelId: modelId, loadTime: loadTime, success: false)
            throw error
        }
    }

    public func unload() async throws {
        if let modelId = await lifecycle.currentResourceId {
            await analyticsService.trackModelUnloading(modelId: modelId)
        }
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

        logger.info("Generating with model: \(modelId)")

        // Apply configuration defaults if not specified in options
        let effectiveOptions = mergeOptions(options)

        // Start generation tracking
        let generationId = await analyticsService.startGeneration(
            modelId: modelId,
            executionTarget: "local"
        )

        // Generate text
        let generatedText: String
        do {
            generatedText = try await service.generate(prompt: prompt, options: effectiveOptions)
        } catch {
            logger.error("Generation failed: \(error)")
            await analyticsService.trackError(error: error, context: .generation)
            throw CapabilityError.operationFailed("Generation", error)
        }

        // Simple token estimation (~4 chars per token)
        let inputTokens = max(1, prompt.count / 4)
        let outputTokens = max(1, generatedText.count / 4)

        // Complete generation tracking
        await analyticsService.completeGeneration(
            generationId: generationId,
            inputTokens: inputTokens,
            outputTokens: outputTokens,
            modelId: modelId,
            executionTarget: "local"
        )

        let metrics = await analyticsService.getMetrics()
        let latencyMs = metrics.lastEventTime.map { $0.timeIntervalSince(metrics.startTime) * 1000 } ?? 0
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

    /// Whether the currently loaded service supports true streaming generation
    /// - Returns: `true` if streaming is supported, `false` otherwise
    /// - Note: Returns `false` if no model is loaded
    public var supportsStreaming: Bool {
        get async {
            guard let service = try? await lifecycle.requireService() else {
                return false
            }
            return service.supportsStreaming
        }
    }

    /// Generate text with streaming
    /// - Parameters:
    ///   - prompt: The input prompt
    ///   - options: Generation options
    /// - Returns: Streaming result with token stream and final metrics
    /// - Throws: `LLMError.streamingNotSupported` if the service doesn't support streaming
    public func generateStream(
        _ prompt: String,
        options: LLMGenerationOptions = LLMGenerationOptions()
    ) async throws -> LLMStreamingResult {
        let service = try await lifecycle.requireService()

        // Check if streaming is supported by this service
        guard service.supportsStreaming else {
            logger.error("Streaming not supported by current service")
            throw LLMError.streamingNotSupported
        }

        let modelId = await lifecycle.currentResourceId ?? "unknown"
        let effectiveOptions = mergeOptions(options)

        logger.info("Starting streaming generation with model: \(modelId)")

        // Start generation tracking
        let generationId = await analyticsService.startGeneration(
            modelId: modelId,
            executionTarget: "local"
        )

        // Create metrics collector
        let collector = StreamingMetricsCollector(
            modelId: modelId,
            generationId: generationId,
            analyticsService: analyticsService
        )

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

    // MARK: - Analytics

    /// Get current generation analytics metrics
    public func getAnalyticsMetrics() async -> GenerationMetrics {
        await analyticsService.getMetrics()
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
    private let generationId: String
    private let analyticsService: GenerationAnalyticsService
    private var startTime: Date?
    private var fullText = ""
    private var tokenCount = 0
    private var firstTokenRecorded = false
    private var isComplete = false
    private var error: Error?
    private var resultContinuation: CheckedContinuation<LLMGenerationResult, Error>?

    init(modelId: String, generationId: String, analyticsService: GenerationAnalyticsService) {
        self.modelId = modelId
        self.generationId = generationId
        self.analyticsService = analyticsService
    }

    func markStart() {
        startTime = Date()
    }

    func recordToken(_ token: String) async {
        fullText += token
        tokenCount += 1

        // Track first token
        if !firstTokenRecorded {
            firstTokenRecorded = true
            await analyticsService.trackFirstToken(generationId: generationId)
        }
    }

    func markComplete() async {
        isComplete = true

        // Simple token estimation (~4 chars per token)
        let inputTokens = 0 // We don't have access to prompt here
        let outputTokens = max(1, fullText.count / 4)

        await analyticsService.completeGeneration(
            generationId: generationId,
            inputTokens: inputTokens,
            outputTokens: outputTokens,
            modelId: modelId,
            executionTarget: "local"
        )

        if let continuation = resultContinuation {
            continuation.resume(returning: buildResult())
            resultContinuation = nil
        }
    }

    func markFailed(_ error: Error) async {
        self.error = error
        await analyticsService.trackError(error: error, context: .generation)

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
