//
//  VoiceAnalyticsService.swift
//  RunAnywhere SDK
//
//  Voice-specific analytics service following unified pattern
//

import Foundation

// MARK: - Voice Analytics Service

/// Voice analytics service using unified pattern
public actor VoiceAnalyticsService: AnalyticsService {

    // MARK: - Type Aliases
    public typealias Event = VoiceEvent
    public typealias Metrics = VoiceMetrics

    // MARK: - Properties

    private let queueManager: AnalyticsQueueManager
    private let logger: SDKLogger
    private var currentSession: SessionInfo?
    private var events: [VoiceEvent] = []

    private struct SessionInfo {
        let id: String
        let modelId: String?
        let startTime: Date
    }

    private var metrics = VoiceMetrics()
    private var totalTranscriptions = 0
    private var totalPipelineExecutions = 0
    private var totalTranscriptionDuration: TimeInterval = 0
    private var totalPipelineDuration: TimeInterval = 0
    private var totalRealTimeFactor: Double = 0

    // MARK: - Initialization

    public init(queueManager: AnalyticsQueueManager = .shared) {
        self.queueManager = queueManager
        self.logger = SDKLogger(category: "VoiceAnalytics")
    }

    // MARK: - Analytics Service Protocol

    public func track(event: VoiceEvent) async {
        events.append(event)
        await queueManager.enqueue(event)
        await processEvent(event)
    }

    public func trackBatch(events: [VoiceEvent]) async {
        self.events.append(contentsOf: events)
        await queueManager.enqueueBatch(events)
        for event in events {
            await processEvent(event)
        }
    }

    public func getMetrics() async -> VoiceMetrics {
        return VoiceMetrics(
            totalEvents: events.count,
            startTime: metrics.startTime,
            lastEventTime: events.last?.timestamp,
            totalTranscriptions: totalTranscriptions,
            totalPipelineExecutions: totalPipelineExecutions,
            averageTranscriptionDuration: totalTranscriptions > 0 ? totalTranscriptionDuration / Double(totalTranscriptions) : 0,
            averagePipelineDuration: totalPipelineExecutions > 0 ? totalPipelineDuration / Double(totalPipelineExecutions) : 0,
            averageRealTimeFactor: totalTranscriptions > 0 ? totalRealTimeFactor / Double(totalTranscriptions) : 0
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

    // MARK: - Voice-Specific Methods

    /// Track pipeline creation
    public func trackPipelineCreation(stages: [String]) async {
        let eventData = PipelineCreationData(
            stageCount: stages.count,
            stages: stages
        )
        let event = VoiceEvent(
            type: .pipelineCreated,
            sessionId: currentSession?.id,
            eventData: eventData
        )

        await track(event: event)
    }

    /// Track transcription start
    public func trackTranscriptionStarted(audioLength: TimeInterval) async {
        let eventData = TranscriptionStartData(
            audioLengthMs: audioLength * 1000,
            startTimestamp: Date().timeIntervalSince1970
        )
        let event = VoiceEvent(
            type: .transcriptionStarted,
            sessionId: currentSession?.id,
            eventData: eventData
        )

        await track(event: event)
    }

    /// Track transcription performance
    public func trackTranscription(
        duration: TimeInterval,
        wordCount: Int,
        audioLength: TimeInterval
    ) async {
        let realTimeFactor = duration / audioLength

        totalTranscriptions += 1
        totalTranscriptionDuration += duration
        totalRealTimeFactor += realTimeFactor

        let eventData = VoiceTranscriptionData(
            durationMs: duration * 1000,
            wordCount: wordCount,
            audioLengthMs: audioLength * 1000,
            realTimeFactor: realTimeFactor
        )
        let event = VoiceEvent(
            type: .transcriptionCompleted,
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
        let event = VoiceEvent(
            type: .error,
            sessionId: currentSession?.id,
            eventData: eventData
        )

        await track(event: event)
    }

    // MARK: - Private Methods

    private func processEvent(_ event: VoiceEvent) async {
        // Custom processing for voice events if needed
    }
}
