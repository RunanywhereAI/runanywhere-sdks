//
//  RunAnywhere+TextGeneration.swift
//  RunAnywhere SDK
//
//  Public API for text generation (LLM) operations.
//  Calls C++ directly via CppBridge.LLM for all operations.
//  Events are emitted by C++ layer via CppEventBridge.
//
//  v2 close-out Phase G-2: the direct-C-callback streaming plumbing
//  (`createTokenStream` + `LLMStreamCallbackContext` + `LLMStreamCallbacks`
//  + `LLMStreamingMetricsCollector`) was DELETED from this file. The
//  public `generateStream` now returns the proto-encoded event stream
//  emitted by `LLMStreamAdapter` (which is the single C-callback
//  registration path — no parallel hand-rolled shim remains).
//

import CRACommons
import Foundation

// MARK: - Text Generation

public extension RunAnywhere {

    /// Simple text generation with automatic event publishing.
    /// - Parameter prompt: The text prompt
    /// - Returns: Generated response (text only)
    static func chat(_ prompt: String) async throws -> String {
        let result = try await generate(prompt, options: nil)
        return result.text
    }

    /// Generate text with full metrics and analytics.
    /// - Parameters:
    ///   - prompt: The text prompt
    ///   - options: Generation options (optional)
    /// - Returns: GenerationResult with full metrics including thinking tokens, timing, performance, etc.
    /// - Note: Events are automatically dispatched via C++ layer
    static func generate(
        _ prompt: String,
        options: LLMGenerationOptions? = nil
    ) async throws -> LLMGenerationResult {
        let opts = options ?? LLMGenerationOptions()
        var request = opts.toRALLMGenerateRequest(prompt: prompt)
        request.streamingEnabled = false
        let result = try await generate(request)
        return LLMGenerationResult(from: result)
    }

    /// Generate text through the generated-proto C++ LLM service ABI.
    static func generate(_ request: RALLMGenerateRequest) async throws -> RALLMGenerationResult {
        guard isInitialized else {
            throw SDKException.general(.notInitialized, "SDK not initialized")
        }

        try await ensureServicesReady()

        guard await isModelLoaded else {
            throw SDKException.llm(.notInitialized, "LLM model not loaded")
        }

        let systemPromptDesc = request.systemPrompt.isEmpty ? "nil" : "set(\(request.systemPrompt.count) chars)"
        SDKLogger.llm.info(
            "[PARAMS] generate: temperature=\(request.temperature), top_p=\(request.topP), "
            + "max_tokens=\(request.maxTokens), system_prompt=\(systemPromptDesc), "
            + "streaming=\(request.streamingEnabled)"
        )

        return try await CppBridge.LLM.shared.generate(request)
    }

    /// Streaming text generation using the Phase G-2 proto-byte event
    /// stream. Returns an `AsyncStream<RALLMStreamEvent>` — one event per
    /// generated token, plus a terminal event (`isFinal == true`) that
    /// carries the `finish_reason` ("stop" / "length" / "cancelled" /
    /// "error") and optional `error_message`.
    ///
    /// Under the hood this delegates to [`LLMStreamAdapter`] which owns
    /// the single `rac_llm_set_stream_proto_callback` registration for
    /// the handle. There is no parallel hand-rolled streaming path; this
    /// is the single C-callback-to-Swift path for LLM tokens.
    ///
    /// Example:
    /// ```swift
    /// let stream = try await RunAnywhere.generateStream(prompt)
    /// for await event in stream {
    ///     if event.isFinal { break }
    ///     print(event.token, terminator: "")
    /// }
    /// ```
    ///
    /// - Parameters:
    ///   - prompt: The text prompt
    ///   - options: Generation options (optional)
    /// - Returns: `AsyncStream<RALLMStreamEvent>` of proto-decoded events.
    static func generateStream(
        _ prompt: String,
        options: LLMGenerationOptions? = nil
    ) async throws -> AsyncStream<RALLMStreamEvent> {
        let opts = options ?? LLMGenerationOptions(streamingEnabled: true)
        var request = opts.toRALLMGenerateRequest(prompt: prompt)
        request.streamingEnabled = true
        return try await generateStream(request)
    }

