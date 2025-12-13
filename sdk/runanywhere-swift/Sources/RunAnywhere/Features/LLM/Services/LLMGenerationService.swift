//
//  LLMGenerationService.swift
//  RunAnywhere SDK
//
//  Main service for text generation
//

import Foundation

/// Main service for text generation
/// Simplified architecture: direct generation without unnecessary wrappers
public class LLMGenerationService {

    private let modelLoadingService: ModelLoadingService
    private let analyticsService: DevAnalyticsSubmissionService
    private let optionsResolver = LLMOptionsResolver()
    private let logger = SDKLogger(category: "LLMGenerationService")

    // Track the current model ID for generation
    private var currentModelId: String?

    public init(
        modelLoadingService: ModelLoadingService? = nil,
        analyticsService: DevAnalyticsSubmissionService? = nil
    ) {
        self.modelLoadingService = modelLoadingService ?? ServiceContainer.shared.modelLoadingService
        self.analyticsService = analyticsService ?? DevAnalyticsSubmissionService.shared
    }

    /// Set the current model ID for generation
    public func setCurrentModel(_ modelId: String?) {
        self.currentModelId = modelId
    }

    /// Set the current model for generation (compatibility overload)
    public func setCurrentModel(_ model: LoadedModel?) {
        self.currentModelId = model?.model.id
    }

    /// Get the current loaded model from ModelLoadingService
    public func getCurrentModel() async -> LoadedModel? {
        guard let modelId = currentModelId else {
            return nil
        }
        return await modelLoadingService.getLoadedModel(modelId)
    }

    // swiftlint:disable:next function_body_length
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
        let startTime = Date()

        // Get remote configuration and resolve options
        let remoteConfig = RunAnywhere.configurationData?.generation
        let resolvedOptions = optionsResolver.resolve(options: options, remoteConfig: remoteConfig)
        let effectivePrompt = optionsResolver.preparePrompt(prompt, withOptions: resolvedOptions)

        // Verify model is loaded - query ModelLoadingService
        guard let loadedModel = await getCurrentModel() else {
            logger.error("❌ No model is currently loaded")
            throw RunAnywhereError.modelNotFound("No model is currently loaded")
        }

        logger.info("🚀 Generating with model: \(loadedModel.model.name)")

        // Generate text with error handling
        let generatedText: String
        do {
            generatedText = try await loadedModel.service.generate(
                prompt: effectivePrompt,
                options: resolvedOptions
            )
            logger.info("✅ Got response: \(generatedText.prefix(100))...")
        } catch {
            logger.error("❌ Generation failed: \(error)")

            // Submit failure analytics (non-blocking)
            submitAnalytics(
                modelId: loadedModel.model.id,
                startTime: startTime,
                prompt: effectivePrompt,
                outputTokens: 0,
                success: false
            )

            // Convert framework errors to user-friendly messages
            if let frameworkError = error as? FrameworkError {
                let errorMessage = frameworkError.localizedDescription.lowercased()
                if errorMessage.contains("timeout") || errorMessage.contains("timed out") {
                    throw RunAnywhereError.generationTimeout(
                        "Text generation timed out. Try a smaller model or simpler prompt."
                    )
                }
            }

            throw RunAnywhereError.generationFailed("Generation failed: \(error.localizedDescription)")
        }

        // Parse thinking content if model supports it
        let modelInfo = loadedModel.model
        let (finalText, thinkingContent) = parseThinkingContent(
            generatedText: generatedText,
            modelInfo: modelInfo
        )

        // Calculate metrics
        let latency = Date().timeIntervalSince(startTime) * 1000
        let tokenCounts = TokenCounter.splitTokenCounts(
            fullText: generatedText,
            thinkingContent: thinkingContent,
            responseContent: finalText
        )
        let tokensPerSecond = TokenCounter.calculateTokensPerSecond(
            tokenCount: tokenCounts.totalTokens,
            elapsedSeconds: latency / 1000.0
        )

        var result = LLMGenerationResult(
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

        // Validate structured output if configured
        if let structuredConfig = resolvedOptions.structuredOutput {
            result.structuredOutputValidation = StructuredOutputHandler().validateStructuredOutput(
                text: result.text,
                config: structuredConfig
            )
        }

        // Submit success analytics (non-blocking)
        submitAnalytics(
            modelId: result.modelUsed,
            startTime: startTime,
            prompt: effectivePrompt,
            outputTokens: result.tokensUsed,
            success: true,
            tokensPerSecond: result.tokensPerSecond
        )

        return result
    }

    // MARK: - Private Helpers

    /// Parse thinking content from generated text if model supports it
    private func parseThinkingContent(
        generatedText: String,
        modelInfo: ModelInfo
    ) -> (finalText: String, thinkingContent: String?) {
        guard modelInfo.supportsThinking else {
            return (generatedText, nil)
        }

        let pattern = modelInfo.thinkingPattern ?? ThinkingTagPattern.defaultPattern
        logger.debug("Parsing thinking with pattern: \(pattern.openingTag)...\(pattern.closingTag)")

        let parseResult = ThinkingParser.parse(text: generatedText, pattern: pattern)
        return (parseResult.content, parseResult.thinkingContent)
    }

    /// Submit analytics in background (non-blocking)
    private func submitAnalytics(
        modelId: String,
        startTime: Date,
        prompt: String,
        outputTokens: Int,
        success: Bool,
        tokensPerSecond: Double = 0
    ) {
        let latency = Date().timeIntervalSince(startTime) * 1000
        let inputTokens = TokenCounter.estimateTokenCount(prompt)
        let analyticsService = self.analyticsService

        Task.detached(priority: .background) {
            await analyticsService.submitInternal(
                generationId: UUID().uuidString,
                modelId: modelId,
                latencyMs: latency,
                tokensPerSecond: tokensPerSecond,
                inputTokens: inputTokens,
                outputTokens: outputTokens,
                success: success
            )
        }
    }
}
