//
//  GenerationAnalyticsService.swift
//  RunAnywhere SDK
//
//  LLM Generation analytics service.
//  Tracks generation operations and metrics.
//  Lifecycle events are handled by ManagedLifecycle.
//

import Foundation

// MARK: - Generation Analytics Service

/// LLM analytics service for tracking generation operations.
/// Model lifecycle events (load/unload) are handled by ManagedLifecycle.
public actor GenerationAnalyticsService {

    // MARK: - Properties

    private let logger = SDKLogger(category: "GenerationAnalytics")

    /// Active generation operations
    private var activeGenerations: [String: GenerationTracker] = [:]

    /// Metrics
    private var totalGenerations = 0
    private var totalTimeToFirstToken: TimeInterval = 0
    private var totalTokensPerSecond: Double = 0
    private var totalInputTokens = 0
    private var totalOutputTokens = 0
    private let startTime = Date()
    private var lastEventTime: Date?

    // MARK: - Types

    private struct GenerationTracker {
        let startTime: Date
        var firstTokenTime: Date?
    }

    // MARK: - Initialization

    public init() {}

    // MARK: - Generation Tracking

    /// Start tracking a generation
    public func startGeneration(modelId: String, executionTarget _: String) -> String {
        let id = UUID().uuidString
        activeGenerations[id] = GenerationTracker(startTime: Date())

        EventPublisher.shared.track(LLMEvent.generationStarted(
            generationId: id,
            modelId: modelId,
            prompt: nil
        ))

        logger.debug("Generation started: \(id)")
        return id
    }

    /// Track first token (time-to-first-token metric)
    public func trackFirstToken(generationId: String) {
        guard var tracker = activeGenerations[generationId] else { return }
        let firstTokenTime = Date()
        tracker.firstTokenTime = firstTokenTime
        activeGenerations[generationId] = tracker

        let latencyMs = firstTokenTime.timeIntervalSince(tracker.startTime) * 1000

        EventPublisher.shared.track(LLMEvent.firstToken(
            generationId: generationId,
            latencyMs: latencyMs
        ))
    }

    /// Track streaming update (analytics only)
    public func trackStreamingUpdate(generationId: String, tokensGenerated: Int) {
        EventPublisher.shared.track(LLMEvent.streamingUpdate(
            generationId: generationId,
            tokensGenerated: tokensGenerated
        ))
    }

    /// Complete a generation
    public func completeGeneration(
        generationId: String,
        inputTokens: Int,
        outputTokens: Int,
        modelId: String,
        executionTarget _: String
    ) {
        guard let tracker = activeGenerations.removeValue(forKey: generationId) else { return }

        let totalTime = Date().timeIntervalSince(tracker.startTime)
        let tokensPerSecond = totalTime > 0 ? Double(outputTokens) / totalTime : 0

        // Update metrics
        totalGenerations += 1
        totalTimeToFirstToken += tracker.firstTokenTime?.timeIntervalSince(tracker.startTime) ?? 0
        totalTokensPerSecond += tokensPerSecond
        totalInputTokens += inputTokens
        totalOutputTokens += outputTokens
        lastEventTime = Date()

        EventPublisher.shared.track(LLMEvent.generationCompleted(
            generationId: generationId,
            modelId: modelId,
            inputTokens: inputTokens,
            outputTokens: outputTokens,
            durationMs: totalTime * 1000,
            tokensPerSecond: tokensPerSecond
        ))

        logger.debug("Generation completed: \(generationId)")
    }

    /// Track generation failure
    public func trackGenerationFailed(generationId: String, error: Error) {
        activeGenerations.removeValue(forKey: generationId)
        lastEventTime = Date()

        EventPublisher.shared.track(LLMEvent.generationFailed(
            generationId: generationId,
            error: error.localizedDescription
        ))
    }

    /// Track an error during operations
    public func trackError(_ error: Error, operation: String) {
        lastEventTime = Date()
        EventPublisher.shared.track(ErrorEvent.error(
            operation: operation,
            message: error.localizedDescription,
            code: (error as NSError).code
        ))
    }

    // MARK: - Metrics

    public func getMetrics() -> GenerationMetrics {
        GenerationMetrics(
            totalEvents: totalGenerations,
            startTime: startTime,
            lastEventTime: lastEventTime,
            totalGenerations: totalGenerations,
            averageTimeToFirstToken: totalGenerations > 0 ? totalTimeToFirstToken / Double(totalGenerations) : 0,
            averageTokensPerSecond: totalGenerations > 0 ? totalTokensPerSecond / Double(totalGenerations) : 0,
            totalInputTokens: totalInputTokens,
            totalOutputTokens: totalOutputTokens
        )
    }
}

// MARK: - Generation Metrics

public struct GenerationMetrics: AnalyticsMetrics {
    public let totalEvents: Int
    public let startTime: Date
    public let lastEventTime: Date?
    public let totalGenerations: Int
    public let averageTimeToFirstToken: TimeInterval
    public let averageTokensPerSecond: Double
    public let totalInputTokens: Int
    public let totalOutputTokens: Int

    public init(
        totalEvents: Int = 0,
        startTime: Date = Date(),
        lastEventTime: Date? = nil,
        totalGenerations: Int = 0,
        averageTimeToFirstToken: TimeInterval = 0,
        averageTokensPerSecond: Double = 0,
        totalInputTokens: Int = 0,
        totalOutputTokens: Int = 0
    ) {
        self.totalEvents = totalEvents
        self.startTime = startTime
        self.lastEventTime = lastEventTime
        self.totalGenerations = totalGenerations
        self.averageTimeToFirstToken = averageTimeToFirstToken
        self.averageTokensPerSecond = averageTokensPerSecond
        self.totalInputTokens = totalInputTokens
        self.totalOutputTokens = totalOutputTokens
    }
}
