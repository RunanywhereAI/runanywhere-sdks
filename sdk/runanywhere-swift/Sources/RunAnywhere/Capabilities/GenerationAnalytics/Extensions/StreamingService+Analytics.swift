import Foundation

/// Extension to add analytics support to StreamingService
extension StreamingService {
    private static let logger = SDKLogger(category: "StreamingService+Analytics")

    /// Generate streaming text with analytics tracking
    public func generateStreamWithAnalytics(
        prompt: String,
        options: GenerationOptions,
        sessionId: UUID? = nil,
        analytics: GenerationAnalyticsService? = nil
    ) -> AsyncThrowingStream<String, Error> {
        return AsyncThrowingStream { continuation in
            Task {
                do {
                    // Get analytics service from container if not provided
                    let analyticsService: GenerationAnalyticsService
                    if let providedAnalytics = analytics {
                        analyticsService = providedAnalytics
                    } else {
                        analyticsService = await ServiceContainer.shared.generationAnalytics
                    }

                    // Get the current loaded model from generation service
                    // Get model from generation service via ServiceContainer
                    guard let loadedModel = ServiceContainer.shared.generationService.getCurrentModel() else {
                        throw SDKError.modelNotFound("No model is currently loaded")
                    }

                    // Start or get session
                    let activeSessionId: UUID
                    if let providedSessionId = sessionId {
                        activeSessionId = providedSessionId
                    } else {
                        let session = await analyticsService.startSession(
                            modelId: loadedModel.model.id,
                            type: .streaming
                        )
                        activeSessionId = session.id
                    }

                    // Start generation tracking
                    let generation = await analyticsService.startGeneration(sessionId: activeSessionId)
                    guard let tracker = await analyticsService.getTracker(for: generation.id) else {
                        // Fallback to regular streaming if tracker creation failed
                        for try await token in generateStream(prompt: prompt, options: options) {
                            continuation.yield(token)
                        }
                        continuation.finish()
                        return
                    }


                    // Check if model supports thinking and get pattern
                    let modelInfo = loadedModel.model
                    let shouldParseThinking = modelInfo.supportsThinking
                    let thinkingPattern = modelInfo.thinkingTagPattern ?? ThinkingTagPattern.defaultPattern

                    // Buffers for thinking parsing
                    var buffer = ""
                    var inThinkingSection = false
                    var hasRecordedFirstToken = false
                    var totalTokens = 0

                    // Track start time for performance metrics
                    let startTime = Date()

                    // Use the actual streaming method from the LLM service
                    Self.logger.debug("About to call streamGenerate on service")
                    Self.logger.debug("Service type: \(type(of: loadedModel.service))")
                    try await loadedModel.service.streamGenerate(
                        prompt: prompt,
                        options: options,
                        onToken: { token in
                            Self.logger.debug("Received token: '\(token)'")
                            // Track token for analytics
                            Task {
                                if !hasRecordedFirstToken {
                                    await tracker.recordFirstToken()
                                    hasRecordedFirstToken = true
                                }
                                await tracker.recordToken()
                            }
                            totalTokens += 1

                            if shouldParseThinking {
                                // Parse token for thinking content
                                let (tokenType, cleanToken) = ThinkingParser.parseStreamingToken(
                                    token: token,
                                    pattern: thinkingPattern,
                                    buffer: &buffer,
                                    inThinkingSection: &inThinkingSection
                                )

                                // Only yield non-thinking tokens
                                if tokenType == .content, let cleanToken = cleanToken {
                                    continuation.yield(cleanToken)
                                }
                            } else {
                                // No thinking support, yield token directly
                                continuation.yield(token)
                            }
                        }
                    )

                    Self.logger.debug("streamGenerate completed")

                    // Complete tracking
                    let endTime = Date()
                    let totalTime = endTime.timeIntervalSince(startTime)

                    // Create analytics-compatible result
                    let analyticsResult = AnalyticsGenerationResult(
                        text: "", // Text is streamed, not stored
                        model: loadedModel,
                        executionTarget: .onDevice,
                        metrics: GenerationMetrics(
                            inputTokens: prompt.count / 4, // Approximate
                            outputTokens: totalTokens,
                            tokensPerSecond: Double(totalTokens) / totalTime,
                            totalTime: totalTime
                        ),
                        cost: GenerationCost(
                            estimated: 0.0,
                            actual: 0.0,
                            saved: calculateSavedCost(totalTokens: totalTokens)
                        )
                    )

                    // Create routing decision (defaulting to on-device for mobile)
                    let routingDecision = RoutingDecision.onDevice(
                        framework: nil,
                        reason: .lowComplexity
                    )

                    let performance = await tracker.complete(
                        result: analyticsResult,
                        routingDecision: routingDecision
                    )

                    await analyticsService.completeGeneration(generation.id, performance: performance)

                    // If this was a single generation session, end it
                    if sessionId == nil {
                        await analyticsService.endSession(activeSessionId)
                    }

                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    /// Generate streaming text with analytics tracking and live metrics
    public func generateStreamWithLiveMetrics(
        prompt: String,
        options: GenerationOptions,
        sessionId: UUID? = nil,
        analytics: GenerationAnalyticsService? = nil,
        onMetrics: @escaping (LiveGenerationMetrics) -> Void
    ) -> AsyncThrowingStream<String, Error> {
        return AsyncThrowingStream { continuation in
            Task {
                do {
                    // Get analytics service from container if not provided
                    let analyticsService: GenerationAnalyticsService
                    if let providedAnalytics = analytics {
                        analyticsService = providedAnalytics
                    } else {
                        analyticsService = await ServiceContainer.shared.generationAnalytics
                    }

                    // Get the current loaded model from generation service
                    // Get model from generation service via ServiceContainer
                    guard let loadedModel = ServiceContainer.shared.generationService.getCurrentModel() else {
                        throw SDKError.modelNotFound("No model is currently loaded")
                    }

                    // Start or get session
                    let activeSessionId: UUID
                    if let providedSessionId = sessionId {
                        activeSessionId = providedSessionId
                    } else {
                        let session = await analyticsService.startSession(
                            modelId: loadedModel.model.id,
                            type: .streaming
                        )
                        activeSessionId = session.id
                    }

                    // Start generation tracking
                    let generation = await analyticsService.startGeneration(sessionId: activeSessionId)

                    // Start observing live metrics
                    Task {
                        for await metrics in await analyticsService.observeLiveMetrics(for: generation.id) {
                            onMetrics(metrics)
                        }
                    }

                    // Use the regular streaming with analytics
                    for try await token in generateStreamWithAnalytics(
                        prompt: prompt,
                        options: options,
                        sessionId: activeSessionId,
                        analytics: analyticsService
                    ) {
                        continuation.yield(token)
                    }

                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    // MARK: - Private Helpers

    private func calculateSavedCost(totalTokens: Int) -> Double {
        // Simple calculation: assume cloud would cost $0.01 per 1000 tokens
        return (Double(totalTokens) / 1000.0) * 0.01
    }
}
