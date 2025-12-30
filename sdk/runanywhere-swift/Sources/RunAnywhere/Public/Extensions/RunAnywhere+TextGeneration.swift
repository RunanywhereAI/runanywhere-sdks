//
//  RunAnywhere+TextGeneration.swift
//  RunAnywhere SDK
//
//  Public API for text generation (LLM) operations.
//  Calls C++ directly via HandleManager for all operations.
//  Events are emitted by C++ layer via CppEventBridge.
//

import CRACommons
import Foundation

// MARK: - Text Generation

public extension RunAnywhere {

    /// Simple text generation with automatic event publishing
    /// - Parameter prompt: The text prompt
    /// - Returns: Generated response (text only)
    static func chat(_ prompt: String) async throws -> String {
        let result = try await generate(prompt, options: nil)
        return result.text
    }

    /// Generate text with full metrics and analytics
    /// - Parameters:
    ///   - prompt: The text prompt
    ///   - options: Generation options (optional)
    /// - Returns: GenerationResult with full metrics including thinking tokens, timing, performance, etc.
    /// - Note: Events are automatically dispatched via C++ layer
    static func generate(
        _ prompt: String,
        options: LLMGenerationOptions? = nil
    ) async throws -> LLMGenerationResult {
        guard isInitialized else {
            throw SDKError.general(.notInitialized, "SDK not initialized")
        }

        try await ensureServicesReady()

        // Get handle from HandleManager
        let handle = try await HandleManager.shared.getLLMHandle()

        // Verify model is loaded
        guard await HandleManager.shared.isLLMLoaded else {
            throw SDKError.llm(.notInitialized, "LLM model not loaded")
        }

        let modelId = await HandleManager.shared.currentLLMModelId ?? "unknown"
        let opts = options ?? LLMGenerationOptions()

        let startTime = Date()

        // Build C options
        var cOptions = rac_llm_options_t()
        cOptions.max_tokens = Int32(opts.maxTokens)
        cOptions.temperature = opts.temperature
        cOptions.top_p = opts.topP
        cOptions.streaming_enabled = RAC_FALSE

        // Generate (C++ emits events)
        var llmResult = rac_llm_result_t()
        let generateResult = prompt.withCString { promptPtr in
            rac_llm_component_generate(handle, promptPtr, &cOptions, &llmResult)
        }

        guard generateResult == RAC_SUCCESS else {
            throw SDKError.llm(.generationFailed, "Generation failed: \(generateResult)")
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

    /// Streaming text generation with complete analytics
    ///
    /// Returns both a token stream for real-time display and a task that resolves to complete metrics.
    ///
    /// Example usage:
    /// ```swift
    /// let result = try await RunAnywhere.generateStream(prompt)
    ///
    /// // Display tokens in real-time
    /// for try await token in result.stream {
    ///     print(token, terminator: "")
    /// }
    ///
    /// // Get complete analytics after streaming finishes
    /// let metrics = try await result.result.value
    /// print("Speed: \(metrics.performanceMetrics.tokensPerSecond) tok/s")
    /// print("Tokens: \(metrics.tokensUsed)")
    /// print("Time: \(metrics.latencyMs)ms")
    /// ```
    ///
    /// - Parameters:
    ///   - prompt: The text prompt
    ///   - options: Generation options (optional)
    /// - Returns: StreamingResult containing both the token stream and final metrics task
    static func generateStream(
        _ prompt: String,
        options: LLMGenerationOptions? = nil
    ) async throws -> LLMStreamingResult {
        guard isInitialized else {
            throw SDKError.general(.notInitialized, "SDK not initialized")
        }

        try await ensureServicesReady()

        let handle = try await HandleManager.shared.getLLMHandle()

        guard await HandleManager.shared.isLLMLoaded else {
            throw SDKError.llm(.notInitialized, "LLM model not loaded")
        }

        let modelId = await HandleManager.shared.currentLLMModelId ?? "unknown"
        let opts = options ?? LLMGenerationOptions()

        let collector = LLMStreamingMetricsCollector(modelId: modelId, promptLength: prompt.count)

        var cOptions = rac_llm_options_t()
        cOptions.max_tokens = Int32(opts.maxTokens)
        cOptions.temperature = opts.temperature
        cOptions.top_p = opts.topP
        cOptions.streaming_enabled = RAC_TRUE

        let stream = createTokenStream(
            prompt: prompt,
            handle: handle,
            options: cOptions,
            collector: collector
        )

        let resultTask = Task<LLMGenerationResult, Error> {
            try await collector.waitForResult()
        }

        return LLMStreamingResult(stream: stream, result: resultTask)
    }

    // MARK: - Private Streaming Helpers

    private static func createTokenStream(
        prompt: String,
        handle: UnsafeMutableRawPointer,
        options: rac_llm_options_t,
        collector: LLMStreamingMetricsCollector
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream<String, Error> { continuation in
            Task {
                do {
                    await collector.markStart()

                    let context = LLMStreamCallbackContext(continuation: continuation, collector: collector)
                    let contextPtr = Unmanaged.passRetained(context).toOpaque()

                    let callbacks = LLMStreamCallbacks.create()
                    var cOptions = options

                    let streamResult = prompt.withCString { promptPtr in
                        rac_llm_component_generate_stream(
                            handle,
                            promptPtr,
                            &cOptions,
                            callbacks.token,
                            callbacks.complete,
                            callbacks.error,
                            contextPtr
                        )
                    }

                    if streamResult != RAC_SUCCESS {
                        Unmanaged<LLMStreamCallbackContext>.fromOpaque(contextPtr).release()
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
    }

}

// MARK: - Streaming Callbacks

private enum LLMStreamCallbacks {
    typealias TokenFn = rac_llm_component_token_callback_fn
    typealias CompleteFn = rac_llm_component_complete_callback_fn
    typealias ErrorFn = rac_llm_component_error_callback_fn

    struct Callbacks {
        let token: TokenFn
        let complete: CompleteFn
        let error: ErrorFn
    }

    static func create() -> Callbacks {
        let tokenCallback: TokenFn = { tokenPtr, userData -> rac_bool_t in
            guard let tokenPtr = tokenPtr, let userData = userData else { return RAC_TRUE }
            let ctx = Unmanaged<LLMStreamCallbackContext>.fromOpaque(userData).takeUnretainedValue()
            let token = String(cString: tokenPtr)
            Task {
                await ctx.collector.recordToken(token)
                ctx.continuation.yield(token)
            }
            return RAC_TRUE
        }

        let completeCallback: CompleteFn = { _, userData in
            guard let userData = userData else { return }
            let ctx = Unmanaged<LLMStreamCallbackContext>.fromOpaque(userData).takeUnretainedValue()
            ctx.continuation.finish()
            Task { await ctx.collector.markComplete() }
        }

        let errorCallback: ErrorFn = { _, errorMsg, userData in
            guard let userData = userData else { return }
            let ctx = Unmanaged<LLMStreamCallbackContext>.fromOpaque(userData).takeUnretainedValue()
            let message = errorMsg.map { String(cString: $0) } ?? "Unknown error"
            let error = SDKError.llm(.generationFailed, message)
            ctx.continuation.finish(throwing: error)
            Task { await ctx.collector.markFailed(error) }
        }

        return Callbacks(token: tokenCallback, complete: completeCallback, error: errorCallback)
    }
}

// MARK: - Streaming Callback Context

private final class LLMStreamCallbackContext: @unchecked Sendable {
    let continuation: AsyncThrowingStream<String, Error>.Continuation
    let collector: LLMStreamingMetricsCollector

    init(continuation: AsyncThrowingStream<String, Error>.Continuation, collector: LLMStreamingMetricsCollector) {
        self.continuation = continuation
        self.collector = collector
    }
}

// MARK: - Streaming Metrics Collector

/// Internal actor for collecting streaming metrics
private actor LLMStreamingMetricsCollector {
    private let modelId: String
    private let promptLength: Int

    private var startTime: Date?
    private var firstTokenTime: Date?
    private var fullText = ""
    private var tokenCount = 0
    private var firstTokenRecorded = false
    private var isComplete = false
    private var error: Error?
    private var resultContinuation: CheckedContinuation<LLMGenerationResult, Error>?

    init(modelId: String, promptLength: Int) {
        self.modelId = modelId
        self.promptLength = promptLength
    }

    func markStart() {
        startTime = Date()
    }

    func recordToken(_ token: String) {
        fullText += token
        tokenCount += 1

        if !firstTokenRecorded {
            firstTokenRecorded = true
            firstTokenTime = Date()
        }
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
            framework: "llamacpp",
            tokensPerSecond: tokensPerSecond,
            timeToFirstTokenMs: timeToFirstTokenMs,
            thinkingTokens: 0,
            responseTokens: outputTokens
        )
    }
}
