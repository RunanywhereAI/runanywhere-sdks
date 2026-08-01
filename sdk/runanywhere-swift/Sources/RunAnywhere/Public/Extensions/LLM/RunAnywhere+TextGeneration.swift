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
        schema: RAJSONSchema
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
        var answerResponse = ""
        var thinkingResponse = ""
        var tokenCount = 0
        var firstTokenTime: Date?
        let startTime = Date()
        var finishReason = ""
        var terminalError: RASDKError?
        var finalEvent: RALLMStreamEvent?

        for await event in events {
            if !event.token.isEmpty {
                if firstTokenTime == nil { firstTokenTime = Date() }
                tokenCount += 1
                if event.kind == .thought {
                    thinkingResponse += event.token
                    if let onThinking {
                        await onThinking(thinkingResponse)
                    }
                } else if event.kind != .toolCall {
                    answerResponse += event.token
                    if let onToken {
                        await onToken(answerResponse)
                    }
                }
            }
            if event.isFinal {
                finalEvent = event
                finishReason = event.finishReason
                terminalError = event.hasError ? event.error : nil
                break
            }
        }

        let totalLatency = Date().timeIntervalSince(startTime) * 1000
        let ttft = firstTokenTime.map { $0.timeIntervalSince(startTime) * 1000 }

        let snapshot = loadedModelSnapshot(category: .language, includeModelMetadata: true)
        let modelID = snapshot.found ? snapshot.modelID : ""
        let framework = snapshot.found
            ? snapshot.model.framework.analyticsKey
            : InferenceFramework.unknown.analyticsKey

        // Prefer the backend's terminal aggregate result (text + metrics) when
        // the final event carries one; otherwise fall back to the locally
        // concatenated text and wall-clock metrics.
        let final = finalEvent.flatMap { $0.hasResult ? $0.result : nil }
        var result = RALLMGenerationResult()
        result.text = final?.text ?? answerResponse
        if let final, final.hasThinkingContent {
            result.thinkingContent = final.thinkingContent
        } else if !thinkingResponse.isEmpty {
            result.thinkingContent = thinkingResponse
        }
        result.usage.inputTokens = final.map { $0.usage.inputTokens } ?? Int32(max(1, prompt.count / 4))
        result.usage.outputTokens = final.map { $0.usage.outputTokens } ?? Int32(tokenCount)
        result.responseTokens = final.map { $0.usage.outputTokens } ?? Int32(tokenCount)
        result.usage.totalTokens = final.map { $0.usage.totalTokens }
            ?? (result.usage.inputTokens + result.usage.outputTokens)
        result.modelUsed = modelID
        result.generationTimeMs = final.map { Double($0.totalTimeMs) } ?? totalLatency
        result.framework = framework
        result.promptEvalTimeMs = final.map { $0.promptEvalTimeMs } ?? 0
        result.decodeTimeMs = final.map { $0.decodeTimeMs } ?? 0
        result.usage.tokensPerSecond = final.map { $0.usage.tokensPerSecond }
            ?? (totalLatency > 0 ? Double(tokenCount) / (totalLatency / 1000) : 0)
        if let ttftFromFinal = final.map({ Double($0.timeToFirstTokenMs) }) {
            result.ttftMs = ttftFromFinal
        } else if let ttft {
            result.ttftMs = ttft
        }
        if !finishReason.isEmpty { result.finishReason = finishReason }
        if let terminalError { result.error = terminalError }
        return result
    }
}
