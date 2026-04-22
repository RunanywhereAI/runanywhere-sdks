//
//  RunAnywhere+TextGeneration.swift
//  RunAnywhere SDK
//
//  Public API for text generation (LLM) operations.
//  Calls C++ directly via CppBridge.LLM for all operations.
//  Events are emitted by C++ layer via CppEventBridge.
//
//  v2 close-out Phase 9: the ~80-LOC `ThinkingContentParser` enum that
//  used to live at the bottom of this file was deleted; the public
//  surface now lives in `CppBridge+LLMThinking.swift` and delegates to
//  the `rac_llm_*` C ABI for byte-equivalent behavior across all SDKs.
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

        // Get handle from CppBridge.LLM
        let handle = try await CppBridge.LLM.shared.getHandle()

        // Verify model is loaded
        guard await CppBridge.LLM.shared.isLoaded else {
            throw SDKError.llm(.notInitialized, "LLM model not loaded")
        }

        let modelId = await CppBridge.LLM.shared.currentModelId ?? "unknown"
        let opts = options ?? LLMGenerationOptions()

        let startTime = Date()

        // Build C options
        var cOptions = rac_llm_options_t()
        cOptions.max_tokens = Int32(opts.maxTokens)
        cOptions.temperature = opts.temperature
        cOptions.top_p = opts.topP
        cOptions.streaming_enabled = RAC_FALSE

        let systemPromptDesc = opts.systemPrompt.map { "set(\($0.count) chars)" } ?? "nil"
        SDKLogger.llm.info(
            "[PARAMS] generate: temperature=\(cOptions.temperature), top_p=\(cOptions.top_p), "
            + "max_tokens=\(cOptions.max_tokens), system_prompt=\(systemPromptDesc), "
            + "streaming=\(cOptions.streaming_enabled == RAC_TRUE)"
        )

        // Generate (C++ emits events) - wrap in system_prompt lifetime scope
        var llmResult = rac_llm_result_t()
        let generateResult: rac_result_t
        if let systemPrompt = opts.systemPrompt {
            generateResult = systemPrompt.withCString { sysPromptPtr in
                cOptions.system_prompt = sysPromptPtr
                return prompt.withCString { promptPtr in
                    rac_llm_component_generate(handle, promptPtr, &cOptions, &llmResult)
                }
            }
        } else {
            cOptions.system_prompt = nil
            generateResult = prompt.withCString { promptPtr in
                rac_llm_component_generate(handle, promptPtr, &cOptions, &llmResult)
            }
        }

        guard generateResult == RAC_SUCCESS else {
            throw SDKError.llm(.generationFailed, "Generation failed: \(generateResult)")
        }

        let endTime = Date()
        let totalTimeMs = endTime.timeIntervalSince(startTime) * 1000

        // Extract result
        let rawText: String
        if let textPtr = llmResult.text {
            rawText = String(cString: textPtr)
        } else {
            rawText = ""
        }
        let inputTokens = Int(llmResult.prompt_tokens)
        let outputTokens = Int(llmResult.completion_tokens)
        let tokensPerSecond = llmResult.tokens_per_second > 0 ? Double(llmResult.tokens_per_second) : 0

        let (generatedText, thinkingContent) = ThinkingContentParser.extract(from: rawText)
        let (thinkingTokens, responseTokens) = ThinkingContentParser.splitTokens(
            totalCompletionTokens: outputTokens,
            responseText: generatedText,
            thinkingContent: thinkingContent
        )

        return LLMGenerationResult(
            text: generatedText,
            thinkingContent: thinkingContent,
            inputTokens: inputTokens,
            tokensUsed: outputTokens,
            modelUsed: modelId,
            latencyMs: totalTimeMs,
            framework: "llamacpp",
            tokensPerSecond: tokensPerSecond,
            timeToFirstTokenMs: nil,
            thinkingTokens: thinkingTokens,
            responseTokens: responseTokens
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

        let handle = try await CppBridge.LLM.shared.getHandle()

        guard await CppBridge.LLM.shared.isLoaded else {
            throw SDKError.llm(.notInitialized, "LLM model not loaded")
        }

        let modelId = await CppBridge.LLM.shared.currentModelId ?? "unknown"
        let opts = options ?? LLMGenerationOptions()

        let collector = LLMStreamingMetricsCollector(modelId: modelId, promptLength: prompt.count)

        var cOptions = rac_llm_options_t()
        cOptions.max_tokens = Int32(opts.maxTokens)
        cOptions.temperature = opts.temperature
        cOptions.top_p = opts.topP
        cOptions.streaming_enabled = RAC_TRUE

        let systemPromptDesc = opts.systemPrompt.map { "set(\($0.count) chars)" } ?? "nil"
        SDKLogger.llm.info(
            "[PARAMS] generateStream: temperature=\(cOptions.temperature), top_p=\(cOptions.top_p), "
            + "max_tokens=\(cOptions.max_tokens), system_prompt=\(systemPromptDesc), "
            + "streaming=\(cOptions.streaming_enabled == RAC_TRUE)"
        )

        let stream = createTokenStream(
            prompt: prompt,
            handle: handle,
            options: cOptions,
            collector: collector,
            systemPrompt: opts.systemPrompt
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
        collector: LLMStreamingMetricsCollector,
        systemPrompt: String? = nil
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream<String, Error> { continuation in
            Task {
                await collector.markStart()

                let context = LLMStreamCallbackContext(continuation: continuation, collector: collector)
                // passRetained: context is released in completeCallback or errorCallback
                let contextPtr = Unmanaged.passRetained(context).toOpaque()

                let callbacks = LLMStreamCallbacks.create()
                var cOptions = options

                let callCFunction: () -> rac_result_t = {
                    prompt.withCString { promptPtr in
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
                }

                let streamResult: rac_result_t
                if let systemPrompt = systemPrompt {
                    streamResult = systemPrompt.withCString { sysPtr in
                        cOptions.system_prompt = sysPtr
                        return callCFunction()
                    }
                } else {
                    cOptions.system_prompt = nil
                    streamResult = callCFunction()
                }

                if streamResult != RAC_SUCCESS {
                    // NOTE: Do not release contextPtr here. The C++ layer always invokes
                    // errorCallback before returning non-SUCCESS, and errorCallback consumes
                    // the retained reference via takeRetainedValue(). Releasing here would
                    // cause a double-release.
                    let error = SDKError.llm(.generationFailed, "Stream generation failed: \(streamResult)")
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
            // Cancellation is handled by an atomic flag in llm_component.cpp — no Swift Task
            // context exists on this C callback thread, so Task.isCancelled would always be false.
            guard let tokenPtr = tokenPtr, let userData = userData else { return RAC_TRUE }
            let ctx = Unmanaged<LLMStreamCallbackContext>.fromOpaque(userData).takeUnretainedValue()
            let token = String(cString: tokenPtr)
            Task {
                await ctx.collector.recordToken(token)
                ctx.continuation.yield(token)
            }
            return RAC_TRUE
        }

        let completeCallback: CompleteFn = { resultPtr, userData in
            guard let userData = userData else { return }
            let ctx = Unmanaged<LLMStreamCallbackContext>.fromOpaque(userData).takeRetainedValue()
            ctx.continuation.finish()

            if let result = resultPtr?.pointee {
                Task {
                    await ctx.collector.markCompleteWithMetrics(
                        promptTokens: Int(result.prompt_tokens),
                        completionTokens: Int(result.completion_tokens),
                        tokensPerSecond: Double(result.tokens_per_second),
                        timeToFirstTokenMs: Double(result.time_to_first_token_ms)
                    )
                }
            } else {
                Task { await ctx.collector.markComplete() }
            }
        }

        let errorCallback: ErrorFn = { _, errorMsg, userData in
            guard let userData = userData else { return }
            let ctx = Unmanaged<LLMStreamCallbackContext>.fromOpaque(userData).takeRetainedValue()
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

// v2 close-out Phase 9 (P2-4): the in-Swift `ThinkingContentParser` enum
// was deleted from this file (~80 LOC). The replacement, with the same
// public API and byte-equivalent behavior, lives in
// `Sources/RunAnywhere/Foundation/Bridge/Extensions/CppBridge+LLMThinking.swift`
// and delegates to the `rac_llm_*` C ABI in
// `rac/features/llm/rac_llm_thinking.h` so all 5 SDKs render
// `<think>...</think>` blocks identically.

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

    private var cppPromptTokens: Int?
    private var cppCompletionTokens: Int?
    private var cppTokensPerSecond: Double?
    private var cppTimeToFirstTokenMs: Double?

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

    func markCompleteWithMetrics(
        promptTokens: Int,
        completionTokens: Int,
        tokensPerSecond: Double,
        timeToFirstTokenMs: Double
    ) {
        if promptTokens > 0 { cppPromptTokens = promptTokens }
        if completionTokens > 0 { cppCompletionTokens = completionTokens }
        if tokensPerSecond > 0 { cppTokensPerSecond = tokensPerSecond }
        if timeToFirstTokenMs > 0 { cppTimeToFirstTokenMs = timeToFirstTokenMs }

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

        let timeToFirstTokenMs: Double?
        if let cppTtft = cppTimeToFirstTokenMs {
            timeToFirstTokenMs = cppTtft
        } else if let start = startTime, let firstToken = firstTokenTime {
            timeToFirstTokenMs = firstToken.timeIntervalSince(start) * 1000
        } else {
            timeToFirstTokenMs = nil
        }

        let outputTokens = cppCompletionTokens ?? max(1, tokenCount)
        // Fallback: if backend didn't report prompt tokens, estimate from prompt
        // character length (~4 chars per token) rather than reporting 0.
        let estimatedPromptTokens = promptLength > 0 ? max(1, promptLength / 4) : 0
        let inputTokens = cppPromptTokens ?? estimatedPromptTokens

        let tokensPerSecond: Double
        if let cppTps = cppTokensPerSecond {
            tokensPerSecond = cppTps
        } else {
            let totalTimeSec = latencyMs / 1000.0
            tokensPerSecond = totalTimeSec > 0 ? Double(outputTokens) / totalTimeSec : 0
        }

        let (responseText, thinkingContent) = ThinkingContentParser.extract(from: fullText)
        let (thinkingTokens, responseTokens) = ThinkingContentParser.splitTokens(
            totalCompletionTokens: outputTokens,
            responseText: responseText,
            thinkingContent: thinkingContent
        )

        return LLMGenerationResult(
            text: responseText,
            thinkingContent: thinkingContent,
            inputTokens: inputTokens,
            tokensUsed: outputTokens,
            modelUsed: modelId,
            latencyMs: latencyMs,
            framework: "llamacpp",
            tokensPerSecond: tokensPerSecond,
            timeToFirstTokenMs: timeToFirstTokenMs,
            thinkingTokens: thinkingTokens,
            responseTokens: responseTokens
        )
    }
}
