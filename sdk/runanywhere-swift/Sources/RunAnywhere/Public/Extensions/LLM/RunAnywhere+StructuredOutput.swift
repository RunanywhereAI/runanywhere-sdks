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
        schema: RAJSONSchema,
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

    /// Stream structured output generation using a JSON schema (CANONICAL_API §3).
    ///
    /// Caller-supplied `options` are forwarded to `generateStream(_:)` so
    /// generation knobs (maxOutputTokens, temperature, topP, preferredFramework,
    /// systemPrompt, …) take effect. Token events from the LLM are
    /// translated into `.token` `RAStructuredOutputStreamEvent`s; on the
    /// final token the accumulated text is parsed via
    /// `extractStructuredOutput` and emitted as a `.completed` event with
    /// the validated `RAStructuredOutputResult` attached.
    ///
    /// Pre-flight failures (e.g. uninitialised SDK) throw synchronously from
    /// the `throws` caller; in-flight failures (LLM driver errors,
    /// parse/validation errors) terminate the returned
    /// `AsyncThrowingStream` so consumers receive them via `for try await`
    /// or the iterator's `throw`, matching the cross-SDK contract (Kotlin
    /// `Flow` exception propagation, Web `AsyncIterable` throw).
    /// (See comment record `swift-public-features-007`.)
    @available(*, deprecated, renamed: "llm.generateStructured(prompt:schema:options:)")
    static func generateStructuredStream(
        prompt: String,
        schema: RAJSONSchema,
        options: RALLMGenerationOptions? = nil
    ) throws -> AsyncThrowingStream<RAStructuredOutputStreamEvent, Error> {
        guard isReady else {
            throw SDKException(code: .notInitialized, message: "SDK not initialized", category: .internal)
        }

        var internalOptions = options ?? RALLMGenerationOptions.defaults()
        internalOptions.structuredOutput = .defaults(schema: schema)
        let request = internalOptions.toRALLMGenerateRequest(prompt: prompt)

        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let stream = try await generateStreamProto(request)
                    var accumulated = ""
                    for await event in stream {
                        if Task.isCancelled { break }
                        if !event.token.isEmpty {
                            accumulated += event.token
                            var emitted = RAStructuredOutputStreamEvent()
                            emitted.kind = .token
                            emitted.token = event.token
                            continuation.yield(emitted)
                        }
                    }
                    let parsed = try parseStructuredOutput(text: accumulated, schema: schema)
                    var terminal = RAStructuredOutputStreamEvent()
                    terminal.kind = .completed
                    terminal.result = parsed
                    continuation.yield(terminal)
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            // Cancelling this wrapper task drops the inner generated stream;
            // its canonical onCancel hook invokes rac_llm_cancel_proto.
            continuation.onTermination = { termination in
                switch termination {
                case .cancelled:
                    task.cancel()
                case .finished:
                    break
                @unknown default:
                    break
                }
            }
        }
    }

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
