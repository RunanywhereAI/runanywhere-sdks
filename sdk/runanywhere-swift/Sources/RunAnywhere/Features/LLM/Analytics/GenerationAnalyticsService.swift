//
//  GenerationAnalyticsService.swift
//  RunAnywhere SDK
//
//  Generation-specific analytics service following unified pattern
//

import Foundation

// MARK: - Generation Analytics Service

/// Generation analytics service using unified pattern
public actor GenerationAnalyticsService: AnalyticsService {

    // MARK: - Type Aliases
    public typealias Event = GenerationEvent
    public typealias Metrics = GenerationMetrics

    // MARK: - Properties

    private let queueManager: AnalyticsQueueManager
    private let logger: SDKLogger
    private var currentSession: SessionInfo?
    private var events: [GenerationEvent] = []

    private struct SessionInfo {
        let id: String
        let modelId: String?
        let startTime: Date
    }

    private var metrics = GenerationMetrics()
    private var totalGenerations = 0
    private var totalTimeToFirstToken: TimeInterval = 0
    private var totalTokensPerSecond: Double = 0
    private var totalInputTokens = 0
    private var totalOutputTokens = 0

    // Generation tracking
    private var activeGenerations: [String: GenerationTracker] = [:]

    private struct GenerationTracker {
        let id: String
        let startTime: Date
        var firstTokenTime: Date?
        var endTime: Date?
        var inputTokens: Int = 0
        var outputTokens: Int = 0
    }

    // MARK: - Initialization

    public init(queueManager: AnalyticsQueueManager = .shared) {
        self.queueManager = queueManager
        self.logger = SDKLogger(category: "GenerationAnalytics")
    }

    // MARK: - Analytics Service Protocol

    public func track(event: GenerationEvent) async {
        events.append(event)
        await queueManager.enqueue(event)
        await processEvent(event)
    }

    public func trackBatch(events: [GenerationEvent]) async {
        self.events.append(contentsOf: events)
        await queueManager.enqueueBatch(events)
        for event in events {
            await processEvent(event)
        }
    }

    public func getMetrics() async -> GenerationMetrics {
        return GenerationMetrics(
            totalEvents: events.count,
            startTime: metrics.startTime,
            lastEventTime: events.last?.timestamp,
            totalGenerations: totalGenerations,
            averageTimeToFirstToken: totalGenerations > 0 ? totalTimeToFirstToken / Double(totalGenerations) : 0,
            averageTokensPerSecond: totalGenerations > 0 ? totalTokensPerSecond / Double(totalGenerations) : 0,
            totalInputTokens: totalInputTokens,
            totalOutputTokens: totalOutputTokens
        )
    }

    public func clearMetrics(olderThan date: Date) async {
        events.removeAll { event in
            event.timestamp < date
        }
    }

    public func startSession(metadata: SessionMetadata) async -> String {
        let sessionInfo = SessionInfo(
            id: metadata.id,
            modelId: metadata.modelId,
            startTime: Date()
        )
        currentSession = sessionInfo
        return metadata.id
    }

    public func endSession(sessionId: String) async {
        if currentSession?.id == sessionId {
            currentSession = nil
        }
    }

    public func isHealthy() async -> Bool {
        return true
    }

    // MARK: - Generation-Specific Methods

    /// Start tracking a new generation
    public func startGeneration(
        generationId: String? = nil,
        modelId: String,
        executionTarget: String
    ) async -> String {
        let id = generationId ?? UUID().uuidString

        let tracker = GenerationTracker(
            id: id,
            startTime: Date()
        )
        activeGenerations[id] = tracker

        let eventData = GenerationStartData(
            generationId: id,
            modelId: modelId,
            executionTarget: executionTarget,
            promptTokens: 0, // Will be updated when available
            maxTokens: 0 // Will be updated when available
        )
        let event = GenerationEvent(
            type: .generationStarted,
            sessionId: currentSession?.id,
            eventData: eventData
        )

        await track(event: event)
        return id
    }

    /// Track first token generation
    public func trackFirstToken(generationId: String) async {
        guard var tracker = activeGenerations[generationId] else { return }

        let firstTokenTime = Date()
        tracker.firstTokenTime = firstTokenTime
        activeGenerations[generationId] = tracker

        let timeToFirstToken = firstTokenTime.timeIntervalSince(tracker.startTime)

        let eventData = FirstTokenData(
            generationId: generationId,
            timeToFirstTokenMs: timeToFirstToken * 1000
        )
        let event = GenerationEvent(
            type: .firstTokenGenerated,
            sessionId: currentSession?.id,
            eventData: eventData
        )

        await track(event: event)
    }

    /// Complete a generation with performance metrics
    public func completeGeneration(
        generationId: String,
        inputTokens: Int,
        outputTokens: Int,
        modelId: String,
        executionTarget: String
    ) async {
        guard var tracker = activeGenerations[generationId] else { return }

        let endTime = Date()
        tracker.endTime = endTime
        tracker.inputTokens = inputTokens
        tracker.outputTokens = outputTokens

        let totalTime = endTime.timeIntervalSince(tracker.startTime)
        let timeToFirstToken = tracker.firstTokenTime?.timeIntervalSince(tracker.startTime) ?? 0
        let tokensPerSecond = totalTime > 0 ? Double(outputTokens) / totalTime : 0

        // Update metrics
        totalGenerations += 1
        totalTimeToFirstToken += timeToFirstToken
        totalTokensPerSecond += tokensPerSecond
        totalInputTokens += inputTokens
        totalOutputTokens += outputTokens

        let eventData = GenerationCompletionData(
            modelId: modelId,
            modelName: nil,
            framework: nil,
            device: nil,
            osVersion: nil,
            platform: nil,
            sdkVersion: nil,
            processingTimeMs: totalTime * 1000,
            success: true,
            inputTokens: inputTokens,
            outputTokens: outputTokens,
            totalTokens: inputTokens + outputTokens,
            tokensPerSecond: tokensPerSecond,
            timeToFirstTokenMs: timeToFirstToken * 1000,
            generationTimeMs: totalTime * 1000
        )
        let event = GenerationEvent(
            type: .generationCompleted,
            sessionId: currentSession?.id,
            eventData: eventData
        )

        await track(event: event)

        // Clean up tracker
        activeGenerations.removeValue(forKey: generationId)
    }

    /// Track streaming update
    public func trackStreamingUpdate(
        generationId: String,
        tokensGenerated: Int
    ) async {
        let eventData = StreamingUpdateData(
            generationId: generationId,
            tokensGenerated: tokensGenerated
        )
        let event = GenerationEvent(
            type: .streamingUpdate,
            sessionId: currentSession?.id,
            eventData: eventData
        )

        await track(event: event)
    }

    /// Track model loading
    public func trackModelLoading(
        modelId: String,
        loadTime: TimeInterval,
        success: Bool
    ) async {
        let eventData = ModelLoadingData(
            modelId: modelId,
            loadTimeMs: loadTime * 1000,
            success: success
        )
        let event = GenerationEvent(
            type: .modelLoaded,
            sessionId: currentSession?.id,
            eventData: eventData
        )

        await track(event: event)
    }

    /// Track model unloading
    public func trackModelUnloading(modelId: String) async {
        let eventData = ModelUnloadingData(modelId: modelId)
        let event = GenerationEvent(
            type: .modelUnloaded,
            sessionId: currentSession?.id,
            eventData: eventData
        )

        await track(event: event)
    }

    /// Track error
    public func trackError(error: Error, context: AnalyticsContext) async {
        let eventData = ErrorEventData(
            error: error.localizedDescription,
            context: context
        )
        let event = GenerationEvent(
            type: .error,
            sessionId: currentSession?.id,
            eventData: eventData
        )

        await track(event: event)
    }

    // MARK: - Private Methods

    private func processEvent(_ event: GenerationEvent) async {
        // Custom processing for generation events if needed
    }
}
