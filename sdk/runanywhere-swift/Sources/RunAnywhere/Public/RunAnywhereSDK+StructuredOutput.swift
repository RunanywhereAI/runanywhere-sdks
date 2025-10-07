import Foundation

// MARK: - Structured Output API

extension RunAnywhereSDK {

    private var structuredOutputLogger: SDKLogger {
        SDKLogger(category: "RunAnywhereSDK.StructuredOutput")
    }

    private var structuredOutputHandler: StructuredOutputHandler {
        StructuredOutputHandler()
    }

    /// Generate structured output that conforms to a Generatable type
    /// - Parameters:
    ///   - type: The type to generate (must conform to Generatable)
    ///   - prompt: The prompt to generate from
    ///   - options: Generation options (structured output config will be added automatically)
    /// - Returns: The generated object of the specified type
    public func generateStructured<T: Generatable>(
        _ type: T.Type,
        prompt: String,
        options: RunAnywhereGenerationOptions? = nil
    ) async throws -> T {
        // Create structured output config
        let structuredConfig = StructuredOutputConfig(
            type: type,
            validationMode: .strict,
            strategy: .automatic,
            includeSchemaInPrompt: true
        )

        // Get system prompt for structured output
        let structuredSystemPrompt = structuredOutputHandler.getSystemPrompt(for: type)

        // Create options with structured output and system prompt
        var effectiveOptions: RunAnywhereGenerationOptions
        if let options = options {
            // Merge with existing options
            effectiveOptions = RunAnywhereGenerationOptions(
                maxTokens: options.maxTokens,
                temperature: options.temperature,
                topP: options.topP,
enableRealTimeTracking: options.enableRealTimeTracking,
                stopSequences: options.stopSequences,
                seed: options.seed,
                streamingEnabled: options.streamingEnabled,
                tokenBudget: options.tokenBudget,
                frameworkOptions: options.frameworkOptions,
                preferredExecutionTarget: options.preferredExecutionTarget,
                structuredOutput: structuredConfig,
                systemPrompt: structuredSystemPrompt
            )
        } else {
            // Use defaults with structured output and system prompt
            effectiveOptions = RunAnywhereGenerationOptions(
                structuredOutput: structuredConfig,
                systemPrompt: structuredSystemPrompt
            )
        }

        // Generate with structured output - with retry logic
        let handler = StructuredOutputHandler()
        var lastError: Error?

        // Try up to 3 times with increasingly strict prompts
        for attempt in 1...3 {
            let result = try await generate(prompt: prompt, options: effectiveOptions)

            do {
                return try handler.parseStructuredOutput(
                    from: result.text,
                    type: type,
                    validationMode: structuredConfig.validationMode
                )
            } catch {
                lastError = error
                structuredOutputLogger.warning("Structured output parsing failed on attempt \(attempt): \(error)")

                // If this isn't the last attempt, retry with the same prompt
                // The handler already adds strong JSON instructions
                if attempt < 3 {
                    // Update options with lower temperature for next attempt
                    effectiveOptions = RunAnywhereGenerationOptions(
                        maxTokens: effectiveOptions.maxTokens,
                        temperature: Float(max(0.1, Double(effectiveOptions.temperature) - 0.2)), // Lower temperature for more deterministic output
                        topP: effectiveOptions.topP,
                        enableRealTimeTracking: effectiveOptions.enableRealTimeTracking,
                        stopSequences: effectiveOptions.stopSequences,
                        seed: effectiveOptions.seed,
                        streamingEnabled: effectiveOptions.streamingEnabled,
                        tokenBudget: effectiveOptions.tokenBudget,
                        frameworkOptions: effectiveOptions.frameworkOptions,
                        preferredExecutionTarget: effectiveOptions.preferredExecutionTarget,
                        structuredOutput: structuredConfig
                    )
                }
            }
        }

        // If all attempts failed, throw the last error
        throw lastError ?? StructuredOutputError.extractionFailed("Failed to generate valid structured output after 3 attempts")
    }

