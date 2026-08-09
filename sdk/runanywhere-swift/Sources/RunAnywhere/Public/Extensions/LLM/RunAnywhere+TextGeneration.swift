//
//  RunAnywhere+TextGeneration.swift
//  RunAnywhere SDK
//
//  Deprecated flat text-generation verbs. The v3 surface is `RunAnywhere.llm`.
//

import Foundation

public extension RunAnywhere {

    /// Generate text from a plain prompt.
    @available(*, deprecated, renamed: "llm.generate(prompt:options:)")
    static func generate(
        prompt: String,
        options: RALLMGenerationOptions? = nil
    ) async throws -> RALLMGenerationResult {
        let requestOptions = options ?? .defaults()
        return try await generateProto(requestOptions.toRALLMGenerateRequest(prompt: prompt))
    }

    /// Stream text generation from a plain prompt.
    @available(*, deprecated, renamed: "llm.generateStream(prompt:options:)")
    static func generateStream(
        prompt: String,
        options: RALLMGenerationOptions? = nil
    ) async throws -> AsyncStream<RALLMStreamEvent> {
        let requestOptions = options ?? .defaults()
        return try await generateStreamProto(requestOptions.toRALLMGenerateRequest(prompt: prompt))
    }

    /// Seed the loaded on-device model's adaptive context with a reusable system prompt.
    static func injectSystemPrompt(_ prompt: String) async throws {
        guard isInitialized else {
            throw SDKException(code: .notInitialized, message: "SDK not initialized", category: .internal)
        }
        try await ensureServicesReady()
        try await CppBridge.LLM.shared.injectSystemPrompt(prompt)
    }

    /// Append text to the loaded on-device model's adaptive context.
    static func appendContext(_ text: String) async throws {
        guard isInitialized else {
            throw SDKException(code: .notInitialized, message: "SDK not initialized", category: .internal)
        }
        try await ensureServicesReady()
        try await CppBridge.LLM.shared.appendContext(text)
    }

    /// Generate from the accumulated adaptive context without clearing the KV cache first.
    static func generateFromContext(
        query: String,
        options: RALLMGenerationOptions? = nil
    ) async throws -> RALLMGenerationResult {
        guard isInitialized else {
            throw SDKException(code: .notInitialized, message: "SDK not initialized", category: .internal)
        }
        try await ensureServicesReady()
        return try await CppBridge.LLM.shared.generateFromContext(query: query, options: options)
    }

    /// Clear the loaded on-device model's adaptive context.
    static func clearContext() async throws {
        guard isInitialized else {
            throw SDKException(code: .notInitialized, message: "SDK not initialized", category: .internal)
        }
        try await ensureServicesReady()
        try await CppBridge.LLM.shared.clearContext()
    }

    /// Generate text through the generated-proto C++ LLM service ABI.
    @available(*, deprecated, renamed: "llm.generate(prompt:options:)")
    static func generate(_ request: RALLMGenerateRequest) async throws -> RALLMGenerationResult {
        try await generateProto(request)
    }

    /// Stream text generation through the generated-proto C++ LLM service ABI.
    @available(*, deprecated, renamed: "llm.generateStream(prompt:options:)")
    static func generateStream(_ request: RALLMGenerateRequest) async throws -> AsyncStream<RALLMStreamEvent> {
        try await generateStreamProto(request)
    }

    /// Cancel the current text generation.
    @available(*, deprecated, message: "Cancel the Task consuming llm.generateStream instead")
    static func cancelGeneration() async {
        guard isReady else { return }
        do {
            _ = try await CppBridge.LLM.shared.cancelProto()
        } catch {
            SDKLogger.llm.warning("cancelGeneration failed: \(error.localizedDescription)")
        }
    }

    /// Extract structured output from a raw text string using a JSON schema.
    @available(*, deprecated, renamed: "llm.generateStructured(prompt:schema:options:)")
    static func extractStructuredOutput(
        text: String,
        schema: JsonSchema
    ) throws -> RAStructuredOutputResult {
        try parseStructuredOutput(text: text, schema: schema)
    }
}

// MARK: - Internal proto-level helpers

extension RunAnywhere {

