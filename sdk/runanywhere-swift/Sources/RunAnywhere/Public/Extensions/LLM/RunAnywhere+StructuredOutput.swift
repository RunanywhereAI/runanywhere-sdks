//
//  RunAnywhere+StructuredOutput.swift
//  RunAnywhere SDK
//
//  Public API for structured output generation.
//  Uses generated structured-output proto requests/results through commons.
//

import Foundation

// MARK: - Structured Output Extensions

public extension RunAnywhere {

    // MARK: - Canonical JSONSchema-based API (CANONICAL_API §3)

    /// Generate structured output from a prompt using a JSON schema (CANONICAL_API §3).
    ///
    /// The model is instructed to produce JSON conforming to `schema`. The raw
    /// output is extracted and returned as an `RAStructuredOutputResult`.
    ///
    /// - Parameters:
    ///   - prompt: The text prompt.
    ///   - schema: The expected JSON schema (`RAJSONSchema`).
    ///   - options: Generation options (optional).
    /// - Returns: `RAStructuredOutputResult` with `rawOutput`, `jsonOutput`, and `validation`.
    static func generateStructured(
        prompt: String,
        schema: RAJSONSchema,
        options: RALLMGenerationOptions? = nil
    ) async throws -> RAStructuredOutputResult {
        guard isInitialized else {
            throw SDKException.general(.notInitialized, "SDK not initialized")
        }

        let structuredOptions = RAStructuredOutputOptions.defaults(schema: schema)
        let promptResult = try CppBridge.StructuredOutput.preparePrompt(
            prompt: prompt,
            options: structuredOptions
        )
        try throwIfStructuredPromptError(promptResult)

        var effectiveOptions = options ?? RALLMGenerationOptions.defaults()
        effectiveOptions.maxTokens = effectiveOptions.maxTokens > 0 ? effectiveOptions.maxTokens : 1500
        effectiveOptions.temperature = effectiveOptions.temperature > 0 ? effectiveOptions.temperature : 0.7
        effectiveOptions.topP = effectiveOptions.topP > 0 ? effectiveOptions.topP : 1.0
        effectiveOptions.streamingEnabled = false
        if promptResult.hasSystemPrompt {
            effectiveOptions.systemPrompt = promptResult.systemPrompt
        }
        effectiveOptions.jsonSchema = promptResult.hasJsonSchema ? promptResult.jsonSchema : structuredOptions.jsonSchema
        effectiveOptions.structuredOutput = structuredOptions

        let generationResult = try await generateForStructuredOutput(prompt, options: effectiveOptions)
        return try extractStructuredOutput(text: generationResult.text, schema: schema)
    }

