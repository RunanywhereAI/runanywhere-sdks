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

    // MARK: - Enterprise Telemetry Methods

    /// Track STT model load with full enterprise metrics
    public func trackModelLoad(
        modelId: String,
        modelName: String,
        framework: InferenceFramework,
        loadTimeMs: Double,
        modelSizeBytes: Int64? = nil,
        success: Bool,
        errorMessage: String? = nil
    ) async {
        let deviceInfo = TelemetryDeviceInfo.current
        let telemetryService = await ServiceContainer.shared.telemetryService

        do {
            try await telemetryService.trackSTTModelLoad(
                modelId: modelId,
                modelName: modelName,
                framework: framework.rawValue,
                loadTimeMs: loadTimeMs,
                modelSizeBytes: modelSizeBytes,
                device: deviceInfo.device,
                osVersion: deviceInfo.osVersion,
                success: success,
                errorMessage: errorMessage
            )
            logger.debug("Tracked STT model load: \(modelName)")
        } catch {
            logger.error("Failed to track STT model load: \(error)")
        }
    }

    /// Track STT transcription start with full enterprise metrics
    public func trackTranscriptionStarted(
        sessionId: String,
        modelId: String,
        modelName: String,
        framework: InferenceFramework,
        language: String
    ) async {
        let deviceInfo = TelemetryDeviceInfo.current
        let telemetryService = await ServiceContainer.shared.telemetryService

        do {
            try await telemetryService.trackSTTTranscriptionStarted(
                sessionId: sessionId,
                modelId: modelId,
                modelName: modelName,
                framework: framework.rawValue,
                language: language,
                device: deviceInfo.device,
                osVersion: deviceInfo.osVersion
            )
            logger.debug("Tracked STT transcription started: \(sessionId)")
        } catch {
            logger.error("Failed to track STT transcription started: \(error)")
        }
    }

    /// Track STT transcription completion with full enterprise metrics
    public func trackTranscriptionCompleted(
        sessionId: String,
        modelId: String,
        modelName: String,
        framework: InferenceFramework,
        language: String,
        audioDurationMs: Double,
        processingTimeMs: Double,
        wordCount: Int,
        characterCount: Int,
        confidence: Float
    ) async {
        let deviceInfo = TelemetryDeviceInfo.current
        let telemetryService = await ServiceContainer.shared.telemetryService

        // Calculate real-time factor (< 1.0 means faster than real-time)
        let realTimeFactor = audioDurationMs > 0 ? processingTimeMs / audioDurationMs : 0

        do {
            try await telemetryService.trackSTTTranscriptionCompleted(
                sessionId: sessionId,
                modelId: modelId,
                modelName: modelName,
                framework: framework.rawValue,
                language: language,
                audioDurationMs: audioDurationMs,
                processingTimeMs: processingTimeMs,
                realTimeFactor: realTimeFactor,
                wordCount: wordCount,
                characterCount: characterCount,
                confidence: confidence,
                device: deviceInfo.device,
                osVersion: deviceInfo.osVersion
            )
            logger.debug("Tracked STT transcription completed: \(sessionId), RTF: \(String(format: "%.3f", realTimeFactor))")
        } catch {
            logger.error("Failed to track STT transcription completed: \(error)")
        }

        // Also update local metrics
        transcriptionCount += 1
        totalConfidence += confidence
        totalLatency += processingTimeMs / 1000.0
    }

    /// Track STT transcription failure with full enterprise metrics
    public func trackTranscriptionFailed(
        sessionId: String,
        modelId: String,
        modelName: String,
        framework: InferenceFramework,
        language: String,
        audioDurationMs: Double,
        processingTimeMs: Double,
        errorMessage: String
    ) async {
        let deviceInfo = TelemetryDeviceInfo.current
        let telemetryService = await ServiceContainer.shared.telemetryService

        do {
            try await telemetryService.trackSTTTranscriptionFailed(
                sessionId: sessionId,
                modelId: modelId,
                modelName: modelName,
                framework: framework.rawValue,
                language: language,
                audioDurationMs: audioDurationMs,
                processingTimeMs: processingTimeMs,
                errorMessage: errorMessage,
                device: deviceInfo.device,
                osVersion: deviceInfo.osVersion
            )
            logger.debug("Tracked STT transcription failed: \(sessionId)")
        } catch {
            logger.error("Failed to track STT transcription failed: \(error)")
        }

        // Clean up any active tracker
        activeTranscriptions.removeValue(forKey: sessionId)
    }

    /// Track STT streaming update for real-time transcription
    public func trackStreamingUpdate(
        sessionId: String,
        modelId: String,
        framework: InferenceFramework,
        partialWordCount: Int,
        elapsedMs: Double
    ) async {
        let telemetryService = await ServiceContainer.shared.telemetryService

        do {
            try await telemetryService.trackSTTStreamingUpdate(
                sessionId: sessionId,
                modelId: modelId,
                framework: framework.rawValue,
                partialWordCount: partialWordCount,
                elapsedMs: elapsedMs
            )
        } catch {
            logger.error("Failed to track STT streaming update: \(error)")
        }
    }

    // MARK: - Private Methods

    private func processEvent(_ event: STTEvent) async {
        // Custom processing for STT events if needed
    }
}
