//
//  GenerationAnalyticsService.swift
//  RunAnywhere SDK
//
//  Generation-specific analytics service following unified pattern
//

import Foundation

// MARK: - Generation Event

/// Generation-specific analytics event
public struct GenerationEvent: AnalyticsEvent {
    public let id: String
    public let type: String
    public let timestamp: Date
    public let sessionId: String?
    public let properties: [String: String]

    public init(
        type: GenerationEventType,
        sessionId: String? = nil,
        properties: [String: String] = [:]
    ) {
        self.id = UUID().uuidString
        self.type = type.rawValue
        self.timestamp = Date()
        self.sessionId = sessionId
        self.properties = properties
    }
}

/// Generation event types
public enum GenerationEventType: String {
    case sessionStarted = "generation_session_started"
    case sessionEnded = "generation_session_ended"
    case generationStarted = "generation_started"
    case generationCompleted = "generation_completed"
    case firstTokenGenerated = "generation_first_token"
    case streamingUpdate = "generation_streaming_update"
    case error = "generation_error"
    case modelLoaded = "generation_model_loaded"
    case modelUnloaded = "generation_model_unloaded"
}

// MARK: - Generation Metrics

/// Generation-specific metrics
public struct GenerationMetrics: AnalyticsMetrics {
    public let totalEvents: Int
    public let startTime: Date
    public let lastEventTime: Date?
    public let totalGenerations: Int
    public let averageTimeToFirstToken: TimeInterval
    public let averageTokensPerSecond: Double
    public let totalInputTokens: Int
    public let totalOutputTokens: Int

    public init() {
        self.totalEvents = 0
        self.startTime = Date()
        self.lastEventTime = nil
        self.totalGenerations = 0
        self.averageTimeToFirstToken = 0
        self.averageTokensPerSecond = 0
        self.totalInputTokens = 0
        self.totalOutputTokens = 0
    }

    internal init(
        totalEvents: Int,
        startTime: Date,
        lastEventTime: Date?,
        totalGenerations: Int,
        averageTimeToFirstToken: TimeInterval,
        averageTokensPerSecond: Double,
        totalInputTokens: Int,
        totalOutputTokens: Int
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

        let event = GenerationEvent(
            type: .generationStarted,
            sessionId: currentSession?.id,
            properties: [
                "generation_id": id,
                "model_id": modelId,
                "execution_target": executionTarget
            ]
        )

        await track(event: event)
        return id
    }

    /// Track first token generation
    public func trackFirstToken(generationId: String) async {
        guard var tracker = activeGenerations[generationId] else { return }

        tracker.firstTokenTime = Date()
        activeGenerations[generationId] = tracker

        let timeToFirstToken = tracker.firstTokenTime!.timeIntervalSince(tracker.startTime)

        let event = GenerationEvent(
            type: .firstTokenGenerated,
            sessionId: currentSession?.id,
            properties: [
                "generation_id": generationId,
                "time_to_first_token_ms": String(timeToFirstToken * 1000)
            ]
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

        tracker.endTime = Date()
        tracker.inputTokens = inputTokens
        tracker.outputTokens = outputTokens

        let totalTime = tracker.endTime!.timeIntervalSince(tracker.startTime)
        let timeToFirstToken = tracker.firstTokenTime?.timeIntervalSince(tracker.startTime) ?? 0
        let tokensPerSecond = totalTime > 0 ? Double(outputTokens) / totalTime : 0

        // Update metrics
        totalGenerations += 1
        totalTimeToFirstToken += timeToFirstToken
        totalTokensPerSecond += tokensPerSecond
        totalInputTokens += inputTokens
        totalOutputTokens += outputTokens

        let event = GenerationEvent(
            type: .generationCompleted,
            sessionId: currentSession?.id,
            properties: [
                "generation_id": generationId,
                "model_id": modelId,
                "execution_target": executionTarget,
                "input_tokens": String(inputTokens),
                "output_tokens": String(outputTokens),
                "total_time_ms": String(totalTime * 1000),
                "time_to_first_token_ms": String(timeToFirstToken * 1000),
                "tokens_per_second": String(tokensPerSecond)
            ]
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
        let event = GenerationEvent(
            type: .streamingUpdate,
            sessionId: currentSession?.id,
            properties: [
                "generation_id": generationId,
                "tokens_generated": String(tokensGenerated)
            ]
        )

        await track(event: event)
    }

    /// Track model loading
    public func trackModelLoading(
        modelId: String,
        loadTime: TimeInterval,
        success: Bool
    ) async {
        let event = GenerationEvent(
            type: .modelLoaded,
            sessionId: currentSession?.id,
            properties: [
                "model_id": modelId,
                "load_time_ms": String(loadTime * 1000),
                "success": String(success)
            ]
        )

        await track(event: event)
    }

    /// Track model unloading
    public func trackModelUnloading(modelId: String) async {
        let event = GenerationEvent(
            type: .modelUnloaded,
            sessionId: currentSession?.id,
            properties: [
                "model_id": modelId
            ]
        )

        await track(event: event)
    }

    /// Track error
    public func trackError(error: Error, context: String) async {
        let event = GenerationEvent(
            type: .error,
            sessionId: currentSession?.id,
            properties: [
                "error": error.localizedDescription,
                "context": context
            ]
        )

        await track(event: event)
    }

    // MARK: - Session Management Override

    /// Start a generation session
    public func startGenerationSession(modelId: String, type: String = "text") async -> String {
        let metadata = SessionMetadata(
            modelId: modelId,
            type: type
        )

        let sessionId = await startSession(metadata: metadata)

        let event = GenerationEvent(
            type: .sessionStarted,
            sessionId: sessionId,
            properties: [
                "model_id": modelId,
                "session_type": type
            ]
        )

        await track(event: event)
        return sessionId
    }

    /// End a generation session
    public func endGenerationSession(sessionId: String) async {
        await endSession(sessionId: sessionId)

        let event = GenerationEvent(
            type: .sessionEnded,
            sessionId: sessionId,
            properties: [:]
        )

        await track(event: event)
    }

    // MARK: - Private Methods

    private func processEvent(_ event: GenerationEvent) async {
        // Custom processing for generation events if needed
    }
}
