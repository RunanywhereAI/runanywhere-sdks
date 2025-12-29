//
//  LLMCapability.swift
//  RunAnywhere SDK
//
//  Thin Swift wrapper over rac_llm_component_* C API.
//  All business logic is in the C++ layer; this is just a Swift interface.
//
//  ⚠️ WARNING: This is a direct wrapper. Do NOT add custom logic here.
//  The C++ layer (runanywhere-commons) is the source of truth.
//

import CRACommons
import Foundation

/// Actor-based LLM capability that provides a simplified interface for text generation.
/// This is a thin wrapper over the C++ rac_llm_component API.
public actor LLMCapability: ModelLoadableCapability {
    public typealias Configuration = LLMConfiguration

    // MARK: - State

    /// Handle to the C++ LLM component
    private var handle: rac_handle_t?

    /// Current configuration
    private var config: LLMConfiguration?

    /// Currently loaded model ID
    private var loadedModelId: String?

    // MARK: - Dependencies

    private let logger = SDKLogger(category: "LLMCapability")
    private let analyticsService: GenerationAnalyticsService

    // MARK: - Initialization

    public init(analyticsService: GenerationAnalyticsService = GenerationAnalyticsService()) {
        self.analyticsService = analyticsService
    }

    deinit {
        if let handle = handle {
            rac_llm_component_destroy(handle)
        }
    }

    // MARK: - Configuration (Capability Protocol)

    public func configure(_ config: LLMConfiguration) {
        self.config = config
    }

    // MARK: - Handle Access (for VoiceAgent)

    /// Get or create the internal handle (for voice agent to share)
    internal func getOrCreateHandle() throws -> rac_handle_t {
        if let handle = handle {
            return handle
        }

        var newHandle: rac_handle_t?
        let createResult = rac_llm_component_create(&newHandle)
        guard createResult == RAC_SUCCESS, let createdHandle = newHandle else {
            throw SDKError.llm(.modelLoadFailed, "Failed to create LLM component: \(createResult)")
        }
        handle = createdHandle
        return createdHandle
    }

    // MARK: - Model Lifecycle (ModelLoadableCapability Protocol)

    public var isModelLoaded: Bool {
        get async {
            guard let handle = handle else { return false }
            return rac_llm_component_is_loaded(handle) == RAC_TRUE
        }
    }

    public var currentModelId: String? {
        get async { loadedModelId }
    }

    public func loadModel(_ modelId: String) async throws {
        // Create component if needed
        if handle == nil {
            var newHandle: rac_handle_t?
            let createResult = rac_llm_component_create(&newHandle)
            guard createResult == RAC_SUCCESS, let newLLMHandle = newHandle else {
                throw SDKError.llm(.modelLoadFailed, "Failed to create LLM component: \(createResult)")
            }
            handle = newLLMHandle
        }

        guard let handle = handle else {
            throw SDKError.llm(.modelLoadFailed, "No LLM component handle")
        }

        // Resolve model ID to local file path
        let modelPath = try await resolveModelPath(modelId)
        logger.info("Loading model from path: \(modelPath)")

        // Load model using resolved path
        let result = modelPath.withCString { pathPtr in
            rac_llm_component_load_model(handle, pathPtr)
        }

        guard result == RAC_SUCCESS else {
            throw SDKError.llm(.modelLoadFailed, "Failed to load model: \(result)")
        }

        loadedModelId = modelId
        logger.info("Model loaded: \(modelId)")
    }

    /// Resolve a model ID to its local file path
    private func resolveModelPath(_ modelId: String) async throws -> String {
        // Get all available models from the registry
        let allModels = try await RunAnywhere.availableModels()

        // Find the model info for this ID
        guard let modelInfo = allModels.first(where: { $0.id == modelId }) else {
            throw SDKError.llm(.modelNotFound, "Model '\(modelId)' not found in registry")
        }

        // Check if model is downloaded
        guard let localPath = modelInfo.localPath else {
            throw SDKError.llm(.modelNotFound, "Model '\(modelId)' is not downloaded. Please download the model first.")
        }

        return localPath.path
    }

    public func unload() async throws {
        guard let handle = handle else { return }

        let result = rac_llm_component_cleanup(handle)
        if result != RAC_SUCCESS {
            logger.warning("Cleanup returned: \(result)")
        }

        loadedModelId = nil
        logger.info("Model unloaded")
    }

    public func cleanup() async {
        if let handle = handle {
            rac_llm_component_cleanup(handle)
            rac_llm_component_destroy(handle)
        }
        handle = nil
        loadedModelId = nil
    }

    /// Cancel the current generation operation
    public func cancel() async {
        guard let handle = handle else { return }
        rac_llm_component_cancel(handle)
        logger.info("Generation cancellation requested")
    }

    // MARK: - Generation

    /// Generate text from a prompt (non-streaming)
    public func generate(
        _ prompt: String,
        options: LLMGenerationOptions = LLMGenerationOptions()
    ) async throws -> LLMGenerationResult {
        guard let handle = handle else {
            throw SDKError.llm(.notInitialized, "LLM not initialized")
        }

        guard rac_llm_component_is_loaded(handle) == RAC_TRUE else {
            throw SDKError.llm(.notInitialized, "LLM model not loaded")
        }

        let modelId = loadedModelId ?? "unknown"
        let effectiveOptions = mergeOptions(options)

        logger.info("Generating with model: \(modelId) (non-streaming)")

        // Start analytics tracking
        let generationId = await analyticsService.startGeneration(
            modelId: modelId,
            framework: .llamaCpp,  // Default, will be updated when we get actual info
            temperature: effectiveOptions.temperature,
            maxTokens: effectiveOptions.maxTokens,
            contextLength: config?.contextLength
        )

        let startTime = Date()

        // Build C options
        var cOptions = rac_llm_options_t()
        cOptions.max_tokens = Int32(effectiveOptions.maxTokens)
        cOptions.temperature = effectiveOptions.temperature
        cOptions.top_p = effectiveOptions.topP
        cOptions.streaming_enabled = RAC_FALSE

        // Generate
        var llmResult = rac_llm_result_t()
        let generateResult = prompt.withCString { promptPtr in
            rac_llm_component_generate(handle, promptPtr, &cOptions, &llmResult)
        }

        guard generateResult == RAC_SUCCESS else {
            let error = SDKError.llm(.generationFailed, "Generation failed: \(generateResult)")
            await analyticsService.trackGenerationFailed(generationId: generationId, error: error)
            throw error
        }

        let endTime = Date()
        let totalTimeMs = endTime.timeIntervalSince(startTime) * 1000

        // Extract result
        let generatedText: String
        if let textPtr = llmResult.text {
            generatedText = String(cString: textPtr)
        } else {
            generatedText = ""
        }
        let inputTokens = Int(llmResult.prompt_tokens)
        let outputTokens = Int(llmResult.completion_tokens)
        let tokensPerSecond = llmResult.tokens_per_second > 0 ? Double(llmResult.tokens_per_second) : 0

        // No explicit free needed - llmResult is a stack-allocated struct

        // Complete analytics
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
            framework: "llamacpp",
            tokensPerSecond: tokensPerSecond,
            timeToFirstTokenMs: nil,
            thinkingTokens: 0,
            responseTokens: outputTokens
        )
    }

    /// Whether the currently loaded service supports true streaming generation
    public var supportsStreaming: Bool {
        get async { true }  // C++ layer supports streaming
    }

    /// Generate text with streaming (token-by-token)
    public func generateStream( // swiftlint:disable:this function_body_length
        _ prompt: String,
        options: LLMGenerationOptions = LLMGenerationOptions()
    ) async throws -> LLMStreamingResult {
        guard let handle = handle else {
            throw SDKError.llm(.notInitialized, "LLM not initialized")
        }

        guard rac_llm_component_is_loaded(handle) == RAC_TRUE else {
            throw SDKError.llm(.notInitialized, "LLM model not loaded")
        }

        let modelId = loadedModelId ?? "unknown"
        let effectiveOptions = mergeOptions(options)

        logger.info("Starting streaming generation with model: \(modelId)")

        // Start streaming analytics
        let generationId = await analyticsService.startStreamingGeneration(
            modelId: modelId,
            framework: .llamaCpp,
            temperature: effectiveOptions.temperature,
            maxTokens: effectiveOptions.maxTokens,
            contextLength: config?.contextLength
        )

        // Create collector for metrics
        let collector = StreamingMetricsCollector(
            modelId: modelId,
            generationId: generationId,
            analyticsService: analyticsService,
            framework: .llamaCpp,
            promptLength: prompt.count
        )

        // Build C options
        var cOptions = rac_llm_options_t()
        cOptions.max_tokens = Int32(effectiveOptions.maxTokens)
        cOptions.temperature = effectiveOptions.temperature
        cOptions.top_p = effectiveOptions.topP
        cOptions.streaming_enabled = RAC_TRUE

        // Create the token stream
        let stream = AsyncThrowingStream<String, Error> { continuation in
            Task {
                do {
                    await collector.markStart()

                    // Create callback context
                    let context = StreamCallbackContext(
                        continuation: continuation,
                        collector: collector
                    )
                    let contextPtr = Unmanaged.passRetained(context).toOpaque()

                    // Token callback
                    let tokenCallback: rac_llm_component_token_callback_fn = { tokenPtr, userData -> rac_bool_t in
                        guard let tokenPtr = tokenPtr, let userData = userData else { return RAC_TRUE }
                        let ctx = Unmanaged<StreamCallbackContext>.fromOpaque(userData).takeUnretainedValue()
                        let token = String(cString: tokenPtr)
                        Task {
                            await ctx.collector.recordToken(token)
                            ctx.continuation.yield(token)
                        }
                        return RAC_TRUE  // Continue streaming
                    }

                    // Complete callback
                    let completeCallback: rac_llm_component_complete_callback_fn = { _, userData in
                        guard let userData = userData else { return }
                        let ctx = Unmanaged<StreamCallbackContext>.fromOpaque(userData).takeUnretainedValue()
                        ctx.continuation.finish()
                        Task {
                            await ctx.collector.markComplete()
                        }
                    }

                    // Error callback
                    let errorCallback: rac_llm_component_error_callback_fn = { _, errorMsg, userData in
                        guard let userData = userData else { return }
                        let ctx = Unmanaged<StreamCallbackContext>.fromOpaque(userData).takeUnretainedValue()
                        let message: String
                        if let msgPtr = errorMsg {
                            message = String(cString: msgPtr)
                        } else {
                            message = "Unknown error"
                        }
                        let error = SDKError.llm(.generationFailed, message)
                        ctx.continuation.finish(throwing: error)
                        Task {
                            await ctx.collector.markFailed(error)
                        }
                    }

                    let streamResult = prompt.withCString { promptPtr in
                        rac_llm_component_generate_stream(
                            handle,
                            promptPtr,
                            &cOptions,
                            tokenCallback,
                            completeCallback,
                            errorCallback,
                            contextPtr
                        )
                    }

                    // Release context after completion is handled by callbacks
                    // Note: we need to manage memory more carefully here
                    if streamResult != RAC_SUCCESS {
                        Unmanaged<StreamCallbackContext>.fromOpaque(contextPtr).release()
                        let error = SDKError.llm(.generationFailed, "Stream generation failed: \(streamResult)")
                        continuation.finish(throwing: error)
                        await collector.markFailed(error)
                    }
                } catch {
                    continuation.finish(throwing: error)
                    await collector.markFailed(error)
                }
            }
        }

        let resultTask = Task<LLMGenerationResult, Error> {
            try await collector.waitForResult()
        }

        return LLMStreamingResult(stream: stream, result: resultTask)
    }

    // MARK: - Analytics

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

// MARK: - Streaming Callback Context

private final class StreamCallbackContext: @unchecked Sendable {
    let continuation: AsyncThrowingStream<String, Error>.Continuation
    let collector: StreamingMetricsCollector

    init(continuation: AsyncThrowingStream<String, Error>.Continuation, collector: StreamingMetricsCollector) {
        self.continuation = continuation
        self.collector = collector
    }
}

// MARK: - Streaming Metrics Collector

/// Internal actor for collecting streaming metrics with TTFT tracking
private actor StreamingMetricsCollector {
    private let modelId: String
    private let generationId: String
    private let analyticsService: GenerationAnalyticsService
    private let framework: InferenceFramework
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
        framework: InferenceFramework,
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

        if !firstTokenRecorded {
            firstTokenRecorded = true
            firstTokenTime = Date()
            await analyticsService.trackFirstToken(generationId: generationId)
        }
    }

    func markComplete() async {
        isComplete = true

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

        var timeToFirstTokenMs: Double?
        if let start = startTime, let firstToken = firstTokenTime {
            timeToFirstTokenMs = firstToken.timeIntervalSince(start) * 1000
        }

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