    internal static func generateProto(_ request: RALLMGenerateRequest) async throws -> RALLMGenerationResult {
        guard isReady else {
            throw SDKException(code: .notInitialized, message: "SDK not initialized", category: .internal)
        }
        try await ensureServicesReady()
        logGenerationParams("generate", options: request.options)
        return try await CppBridge.LLM.shared.generate(request)
    }

    internal static func generateStreamProto(
        _ request: RALLMGenerateRequest
    ) async throws -> AsyncStream<RALLMStreamEvent> {
        guard isReady else {
            throw SDKException(code: .notInitialized, message: "SDK not initialized", category: .internal)
        }
        try await ensureServicesReady()
        logGenerationParams("generateStream", options: request.options)
        return try await CppBridge.LLM.shared.generateStream(request)
    }

    private static func logGenerationParams(_ verb: String, options: RALLMGenerationOptions) {
        let systemPromptDesc = options.systemPrompt.isEmpty ? "nil" : "set(\(options.systemPrompt.count) chars)"
        SDKLogger.llm.info(
            "[PARAMS] \(verb): temperature=\(options.temperature), top_p=\(options.topP), "
            + "max_output_tokens=\(options.maxOutputTokens), system_prompt=\(systemPromptDesc)"
        )
    }
}

// MARK: - Stream aggregation (deprecated)

public extension RunAnywhere {

    /// Build a canonical `RALLMGenerationResult` from a stream of events.
    @available(*, deprecated, message: "llm.generateStream emits a .completed event carrying the full result")
    static func aggregateStream(
        prompt: String,
        events: AsyncStream<RALLMStreamEvent>,
        onThinking: ((String) async -> Void)? = nil,
        onToken: ((String) async -> Void)? = nil
    ) async -> RALLMGenerationResult {
        let startTime = Date()
        let stream = await drainStream(events, onThinking: onThinking, onToken: onToken)
        let answerResponse = stream.answer
        let thinkingResponse = stream.thinking
        let finalEvent = stream.finalEvent

        let totalLatency = Date().timeIntervalSince(startTime) * 1000
        let ttft = stream.firstTokenTime.map { $0.timeIntervalSince(startTime) * 1000 }

        let snapshot = loadedModelSnapshot(category: .language, includeModelMetadata: true)
        let modelID = snapshot.found ? snapshot.modelID : ""
        let framework = snapshot.found
            ? snapshot.model.framework.analyticsKey
            : InferenceFramework.unknown.analyticsKey

        // Prefer the backend's terminal aggregate result (text + metrics) when
        // the final event carries one, matching the Web SDK; otherwise fall back
        // to the locally concatenated text / wall-clock metrics.
        //
        // Connect (and some backends) may emit a final event whose `result.text`
        // is empty/short even after tokens were streamed. Never replace a longer
        // accumulated transcript with a weaker terminal payload — that shows up
        // as "here's the code:" with no code after the stream completes.
        let final = finalEvent.flatMap { $0.hasResult ? $0.result : nil }
        var result = RALLMGenerationResult()
        if let finalText = final?.text, !finalText.isEmpty, finalText.count >= answerResponse.count {
            result.text = finalText
        } else {
            result.text = answerResponse.isEmpty ? (final?.text ?? "") : answerResponse
        }
        if let final, final.hasThinkingContent {
            result.thinkingContent = final.thinkingContent
        } else if !thinkingResponse.isEmpty {
            result.thinkingContent = thinkingResponse
        }
        result.usage.inputTokens = final.map { $0.usage.inputTokens } ?? Int32(max(1, prompt.count / 4))
        result.usage.outputTokens = final.map { $0.usage.outputTokens } ?? Int32(stream.tokenCount)
        result.responseTokens = final.map { $0.usage.outputTokens } ?? Int32(stream.tokenCount)
        result.usage.totalTokens = final.map { $0.usage.totalTokens }
            ?? (result.usage.inputTokens + result.usage.outputTokens)
        result.modelUsed = modelID
        // totalTimeMs was deleted outright; generationTimeMs (already a
        // Double) is the sole wall-clock field left on this message.
        let generationTimeMs: Double = {
            if let fromFinal = final?.generationTimeMs, fromFinal > 0 { return fromFinal }
            return totalLatency
        }()
        result.generationTimeMs = generationTimeMs
        result.framework = framework
        applyTimingMetrics(
            to: &result,
            final: final,
            wallClockTtftMs: ttft,
            generationTimeMs: generationTimeMs
        )
        if stream.finishReason != .unspecified { result.finishReason = stream.finishReason }
        if let terminalError = stream.terminalError { result.error = terminalError }
        return result
    }
}

