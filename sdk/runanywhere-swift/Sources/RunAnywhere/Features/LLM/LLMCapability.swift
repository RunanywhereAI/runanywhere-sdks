//
//  LLMCapability.swift
//  RunAnywhere SDK
//
//  Actor-based LLM capability that owns model lifecycle and generation.
//  Uses ManagedLifecycle for unified lifecycle + analytics handling.
//

import Foundation

/// Actor-based LLM capability that provides a simplified interface for text generation.
/// Owns the model lifecycle and provides thread-safe access to LLM operations.
///
/// Uses `ManagedLifecycle` to handle model loading/unloading with automatic analytics tracking,
/// eliminating duplicate lifecycle management code.
public actor LLMCapability: ModelLoadableCapability {
    public typealias Configuration = LLMConfiguration
    public typealias Service = LLMService

    // MARK: - State

    /// Managed lifecycle with integrated event tracking
    private let managedLifecycle: ManagedLifecycle<LLMService>

    /// Current configuration
    private var config: LLMConfiguration?

    // MARK: - Dependencies

    private let logger = SDKLogger(category: "LLMCapability")
    private let analyticsService: GenerationAnalyticsService

    // MARK: - Initialization

    public init(analyticsService: GenerationAnalyticsService = GenerationAnalyticsService()) {
        self.analyticsService = analyticsService
        self.managedLifecycle = ManagedLifecycle.forLLM()
    }

    // MARK: - Configuration (Capability Protocol)

    public func configure(_ config: LLMConfiguration) {
        self.config = config
        Task { await managedLifecycle.configure(config) }
    }

    // MARK: - Model Lifecycle (ModelLoadableCapability Protocol)
    // All lifecycle operations are delegated to ManagedLifecycle which handles analytics automatically

    public var isModelLoaded: Bool {
        get async { await managedLifecycle.isLoaded }
    }

    public var currentModelId: String? {
        get async { await managedLifecycle.currentResourceId }
    }

    public func loadModel(_ modelId: String) async throws {
        try await managedLifecycle.load(modelId)
    }

    public func unload() async throws {
        await managedLifecycle.unload()
    }

    public func cleanup() async {
        await managedLifecycle.reset()
    }

    /// Cancel the current generation operation
    /// - Note: This is a best-effort cancellation; some backends may not support mid-generation cancellation
    public func cancel() async {
        // Get the current service if available
        if let service = await managedLifecycle.currentService {
            // Try to cancel if the service supports it
            await service.cancel()
        }
        logger.info("Generation cancellation requested")
    }

    // MARK: - Generation

    /// Generate text from a prompt (non-streaming)
    /// - Parameters:
    ///   - prompt: The input prompt
    ///   - options: Generation options
    /// - Returns: Generation result with text and metrics
    /// - Note: This is a non-streaming generation. Time-to-first-token (TTFT) is not tracked
    ///         since the entire response is returned at once. Use `generateStream()` for TTFT metrics.
    public func generate(
        _ prompt: String,
        options: LLMGenerationOptions = LLMGenerationOptions()
    ) async throws -> LLMGenerationResult {
        let service = try await managedLifecycle.requireService()
        let modelId = await managedLifecycle.resourceIdOrUnknown()

        logger.info("Generating with model: \(modelId) (non-streaming)")

        // Apply configuration defaults if not specified in options
        let effectiveOptions = mergeOptions(options)

        let startTime = Date()

        // Start generation tracking (non-streaming mode)
        // Use service's actual context length, fallback to config if not available
        let contextLength = service.contextLength ?? config?.contextLength
        let generationId = await analyticsService.startGeneration(
            modelId: modelId,
            framework: service.inferenceFramework,
            temperature: effectiveOptions.temperature,
            maxTokens: effectiveOptions.maxTokens,
            contextLength: contextLength
        )

        // Generate text
        let generatedText: String
        do {
            generatedText = try await service.generate(prompt: prompt, options: effectiveOptions)
        } catch {
            logger.error("Generation failed: \(error)")
            await analyticsService.trackGenerationFailed(generationId: generationId, error: error)
            await managedLifecycle.trackOperationError(error, operation: "generate")
            throw CapabilityError.operationFailed("Generation", error)
        }

        let endTime = Date()
        let totalTimeMs = endTime.timeIntervalSince(startTime) * 1000

        // Simple token estimation (~4 chars per token)
        let inputTokens = max(1, prompt.count / 4)
        let outputTokens = max(1, generatedText.count / 4)
        let tokensPerSecond = totalTimeMs > 0 ? Double(outputTokens) / (totalTimeMs / 1000.0) : 0

        // Complete generation tracking
        await analyticsService.completeGeneration(
            generationId: generationId,
            inputTokens: inputTokens,
            outputTokens: outputTokens,
            modelId: modelId
        )

        logger.info("Generation completed: \(outputTokens) tokens in \(Int(totalTimeMs))ms")

        return LLMGenerationResult(
            text: generatedText,
            thinkingContent: nil,
            inputTokens: inputTokens,
            tokensUsed: outputTokens,
            modelUsed: modelId,
            latencyMs: totalTimeMs,
            framework: service.inferenceFramework.rawValue,
            tokensPerSecond: tokensPerSecond,
            timeToFirstTokenMs: nil,  // Non-streaming: no TTFT
            thinkingTokens: 0,
            responseTokens: outputTokens
        )
    }

    /// Whether the currently loaded service supports true streaming generation
    /// - Returns: `true` if streaming is supported, `false` otherwise
    /// - Note: Returns `false` if no model is loaded
    public var supportsStreaming: Bool {
        get async {
            guard let service = await managedLifecycle.currentService else {
                return false
            }
            return service.supportsStreaming
        }
    }

    /// Generate text with streaming (token-by-token)
    /// - Parameters:
    ///   - prompt: The input prompt
    ///   - options: Generation options
    /// - Returns: Streaming result with token stream and final metrics
    /// - Throws: `LLMError.streamingNotSupported` if the service doesn't support streaming
    /// - Note: Time-to-first-token (TTFT) is tracked for streaming generations
    public func generateStream(
        _ prompt: String,
        options: LLMGenerationOptions = LLMGenerationOptions()
    ) async throws -> LLMStreamingResult {
        let service = try await managedLifecycle.requireService()

        // Check if streaming is supported by this service
        guard service.supportsStreaming else {
            logger.error("Streaming not supported by current service")
            throw LLMError.streamingNotSupported
        }

        let modelId = await managedLifecycle.resourceIdOrUnknown()
        let effectiveOptions = mergeOptions(options)
        let framework = service.inferenceFramework

        logger.info("Starting streaming generation with model: \(modelId)")

        // Start streaming generation tracking
        // Use service's actual context length, fallback to config if not available
        let contextLength = service.contextLength ?? config?.contextLength
        let generationId = await analyticsService.startStreamingGeneration(
            modelId: modelId,
            framework: framework,
            temperature: effectiveOptions.temperature,
            maxTokens: effectiveOptions.maxTokens,
            contextLength: contextLength
        )

        // Create metrics collector
        let collector = StreamingMetricsCollector(
            modelId: modelId,
            generationId: generationId,
            analyticsService: analyticsService,
            framework: framework,
            promptLength: prompt.count
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

/// Internal actor for collecting streaming metrics with TTFT tracking
private actor StreamingMetricsCollector {
    private let modelId: String
    private let generationId: String
    private let analyticsService: GenerationAnalyticsService
    private let framework: InferenceFrameworkType
    private let promptLength: Int

    private var startTime: Date?
    private var firstTokenTime: Date?
    private var fullText = ""
    private var tokenCount = 0
    private var firstTokenRecorded = false
    private var isComplete = false
    private var error: Error?
    private var resultContinuation: CheckedContinuation<LLMGenerationResult, Error>?

    init(
        modelId: String,
        generationId: String,
        analyticsService: GenerationAnalyticsService,
        framework: InferenceFrameworkType,
        promptLength: Int
    ) {
        self.modelId = modelId
        self.generationId = generationId
        self.analyticsService = analyticsService
        self.framework = framework
        self.promptLength = promptLength
    }

    func markStart() {
        startTime = Date()
    }

    func recordToken(_ token: String) async {
        fullText += token
        tokenCount += 1

        // Track first token for TTFT metric
        if !firstTokenRecorded {
            firstTokenRecorded = true
            firstTokenTime = Date()
            await analyticsService.trackFirstToken(generationId: generationId)
        }
    }

    func markComplete() async {
        isComplete = true

        // Simple token estimation (~4 chars per token)
        let inputTokens = max(1, promptLength / 4)
        let outputTokens = max(1, fullText.count / 4)

        await analyticsService.completeGeneration(
            generationId: generationId,
            inputTokens: inputTokens,
            outputTokens: outputTokens,
            modelId: modelId
        )

        if let continuation = resultContinuation {
            continuation.resume(returning: buildResult())
            resultContinuation = nil
        }
    }

    func markFailed(_ error: Error) async {
        self.error = error
        await analyticsService.trackGenerationFailed(generationId: generationId, error: error)

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

        // Calculate TTFT for streaming
        var timeToFirstTokenMs: Double?
        if let start = startTime, let firstToken = firstTokenTime {
            timeToFirstTokenMs = firstToken.timeIntervalSince(start) * 1000
        }

        // Simple token estimation (~4 chars per token)
        let inputTokens = max(1, promptLength / 4)
        let outputTokens = max(1, fullText.count / 4)
        let tokensPerSecond = latencyMs > 0 ? Double(outputTokens) / (latencyMs / 1000.0) : 0

        return LLMGenerationResult(
            text: fullText,
            thinkingContent: nil,
            inputTokens: inputTokens,
            tokensUsed: outputTokens,
            modelUsed: modelId,
            latencyMs: latencyMs,
            framework: framework.rawValue,
            tokensPerSecond: tokensPerSecond,
            timeToFirstTokenMs: timeToFirstTokenMs,
            thinkingTokens: 0,
            responseTokens: outputTokens
        )
    }
}
