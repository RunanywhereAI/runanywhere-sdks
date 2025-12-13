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
        events.publish(SDKGenerationEvent.started(prompt: prompt))

        do {
            let result = try await serviceContainer.structuredOutputService.generateStructured(
                type,
                prompt: prompt,
                options: options,
                generationService: serviceContainer.generationService
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
        options: LLMGenerationOptions? = nil
    ) -> StructuredOutputStreamResult<T> {
        return serviceContainer.structuredOutputService.generateStructuredStream(
            type,
            content: content,
            options: options,
            streamGenerator: { prompt, opts in
                serviceContainer.streamingService.generateStreamWithMetrics(
                    prompt: prompt,
                    options: opts
                )
            }
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
        options: LLMGenerationOptions? = nil
    ) async throws -> LLMGenerationResult {
        events.publish(SDKGenerationEvent.started(prompt: prompt))

        do {
            let result = try await serviceContainer.structuredOutputService.generateWithStructuredOutput(
                prompt: prompt,
                structuredOutput: structuredOutput,
                options: options,
                generationService: serviceContainer.generationService
            )

            events.publish(SDKGenerationEvent.completed(
                response: result.text,
                tokensUsed: result.tokensUsed,
                latencyMs: result.latencyMs
            ))

            return result
        } catch {
            events.publish(SDKGenerationEvent.failed(error))
            throw error
        }
    }
}