// MARK: - Stream aggregation internals

private extension RunAnywhere {

    /// What one pass over the event stream accumulated.
    struct DrainedStream {
        var answer = ""
        var thinking = ""
        var tokenCount = 0
        var firstTokenTime: Date?
        var finishReason: RAFinishReason = .unspecified
        var terminalError: RASDKError?
        var finalEvent: RALLMStreamEvent?
    }

    /// Consume `events` to the first terminal event, invoking the caller's
    /// per-token hooks as text arrives.
    static func drainStream(
        _ events: AsyncStream<RALLMStreamEvent>,
        onThinking: ((String) async -> Void)?,
        onToken: ((String) async -> Void)?
    ) async -> DrainedStream {
        var drained = DrainedStream()
        for await event in events {
            if !event.token.isEmpty {
                if drained.firstTokenTime == nil { drained.firstTokenTime = Date() }
                drained.tokenCount += 1
                // RALLMStreamEvent's discriminator is the event-level
                // `eventKind: RALLMStreamEventKind`, not a per-token
                // `RATokenKind` field (`.kind` doesn't exist on this type).
                if event.eventKind == .thinking {
                    drained.thinking += event.token
                    if let onThinking {
                        await onThinking(drained.thinking)
                    }
                } else if event.eventKind != .toolCall {
                    drained.answer += event.token
                    if let onToken {
                        await onToken(drained.answer)
                    }
                }
            }
            // isFinal was deleted outright; .completed/.error are the
            // terminal event_kind values now (idl/llm_service.proto).
            if event.eventKind == .completed || event.eventKind == .error {
                drained.finalEvent = event
                drained.finishReason = event.finishReason
                drained.terminalError = event.hasError ? event.error : nil
                break
            }
        }
        return drained
    }

    /// Fill in the throughput/latency fields, preferring the backend's own
    /// numbers and falling back to wall clock.
    ///
    /// tokensPerSecond was renamed decodeTokensPerSecond and moved onto the
    /// shared RATokenUsage message (idl/token_usage.proto). Batch-buffered
    /// streams (Maple/Bonsai) dump tokens only after the full generate;
    /// wall-to-first ≈ total and "decode = total − ttft" becomes a few ms →
    /// absurd tok/s and a fake 15s TTFT. Match commons.
    static func applyTimingMetrics(
        to result: inout RALLMGenerationResult,
        final: RALLMGenerationResult?,
        wallClockTtftMs: Double?,
        generationTimeMs: Double
    ) {
        let reportedTps = final?.usage.decodeTokensPerSecond ?? 0
        let reportedTtft: Int64? = {
            if let ttftFromFinal = final?.usage.ttftMs, ttftFromFinal > 0 { return ttftFromFinal }
            if let wallClockTtftMs { return Int64(wallClockTtftMs.rounded()) }
            return nil
        }()
        let outputTokens = Int(result.usage.outputTokens)
        let wallTps = generationTimeMs > 0 && outputTokens > 0
            ? Double(outputTokens) / (generationTimeMs / 1000.0) : 0
        let decodeWindow = reportedTtft.map { generationTimeMs - Double($0) } ?? generationTimeMs
        let batchBuffered =
            reportedTtft != nil && decodeWindow < max(50.0, generationTimeMs * 0.05)
        if batchBuffered {
            result.usage.decodeTokensPerSecond = wallTps
            result.usage.ttftMs = 0
            result.promptEvalTimeMs = 0
            result.decodeTimeMs = Int64(generationTimeMs.rounded())
        } else {
            result.usage.decodeTokensPerSecond = reportedTps > 0 ? reportedTps : wallTps
            if let reportedTtft { result.usage.ttftMs = reportedTtft }
            result.promptEvalTimeMs = final?.promptEvalTimeMs ?? (reportedTtft ?? 0)
            result.decodeTimeMs = final?.decodeTimeMs ?? 0
        }
    }
}
