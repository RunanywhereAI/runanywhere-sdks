//
//  SpeakerDiarizationAnalyticsService.swift
//  RunAnywhere SDK
//
//  Speaker diarization analytics service.
//  Tracks diarization sessions and metrics.
//

import Foundation

// MARK: - Speaker Diarization Analytics Service

/// Speaker diarization analytics service for tracking diarization sessions.
public actor SpeakerDiarizationAnalyticsService {

    // MARK: - Properties

    private let logger = SDKLogger(category: "SpeakerDiarizationAnalytics")
    private var currentSession: SessionInfo?

    private struct SessionInfo {
        let id: String
        let startTime: Date
    }

    // Metrics
    private var sessionCount = 0
    private var totalSpeakersDetected = 0
    private var totalProcessingTime: Double = 0
    private let startTime = Date()
    private var lastEventTime: Date?

    // MARK: - Initialization

    public init() {}

    // MARK: - Session Methods

    /// Start a diarization session
    public func startDiarizationSession(maxSpeakers _: Int) -> String {
        let sessionId = UUID().uuidString
        currentSession = SessionInfo(
            id: sessionId,
            startTime: Date()
        )

        EventPublisher.shared.track(SpeakerDiarizationEvent.sessionStarted(sessionId: sessionId))
        logger.debug("Started diarization session: \(sessionId)")
        return sessionId
    }

    /// Complete a diarization session
    public func completeDiarizationSession(speakerCount: Int, segmentCount _: Int, averageConfidence _: Float) {
        guard let session = currentSession else { return }

        let processingTimeMs = Date().timeIntervalSince(session.startTime) * 1000

        EventPublisher.shared.track(SpeakerDiarizationEvent.sessionCompleted(
            sessionId: session.id,
            durationMs: processingTimeMs,
            speakersDetected: speakerCount
        ))

        // Update metrics
        sessionCount += 1
        totalSpeakersDetected += speakerCount
        totalProcessingTime += processingTimeMs
        lastEventTime = Date()

        currentSession = nil
        logger.debug("Completed diarization session: \(session.id)")
    }

    /// Track session failure
    public func trackSessionFailed(error: String) {
        guard let session = currentSession else { return }
        lastEventTime = Date()

        EventPublisher.shared.track(SpeakerDiarizationEvent.error(
            sessionId: session.id,
            message: error
        ))

        currentSession = nil
        logger.debug("Diarization session failed: \(session.id)")
    }

    /// Track speaker detection
    public func trackSpeakerDetected(speakerId: String, confidence: Float) {
        EventPublisher.shared.track(SpeakerDiarizationEvent.speakerDetected(
            speakerId: speakerId,
            confidence: confidence
        ))
    }

    /// Track speaker change
    public func trackSpeakerChanged(from: String?, to: String) {
        EventPublisher.shared.track(SpeakerDiarizationEvent.speakerChanged(
            fromSpeaker: from,
            toSpeaker: to
        ))
    }

    // MARK: - Metrics

    public func getMetrics() -> SpeakerDiarizationMetrics {
        SpeakerDiarizationMetrics(
            totalEvents: sessionCount,
            startTime: startTime,
            lastEventTime: lastEventTime,
            totalSessions: sessionCount,
            totalSpeakersDetected: totalSpeakersDetected,
            averageProcessingTimeMs: sessionCount > 0 ? totalProcessingTime / Double(sessionCount) : 0
        )
    }
}
