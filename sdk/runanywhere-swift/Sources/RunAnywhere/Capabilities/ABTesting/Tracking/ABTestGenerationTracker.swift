//
//  ABTestGenerationTracker.swift
//  RunAnywhere SDK
//
//  Tracks generation metrics for A/B tests
//

import Foundation

/// Tracks generation performance for A/B testing
public class ABTestGenerationTracker {
    // MARK: - Properties

    private let performanceMonitor = RealtimePerformanceMonitor.shared
    private let abTestService: ABTestService
    private let logger = SDKLogger(category: "GenerationTracker")

    // MARK: - Initialization

    public init(abTestService: ABTestService) {
        self.abTestService = abTestService
    }

    // MARK: - Public Methods

    /// Track generation for A/B testing
    public func trackGeneration(
        testId: UUID,
        variantId: UUID,
        framework: LLMFramework,
        modelInfo: ModelInfo,
        prompt: String,
        completion: @escaping (GenerationTracking) -> Void
    ) -> GenerationTracking {
        // Start performance monitoring
        performanceMonitor.beginGeneration(framework: framework, modelInfo: modelInfo)

        let tracking = GenerationTracking(
            testId: testId,
            variantId: variantId
        )

        // Set up completion handler
        tracking.completionHandler = { [weak self] tracking in
            guard let self = self else { return }

            // End performance monitoring
            if let summary = self.performanceMonitor.endGeneration() {
                // Record metrics
                Task {
                    await self.abTestService.recordMetric(
                        testId: testId,
                        variantId: variantId,
                        metric: .tokensPerSecond(summary.tokensPerSecond)
                    )

                    await self.abTestService.recordMetric(
                        testId: testId,
                        variantId: variantId,
                        metric: .timeToFirstToken(summary.timeToFirstToken)
                    )

                    await self.abTestService.recordMetric(
                        testId: testId,
                        variantId: variantId,
                        metric: .memoryUsage(summary.memoryUsed)
                    )
                }
            }

            completion(tracking)
        }

        logger.debug("Started generation tracking for test \(testId), variant \(variantId)")

        return tracking
    }
}