    /// Generate structured output with custom validation mode
    /// - Parameters:
    ///   - type: The type to generate (must conform to Generatable)
    ///   - prompt: The prompt to generate from
    ///   - validationMode: How strictly to validate the output
    ///   - options: Generation options
    /// - Returns: The generated object of the specified type
    public func generateStructured<T: Generatable>(
        _ type: T.Type,
        prompt: String,
        validationMode: SchemaValidationMode,
        options: RunAnywhereGenerationOptions? = nil
    ) async throws -> T {
        // Create structured output config with custom validation
        let structuredConfig = StructuredOutputConfig(
            type: type,
            validationMode: validationMode,
            strategy: .automatic,
            includeSchemaInPrompt: true
        )

        // Get system prompt for structured output
        let structuredSystemPrompt = structuredOutputHandler.getSystemPrompt(for: type)

        // Create options with structured output and system prompt
        var effectiveOptions: RunAnywhereGenerationOptions
        if let options = options {
            effectiveOptions = RunAnywhereGenerationOptions(
                maxTokens: options.maxTokens,
                temperature: options.temperature,
                topP: options.topP,
enableRealTimeTracking: options.enableRealTimeTracking,
                stopSequences: options.stopSequences,
                seed: options.seed,
                streamingEnabled: options.streamingEnabled,
                tokenBudget: options.tokenBudget,
                frameworkOptions: options.frameworkOptions,
                preferredExecutionTarget: options.preferredExecutionTarget,
                structuredOutput: structuredConfig,
                systemPrompt: structuredSystemPrompt
            )
        } else {
            effectiveOptions = RunAnywhereGenerationOptions(
                structuredOutput: structuredConfig,
                systemPrompt: structuredSystemPrompt
            )
        }

        // Generate with structured output - with retry logic
        let handler = StructuredOutputHandler()
        var lastError: Error?

        // Try up to 3 times with increasingly strict prompts
        for attempt in 1...3 {
            let result = try await generate(prompt: prompt, options: effectiveOptions)

            do {
                return try handler.parseStructuredOutput(
                    from: result.text,
                    type: type,
                    validationMode: validationMode
                )
            } catch {
                lastError = error
                structuredOutputLogger.warning("Structured output parsing failed on attempt \(attempt): \(error)")

                // If this isn't the last attempt, retry with lower temperature
                if attempt < 3 {
                    // Update options with lower temperature for next attempt
                    effectiveOptions = RunAnywhereGenerationOptions(
                        maxTokens: effectiveOptions.maxTokens,
                        temperature: Float(max(0.1, Double(effectiveOptions.temperature) - 0.2)), // Lower temperature for more deterministic output
                        topP: effectiveOptions.topP,
                        enableRealTimeTracking: effectiveOptions.enableRealTimeTracking,
                        stopSequences: effectiveOptions.stopSequences,
                        seed: effectiveOptions.seed,
                        streamingEnabled: effectiveOptions.streamingEnabled,
                        tokenBudget: effectiveOptions.tokenBudget,
                        frameworkOptions: effectiveOptions.frameworkOptions,
                        preferredExecutionTarget: effectiveOptions.preferredExecutionTarget,
                        structuredOutput: structuredConfig
                    )
                }
            }
        }

        // If all attempts failed, throw the last error
        throw lastError ?? StructuredOutputError.extractionFailed("Failed to generate valid structured output after 3 attempts")
    }

    /// Generate raw text with structured output validation
    /// This method returns the raw GenerationResult with validation info
    /// - Parameters:
    ///   - prompt: The prompt to generate from
    ///   - structuredOutput: Structured output configuration
    ///   - options: Generation options
    /// - Returns: Generation result with structured output validation
    public func generateWithStructuredOutput(
        prompt: String,
        structuredOutput: StructuredOutputConfig,
        options: RunAnywhereGenerationOptions? = nil
    ) async throws -> GenerationResult {
        // Create options with structured output
        let effectiveOptions: RunAnywhereGenerationOptions
        if let options = options {
            effectiveOptions = RunAnywhereGenerationOptions(
                maxTokens: options.maxTokens,
                temperature: options.temperature,
                topP: options.topP,
enableRealTimeTracking: options.enableRealTimeTracking,
                stopSequences: options.stopSequences,
                seed: options.seed,
                streamingEnabled: options.streamingEnabled,
                tokenBudget: options.tokenBudget,
                frameworkOptions: options.frameworkOptions,
                preferredExecutionTarget: options.preferredExecutionTarget,
                structuredOutput: structuredOutput
            )
        } else {
            effectiveOptions = RunAnywhereGenerationOptions(structuredOutput: structuredOutput)
        }

        return try await generate(prompt: prompt, options: effectiveOptions)
    }
}
