import Foundation

/// Main service for text generation
public class GenerationService {
    private let routingService: RoutingService
    private let modelLoadingService: ModelLoadingService
    private let optionsResolver = GenerationOptionsResolver()
    private let logger: SDKLogger = SDKLogger(category: "GenerationService")

    // Current loaded model
    private var currentLoadedModel: LoadedModel?

    public init(
        routingService: RoutingService,
        modelLoadingService: ModelLoadingService? = nil
    ) {
        self.routingService = routingService
        self.modelLoadingService = modelLoadingService ?? ServiceContainer.shared.modelLoadingService
    }

    /// Set the current loaded model for generation
    public func setCurrentModel(_ model: LoadedModel?) {
        self.currentLoadedModel = model
    }

    /// Get the current loaded model
    public func getCurrentModel() -> LoadedModel? {
        return currentLoadedModel
    }

    /// Generate text using the loaded model
    ///
    /// Priority for settings resolution:
    /// 1. Runtime Options (highest priority) - User knows best for their specific request
    /// 2. Remote Configuration - Organization-wide defaults from console
    /// 3. SDK Defaults (lowest priority) - Fallback values when nothing else is specified
    public func generate(
        prompt: String,
        options: RunAnywhereGenerationOptions
    ) async throws -> GenerationResult {
        // Start performance tracking
        _ = Date() // Will be used for performance metrics in future

        // Get remote configuration
        let remoteConfig = RunAnywhere.configurationData?.generation

        // Apply remote constraints to options (respecting priority: Runtime > Remote > SDK Defaults)
        let resolvedOptions = optionsResolver.resolve(
            options: options,
            remoteConfig: remoteConfig
        )

        // Prepare prompt with system prompt and structured output formatting
        let effectivePrompt = optionsResolver.preparePrompt(prompt, withOptions: resolvedOptions)

        // Get routing decision
        let routingDecision = try await routingService.determineRouting(
            prompt: effectivePrompt,
            context: nil,
            options: resolvedOptions
        )

        // Generate based on routing decision
        let result: GenerationResult

        switch routingDecision {
        case .onDevice(let framework, _):
            result = try await generateOnDevice(
                prompt: effectivePrompt,
                options: resolvedOptions,
                framework: framework
            )

        case .cloud(let provider, _):
            result = try await generateInCloud(
                prompt: effectivePrompt,
                options: resolvedOptions,
                provider: provider
            )

        case .hybrid(let devicePortion, let framework, _):
            result = try await generateHybrid(
                prompt: effectivePrompt,
                options: resolvedOptions,
                devicePortion: devicePortion,
                framework: framework
            )
        }

        // Validate structured output if configured
        if let structuredConfig = resolvedOptions.structuredOutput {
            let validation = StructuredOutputHandler().validateStructuredOutput(
                text: result.text,
                config: structuredConfig
            )

            // Add validation info to result metadata
            var updatedResult = result
            updatedResult.structuredOutputValidation = validation

            return updatedResult
        }

        return result
    }

