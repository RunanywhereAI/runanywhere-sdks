//
//  RunAnywhere+StructuredOutput.swift
//  RunAnywhere SDK
//
//  Public API for structured output generation.
//  Uses C++ rac_structured_output_* APIs for JSON extraction.
//

import CRACommons
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
        options: LLMGenerationOptions? = nil
    ) async throws -> RAStructuredOutputResult {
        guard isInitialized else {
            throw SDKException.general(.notInitialized, "SDK not initialized")
        }

        // Build a system prompt instructing the model to output JSON.
        var systemPromptPtr: UnsafeMutablePointer<CChar>?
        let schemaJson: String
        if let jsonData = try? JSONSerialization.data(withJSONObject: [:]),
           let jsonStr = String(data: jsonData, encoding: .utf8) {
            schemaJson = jsonStr
        } else {
            schemaJson = "{}"
        }
        let sysPrompt: String = schemaJson.withCString { schemaPtr in
            let rc = rac_structured_output_get_system_prompt(schemaPtr, &systemPromptPtr)
            if rc == RAC_SUCCESS, let ptr = systemPromptPtr {
                let s = String(cString: ptr)
                rac_free(ptr)
                return s
            }
            return "Output only valid JSON matching the provided schema."
        }

        let effectiveOptions = LLMGenerationOptions(
            maxTokens: options?.maxTokens ?? 1500,
            temperature: options?.temperature ?? 0.7,
            topP: options?.topP ?? 1.0,
            stopSequences: options?.stopSequences ?? [],
            streamingEnabled: false,
            preferredFramework: options?.preferredFramework,
            structuredOutput: nil,
            systemPrompt: sysPrompt
        )

        let generationResult = try await generateForStructuredOutput(prompt, options: effectiveOptions)
        return extractStructuredOutput(text: generationResult.text, schema: schema)
    }

    /// Stream structured output generation using a JSON schema (CANONICAL_API §3).
    ///
    /// Yields `RAStructuredOutputResult` values as tokens accumulate, with a
    /// final result when generation completes.
    ///
    /// - Parameters:
    ///   - prompt: The text prompt.
    ///   - schema: The expected JSON schema (`RAJSONSchema`).
    ///   - options: Generation options (optional).
    /// - Returns: `AsyncStream<RAStructuredOutputResult>` — last event carries the complete result.
    static func generateStructuredStream(
        prompt: String,
        schema: RAJSONSchema,
        options: LLMGenerationOptions? = nil
    ) -> AsyncStream<RAStructuredOutputResult> {
        AsyncStream { continuation in
            Task {
                guard isInitialized else {
                    continuation.finish()
                    return
                }
                do {
                    let effectiveOptions = LLMGenerationOptions(
                        maxTokens: options?.maxTokens ?? 1500,
                        temperature: options?.temperature ?? 0.7,
                        topP: options?.topP ?? 1.0,
                        stopSequences: options?.stopSequences ?? [],
                        streamingEnabled: true,
                        preferredFramework: options?.preferredFramework
                    )
                    var accumulated = ""
                    let eventStream = try await generateStream(prompt, options: effectiveOptions)
                    for await event in eventStream {
                        if !event.token.isEmpty {
                            accumulated += event.token
                            // Emit an in-progress partial result
                            var partial = RAStructuredOutputResult()
                            partial.rawText = accumulated
                            continuation.yield(partial)
                        }
                        if event.isFinal { break }
                    }
                    // Emit the final result with JSON extraction attempted
                    let final_ = extractStructuredOutput(text: accumulated, schema: schema)
                    continuation.yield(final_)
                    continuation.finish()
                } catch {
                    continuation.finish()
                }
            }
        }
    }

    // MARK: - Generic Generatable API (kept for backward compatibility)

    /// Generate structured output that conforms to a Generatable type (non-streaming)
    /// - Parameters:
    ///   - type: The type to generate (must conform to Generatable)
    ///   - prompt: The prompt to generate from
    ///   - options: Generation options (structured output config will be added automatically)
    /// - Returns: The generated object of the specified type
    static func generateStructured<T: Generatable>(
        _ type: T.Type,
        prompt: String,
        options: LLMGenerationOptions? = nil
    ) async throws -> T {
        // Get system prompt from C++
        let systemPrompt = getStructuredOutputSystemPrompt(for: type)

        // Create effective options with system prompt
        let effectiveOptions = LLMGenerationOptions(
            maxTokens: options?.maxTokens ?? type.generationHints?.maxTokens ?? 1500,
            temperature: options?.temperature ?? type.generationHints?.temperature ?? 0.7,
            topP: options?.topP ?? 1.0,
            stopSequences: options?.stopSequences ?? [],
            streamingEnabled: false,
            preferredFramework: options?.preferredFramework,
            structuredOutput: StructuredOutputConfig(
                type: type,
                includeSchemaInPrompt: false
            ),
            systemPrompt: systemPrompt
        )

        // Generate text via CppBridge.LLM
        let generationResult = try await generateForStructuredOutput(prompt, options: effectiveOptions)

        // Extract JSON using C++ and parse to Swift type
        return try parseStructuredOutput(from: generationResult.text, type: type)
    }

    /// Generate structured output with streaming support
    /// - Parameters:
    ///   - type: The type to generate (must conform to Generatable)
    ///   - content: The content to generate from (e.g., educational content for quiz)
    ///   - options: Generation options (optional)
    /// - Returns: A structured output stream containing tokens and final result
    static func generateStructuredStream<T: Generatable>(
        _ type: T.Type,
        content: String,
        options: LLMGenerationOptions? = nil
    ) -> StructuredOutputStreamResult<T> {
        let accumulator = StreamAccumulator()

        // Get system prompt from C++
        let systemPrompt = getStructuredOutputSystemPrompt(for: type)

        // Create effective options with system prompt
        let effectiveOptions = LLMGenerationOptions(
            maxTokens: options?.maxTokens ?? type.generationHints?.maxTokens ?? 1500,
            temperature: options?.temperature ?? type.generationHints?.temperature ?? 0.7,
            topP: options?.topP ?? 1.0,
            stopSequences: options?.stopSequences ?? [],
            streamingEnabled: true,
            preferredFramework: options?.preferredFramework,
            structuredOutput: StructuredOutputConfig(
                type: type,
                includeSchemaInPrompt: false
            ),
            systemPrompt: systemPrompt
        )

        // Create token stream
        let tokenStream = AsyncThrowingStream<StreamToken, Error> { continuation in
            Task {
                do {
                    var tokenIndex = 0

                    // v2 close-out Phase G-2: generateStream returns
                    // AsyncStream<RALLMStreamEvent>; unwrap token text
                    // per event and stop at the terminal is_final marker.
                    let eventStream = try await generateStream(content, options: effectiveOptions)
                    for await event in eventStream {
                        let tokenText = event.token
                        if !tokenText.isEmpty {
                            let streamToken = StreamToken(
                                text: tokenText,
                                timestamp: Date(),
                                tokenIndex: tokenIndex
                            )
                            await accumulator.append(tokenText)
                            continuation.yield(streamToken)
                            tokenIndex += 1
                        }
                        if event.isFinal {
                            if !event.errorMessage.isEmpty {
                                throw SDKException.llm(.generationFailed, event.errorMessage)
                            }
                            break
                        }
                    }

                    await accumulator.markComplete()
                    continuation.finish()
                } catch {
                    await accumulator.markComplete()
                    continuation.finish(throwing: error)
                }
            }
        }

        // Create result task that waits for streaming to complete
        let resultTask = Task<T, Error> {
            // Wait for accumulation to complete
            await accumulator.waitForCompletion()

            // Get full response
            let fullResponse = await accumulator.fullText

            // Parse using C++ extraction + Swift decoding with retry logic
            var lastError: Error?

            for attempt in 1...3 {
                do {
                    return try parseStructuredOutput(from: fullResponse, type: type)
                } catch {
                    lastError = error
                    if attempt < 3 {
                        try? await Task.sleep(nanoseconds: 100_000_000)
                    }
                }
            }

            throw lastError ?? SDKException.llm(.extractionFailed, "Failed to parse structured output after 3 attempts")
        }

        return StructuredOutputStreamResult(tokenStream: tokenStream, result: resultTask)
    }

    /// Generate with structured output configuration
    /// - Parameters:
    ///   - prompt: The prompt to generate from
    ///   - structuredOutput: Structured output configuration
    ///   - options: Generation options
    /// - Returns: Generation result with structured data
    static func generateWithStructuredOutput(
        prompt: String,
        structuredOutput: StructuredOutputConfig,
        options: LLMGenerationOptions? = nil
    ) async throws -> LLMGenerationResult {
        let baseOptions = options ?? LLMGenerationOptions()
        let internalOptions = LLMGenerationOptions(
            maxTokens: baseOptions.maxTokens,
            temperature: baseOptions.temperature,
            topP: baseOptions.topP,
            stopSequences: baseOptions.stopSequences,
            streamingEnabled: baseOptions.streamingEnabled,
            preferredFramework: baseOptions.preferredFramework,
            structuredOutput: structuredOutput,
            systemPrompt: baseOptions.systemPrompt
        )

        return try await generateForStructuredOutput(prompt, options: internalOptions)
    }

    // MARK: - Private Helpers

    /// Get system prompt for structured output using C++ API
    private static func getStructuredOutputSystemPrompt<T: Generatable>(for type: T.Type) -> String {
        var promptPtr: UnsafeMutablePointer<CChar>?

        let result = type.jsonSchema.withCString { schemaPtr in
            rac_structured_output_get_system_prompt(schemaPtr, &promptPtr)
        }

        guard result == RAC_SUCCESS, let ptr = promptPtr else {
            // Fallback to basic prompt if C++ fails
            return """
            You are a JSON generator that outputs ONLY valid JSON without any additional text.
            Start with { and end with }. No text before or after.
            Expected schema: \(type.jsonSchema)
            """
        }

        let prompt = String(cString: ptr)
        rac_free(ptr)
        return prompt
    }

    /// Parse structured output using C++ JSON extraction + Swift decoding
    private static func parseStructuredOutput<T: Generatable>(
        from text: String,
        type: T.Type
    ) throws -> T {
        // Use C++ to extract JSON from the response
        var jsonPtr: UnsafeMutablePointer<CChar>?

        let extractResult = text.withCString { textPtr in
            rac_structured_output_extract_json(textPtr, &jsonPtr, nil)
        }

        guard extractResult == RAC_SUCCESS, let ptr = jsonPtr else {
            throw SDKException.llm(.extractionFailed, "No valid JSON found in the response")
        }

        let jsonString = String(cString: ptr)
        rac_free(ptr)

        // Convert to Data and decode using Swift's JSONDecoder
        guard let jsonData = jsonString.data(using: .utf8) else {
            throw SDKException.llm(.invalidFormat, "Failed to convert JSON string to data")
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        do {
            return try decoder.decode(type, from: jsonData)
        } catch {
            throw SDKException.llm(.validationFailed, "JSON decoding failed: \(error.localizedDescription)")
        }
    }

    /// Internal generation for structured output through the generated-proto LLM ABI.
    private static func generateForStructuredOutput(
        _ prompt: String,
        options: LLMGenerationOptions
    ) async throws -> LLMGenerationResult {
        try await generate(prompt, options: options)
    }
}
