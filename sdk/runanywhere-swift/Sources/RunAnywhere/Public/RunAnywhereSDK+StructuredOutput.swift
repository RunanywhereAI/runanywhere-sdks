import Foundation

// MARK: - Structured Output API

extension RunAnywhereSDK {

    /// Generate structured output that conforms to a Generatable type
    /// - Parameters:
    ///   - type: The type to generate (must conform to Generatable)
    ///   - prompt: The prompt to generate from
    ///   - options: Generation options (structured output config will be added automatically)
    /// - Returns: The generated object of the specified type
    public func generateStructured<T: Generatable>(
        _ type: T.Type,
        prompt: String,
        options: GenerationOptions? = nil
    ) async throws -> T {
        // Create structured output config
        let structuredConfig = StructuredOutputConfig(
            type: type,
            validationMode: .strict,
            strategy: .automatic,
            includeSchemaInPrompt: true
        )

        // Create options with structured output
        let effectiveOptions: GenerationOptions
        if let options = options {
            // Merge with existing options
            effectiveOptions = GenerationOptions(
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
                structuredOutput: structuredConfig
            )
        } else {
            // Use defaults with structured output
            effectiveOptions = GenerationOptions(structuredOutput: structuredConfig)
        }

        // Generate with structured output
        let result = try await generate(prompt: prompt, options: effectiveOptions)

        // Parse the structured output
        let handler = StructuredOutputHandler()
        return try handler.parseStructuredOutput(
            from: result.text,
            type: type,
            validationMode: structuredConfig.validationMode
        )
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
        options: GenerationOptions? = nil
    ) async throws -> T {
        // Create structured output config with custom validation
        let structuredConfig = StructuredOutputConfig(
            type: type,
            validationMode: validationMode,
            strategy: .automatic,
            includeSchemaInPrompt: true
        )

        // Create options with structured output
        let effectiveOptions: GenerationOptions
        if let options = options {
            effectiveOptions = GenerationOptions(
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
                structuredOutput: structuredConfig
            )
        } else {
            effectiveOptions = GenerationOptions(structuredOutput: structuredConfig)
        }

        // Generate with structured output
        let result = try await generate(prompt: prompt, options: effectiveOptions)

        // Parse the structured output
        let handler = StructuredOutputHandler()
        return try handler.parseStructuredOutput(
            from: result.text,
            type: type,
            validationMode: validationMode
        )
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
        options: GenerationOptions? = nil
    ) async throws -> GenerationResult {
        // Create options with structured output
        let effectiveOptions: GenerationOptions
        if let options = options {
            effectiveOptions = GenerationOptions(
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
            effectiveOptions = GenerationOptions(structuredOutput: structuredOutput)
        }

        return try await generate(prompt: prompt, options: effectiveOptions)
    }
}