    private func generateOnDevice(
        prompt: String,
        options: RunAnywhereGenerationOptions,
        framework: LLMFramework?
    ) async throws -> GenerationResult {
        logger.info("🚀 Starting on-device generation")
        let startTime = Date()

        // Use the current loaded model
        guard let loadedModel = currentLoadedModel else {
            logger.error("❌ No model is currently loaded")
            throw SDKError.modelNotFound("No model is currently loaded")
        }

        logger.info("✅ Using loaded model: \(loadedModel.model.name)")


        logger.debug("🚀 Calling service.generate() with graceful error handling")

        // Generate text using the actual loaded model's service with enhanced error handling
        let generatedText: String
        do {
            generatedText = try await loadedModel.service.generate(
                prompt: prompt,
                options: options
            )
            logger.info("✅ Got response from service: \(generatedText.prefix(100))...")
        } catch {
            logger.error("❌ Generation failed with error: \(error)")

            // Enhanced error handling - if it's a timeout or framework error, provide helpful fallback
            if let frameworkError = error as? FrameworkError {
                logger.warning("🔄 Framework error detected: \(frameworkError)")

                // For timeout errors, check the error message for timeout indicators
                let errorMessage = frameworkError.localizedDescription.lowercased()
                if errorMessage.contains("timeout") || errorMessage.contains("timed out") {
                    throw SDKError.generationTimeout("Text generation timed out. The model may be too large for this device or the prompt too complex. Try using a smaller model or simpler prompt.")
                }
            }

            // Re-throw the original error with additional context
            throw SDKError.generationFailed("On-device generation failed: \(error.localizedDescription)")
        }

        // Parse thinking content if model supports it
        let modelInfo = loadedModel.model
        let (finalText, thinkingContent): (String, String?)

        logger.debug("Model \(modelInfo.name) supports thinking: \(modelInfo.supportsThinking)")
        if modelInfo.supportsThinking {
            let pattern = ThinkingTagPattern.defaultPattern
            logger.debug("Using thinking pattern: \(pattern.openingTag)...\(pattern.closingTag)")
            logger.debug("Raw generated text: \(generatedText)")

            let parseResult = ThinkingParser.parse(text: generatedText, pattern: pattern)
            finalText = parseResult.content
            thinkingContent = parseResult.thinkingContent

            logger.debug("Parsed content: \(finalText)")
            logger.debug("Thinking content: \(thinkingContent ?? "None")")
        } else {
            finalText = generatedText
            thinkingContent = nil
        }

        // Calculate metrics based on final text (without thinking)
        let latency = Date().timeIntervalSince(startTime) * 1000 // Convert to milliseconds
        let estimatedTokens = finalText.split(separator: " ").count
        let tokensPerSecond = Double(estimatedTokens) / (latency / 1000.0)

        // Get memory usage (placeholder - actual implementation depends on service)
        let memoryUsage: Int64 = 0 // TODO: Add memory tracking to LLMService protocol

        return GenerationResult(
            text: finalText,
            thinkingContent: thinkingContent,
            tokensUsed: estimatedTokens,
            modelUsed: loadedModel.model.id,
            latencyMs: latency,
            executionTarget: .onDevice,
            savedAmount: 0.001, // Calculate based on cloud pricing
            performanceMetrics: PerformanceMetrics(
                inferenceTimeMs: latency,
                tokensPerSecond: tokensPerSecond,
                peakMemoryUsage: memoryUsage
            )
        )
    }

    private func generateInCloud(
        prompt: String,
        options: RunAnywhereGenerationOptions,
        provider: String?
    ) async throws -> GenerationResult {
        // Placeholder implementation
        return GenerationResult(
            text: "Generated text in cloud",
            tokensUsed: 10,
            modelUsed: "cloud-model",
            latencyMs: 50.0,
            executionTarget: .cloud,
            savedAmount: 0.001,
            performanceMetrics: PerformanceMetrics(
                inferenceTimeMs: 50.0,
                tokensPerSecond: 20.0
            )
        )
    }

    private func generateHybrid(
        prompt: String,
        options: RunAnywhereGenerationOptions,
        devicePortion: Double,
        framework: LLMFramework?
    ) async throws -> GenerationResult {
        // For hybrid approach, use on-device generation with partial processing
        // In a real implementation, this would split processing between device and cloud
        let startTime = Date()

        // Use the current loaded model
        guard let loadedModel = currentLoadedModel else {
            throw SDKError.modelNotFound("No model is currently loaded")
        }


        // For now, use on-device generation entirely
        // In a real implementation, this would coordinate between device and cloud
        let generatedText = try await loadedModel.service.generate(
            prompt: prompt,
            options: options
        )

        // Calculate metrics
        let latency = Date().timeIntervalSince(startTime) * 1000
        let estimatedTokens = generatedText.split(separator: " ").count
        let tokensPerSecond = Double(estimatedTokens) / (latency / 1000.0)

        // Get memory usage (placeholder - actual implementation depends on service)
        let memoryUsage: Int64 = 0 // TODO: Add memory tracking to LLMService protocol

        // Parse thinking content if model supports it
        let modelInfo = loadedModel.model
        let (finalText, thinkingContent): (String, String?)

        if modelInfo.supportsThinking {
            let pattern = ThinkingTagPattern.defaultPattern
            let parseResult = ThinkingParser.parse(text: generatedText, pattern: pattern)
            finalText = parseResult.content
            thinkingContent = parseResult.thinkingContent
        } else {
            finalText = generatedText
            thinkingContent = nil
        }

        return GenerationResult(
            text: finalText,
            thinkingContent: thinkingContent,
            tokensUsed: estimatedTokens,
            modelUsed: loadedModel.model.id,
            latencyMs: latency,
            executionTarget: .hybrid,
            savedAmount: 0.0005, // Hybrid saves less than full on-device
            performanceMetrics: PerformanceMetrics(
                inferenceTimeMs: latency,
                tokensPerSecond: tokensPerSecond,
                peakMemoryUsage: memoryUsage
            )
        )
    }
}
