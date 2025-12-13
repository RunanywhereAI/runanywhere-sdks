//
//  LLMGenerationService.swift
//  RunAnywhere SDK
//
//  Main service for text generation
//

import Foundation

/// Main service for text generation
public class LLMGenerationService {

    private let modelLoadingService: ModelLoadingService
    private let analyticsService: DevAnalyticsSubmissionService
    private let optionsResolver = LLMOptionsResolver()
    private let logger = SDKLogger(category: "LLMGenerationService")

    // Current loaded model
    private var currentLoadedModel: LoadedModel?

    public init(
        modelLoadingService: ModelLoadingService? = nil,
        analyticsService: DevAnalyticsSubmissionService? = nil
    ) {
        self.modelLoadingService = modelLoadingService ?? ServiceContainer.shared.modelLoadingService
        self.analyticsService = analyticsService ?? DevAnalyticsSubmissionService.shared
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
        options: LLMGenerationOptions
    ) async throws -> LLMGenerationResult {
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

        // Always use on-device generation
        let result = try await generateOnDevice(
            prompt: effectivePrompt,
            options: resolvedOptions,
            framework: nil
        )

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

    // swiftlint:disable:next function_body_length
    private func generateOnDevice(
        prompt: String,
        options: LLMGenerationOptions,
        framework: LLMFramework?
    ) async throws -> LLMGenerationResult {
        logger.info("🚀 Starting on-device generation")
        let startTime = Date()

        // Use the current loaded model
        guard let loadedModel = currentLoadedModel else {
            logger.error("❌ No model is currently loaded")
            throw RunAnywhereError.modelNotFound("No model is currently loaded")
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

            // Submit analytics for failed generation (non-blocking, silent failures)
            let latency = Date().timeIntervalSince(startTime) * 1000
            let inputTokens = TokenCounter.estimateTokenCount(prompt)
            let analyticsService = self.analyticsService
            Task.detached(priority: .background) {
                await analyticsService.submitInternal(
                    generationId: UUID().uuidString,
                    modelId: loadedModel.model.id,
                    latencyMs: latency,
                    tokensPerSecond: 0,
                    inputTokens: inputTokens,
                    outputTokens: 0,
                    success: false
                )
            }

            // Enhanced error handling - if it's a timeout or framework error, provide helpful fallback
            if let frameworkError = error as? FrameworkError {
                logger.warning("🔄 Framework error detected: \(frameworkError)")

                // For timeout errors, check the error message for timeout indicators
                let errorMessage = frameworkError.localizedDescription.lowercased()
                if errorMessage.contains("timeout") || errorMessage.contains("timed out") {
                    let message = "Text generation timed out. The model may be too large for this device or " +
                        "the prompt too complex. Try using a smaller model or simpler prompt."
                    throw RunAnywhereError.generationTimeout(message)
                }
            }

            // Re-throw the original error with additional context
            throw RunAnywhereError.generationFailed("On-device generation failed: \(error.localizedDescription)")
        }

        // Parse thinking content if model supports it
        let modelInfo = loadedModel.model
        let (finalText, thinkingContent): (String, String?)
        var thinkingTimeMs: TimeInterval?

        logger.debug("Model \(modelInfo.name) supports thinking: \(modelInfo.supportsThinking)")
        if modelInfo.supportsThinking {
            // Use model-specific pattern or fall back to default
            let pattern = modelInfo.thinkingPattern ?? ThinkingTagPattern.defaultPattern
            logger.debug("Using thinking pattern: \(pattern.openingTag)...\(pattern.closingTag)")
            logger.debug("Raw generated text length: \(generatedText.count) chars")

            let parseResult = ThinkingParser.parse(text: generatedText, pattern: pattern)
            finalText = parseResult.content
            thinkingContent = parseResult.thinkingContent

            logger.debug("Parsed content length: \(finalText.count) chars")
            if let thinking = thinkingContent {
                logger.debug("Thinking content length: \(thinking.count) chars")
            }

            // For non-streaming, we can estimate thinking took ~60% of generation time if present
            if let thinking = thinkingContent, !thinking.isEmpty {
                let totalLatency = Date().timeIntervalSince(startTime) * 1000
                thinkingTimeMs = totalLatency * 0.6
            }
        } else {
            finalText = generatedText
            thinkingContent = nil
        }

        // Calculate metrics using improved token counting
        let latency = Date().timeIntervalSince(startTime) * 1000 // Convert to milliseconds
        let tokenCounts = TokenCounter.splitTokenCounts(
            fullText: generatedText,
            thinkingContent: thinkingContent,
            responseContent: finalText
        )

        let tokensPerSecond = TokenCounter.calculateTokensPerSecond(
            tokenCount: tokenCounts.totalTokens,
            elapsedSeconds: latency / 1000.0
        )

        let result = LLMGenerationResult(
            text: finalText,
            thinkingContent: thinkingContent,
            tokensUsed: tokenCounts.totalTokens,
            modelUsed: loadedModel.model.id,
            latencyMs: latency,
            framework: loadedModel.model.compatibleFrameworks.first,
            tokensPerSecond: tokensPerSecond,
            thinkingTokens: tokenCounts.thinkingTokens,
            responseTokens: tokenCounts.responseTokens
        )

        // Submit analytics (non-blocking, silent failures)
        let inputTokenCount = TokenCounter.estimateTokenCount(prompt)
        let analyticsService = self.analyticsService
        Task.detached(priority: .background) {
            await analyticsService.submitInternal(
                generationId: UUID().uuidString,
                modelId: result.modelUsed,
                latencyMs: result.latencyMs,
                tokensPerSecond: result.tokensPerSecond,
                inputTokens: inputTokenCount,
                outputTokens: result.tokensUsed,
                success: true
            )
        }

        return result
    }
}
