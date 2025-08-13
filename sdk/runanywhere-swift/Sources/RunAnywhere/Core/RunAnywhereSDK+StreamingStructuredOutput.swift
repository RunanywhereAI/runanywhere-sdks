//
//  RunAnywhereSDK+StreamingStructuredOutput.swift
//  RunAnywhere
//
//  Streaming structured output generation with real-time token display
//

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

// MARK: - SDK Extension

public extension RunAnywhereSDK {
    /// Generate structured output with streaming support
    /// - Parameters:
    ///   - type: The type to generate (must conform to Generatable)
    ///   - content: The content to generate from (e.g., educational content for quiz)
    ///   - options: Generation options (optional)
    /// - Returns: A structured output stream containing tokens and final result
    func generateStructuredStream<T: Generatable>(
        _ type: T.Type,
        content: String,
        options: GenerationOptions? = nil
    ) -> StructuredOutputStreamResult<T> {
        // Create a shared accumulator
        let accumulator = StreamAccumulator()

        // Create structured output handler
        let handler = StructuredOutputHandler()

        // Get system prompt for structured output
        let systemPrompt = handler.getSystemPrompt(for: type)

        // Create effective options with system prompt
        let effectiveOptions = GenerationOptions(
            maxTokens: options?.maxTokens ?? type.generationHints?.maxTokens ?? 1500,
            temperature: options?.temperature ?? type.generationHints?.temperature ?? 0.7,
            topP: options?.topP ?? 1.0,
            enableRealTimeTracking: options?.enableRealTimeTracking ?? true,
            stopSequences: options?.stopSequences ?? [],
            seed: options?.seed,
            streamingEnabled: true,
            tokenBudget: options?.tokenBudget,
            frameworkOptions: options?.frameworkOptions,
            preferredExecutionTarget: options?.preferredExecutionTarget,
            structuredOutput: StructuredOutputConfig(
                type: type,
                validationMode: .lenient,
                strategy: .automatic,
                includeSchemaInPrompt: false  // Schema is in system prompt
            ),
            systemPrompt: systemPrompt
        )

        // Build user prompt (without formatting instructions since they're in system prompt)
        let userPrompt = handler.buildUserPrompt(
            for: type,
            content: content
        )

        // Create token stream
        let tokenStream = AsyncThrowingStream<StreamToken, Error> { continuation in
            Task {
                do {
                    var tokenIndex = 0

                    // Stream tokens
                    for try await token in self.generateStream(prompt: userPrompt, options: effectiveOptions) {
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

            // Log the full response for debugging
            logger.info("[RunAnywhereSDK] Full response length: \(fullResponse.count) characters")
            logger.debug("[RunAnywhereSDK] Full response content: \(fullResponse)")

            // Parse using StructuredOutputHandler with retry logic
            var lastError: Error?

            for attempt in 1...3 {
                do {
                    return try handler.parseStructuredOutput(
                        from: fullResponse,
                        type: type,
                        validationMode: SchemaValidationMode.lenient
                    )
                } catch {
                    lastError = error
                    logger.error("[RunAnywhereSDK] Structured output parsing failed on attempt \(attempt): \(error)")
                    if attempt < 3 {
                        // Log more details for debugging
                        logger.debug("[RunAnywhereSDK] Response being parsed: \(fullResponse.prefix(500))...")
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
}

// MARK: - Generatable Protocol Extensions

extension Generatable {
    /// Type-specific generation hints
    public static var generationHints: GenerationHints? {
        return nil
    }
}

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
