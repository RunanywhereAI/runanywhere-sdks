import Foundation

// MARK: - Structured Output Extensions (Event-Based)

public extension RunAnywhere {

    /// Generate structured output that conforms to a Generatable type with events
    /// - Parameters:
    ///   - type: The type to generate (must conform to Generatable)
    ///   - prompt: The prompt to generate from
    ///   - options: Generation options (structured output config will be added automatically)
    /// - Returns: The generated object of the specified type
    static func generateStructured<T: Generatable>(
        _ type: T.Type,
        prompt: String,
        options: GenerationOptions? = nil
    ) async throws -> T {
        await events.publish(SDKGenerationEvent.started(prompt: prompt))

        do {
            let internalOptions = options?.toInternalOptions()
            let result = try await RunAnywhereSDK.shared.generateStructured(
                type,
                prompt: prompt,
                options: internalOptions
            )

            await events.publish(SDKGenerationEvent.completed(
                response: "Structured output generated for \(String(describing: type))",
                tokensUsed: 0, // Would need to be tracked properly
                latencyMs: 0    // Would need to be tracked properly
            ))

            return result
        } catch {
            await events.publish(SDKGenerationEvent.failed(error))
            throw error
        }
    }

    /// Generate structured output with validation mode
    /// - Parameters:
    ///   - type: The type to generate
    ///   - prompt: The prompt to generate from
    ///   - validationMode: Schema validation mode
    ///   - options: Generation options
    /// - Returns: The generated object of the specified type
    static func generateStructured<T: Generatable>(
        _ type: T.Type,
        prompt: String,
        validationMode: SchemaValidationMode,
        options: GenerationOptions? = nil
    ) async throws -> T {
        await events.publish(SDKGenerationEvent.started(prompt: prompt))

        do {
            let internalOptions = options?.toInternalOptions()
            let result = try await RunAnywhereSDK.shared.generateStructured(
                type,
                prompt: prompt,
                validationMode: validationMode,
                options: internalOptions
            )

            await events.publish(SDKGenerationEvent.completed(
                response: "Structured output generated with validation mode: \(validationMode)",
                tokensUsed: 0,
                latencyMs: 0
            ))

            return result
        } catch {
            await events.publish(SDKGenerationEvent.failed(error))
            throw error
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
        structuredOutput: StructuredOutputConfig,
        options: GenerationOptions? = nil
    ) async throws -> GenerationResult {
        await events.publish(SDKGenerationEvent.started(prompt: prompt))

        do {
            let internalOptions = options?.toInternalOptions()
            let result = try await RunAnywhereSDK.shared.generateWithStructuredOutput(
                prompt: prompt,
                structuredOutput: structuredOutput,
                options: internalOptions
            )

            await events.publish(SDKGenerationEvent.completed(
                response: result.text,
                tokensUsed: result.tokensUsed,
                latencyMs: result.latencyMs
            ))

            if result.savedAmount > 0 {
                await events.publish(SDKGenerationEvent.costCalculated(
                    amount: 0,
                    savedAmount: result.savedAmount
                ))
            }

            return result
        } catch {
            await events.publish(SDKGenerationEvent.failed(error))
            throw error
        }
    }
}
