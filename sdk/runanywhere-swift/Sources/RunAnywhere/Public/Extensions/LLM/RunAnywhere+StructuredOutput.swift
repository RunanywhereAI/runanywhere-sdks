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
    /// Caller-supplied `options` (maxTokens, temperature, topP, preferredFramework,
    /// systemPrompt, …) are forwarded to the underlying LLM through
    /// `generateWithStructuredOutput(_:)`; the resulting raw text is then
    /// passed to `extractStructuredOutput(text:schema:)` so commons still owns
    /// extraction, canonicalization, and schema validation. This restores the
    /// pre-PR-494 behavior where caller generation knobs were honored
    /// (see comment record `swift-public-features-004`).
    static func generateStructured(
        prompt: String,
        schema: RAJSONSchema,
        options: RALLMGenerationOptions? = nil
    ) async throws -> RAStructuredOutputResult {
        guard isInitialized else {
            throw SDKException(code: .notInitialized, message: "SDK not initialized", category: .internal)
        }
        let generation = try await generateWithStructuredOutput(
            prompt: prompt,
            structuredOutput: .defaults(schema: schema),
            options: options
        )
        return try extractStructuredOutput(text: generation.text, schema: schema)
    }

    /// Stream structured output generation using a JSON schema (CANONICAL_API §3).
    ///
    /// Caller-supplied `options` are forwarded to `generateStream(_:)` so
    /// generation knobs (maxTokens, temperature, topP, preferredFramework,
    /// systemPrompt, …) take effect. Token events from the LLM are
    /// translated into `.token` `RAStructuredOutputStreamEvent`s; on the
    /// final token the accumulated text is parsed via
    /// `extractStructuredOutput` and emitted as a `.completed` event with
    /// the validated `RAStructuredOutputResult` attached. Decoding/validation
    /// failures are surfaced as a terminal `.error` event.
    /// (See comment record `swift-public-features-004`.)
    static func generateStructuredStream(
        prompt: String,
        schema: RAJSONSchema,
        options: RALLMGenerationOptions? = nil
    ) -> AsyncStream<RAStructuredOutputStreamEvent> {
        guard isInitialized else { return errorStream("SDK not initialized") }

        var internalOptions = options ?? RALLMGenerationOptions.defaults()
        internalOptions.structuredOutput = .defaults(schema: schema)
        var request = internalOptions.toRALLMGenerateRequest(prompt: prompt)
        request.streamingEnabled = true

        return AsyncStream { continuation in
            let task = Task {
                do {
                    let stream = try await generateStream(request)
                    var accumulated = ""
                    var seq: UInt64 = 0
                    for await event in stream {
                        if Task.isCancelled { break }
                        if !event.token.isEmpty {
                            accumulated += event.token
                            seq &+= 1
                            var emitted = RAStructuredOutputStreamEvent()
                            emitted.kind = .token
                            emitted.token = event.token
                            emitted.seq = seq
                            continuation.yield(emitted)
                        }
                    }
                    seq &+= 1
                    do {
                        let parsed = try extractStructuredOutput(text: accumulated, schema: schema)
                        var terminal = RAStructuredOutputStreamEvent()
                        terminal.kind = .completed
                        terminal.result = parsed
                        terminal.seq = seq
                        continuation.yield(terminal)
                    } catch {
                        var failure = RAStructuredOutputStreamEvent()
                        failure.kind = .error
                        failure.errorMessage = error.localizedDescription
                        failure.seq = seq
                        continuation.yield(failure)
                    }
                    continuation.finish()
                } catch {
                    var failure = RAStructuredOutputStreamEvent()
                    failure.kind = .error
                    failure.errorMessage = error.localizedDescription
                    continuation.yield(failure)
                    continuation.finish()
                }
            }
            // Defensive belt-and-braces cancellation (pass2-syn-073):
            // The inner `generateStream` AsyncStream already wires its own
            // `onCancel` to `rac_llm_cancel_proto` via the generated proto
            // adapter (see pass2-syn-018), so cancelling `task` here will
            // cascade through `for await` → inner stream `.cancelled` →
            // native cancel. This block additionally invokes the public
            // `cancelGeneration()` API directly so consumer cancellation
            // (view-model deinit, navigation away, parent `Task.cancel()`)
            // *always* tears down the native LLM, even if a future refactor
            // of the inner generator drops or delays the cascade.
            continuation.onTermination = { _ in
                task.cancel()
                Task { await RunAnywhere.cancelGeneration() }
            }
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
