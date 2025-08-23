//
//  STTAnalyticsService.swift
//  RunAnywhere SDK
//
//  STT-specific analytics service following unified pattern
//

import Foundation

// MARK: - STT Event

/// STT-specific analytics event
public struct STTEvent: AnalyticsEvent {
    public let id: String
    public let type: String
    public let timestamp: Date
    public let sessionId: String?
    public let properties: [String: String]

    public init(
        type: STTEventType,
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

/// STT event types
public enum STTEventType: String {
    case transcriptionStarted = "stt_transcription_started"
    case transcriptionCompleted = "stt_transcription_completed"
    case partialTranscript = "stt_partial_transcript"
    case finalTranscript = "stt_final_transcript"
    case speakerDetected = "stt_speaker_detected"
    case speakerChanged = "stt_speaker_changed"
    case languageDetected = "stt_language_detected"
    case error = "stt_error"
}

// MARK: - STT Metrics

/// STT-specific metrics
public struct STTMetrics: AnalyticsMetrics {
    public let totalEvents: Int
    public let startTime: Date
    public let lastEventTime: Date?
    public let totalTranscriptions: Int
    public let averageConfidence: Float
    public let averageLatency: TimeInterval

    public init() {
        self.totalEvents = 0
        self.startTime = Date()
        self.lastEventTime = nil
        self.totalTranscriptions = 0
        self.averageConfidence = 0
        self.averageLatency = 0
    }
}

// MARK: - STT Analytics Service

/// STT analytics service using unified pattern
public actor STTAnalyticsService: AnalyticsService {

    // MARK: - Type Aliases
    public typealias Event = STTEvent
    public typealias Metrics = STTMetrics

    // MARK: - Properties

    private let queueManager: AnalyticsQueueManager
    private let logger: SDKLogger
    private var currentSession: SessionInfo?
    private var events: [STTEvent] = []

    private struct SessionInfo {
        let id: String
        let modelId: String?
        let startTime: Date
    }

    private var metrics = STTMetrics()
    private var transcriptionCount = 0
    private var totalConfidence: Float = 0
    private var totalLatency: TimeInterval = 0

    // MARK: - Initialization

    public init(queueManager: AnalyticsQueueManager = .shared) {
        self.queueManager = queueManager
        self.logger = SDKLogger(category: "STTAnalytics")
    }

    // MARK: - Analytics Service Protocol

    public func track(event: STTEvent) async {
        events.append(event)
        await queueManager.enqueue(event)
        await processEvent(event)
    }

    public func trackBatch(events: [STTEvent]) async {
        self.events.append(contentsOf: events)
        await queueManager.enqueueBatch(events)
        for event in events {
            await processEvent(event)
        }
    }

    public func getMetrics() async -> STTMetrics {
        return STTMetrics(
            totalEvents: events.count,
            startTime: metrics.startTime,
            lastEventTime: events.last?.timestamp,
            totalTranscriptions: transcriptionCount,
            averageConfidence: transcriptionCount > 0 ? totalConfidence / Float(transcriptionCount) : 0,
            averageLatency: transcriptionCount > 0 ? totalLatency / Double(transcriptionCount) : 0
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

    // MARK: - STT-Specific Methods

    /// Track a transcription completion
    public func trackTranscription(
        text: String,
        confidence: Float,
        duration: TimeInterval,
        audioLength: TimeInterval,
        speaker: String? = nil
    ) async {
        let properties: [String: String] = [
            "word_count": String(text.split(separator: " ").count),
            "confidence": String(confidence),
            "duration_ms": String(duration * 1000),
            "audio_length_ms": String(audioLength * 1000),
            "real_time_factor": String(duration / audioLength),
            "speaker_id": speaker ?? "unknown"
        ]

        let event = STTEvent(
            type: .transcriptionCompleted,
            sessionId: currentSession?.id,
            properties: properties
        )

        await track(event: event)

        // Update metrics
        transcriptionCount += 1
        totalConfidence += confidence
        totalLatency += duration
    }

    /// Track speaker change
    public func trackSpeakerChange(from: String?, to: String) async {
        let event = STTEvent(
            type: .speakerChanged,
            sessionId: currentSession?.id,
            properties: [
                "from_speaker": from ?? "none",
                "to_speaker": to,
                "timestamp": String(Date().timeIntervalSince1970)
            ]
        )
        await track(event: event)
    }

    /// Track language detection
    public func trackLanguageDetection(language: String, confidence: Float) async {
        let event = STTEvent(
            type: .languageDetected,
            sessionId: currentSession?.id,
            properties: [
                "language": language,
                "confidence": String(confidence)
            ]
        )
        await track(event: event)
    }

    /// Track partial transcript
    public func trackPartialTranscript(text: String) async {
        let event = STTEvent(
            type: .partialTranscript,
            sessionId: currentSession?.id,
            properties: [
                "text_length": String(text.count),
                "word_count": String(text.split(separator: " ").count)
            ]
        )
        await track(event: event)
    }

    /// Track error
    public func trackError(error: Error, context: String) async {
        let event = STTEvent(
            type: .error,
            sessionId: currentSession?.id,
            properties: [
                "error": error.localizedDescription,
                "context": context
            ]
        )
        await track(event: event)
    }

    // MARK: - Private Methods

    private func processEvent(_ event: STTEvent) async {
        // Custom processing for STT events if needed
        // This is called after each event is tracked
    }
}
