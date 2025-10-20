import Foundation

// MARK: - Streaming Structured Output Types

/// Token emitted during streaming
public struct StreamToken {
    public let text: String
    public let timestamp: Date
    public let tokenIndex: Int

    public init(text: String, timestamp: Date = Date(), tokenIndex: Int) {
        self.text = text
        self.timestamp = timestamp
        self.tokenIndex = tokenIndex
    }
}

/// Result containing both the token stream and final parsed result
public struct StructuredOutputStreamResult<T: Generatable> {
    /// Stream of tokens as they're generated
    public let tokenStream: AsyncThrowingStream<StreamToken, Error>

    /// Final parsed result (available after stream completes)
    public let result: Task<T, Error>
}

// MARK: - Stream Accumulator

/// Accumulates tokens during streaming for later parsing
actor StreamAccumulator {
    private var text = ""
    private var isComplete = false
    private var completionContinuation: CheckedContinuation<Void, Never>?

    func append(_ token: String) {
        text += token
    }

    var fullText: String {
        return text
    }

    func markComplete() {
        guard !isComplete else { return }
        isComplete = true
        completionContinuation?.resume()
        completionContinuation = nil
    }

    func waitForCompletion() async {
        guard !isComplete else { return }

        await withCheckedContinuation { continuation in
            if isComplete {
                continuation.resume()
            } else {
                completionContinuation = continuation
            }
        }
    }
}

// MARK: - Generation Hints

public struct GenerationHints {
    public let temperature: Float?
    public let maxTokens: Int?
    public let systemRole: String?

    public init(temperature: Float? = nil, maxTokens: Int? = nil, systemRole: String? = nil) {
        self.temperature = temperature
        self.maxTokens = maxTokens
        self.systemRole = systemRole
    }
}

// MARK: - Generatable Protocol Extensions

extension Generatable {
    /// Type-specific generation hints
    public static var generationHints: GenerationHints? {
        return nil
    }
}

// MARK: - Structured Output Extensions (Event-Based)

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
        options: RunAnywhereGenerationOptions? = nil
    ) async throws -> T {
        events.publish(SDKGenerationEvent.started(prompt: prompt))

        do {
            // Create structured output handler
            let handler = StructuredOutputHandler()

            // Get system prompt for structured output
            let systemPrompt = handler.getSystemPrompt(for: type)

            // Create effective options with system prompt
            let effectiveOptions = RunAnywhereGenerationOptions(
                maxTokens: options?.maxTokens ?? type.generationHints?.maxTokens ?? 1500,
                temperature: options?.temperature ?? type.generationHints?.temperature ?? 0.7,
                topP: options?.topP ?? 1.0,
                enableRealTimeTracking: options?.enableRealTimeTracking ?? true,
                stopSequences: options?.stopSequences ?? [],
                streamingEnabled: false,
                preferredExecutionTarget: options?.preferredExecutionTarget,
                preferredFramework: options?.preferredFramework,
                structuredOutput: StructuredOutputConfig(
                    type: type,
                    includeSchemaInPrompt: false
                ),
                systemPrompt: systemPrompt
            )

            // Build user prompt
            let userPrompt = handler.buildUserPrompt(for: type, content: prompt)

            // Generate the text
            let generationResult = try await RunAnywhere.generate(userPrompt, options: effectiveOptions)

            // Parse using StructuredOutputHandler
            let result = try handler.parseStructuredOutput(
                from: generationResult.text,
                type: type
            )

            events.publish(SDKGenerationEvent.completed(
                response: "Structured output generated for \(String(describing: type))",
                tokensUsed: 0,
                latencyMs: 0
            ))

            return result
        } catch {
            events.publish(SDKGenerationEvent.failed(error))
            throw error
        }
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
        options: RunAnywhereGenerationOptions? = nil
    ) -> StructuredOutputStreamResult<T> {
        // Create a shared accumulator
        let accumulator = StreamAccumulator()

        // Create structured output handler
        let handler = StructuredOutputHandler()

        // Get system prompt for structured output
        let systemPrompt = handler.getSystemPrompt(for: type)

        // Create effective options with system prompt
        let effectiveOptions = RunAnywhereGenerationOptions(
            maxTokens: options?.maxTokens ?? type.generationHints?.maxTokens ?? 1500,
            temperature: options?.temperature ?? type.generationHints?.temperature ?? 0.7,
            topP: options?.topP ?? 1.0,
            enableRealTimeTracking: options?.enableRealTimeTracking ?? true,
            stopSequences: options?.stopSequences ?? [],
            streamingEnabled: true,
            preferredExecutionTarget: options?.preferredExecutionTarget,
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
                    let streamingResult = try await RunAnywhere.generateStream(userPrompt, options: effectiveOptions)
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

            throw lastError ?? StructuredOutputError.extractionFailed("Failed to parse structured output after 3 attempts")
        }

        return StructuredOutputStreamResult(
            tokenStream: tokenStream,
            result: resultTask
        )
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
        options: RunAnywhereGenerationOptions? = nil
    ) async throws -> GenerationResult {
        events.publish(SDKGenerationEvent.started(prompt: prompt))

        do {
            // Generate using regular generation with structured config in options
            let baseOptions = options ?? RunAnywhereGenerationOptions()
            let internalOptions = RunAnywhereGenerationOptions(
                maxTokens: baseOptions.maxTokens,
                temperature: baseOptions.temperature,
                topP: baseOptions.topP,
                enableRealTimeTracking: baseOptions.enableRealTimeTracking,
                stopSequences: baseOptions.stopSequences,
                streamingEnabled: baseOptions.streamingEnabled,
                preferredExecutionTarget: baseOptions.preferredExecutionTarget,
                preferredFramework: baseOptions.preferredFramework,
                structuredOutput: structuredOutput,
                systemPrompt: baseOptions.systemPrompt
            )

            let result = try await RunAnywhere.serviceContainer.generationService.generate(
                prompt: prompt,
                options: internalOptions
            )

            events.publish(SDKGenerationEvent.completed(
                response: result.text,
                tokensUsed: result.tokensUsed,
                latencyMs: result.latencyMs
            ))

            if result.savedAmount > 0 {
                events.publish(SDKGenerationEvent.costCalculated(
                    amount: 0,
                    savedAmount: result.savedAmount
                ))
            }

            return result
        } catch {
            events.publish(SDKGenerationEvent.failed(error))
            throw error
        }
    }
}
