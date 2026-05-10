//
//  RunAnywhere+StructuredOutput.swift
//  RunAnywhere SDK
//
//  Public façade for structured output generation. All orchestration —
//  prompt preparation, model invocation, thinking-tag stripping, JSON
//  extraction, schema validation — lives in the commons C++ layer behind
//  `rac_structured_output_*_proto`. Swift exposes Swift-idiomatic
//  async/throws/AsyncStream wrappers and nothing else.
//

import Foundation

public extension RunAnywhere {

    /// Generate structured output from a prompt using a JSON schema (CANONICAL_API §3).
    ///
    /// Commons owns the full pipeline (prepare prompt → run lifecycle LLM →
    /// strip thinking tags → extract JSON → validate). `options` is accepted
    /// for cross-SDK API parity; commons currently uses default generation
    /// parameters.
    static func generateStructured(
        prompt: String,
        schema: RAJSONSchema,
        options: RALLMGenerationOptions? = nil
    ) async throws -> RAStructuredOutputResult {
        _ = options
        guard isInitialized else {
            throw SDKException(code: .notInitialized, message: "SDK not initialized", category: .internal)
        }
        return try CppBridge.StructuredOutput.generate(
            CppBridge.StructuredOutput.makeGenerateRequest(
                prompt: prompt,
                options: .defaults(schema: schema)
            )
        )
    }

    /// Stream structured output generation using a JSON schema (CANONICAL_API §3).
    ///
    /// Commons emits `RAStructuredOutputStreamEvent` payloads (token, partial
    /// JSON, terminal completed/error). Sequence numbers, timestamps and
    /// request IDs are populated by the C++ stream producer.
    static func generateStructuredStream(
        prompt: String,
        schema: RAJSONSchema,
        options: RALLMGenerationOptions? = nil
    ) -> AsyncStream<RAStructuredOutputStreamEvent> {
        _ = options
        guard isInitialized else { return errorStream("SDK not initialized") }
        do {
            return try CppBridge.StructuredOutput.generateStream(
                CppBridge.StructuredOutput.makeGenerateRequest(
                    prompt: prompt,
                    options: .defaults(schema: schema)
                )
            )
        } catch {
            return errorStream(error.localizedDescription)
        }
    }

    /// Generate raw text via the LLM with a structured-output configuration
    /// applied to the request. Returns the raw `RALLMGenerationResult`; callers
    /// can pass `text` to `extractStructuredOutput(text:schema:)` for parsing.
    static func generateWithStructuredOutput(
        prompt: String,
        structuredOutput: RAStructuredOutputOptions,
        options: RALLMGenerationOptions? = nil
    ) async throws -> RALLMGenerationResult {
        var internalOptions = options ?? RALLMGenerationOptions.defaults()
        internalOptions.structuredOutput = structuredOutput
        if structuredOutput.includeSchemaInPrompt {
            let prep = try CppBridge.StructuredOutput.preparePrompt(prompt: prompt, options: structuredOutput)
            guard prep.errorCode == 0 else {
                throw SDKException(code: .processingFailed, message: prep.errorMessage, category: .internal)
            }
            if prep.hasSystemPrompt { internalOptions.systemPrompt = prep.systemPrompt }
        }
        var request = internalOptions.toRALLMGenerateRequest(prompt: prompt)
        request.streamingEnabled = false
        return try await generate(request)
    }

    private static func errorStream(_ message: String) -> AsyncStream<RAStructuredOutputStreamEvent> {
        AsyncStream { continuation in
            var event = RAStructuredOutputStreamEvent()
            event.kind = .error
            event.errorMessage = message
            continuation.yield(event)
            continuation.finish()
        }
    }
}
