//
//  SpeakerDiarizationAnalyticsService.swift
//  RunAnywhere SDK
//
//  Speaker diarization analytics service following unified pattern
//

import Foundation

// MARK: - Speaker Diarization Analytics Service

/// Speaker diarization analytics service using unified pattern
public actor SpeakerDiarizationAnalyticsService: AnalyticsService {

    // MARK: - Type Aliases
    public typealias Event = SpeakerDiarizationEvent
    public typealias Metrics = SpeakerDiarizationMetrics

    // MARK: - Properties

    private let queueManager: AnalyticsQueueManager
    private let logger: SDKLogger
    private var currentSession: SessionInfo?
    private var events: [SpeakerDiarizationEvent] = []

    private struct SessionInfo {
        let id: String
        let maxSpeakers: Int
        let startTime: Date
    }

    private var metrics = SpeakerDiarizationMetrics()
    private var sessionCount = 0
    private var totalSpeakersDetected = 0
    private var totalProcessingTime: Double = 0

    // MARK: - Initialization

    public init(queueManager: AnalyticsQueueManager = .shared) {
        self.queueManager = queueManager
        self.logger = SDKLogger(category: "SpeakerDiarizationAnalytics")
    }

    // MARK: - Analytics Service Protocol

    public func track(event: SpeakerDiarizationEvent) async {
        events.append(event)
        await queueManager.enqueue(event)
        await processEvent(event)
    }

    public func trackBatch(events: [SpeakerDiarizationEvent]) async {
        self.events.append(contentsOf: events)
        await queueManager.enqueueBatch(events)
        for event in events {
            await processEvent(event)
        }
    }

    public func getMetrics() async -> SpeakerDiarizationMetrics {
        return SpeakerDiarizationMetrics(
            totalEvents: events.count,
            startTime: metrics.startTime,
            lastEventTime: events.last?.timestamp,
            totalSessions: sessionCount,
            totalSpeakersDetected: totalSpeakersDetected,
            averageProcessingTimeMs: sessionCount > 0 ? totalProcessingTime / Double(sessionCount) : 0
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
            maxSpeakers: 10,
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

    // MARK: - Diarization-Specific Methods

    /// Start a diarization session
    public func startDiarizationSession(maxSpeakers: Int) async -> String {
        let sessionId = UUID().uuidString
        let sessionInfo = SessionInfo(
            id: sessionId,
            maxSpeakers: maxSpeakers,
            startTime: Date()
        )
        currentSession = sessionInfo

        let eventData = DiarizationSessionStartData(maxSpeakers: maxSpeakers)
        let event = SpeakerDiarizationEvent(
            type: .sessionStarted,
            sessionId: sessionId,
            eventData: eventData
        )

        await track(event: event)
        logger.debug("Started diarization session: \(sessionId)")
        return sessionId
    }

    /// Complete a diarization session
    public func completeDiarizationSession(
        speakerCount: Int,
        segmentCount: Int,
        averageConfidence: Double
    ) async {
        guard let session = currentSession else { return }

        let processingTimeMs = Date().timeIntervalSince(session.startTime) * 1000

        let eventData = DiarizationSessionCompletionData(
            processingTimeMs: processingTimeMs,
            speakerCount: speakerCount,
            segmentCount: segmentCount,
            averageConfidence: averageConfidence,
            maxSpeakers: session.maxSpeakers,
            success: true
        )
        let event = SpeakerDiarizationEvent(
            type: .sessionCompleted,
            sessionId: session.id,
            eventData: eventData
        )

        await track(event: event)

        // Update metrics
        sessionCount += 1
        totalSpeakersDetected += speakerCount
        totalProcessingTime += processingTimeMs

        currentSession = nil
        logger.debug("Completed diarization session: \(session.id), speakers: \(speakerCount)")
    }

    /// Track diarization session failure
    public func trackSessionFailed(errorMessage: String) async {
        guard let session = currentSession else { return }

        let processingTimeMs = Date().timeIntervalSince(session.startTime) * 1000

        let eventData = DiarizationSessionFailureData(
            processingTimeMs: processingTimeMs,
            maxSpeakers: session.maxSpeakers,
            errorMessage: errorMessage
        )
        let event = SpeakerDiarizationEvent(
            type: .error,
            sessionId: session.id,
            eventData: eventData
        )

        await track(event: event)
        currentSession = nil
        logger.debug("Diarization session failed: \(session.id)")
    }

    /// Track speaker detection
    public func trackSpeakerDetected(
        speakerId: String,
        speakerIndex: Int,
        confidence: Double
    ) async {
        let eventData = DiarizationSpeakerDetectedData(
            speakerId: speakerId,
            speakerIndex: speakerIndex,
            confidence: confidence
        )
        let event = SpeakerDiarizationEvent(
            type: .speakerDetected,
            sessionId: currentSession?.id,
            eventData: eventData
        )

        await track(event: event)
    }

    /// Track speaker change
    public func trackSpeakerChanged(from: String?, to: String) async {
        let eventData = DiarizationSpeakerChangedData(
            fromSpeakerId: from,
            toSpeakerId: to
        )
        let event = SpeakerDiarizationEvent(
            type: .speakerChanged,
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
        let event = SpeakerDiarizationEvent(
            type: .error,
            sessionId: currentSession?.id,
            eventData: eventData
        )

        await track(event: event)
    }

    // MARK: - Private Methods

    private func processEvent(_ event: SpeakerDiarizationEvent) async {
        // Custom processing for diarization events if needed
    }
}