    /// Stream structured output generation using a JSON schema (CANONICAL_API §3).
    ///
    /// Yields generated `RAStructuredOutputStreamEvent` values as tokens
    /// accumulate, with a completed event carrying the final extracted result.
    ///
    /// - Parameters:
    ///   - prompt: The text prompt.
    ///   - schema: The expected JSON schema (`RAJSONSchema`).
    ///   - options: Generation options (optional).
    /// - Returns: `AsyncStream<RAStructuredOutputStreamEvent>` with token,
    ///            completed, or error events.
    static func generateStructuredStream(
        prompt: String,
        schema: RAJSONSchema,
        options: RALLMGenerationOptions? = nil
    ) -> AsyncStream<RAStructuredOutputStreamEvent> {
        AsyncStream { continuation in
            Task {
                let requestID = UUID().uuidString
                var sequence: UInt64 = 0

                func makeEvent(_ kind: RAStructuredOutputStreamEventKind) -> RAStructuredOutputStreamEvent {
                    var event = RAStructuredOutputStreamEvent()
                    event.seq = sequence
                    event.timestampUs = Int64(Date().timeIntervalSince1970 * 1_000_000)
                    event.requestID = requestID
                    event.kind = kind
                    sequence += 1
                    return event
                }

                guard isInitialized else {
                    var event = makeEvent(.error)
                    event.errorMessage = "SDK not initialized"
                    continuation.yield(event)
                    continuation.finish()
                    return
                }
                do {
                    let structuredOptions = RAStructuredOutputOptions.defaults(schema: schema)
                    let promptResult = try CppBridge.StructuredOutput.preparePrompt(
                        prompt: prompt,
                        options: structuredOptions
                    )
                    try throwIfStructuredPromptError(promptResult)
                    var effectiveOptions = options ?? RALLMGenerationOptions.defaults()
                    effectiveOptions.maxTokens = effectiveOptions.maxTokens > 0 ? effectiveOptions.maxTokens : 1500
                    effectiveOptions.temperature = effectiveOptions.temperature > 0 ? effectiveOptions.temperature : 0.7
                    effectiveOptions.topP = effectiveOptions.topP > 0 ? effectiveOptions.topP : 1.0
                    effectiveOptions.streamingEnabled = true
                    if promptResult.hasSystemPrompt {
                        effectiveOptions.systemPrompt = promptResult.systemPrompt
                    }
                    effectiveOptions.jsonSchema = promptResult.hasJsonSchema
                        ? promptResult.jsonSchema
                        : structuredOptions.jsonSchema
                    effectiveOptions.structuredOutput = structuredOptions
                    var accumulated = ""
                    var streamRequest = effectiveOptions.toRALLMGenerateRequest(prompt: prompt)
                    streamRequest.streamingEnabled = true
                    let eventStream = try await generateStream(streamRequest)
                    for await event in eventStream {
                        if !event.token.isEmpty {
                            accumulated += event.token
                            var tokenEvent = makeEvent(.token)
                            tokenEvent.token = event.token
                            tokenEvent.partialJson = accumulated
                            continuation.yield(tokenEvent)
                        }
                        if event.isFinal {
                            if !event.errorMessage.isEmpty {
                                var errorEvent = makeEvent(.error)
                                errorEvent.errorMessage = event.errorMessage
                                continuation.yield(errorEvent)
                                continuation.finish()
                                return
                            }
                            break
                        }
                    }
                    let finalResult = try extractStructuredOutput(text: accumulated, schema: schema)
                    var completedEvent = makeEvent(.completed)
                    completedEvent.result = finalResult
                    completedEvent.validation = finalResult.validation
                    continuation.yield(completedEvent)
                    continuation.finish()
                } catch {
                    var errorEvent = makeEvent(.error)
                    errorEvent.errorMessage = error.localizedDescription
                    continuation.yield(errorEvent)
                    continuation.finish()
                }
            }
        }
    }

    /// Generate with structured output configuration
    /// - Parameters:
    ///   - prompt: The prompt to generate from
    ///   - structuredOutput: Structured output configuration
    ///   - options: Generation options
    /// - Returns: Generation result with structured data
    static func generateWithStructuredOutput(
        prompt: String,
        structuredOutput: RAStructuredOutputOptions,
        options: RALLMGenerationOptions? = nil
    ) async throws -> RALLMGenerationResult {
        var internalOptions = options ?? RALLMGenerationOptions.defaults()
        internalOptions.structuredOutput = structuredOutput
        let schemaJson = structuredOutput.hasJsonSchema && !structuredOutput.jsonSchema.isEmpty
            ? structuredOutput.jsonSchema
            : structuredOutput.schema.jsonSchemaString
        internalOptions.jsonSchema = schemaJson
        if structuredOutput.includeSchemaInPrompt {
            let promptResult = try CppBridge.StructuredOutput.preparePrompt(
                prompt: prompt,
                options: structuredOutput
            )
            try throwIfStructuredPromptError(promptResult)
            if promptResult.hasSystemPrompt {
                internalOptions.systemPrompt = promptResult.systemPrompt
            }
        }

        return try await generateForStructuredOutput(prompt, options: internalOptions)
    }

    // MARK: - Private Helpers

    private static func throwIfStructuredPromptError(
        _ result: RAStructuredOutputPromptResult
    ) throws {
        guard result.errorCode == 0 else {
            throw SDKException.general(
                .processingFailed,
                result.hasErrorMessage && !result.errorMessage.isEmpty
                    ? result.errorMessage
                    : "Structured output prompt preparation failed: \(result.errorCode)"
            )
        }
    }

    /// Internal generation for structured output through the generated-proto LLM ABI.
    private static func generateForStructuredOutput(
        _ prompt: String,
        options: RALLMGenerationOptions
    ) async throws -> RALLMGenerationResult {
        var request = options.toRALLMGenerateRequest(prompt: prompt)
        request.streamingEnabled = false
        return try await generate(request)
    }
}
