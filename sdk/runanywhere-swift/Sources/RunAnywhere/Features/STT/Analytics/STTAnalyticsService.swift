//
//  STTAnalyticsService.swift
//  RunAnywhere SDK
//
//  STT analytics service.
//  Tracks transcription operations and metrics.
//  Lifecycle events are handled by ManagedLifecycle.
//

import Foundation

// MARK: - STT Analytics Service

/// STT analytics service for tracking transcription operations.
/// Model lifecycle events (load/unload) are handled by ManagedLifecycle.
public actor STTAnalyticsService {

    // MARK: - Properties

    private let logger = SDKLogger(category: "STTAnalytics")

    /// Active transcription operations
    private var activeTranscriptions: [String: TranscriptionTracker] = [:]

    /// Metrics
    private var transcriptionCount = 0
    private var totalConfidence: Float = 0
    private var totalLatency: TimeInterval = 0
    private let startTime = Date()
    private var lastEventTime: Date?

    // MARK: - Types

    private struct TranscriptionTracker {
        let id: String
        let startTime: Date
        let audioLengthMs: Double
        let language: String
    }

    // MARK: - Initialization

    public init() {}

    // MARK: - Transcription Tracking

    /// Start tracking a transcription
    public func startTranscription(audioLengthMs: Double, language: String) -> String {
        let id = UUID().uuidString
        activeTranscriptions[id] = TranscriptionTracker(
            id: id,
            startTime: Date(),
            audioLengthMs: audioLengthMs,
            language: language
        )

        EventPublisher.shared.track(STTEvent.transcriptionStarted(
            transcriptionId: id,
            audioLengthMs: audioLengthMs,
            language: language
        ))

        logger.debug("Transcription started: \(id)")
        return id
    }

    /// Track partial transcript
    public func trackPartialTranscript(text: String) {
        let wordCount = text.split(separator: " ").count
        EventPublisher.shared.track(STTEvent.partialTranscript(text: text, wordCount: wordCount))
    }

    /// Track final transcript
    public func trackFinalTranscript(text: String, confidence: Float) {
        EventPublisher.shared.track(STTEvent.finalTranscript(text: text, confidence: confidence))
    }

    /// Complete a transcription
    public func completeTranscription(
        transcriptionId: String,
        text: String,
        confidence: Float
    ) {
        guard let tracker = activeTranscriptions.removeValue(forKey: transcriptionId) else { return }

        let processingTimeMs = Date().timeIntervalSince(tracker.startTime) * 1000
        let wordCount = text.split(separator: " ").count

        // Update metrics
        transcriptionCount += 1
        totalConfidence += confidence
        totalLatency += processingTimeMs / 1000.0
        lastEventTime = Date()

        EventPublisher.shared.track(STTEvent.transcriptionCompleted(
            transcriptionId: transcriptionId,
            text: text,
            confidence: confidence,
            durationMs: processingTimeMs,
            audioLengthMs: tracker.audioLengthMs,
            wordCount: wordCount
        ))

        logger.debug("Transcription completed: \(transcriptionId)")
    }

    /// Track transcription failure
    public func trackTranscriptionFailed(
        transcriptionId: String,
        audioLengthMs: Double,
        processingTimeMs: Double,
        errorMessage: String
    ) {
        activeTranscriptions.removeValue(forKey: transcriptionId)
        lastEventTime = Date()

        EventPublisher.shared.track(STTEvent.transcriptionFailed(
            transcriptionId: transcriptionId,
            error: errorMessage
        ))
    }

    /// Track language detection (analytics only)
    public func trackLanguageDetection(language: String, confidence: Float) {
        EventPublisher.shared.track(STTEvent.languageDetected(
            language: language,
            confidence: confidence
        ))
    }

    /// Track speaker change (analytics only)
    public func trackSpeakerChange(from: String?, to: String) {
        EventPublisher.shared.track(STTEvent.speakerChanged(fromSpeaker: from, toSpeaker: to))
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

    public func getMetrics() -> STTMetrics {
        STTMetrics(
            totalEvents: transcriptionCount,
            startTime: startTime,
            lastEventTime: lastEventTime,
            totalTranscriptions: transcriptionCount,
            averageConfidence: transcriptionCount > 0 ? totalConfidence / Float(transcriptionCount) : 0,
            averageLatency: transcriptionCount > 0 ? totalLatency / Double(transcriptionCount) : 0
        )
    }
}

// MARK: - STT Metrics

public struct STTMetrics: AnalyticsMetrics {
    public let totalEvents: Int
    public let startTime: Date
    public let lastEventTime: Date?
    public let totalTranscriptions: Int
    public let averageConfidence: Float
    public let averageLatency: TimeInterval

    public init(
        totalEvents: Int = 0,
        startTime: Date = Date(),
        lastEventTime: Date? = nil,
        totalTranscriptions: Int = 0,
        averageConfidence: Float = 0,
        averageLatency: TimeInterval = 0
    ) {
        self.totalEvents = totalEvents
        self.startTime = startTime
        self.lastEventTime = lastEventTime
        self.totalTranscriptions = totalTranscriptions
        self.averageConfidence = averageConfidence
        self.averageLatency = averageLatency
    }
}
