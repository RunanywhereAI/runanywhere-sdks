import Foundation

// MARK: - Structured Output Generation Service

/// Service for generating structured output from LLMs
public final class StructuredOutputGenerationService {

    private let handler: StructuredOutputHandler

    public init() {
        self.handler = StructuredOutputHandler()
    }

    // MARK: - Non-Streaming Generation

    /// Generate structured output that conforms to a Generatable type (non-streaming)
    /// - Parameters:
    ///   - type: The type to generate (must conform to Generatable)
    ///   - prompt: The prompt to generate from
    ///   - options: Generation options (structured output config will be added automatically)
    ///   - llmCapability: The LLM capability to use for generation
    /// - Returns: The generated object of the specified type
    public func generateStructured<T: Generatable>(
        _ type: T.Type,
        prompt: String,
        options: LLMGenerationOptions?,
        llmCapability: LLMCapability
    ) async throws -> T {
        // Get system prompt for structured output
        let systemPrompt = handler.getSystemPrompt(for: type)

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

        // Build user prompt
        let userPrompt = handler.buildUserPrompt(for: type, content: prompt)

        // Generate the text using LLMCapability
        let generationResult = try await llmCapability.generate(
            userPrompt,
            options: effectiveOptions
        )

        // Parse using StructuredOutputHandler
        let result = try handler.parseStructuredOutput(
            from: generationResult.text,
            type: type
        )

        return result
    }

    // MARK: - Streaming Generation

    /// Generate structured output with streaming support
    /// - Parameters:
    ///   - type: The type to generate (must conform to Generatable)
    ///   - content: The content to generate from
    ///   - options: Generation options (optional)
    ///   - streamGenerator: Function to generate token stream
    /// - Returns: A structured output stream containing tokens and final result
    public func generateStructuredStream<T: Generatable>(
        _ type: T.Type,
        content: String,
        options: LLMGenerationOptions?,
        streamGenerator: @escaping (String, LLMGenerationOptions) async throws -> LLMStreamingResult
    ) -> StructuredOutputStreamResult<T> {
        // Create a shared accumulator
        let accumulator = StreamAccumulator()
        let handler = self.handler

        // Get system prompt for structured output
        let systemPrompt = handler.getSystemPrompt(for: type)

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

        // Build user prompt
        let userPrompt = handler.buildUserPrompt(for: type, content: content)

        // Create token stream
        let tokenStream = AsyncThrowingStream<StreamToken, Error> { continuation in
            Task {
                do {
                    var tokenIndex = 0

                    // Stream tokens
                    let streamingResult = try await streamGenerator(userPrompt, effectiveOptions)
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

            // Parse using StructuredOutputHandler with retry logic
            var lastError: Error?

            for attempt in 1...3 {
                do {
                    return try handler.parseStructuredOutput(
                        from: fullResponse,
                        type: type
                    )
                } catch {
                    lastError = error
                    if attempt < 3 {
                        // Brief delay before retry
                        try? await Task.sleep(nanoseconds: 100_000_000)
                    }
                }
            }

            throw lastError ?? SDKError.llm(.extractionFailed, "Failed to parse structured output after 3 attempts")
        }

        return StructuredOutputStreamResult(
            tokenStream: tokenStream,
            result: resultTask
        )
    }

    // MARK: - Generation with Config

    /// Generate with structured output configuration
    /// - Parameters:
    ///   - prompt: The prompt to generate from
    ///   - structuredOutput: Structured output configuration
    ///   - options: Generation options
    ///   - llmCapability: The LLM capability to use for generation
    /// - Returns: Generation result with structured data
    public func generateWithStructuredOutput(
        prompt: String,
        structuredOutput: StructuredOutputConfig,
        options: LLMGenerationOptions?,
        llmCapability: LLMCapability
    ) async throws -> LLMGenerationResult {
        // Generate using regular generation with structured config in options
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

        return try await llmCapability.generate(
            prompt,
            options: internalOptions
        )
    }
}
