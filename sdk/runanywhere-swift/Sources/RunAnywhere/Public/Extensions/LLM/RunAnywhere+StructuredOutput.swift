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
    /// Caller-supplied `options` (maxOutputTokens, temperature, topP, preferredFramework,
    /// systemPrompt, …) are forwarded to the underlying LLM through
    /// `generateWithStructuredOutput(_:)`; the resulting raw text is then
    /// passed to `extractStructuredOutput(text:schema:)` so commons still owns
    /// extraction, canonicalization, and schema validation. This restores the
    /// pre-PR-494 behavior where caller generation knobs were honored
    /// (see comment record `swift-public-features-004`).
    @available(*, deprecated, renamed: "llm.generateStructured(prompt:schema:options:)")
    static func generateStructured(
        prompt: String,
        schema: JsonSchema,
        options: RALLMGenerationOptions? = nil
    ) async throws -> RAStructuredOutputResult {
        guard isReady else {
            throw SDKException(code: .notInitialized, message: "SDK not initialized", category: .internal)
        }
        let generation = try await generateWithStructuredOutputProto(
            prompt: prompt,
            structuredOutput: .defaults(schema: schema),
            options: options
        )
        return try parseStructuredOutput(text: generation.text, schema: schema)
    }

    // generateStructuredStream(_:schema:options:) is deleted: its return
    // type, RAStructuredOutputStreamEvent (and StructuredOutputStreamEventKind),
    // was removed outright from idl/structured_output.proto with no
    // replacement -- structured GENERATION now streams through the ordinary
    // `RunAnywhere.llm.generateStream`/`generateStream(request)` path with
    // `LLMGenerationOptions.structuredOutput` set, using the surviving
    // RALLMStreamEvent shape. Had zero live callers (verified against the
    // example app and this module's tests) at the time of the API
    // realignment. Mirrors the Kotlin SDK's identical deletion.

    /// Generate raw text via the LLM with a structured-output configuration
    /// applied to the request. Returns the raw `RALLMGenerationResult`; callers
    /// can pass `text` to `extractStructuredOutput(text:schema:)` for parsing.
    @available(*, deprecated, renamed: "llm.generateStructured(prompt:schema:options:)")
    static func generateWithStructuredOutput(
        prompt: String,
        structuredOutput: RAStructuredOutputOptions,
        options: RALLMGenerationOptions? = nil
    ) async throws -> RALLMGenerationResult {
        try await generateWithStructuredOutputProto(
            prompt: prompt,
            structuredOutput: structuredOutput,
            options: options
        )
    }

    internal static func generateWithStructuredOutputProto(
        prompt: String,
        structuredOutput: RAStructuredOutputOptions,
        options: RALLMGenerationOptions? = nil
    ) async throws -> RALLMGenerationResult {
        var internalOptions = options ?? RALLMGenerationOptions.defaults()
        internalOptions.structuredOutput = structuredOutput
        if structuredOutput.includeSchemaInPrompt {
            let prep = try CppBridge.StructuredOutput.preparePrompt(prompt: prompt, options: structuredOutput)
            guard !prep.hasError else {
                throw SDKException(proto: prep.error)
            }
            if prep.hasSystemPrompt { internalOptions.systemPrompt = prep.systemPrompt }
        }
        let request = internalOptions.toRALLMGenerateRequest(prompt: prompt)
        return try await generateProto(request)
    }

}
