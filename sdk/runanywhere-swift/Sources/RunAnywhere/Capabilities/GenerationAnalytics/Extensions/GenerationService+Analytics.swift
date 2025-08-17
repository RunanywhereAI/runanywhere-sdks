import Foundation

/// Extension to add analytics support to GenerationService
extension GenerationService {

    /// Generate text with analytics tracking
    public func generateWithAnalytics(
        prompt: String,
        options: RunAnywhereGenerationOptions,
        sessionId: UUID? = nil,
        analytics: GenerationAnalyticsService? = nil
    ) async throws -> GenerationResult {
        // Get analytics service from container if not provided
        let analyticsService: GenerationAnalyticsService
        if let providedAnalytics = analytics {
            analyticsService = providedAnalytics
        } else {
            analyticsService = await ServiceContainer.shared.generationAnalytics
        }

        // Start or get session
        let activeSessionId: UUID
        if let providedSessionId = sessionId {
            activeSessionId = providedSessionId
        } else {
            // Get current model ID for session
            let modelId = getCurrentModel()?.model.id ?? "unknown"
            let session = await analyticsService.startSession(
                modelId: modelId,
                type: .singleGeneration
            )
            activeSessionId = session.id
        }

        // Start generation tracking
        let generation = await analyticsService.startGeneration(sessionId: activeSessionId)
        guard let tracker = await analyticsService.getTracker(for: generation.id) else {
            // Fallback to regular generation if tracker creation failed
            return try await generate(prompt: prompt, options: options)
        }

        // Use the base generate method to handle routing and context
        // This avoids accessing private properties
        let routingDecision: RoutingDecision = .onDevice(
            framework: nil,
            reason: .lowComplexity
        )

        // Start performance tracking
        let startTime = Date()
        var hasRecordedFirstToken = false

        // Use the base generate method and track tokens based on the result
        let result = try await generate(prompt: prompt, options: options)

        // Track tokens based on the execution target
        switch result.executionTarget {
        case .onDevice:
            // For on-device, we can estimate token generation over time
            let tokensGenerated = result.tokensUsed
            if tokensGenerated > 0 {
                await tracker.recordFirstToken()
                await tracker.recordTokens(tokensGenerated)
            }

        case .cloud, .hybrid:
            // For cloud/hybrid, record all tokens at once
            await tracker.recordTokens(result.tokensUsed)
        }

        // Create analytics-compatible result
        guard let model = getCurrentModel() else {
            throw SDKError.modelNotFound("Model not available for analytics")
        }

        // Create analytics metrics from SDK result
        let metrics = GenerationMetrics(
            inputTokens: result.tokensUsed / 2, // Approximate input tokens
            outputTokens: result.tokensUsed / 2, // Approximate output tokens
            tokensPerSecond: result.performanceMetrics.tokensPerSecond,
            totalTime: result.latencyMs / 1000.0
        )

        let cost = GenerationCost(
            estimated: result.savedAmount,
            actual: 0.0, // On-device has no actual cost
            saved: result.savedAmount
        )

        // Create analytics result structure
        let analyticsResult = AnalyticsGenerationResult(
            text: result.text,
            model: model,
            executionTarget: result.executionTarget,
            metrics: metrics,
            cost: cost
        )

        // Complete tracking with performance metrics
        let performance = await tracker.complete(
            result: analyticsResult,
            routingDecision: routingDecision
        )

        await analyticsService.completeGeneration(generation.id, performance: performance)

        // If this was a single generation session, end it
        if sessionId == nil {
            await analyticsService.endSession(activeSessionId)
        }

        return result
    }

    // MARK: - Private Helper Methods

    private func calculateSavedCost(for text: String) -> Double {
        // Simple calculation: assume cloud would cost $0.01 per 1000 tokens
        let tokens = Double(text.count / 4)
        return (tokens / 1000.0) * 0.01
    }
}
