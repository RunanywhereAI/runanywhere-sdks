//
//  RunAnywhere+TextGeneration.swift
//  RunAnywhere SDK
//
//  Public API for text generation (LLM) operations.
//  Calls C++ directly via CppBridge.LLM for all operations.
//  Events are emitted by C++ layer via CppEventBridge.
//


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
