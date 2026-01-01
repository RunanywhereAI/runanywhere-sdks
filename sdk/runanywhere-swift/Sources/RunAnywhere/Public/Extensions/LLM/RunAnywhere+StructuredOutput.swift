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

                    // Stream tokens via public API
                    let streamingResult = try await generateStream(content, options: effectiveOptions)
                    for try await token in streamingResult.stream {
                        let streamToken = StreamToken(
                            text: token,
                            timestamp: Date(),
                            tokenIndex: tokenIndex
                        )

                        // Accumulate for parsing
                        await accumulator.append(token)

                        // Yield to UI
                        continuation.yield(streamToken)
                        tokenIndex += 1
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

            throw lastError ?? SDKError.llm(.extractionFailed, "Failed to parse structured output after 3 attempts")
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
            throw SDKError.llm(.extractionFailed, "No valid JSON found in the response")
        }

        let jsonString = String(cString: ptr)
        rac_free(ptr)

        // Convert to Data and decode using Swift's JSONDecoder
        guard let jsonData = jsonString.data(using: .utf8) else {
            throw SDKError.llm(.invalidFormat, "Failed to convert JSON string to data")
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        do {
            return try decoder.decode(type, from: jsonData)
        } catch {
            throw SDKError.llm(.validationFailed, "JSON decoding failed: \(error.localizedDescription)")
        }
    }

    /// Internal generation for structured output (calls C++ directly)
    private static func generateForStructuredOutput(
        _ prompt: String,
        options: LLMGenerationOptions
    ) async throws -> LLMGenerationResult {
        guard isInitialized else {
            throw SDKError.general(.notInitialized, "SDK not initialized")
        }

        let handle = try await CppBridge.LLM.shared.getHandle()

        guard await CppBridge.LLM.shared.isLoaded else {
            throw SDKError.llm(.notInitialized, "LLM model not loaded")
        }

        let modelId = await CppBridge.LLM.shared.currentModelId ?? "unknown"
        let startTime = Date()

        // Build C options
        var cOptions = rac_llm_options_t()
        cOptions.max_tokens = Int32(options.maxTokens)
        cOptions.temperature = options.temperature
        cOptions.top_p = options.topP
        cOptions.streaming_enabled = RAC_FALSE

        // Generate
        var llmResult = rac_llm_result_t()
        let generateResult = prompt.withCString { promptPtr in
            rac_llm_component_generate(handle, promptPtr, &cOptions, &llmResult)
        }

        guard generateResult == RAC_SUCCESS else {
            throw SDKError.llm(.generationFailed, "Generation failed: \(generateResult)")
        }

        let totalTimeMs = Date().timeIntervalSince(startTime) * 1000
        let generatedText = llmResult.text.map { String(cString: $0) } ?? ""

        return LLMGenerationResult(
            text: generatedText,
            thinkingContent: nil,
            inputTokens: Int(llmResult.prompt_tokens),
            tokensUsed: Int(llmResult.completion_tokens),
            modelUsed: modelId,
            latencyMs: totalTimeMs,
            framework: "llamacpp",
            tokensPerSecond: Double(llmResult.tokens_per_second),
            timeToFirstTokenMs: nil,
            thinkingTokens: 0,
            responseTokens: Int(llmResult.completion_tokens)
        )
    }
}
