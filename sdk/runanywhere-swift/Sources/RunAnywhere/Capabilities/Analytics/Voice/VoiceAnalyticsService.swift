//
//  VoiceAnalyticsService.swift
//  RunAnywhere SDK
//
//  Voice-specific analytics service following unified pattern
//

import Foundation

// MARK: - Voice Event

/// Voice-specific analytics event
public struct VoiceEvent: AnalyticsEvent {
    public let id: String
    public let type: String
    public let timestamp: Date
    public let sessionId: String?
    public let eventData: any AnalyticsEventData

    public init(
        type: VoiceEventType,
        sessionId: String? = nil,
        eventData: any AnalyticsEventData
    ) {
        self.id = UUID().uuidString
        self.type = type.rawValue
        self.timestamp = Date()
        self.sessionId = sessionId
        self.eventData = eventData
    }
}

/// Voice event types
public enum VoiceEventType: String {
    case pipelineCreated = "voice_pipeline_created"
    case pipelineStarted = "voice_pipeline_started"
    case pipelineCompleted = "voice_pipeline_completed"
    case transcriptionStarted = "voice_transcription_started"
    case transcriptionCompleted = "voice_transcription_completed"
    case stageExecuted = "voice_stage_executed"
    case error = "voice_error"
}

// MARK: - Voice Metrics

/// Voice-specific metrics
public struct VoiceMetrics: AnalyticsMetrics {
    public let totalEvents: Int
    public let startTime: Date
    public let lastEventTime: Date?
    public let totalTranscriptions: Int
    public let totalPipelineExecutions: Int
    public let averageTranscriptionDuration: TimeInterval
    public let averagePipelineDuration: TimeInterval
    public let averageRealTimeFactor: Double

    public init() {
        self.totalEvents = 0
        self.startTime = Date()
        self.lastEventTime = nil
        self.totalTranscriptions = 0
        self.totalPipelineExecutions = 0
        self.averageTranscriptionDuration = 0
        self.averagePipelineDuration = 0
        self.averageRealTimeFactor = 0
    }

    public init(
        totalEvents: Int,
        startTime: Date,
        lastEventTime: Date?,
        totalTranscriptions: Int,
        totalPipelineExecutions: Int,
        averageTranscriptionDuration: TimeInterval,
        averagePipelineDuration: TimeInterval,
        averageRealTimeFactor: Double
    ) {
        self.totalEvents = totalEvents
        self.startTime = startTime
        self.lastEventTime = lastEventTime
        self.totalTranscriptions = totalTranscriptions
        self.totalPipelineExecutions = totalPipelineExecutions
        self.averageTranscriptionDuration = averageTranscriptionDuration
        self.averagePipelineDuration = averagePipelineDuration
        self.averageRealTimeFactor = averageRealTimeFactor
    }

}

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

    /// Track pipeline start
    public func trackPipelineStarted(stages: [String]) async {
        let eventData = PipelineStartedData(
            stageCount: stages.count,
            stages: stages,
            startTimestamp: Date().timeIntervalSince1970
        )
        let event = VoiceEvent(
            type: .pipelineStarted,
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

    /// Track pipeline execution
    public func trackPipelineExecution(
        stages: [String],
        totalTime: TimeInterval
    ) async {
        totalPipelineExecutions += 1
        totalPipelineDuration += totalTime

        let eventData = PipelineCompletionData(
            stageCount: stages.count,
            stages: stages,
            totalTimeMs: totalTime * 1000
        )
        let event = VoiceEvent(
            type: .pipelineCompleted,
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

    /// Track stage execution
    public func trackStageExecution(
        stage: String,
        duration: TimeInterval
    ) async {
        let eventData = StageExecutionData(
            stageName: stage,
            durationMs: duration * 1000
        )
        let event = VoiceEvent(
            type: .stageExecuted,
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
