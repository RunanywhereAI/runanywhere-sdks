import CRACommons
import Foundation

// MARK: - Structured Output Generation Service

/// Service for generating structured output from LLMs.
/// Uses CapabilityManager directly to call C++ layer.
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
    /// - Returns: The generated object of the specified type
    public func generateStructured<T: Generatable>(
        _ type: T.Type,
        prompt: String,
        options: LLMGenerationOptions? = nil
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

        // Generate the text directly via CapabilityManager → C++
        let generationResult = try await generateViaCapabilityManager(userPrompt, options: effectiveOptions)

        // Parse using StructuredOutputHandler
        let result = try handler.parseStructuredOutput(
            from: generationResult.text,
            type: type
        )

        return result
    }

    /// Internal: Generate via CapabilityManager (calls C++ directly)
    private func generateViaCapabilityManager(_ prompt: String, options: LLMGenerationOptions) async throws -> LLMGenerationResult {
        let handle = try await CapabilityManager.shared.getLLMHandle()

        guard await CapabilityManager.shared.isLLMLoaded else {
            throw SDKError.llm(.notInitialized, "LLM model not loaded")
        }

        let modelId = await CapabilityManager.shared.currentLLMModelId ?? "unknown"
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

    // MARK: - Streaming Generation

    /// Generate structured output with streaming support
    /// - Parameters:
    ///   - type: The type to generate (must conform to Generatable)
    ///   - content: The content to generate from
    ///   - options: Generation options (optional)
    /// - Returns: A structured output stream containing tokens and final result
    public func generateStructuredStream<T: Generatable>(
        _ type: T.Type,
        content: String,
        options: LLMGenerationOptions? = nil
    ) -> StructuredOutputStreamResult<T> {
        // Internal stream generator that calls CapabilityManager directly
        let streamGenerator: (String, LLMGenerationOptions) async throws -> LLMStreamingResult = { prompt, opts in
            try await RunAnywhere.generateStream(prompt, options: opts)
        }
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
    /// - Returns: Generation result with structured data
    public func generateWithStructuredOutput(
        prompt: String,
        structuredOutput: StructuredOutputConfig,
        options: LLMGenerationOptions? = nil
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

        return try await generateViaCapabilityManager(prompt, options: internalOptions)
    }
}
