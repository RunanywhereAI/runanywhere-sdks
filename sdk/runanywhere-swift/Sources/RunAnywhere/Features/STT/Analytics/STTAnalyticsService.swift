//
//  STTAnalyticsService.swift
//  RunAnywhere SDK
//
//  STT-specific analytics service following unified pattern
//

import Foundation

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

    // Transcription tracking
    private var activeTranscriptions: [String: TranscriptionTracker] = [:]

    private struct TranscriptionTracker {
        let id: String
        let startTime: Date
        let audioLengthMs: Double
        let language: String
    }

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

    /// Start tracking a transcription operation
    public func startTranscription(
        transcriptionId: String? = nil,
        audioLengthMs: Double,
        language: String
    ) async -> String {
        let id = transcriptionId ?? UUID().uuidString

        let tracker = TranscriptionTracker(
            id: id,
            startTime: Date(),
            audioLengthMs: audioLengthMs,
            language: language
        )
        activeTranscriptions[id] = tracker

        let eventData = TranscriptionStartData(
            audioLengthMs: audioLengthMs,
            startTimestamp: Date().timeIntervalSince1970
        )
        let event = STTEvent(
            type: .transcriptionStarted,
            sessionId: currentSession?.id,
            eventData: eventData
        )
        await track(event: event)

        return id
    }

    /// Complete a transcription operation
    public func completeTranscription(
        transcriptionId: String,
        text: String,
        confidence: Float,
        speaker: String? = nil
    ) async {
        guard let tracker = activeTranscriptions[transcriptionId] else { return }

        let processingTimeMs = Date().timeIntervalSince(tracker.startTime) * 1000

        let eventData = STTTranscriptionData(
            wordCount: text.split(separator: " ").count,
            confidence: confidence,
            durationMs: processingTimeMs,
            audioLengthMs: tracker.audioLengthMs,
            realTimeFactor: processingTimeMs / tracker.audioLengthMs,
            speakerId: speaker ?? "unknown"
        )
        let event = STTEvent(
            type: .transcriptionCompleted,
            sessionId: currentSession?.id,
            eventData: eventData
        )
        await track(event: event)

        // Update metrics
        transcriptionCount += 1
        totalConfidence += confidence
        totalLatency += processingTimeMs / 1000.0

        // Clean up tracker
        activeTranscriptions.removeValue(forKey: transcriptionId)
    }

    /// Track a transcription completion (legacy method)
    public func trackTranscription(
        text: String,
        confidence: Float,
        duration: TimeInterval,
        audioLength: TimeInterval,
        speaker: String? = nil
    ) async {
        let eventData = STTTranscriptionData(
            wordCount: text.split(separator: " ").count,
            confidence: confidence,
            durationMs: duration * 1000,
            audioLengthMs: audioLength * 1000,
            realTimeFactor: duration / audioLength,
            speakerId: speaker ?? "unknown"
        )

        let event = STTEvent(
            type: .transcriptionCompleted,
            sessionId: currentSession?.id,
            eventData: eventData
        )

        await track(event: event)

        // Update metrics
        transcriptionCount += 1
        totalConfidence += confidence
        totalLatency += duration
    }

    /// Track speaker change
    public func trackSpeakerChange(from: String?, to: String) async {
        let eventData = SpeakerChangeData(
            fromSpeaker: from,
            toSpeaker: to,
            timestamp: Date().timeIntervalSince1970
        )
        let event = STTEvent(
            type: .speakerChanged,
            sessionId: currentSession?.id,
            eventData: eventData
        )
        await track(event: event)
    }

    /// Track language detection
    public func trackLanguageDetection(language: String, confidence: Float) async {
        let eventData = LanguageDetectionData(
            language: language,
            confidence: confidence
        )
        let event = STTEvent(
            type: .languageDetected,
            sessionId: currentSession?.id,
            eventData: eventData
        )
        await track(event: event)
    }

    /// Track transcription start (legacy method)
    public func trackTranscriptionStarted(audioLength: TimeInterval) async {
        let eventData = TranscriptionStartData(
            audioLengthMs: audioLength * 1000,
            startTimestamp: Date().timeIntervalSince1970
        )
        let event = STTEvent(
            type: .transcriptionStarted,
            sessionId: currentSession?.id,
            eventData: eventData
        )
        await track(event: event)
    }

    /// Track final transcript
    public func trackFinalTranscript(text: String, confidence: Float, speaker: String? = nil) async {
        let eventData = FinalTranscriptData(
            textLength: text.count,
            wordCount: text.split(separator: " ").count,
            confidence: confidence,
            speakerId: speaker ?? "unknown",
            timestamp: Date().timeIntervalSince1970
        )
        let event = STTEvent(
            type: .finalTranscript,
            sessionId: currentSession?.id,
            eventData: eventData
        )
        await track(event: event)
    }

    /// Track partial transcript
    public func trackPartialTranscript(text: String) async {
        let eventData = PartialTranscriptData(
            textLength: text.count,
            wordCount: text.split(separator: " ").count
        )
        let event = STTEvent(
            type: .partialTranscript,
            sessionId: currentSession?.id,
            eventData: eventData
        )
        await track(event: event)
    }

    /// Track speaker detection
    public func trackSpeakerDetection(speaker: String, confidence: Float) async {
        let eventData = SpeakerDetectionData(
            speakerId: speaker,
            confidence: confidence,
            timestamp: Date().timeIntervalSince1970
        )
        let event = STTEvent(
            type: .speakerDetected,
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
        let event = STTEvent(
            type: .error,
            sessionId: currentSession?.id,
            eventData: eventData
        )
        await track(event: event)
    }

    /// Track transcription failure
    public func trackTranscriptionFailed(
        transcriptionId: String,
        audioLengthMs: Double,
        processingTimeMs: Double,
        errorMessage: String
    ) async {
        let eventData = STTTranscriptionFailureData(
            transcriptionId: transcriptionId,
            audioLengthMs: audioLengthMs,
            processingTimeMs: processingTimeMs,
            errorMessage: errorMessage
        )
        let event = STTEvent(
            type: .error,
            sessionId: currentSession?.id,
            eventData: eventData
        )
        await track(event: event)

        // Clean up any active tracker
        activeTranscriptions.removeValue(forKey: transcriptionId)
    }

    /// Track model loading
    public func trackModelLoading(
        modelId: String,
        loadTime: TimeInterval,
        success: Bool
    ) async {
        let eventData = STTModelLoadingData(
            modelId: modelId,
            loadTimeMs: loadTime * 1000,
            success: success
        )
        let event = STTEvent(
            type: success ? .modelLoaded : .modelLoadFailed,
            sessionId: currentSession?.id,
            eventData: eventData
        )

        await track(event: event)
    }

    // MARK: - Private Methods

    private func processEvent(_ event: STTEvent) async {
        // Custom processing for STT events if needed
    }
}
