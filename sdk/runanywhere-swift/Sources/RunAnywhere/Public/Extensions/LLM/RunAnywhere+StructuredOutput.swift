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
    /// the validated `RAStructuredOutputResult` attached.
    ///
    /// Pre-flight failures (e.g. uninitialised SDK) throw synchronously from
    /// the `throws` caller; in-flight failures (LLM driver errors,
    /// parse/validation errors) terminate the returned
    /// `AsyncThrowingStream` so consumers receive them via `for try await`
    /// or the iterator's `throw`, matching the cross-SDK contract (Kotlin
    /// `Flow` exception propagation, Web `AsyncIterable` throw).
    /// (See comment record `swift-public-features-007`.)
    static func generateStructuredStream(
        prompt: String,
        schema: RAJSONSchema,
        options: RALLMGenerationOptions? = nil
    ) throws -> AsyncThrowingStream<RAStructuredOutputStreamEvent, Error> {
        guard isInitialized else {
            throw SDKException(code: .notInitialized, message: "SDK not initialized", category: .internal)
        }

        var internalOptions = options ?? RALLMGenerationOptions.defaults()
        internalOptions.structuredOutput = .defaults(schema: schema)
        var request = internalOptions.toRALLMGenerateRequest(prompt: prompt)
        request.streamingEnabled = true

        return AsyncThrowingStream { continuation in
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
                    let parsed = try extractStructuredOutput(text: accumulated, schema: schema)
                    var terminal = RAStructuredOutputStreamEvent()
                    terminal.kind = .completed
                    terminal.result = parsed
                    terminal.seq = seq
                    continuation.yield(terminal)
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            // Manual cancellation fallback (pass3-syn-058):
            // The inner `generateStream` AsyncStream does NOT yet wire its
            // own `onCancel` to `rac_llm_cancel_proto` — the proto-ABI
            // codegen template still omits the `onCancel:` argument on the
            // LLM builder (see Generated/ModalityProtoABI+Generated.swift
            // around lines 308-329). Until the generator is fixed (tracked
            // by pass3-syn-059 / pass3-syn-061), this block manually
            // invokes `cancelGeneration()` on consumer cancellation so
            // view-model deinit, navigation away, or a parent
            // `Task.cancel()` always tears down the native LLM.
            //
            // IMPORTANT: switch on `termination` and only fire the native
            // cancel on `.cancelled`. `.finished` means the producer Task
            // above already called `continuation.finish()` after the
            // terminal `.completed` event (or `.finish(throwing:)` after an
            // error) — calling `cancelGeneration()` there would invoke
            // `rac_llm_cancel_proto` on the lifecycle LLM handle and race
            // with any follow-up `RunAnywhere.generate(...)` the caller
            // kicks off immediately after the stream completes. See the
            // canonical pattern in CppBridge+ModalityProtoABI.swift.
            continuation.onTermination = { termination in
                switch termination {
                case .cancelled:
                    task.cancel()
                    Task { await RunAnywhere.cancelGeneration() }
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

}
