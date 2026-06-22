//
//  RunAnywhere+TextGeneration.swift
//  RunAnywhere SDK
//
//  Public API for text generation (LLM) operations.
//  Calls C++ directly via CppBridge.LLM for all operations.
//  Events are emitted by C++ layer via CppEventBridge.
//

import Foundation

// MARK: - Text Generation

public extension RunAnywhere {

    /// Generate text from a plain prompt — convenience overload that mirrors
    /// the Kotlin `RunAnywhere.generate(prompt:options:)` signature.
    /// Forwards to the proto-request variant after assembling the request
    /// from `options ?? .defaults()`.
    static func generate(
        prompt: String,
        options: RALLMGenerationOptions? = nil
    ) async throws -> RALLMGenerationResult {
        var request = (options ?? .defaults()).toRALLMGenerateRequest(prompt: prompt)
        request.streamingEnabled = false
        return try await generate(request)
    }

    /// Stream text generation from a plain prompt — convenience overload that
    /// mirrors the Kotlin `RunAnywhere.generateStream(prompt:options:)`
    /// signature. Forwards to the proto-request variant after assembling
    /// the request from `options ?? .defaults()` and enabling streaming.
    static func generateStream(
        prompt: String,
        options: RALLMGenerationOptions? = nil
    ) async throws -> AsyncStream<RALLMStreamEvent> {
        var request = (options ?? .defaults()).toRALLMGenerateRequest(prompt: prompt)
        request.streamingEnabled = true
        return try await generateStream(request)
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
    static func generate(_ request: RALLMGenerateRequest) async throws -> RALLMGenerationResult {
        guard isInitialized else {
            throw SDKException(code: .notInitialized, message: "SDK not initialized", category: .internal)
        }

        try await ensureServicesReady()

        let systemPromptDesc = request.systemPrompt.isEmpty ? "nil" : "set(\(request.systemPrompt.count) chars)"
        SDKLogger.llm.info(
            "[PARAMS] generate: temperature=\(request.temperature), top_p=\(request.topP), "
            + "max_tokens=\(request.maxTokens), system_prompt=\(systemPromptDesc), "
            + "streaming=\(request.streamingEnabled)"
        )

        return try await CppBridge.LLM.shared.generate(request)
    }

    /// Stream text generation through the generated-proto C++ LLM service ABI.
    ///
    /// Each `RALLMStreamEvent` is decoded from the full proto envelope so all
    /// optional fields are surfaced to consumers without any switch-case
    /// filtering at the adapter layer:
    ///   - `token` / `kind` / `tokenID` / `logprob` for streaming tokens
    ///   - `eventKind` (proto `LLMStreamEventKind`) to classify the event
    ///   - `toolCall` (proto field 18, hotspot-idl-002) when the event
    ///     represents a structured tool-call boundary — consumers can read
    ///     `event.hasToolCall` / `event.toolCall` directly without falling
    ///     back to JSON-parsing the raw `token` text (pass2-syn-010 follow-up).
    ///   - `result` (final aggregate metrics on terminal events).
    static func generateStream(_ request: RALLMGenerateRequest) async throws -> AsyncStream<RALLMStreamEvent> {
        guard isInitialized else {
            throw SDKException(code: .notInitialized, message: "SDK not initialized", category: .internal)
        }

        try await ensureServicesReady()

        let systemPromptDesc = request.systemPrompt.isEmpty ? "nil" : "set(\(request.systemPrompt.count) chars)"
        SDKLogger.llm.info(
            "[PARAMS] generateStream: temperature=\(request.temperature), top_p=\(request.topP), "
            + "max_tokens=\(request.maxTokens), system_prompt=\(systemPromptDesc), "
            + "streaming=\(request.streamingEnabled)"
        )

        return try await CppBridge.LLM.shared.generateStream(request)
    }

    /// Cancel the current text generation.
    ///
    /// Routes through the lifecycle proto ABI (`rac_llm_cancel_proto`) so the
    /// active `generate` / `generateStream` call — which runs through the
    /// handleless lifecycle path — observes the cancel signal and terminates
    /// promptly with `finishReason == .cancelled`. Calling the legacy
    /// per-component actor `cancel()` is a no-op against lifecycle generation
    /// (see comment record `hotspot-swift-public-features-002`).
    static func cancelGeneration() async {
        guard isInitialized else { return }
        do {
            _ = try await CppBridge.LLM.shared.cancelProto()
        } catch {
            SDKLogger.llm.warning("cancelGeneration failed: \(error.localizedDescription)")
        }
    }

    /// Build a canonical `RALLMGenerationResult` from a stream of
    /// `RALLMStreamEvent`s and the currently-loaded LLM model.
    ///
    /// Example apps previously synthesised this struct themselves with a
    /// hardcoded `framework = "llamacpp"` literal because the SDK exposed
    /// only the per-token stream. The aggregation logic (concatenating
    /// `event.token` text, counting tokens, computing TTFT/throughput from
    /// timestamps) is now owned by the SDK and the framework string is
    /// resolved from `currentModel(_:).framework.analyticsKey` so callers
    /// stay aligned with the registry's canonical framework label.
    ///
    /// - Parameters:
    ///   - prompt: Prompt text used to estimate `inputTokens` when the
    ///     backend does not surface it directly.
    ///   - events: AsyncStream of stream events from
    ///     `generateStream(_:)`. The function consumes the stream until
    ///     `isFinal == true` or the stream finishes.
    ///   - onToken: Optional callback invoked for each non-empty
    ///     `event.token` text. Receives the aggregated transcript so far
    ///     (suitable for live UI updates).
    /// - Returns: A populated `RALLMGenerationResult` whose `framework`
    ///   field matches the loaded LLM model's analytics key; on terminal
    ///   error events the `errorMessage` is propagated.
    static func aggregateStream(
        prompt: String,
        events: AsyncStream<RALLMStreamEvent>,
        onToken: ((String) async -> Void)? = nil
    ) async -> RALLMGenerationResult {
        var fullResponse = ""
        var tokenCount = 0
        var firstTokenTime: Date?
        let startTime = Date()
        var finishReason = ""
        var terminalError = ""
        var finalEvent: RALLMStreamEvent?

        for await event in events {
            if !event.token.isEmpty {
                if firstTokenTime == nil { firstTokenTime = Date() }
                fullResponse += event.token
                tokenCount += 1
                if let onToken {
                    await onToken(fullResponse)
                }
            }
            if event.isFinal {
                finalEvent = event
                finishReason = event.finishReason
                terminalError = event.errorMessage
                break
            }
        }

        let totalLatency = Date().timeIntervalSince(startTime) * 1000
        let ttft = firstTokenTime.map { $0.timeIntervalSince(startTime) * 1000 }

        var llmRequest = RACurrentModelRequest()
        llmRequest.category = .language
        let snapshot = RunAnywhere.currentModel(llmRequest)
        let modelID = snapshot.found ? snapshot.modelID : ""
        let framework = snapshot.found
            ? snapshot.model.framework.analyticsKey
            : InferenceFramework.unknown.analyticsKey

        // Prefer the backend's terminal aggregate result (text + metrics) when
        // the final event carries one, matching the Web SDK; otherwise fall back
        // to the locally concatenated text / wall-clock metrics.
        let final = finalEvent.flatMap { $0.hasResult ? $0.result : nil }
        var result = RALLMGenerationResult()
        result.text = final?.text ?? fullResponse
        if let final, final.hasThinkingContent {
            result.thinkingContent = final.thinkingContent
        }
        result.inputTokens = final.map { $0.promptTokens } ?? Int32(max(1, prompt.count / 4))
        result.tokensGenerated = final.map { $0.completionTokens } ?? Int32(tokenCount)
        result.responseTokens = final.map { $0.completionTokens } ?? Int32(tokenCount)
        result.totalTokens = final.map { $0.totalTokens } ?? (result.inputTokens + result.tokensGenerated)
        result.modelUsed = modelID
        result.generationTimeMs = final.map { Double($0.totalTimeMs) } ?? totalLatency
        result.framework = framework
        result.promptEvalTimeMs = final.map { $0.promptEvalTimeMs } ?? 0
        result.decodeTimeMs = final.map { $0.decodeTimeMs } ?? 0
        result.tokensPerSecond = final.map { Double($0.tokensPerSecond) }
            ?? (totalLatency > 0 ? Double(tokenCount) / (totalLatency / 1000) : 0)
        if let ttftFromFinal = final.map({ Double($0.timeToFirstTokenMs) }) {
            result.ttftMs = ttftFromFinal
        } else if let ttft {
            result.ttftMs = ttft
        }
        if !finishReason.isEmpty { result.finishReason = finishReason }
        if !terminalError.isEmpty { result.errorMessage = terminalError }
        return result
    }
}

// MARK: - Structured Output Extraction

public extension RunAnywhere {

    /// Extract structured output from a raw text string using a JSON schema.
    ///
    /// Delegates to the generated structured-output parse proto ABI so commons
    /// owns extraction, canonicalization, and schema validation.
    static func extractStructuredOutput(
        text: String,
        schema: RAJSONSchema
    ) throws -> RAStructuredOutputResult {
        try CppBridge.StructuredOutput.parse(
            CppBridge.StructuredOutput.makeParseRequest(text: text, schema: schema)
        )
    }
}