    /// Stream text generation through the generated-proto C++ LLM service ABI.
    static func generateStream(_ request: RALLMGenerateRequest) async throws -> AsyncStream<RALLMStreamEvent> {
        guard isInitialized else {
            throw SDKException.general(.notInitialized, "SDK not initialized")
        }

        try await ensureServicesReady()

        guard await isModelLoaded else {
            throw SDKException.llm(.notInitialized, "LLM model not loaded")
        }

        let systemPromptDesc = request.systemPrompt.isEmpty ? "nil" : "set(\(request.systemPrompt.count) chars)"
        SDKLogger.llm.info(
            "[PARAMS] generateStream: temperature=\(request.temperature), top_p=\(request.topP), "
            + "max_tokens=\(request.maxTokens), system_prompt=\(systemPromptDesc), "
            + "streaming=\(request.streamingEnabled)"
        )

        return try await CppBridge.LLM.shared.generateStream(request)
    }
}

// MARK: - Thinking Token Utilities (CANONICAL_API §3)

public extension RunAnywhere {

    /// Extract `<think>…</think>` blocks from model output.
    ///
    /// Returns the text outside the block as `.text` and the thinking
    /// content inside the block as `.thinking` (nil if no block found).
    ///
    /// - Parameter text: Raw model output that may contain `<think>` blocks.
    /// - Returns: `ThinkingExtractionResult` with `.text` and `.thinking`.
    static func extractThinkingTokens(_ text: String) -> ThinkingExtractionResult {
        let (responseText, thinkingContent) = ThinkingContentParser.extract(from: text)
        return ThinkingExtractionResult(text: responseText, thinking: thinkingContent)
    }

    /// Remove all `<think>…</think>` blocks (including unclosed trailing ones)
    /// from model output.
    ///
    /// - Parameter text: Raw model output.
    /// - Returns: Text with all thinking blocks removed.
    static func stripThinkingTokens(_ text: String) -> String {
        return ThinkingContentParser.strip(from: text)
    }

    /// Split model output into a `(thinking, response)` tuple.
    ///
    /// If no `<think>` block is found, `thinking` is empty and `response`
    /// contains the full text.
    ///
    /// - Parameter text: Raw model output.
    /// - Returns: Named tuple `(thinking: String, response: String)`.
    static func splitThinkingAndResponse(_ text: String) -> (thinking: String, response: String) {
        let (responseText, thinkingContent) = ThinkingContentParser.extract(from: text)
        return (thinking: thinkingContent ?? "", response: responseText)
    }
}

// MARK: - Structured Output Extraction (CANONICAL_API §3)

public extension RunAnywhere {

    /// Extract structured output from a raw text string using a JSON schema.
    ///
    /// Delegates to the `rac_structured_output_extract_json` C ABI to find
    /// and validate the JSON in `text`, then wraps the result in an
    /// `RAStructuredOutputResult`.
    ///
    /// - Parameters:
    ///   - text: Raw text (e.g. a previously-generated LLM response).
    ///   - schema: The expected JSON schema (`RAJSONSchema` / `JSONSchema`).
    /// - Returns: `RAStructuredOutputResult` with `rawOutput`, `jsonOutput`, and `validation`.
    static func extractStructuredOutput(
        text: String,
        schema: RAJSONSchema
    ) -> RAStructuredOutputResult {
        var jsonPtr: UnsafeMutablePointer<CChar>?
        let extractResult = text.withCString { textPtr in
            rac_structured_output_extract_json(textPtr, &jsonPtr, nil)
        }

        var result = RAStructuredOutputResult()
        result.rawText = text

        if extractResult == RAC_SUCCESS, let ptr = jsonPtr {
            let jsonString = String(cString: ptr)
            rac_free(ptr)
            if let jsonData = jsonString.data(using: .utf8) {
                result.parsedJson = jsonData
            }
            var validation = RAStructuredOutputValidation()
            validation.isValid = true
            validation.containsJson = true
            result.validation = validation
        } else {
            var validation = RAStructuredOutputValidation()
            validation.isValid = false
            validation.containsJson = false
            validation.errorMessage = "No valid JSON found in the response"
            result.validation = validation
        }
        return result
    }
}

// MARK: - ThinkingExtractionResult

/// Result of extracting thinking tokens from model output.
public struct ThinkingExtractionResult: Sendable {
    /// The response text with thinking blocks removed.
    public let text: String
    /// The extracted thinking content, or nil if no `<think>` block was found.
    public let thinking: String?

    public init(text: String, thinking: String?) {
        self.text = text
        self.thinking = thinking
    }
}

// v2 close-out Phase 9 (P2-4): the in-Swift `ThinkingContentParser` enum
// was deleted from this file (~80 LOC). The replacement, with the same
// public API and byte-equivalent behavior, lives in
// `Sources/RunAnywhere/Foundation/Bridge/Extensions/CppBridge+LLMThinking.swift`
// and delegates to the `rac_llm_*` C ABI in
// `rac/features/llm/rac_llm_thinking.h`.
