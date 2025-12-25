//
//  STTAnalyticsService.swift
//  RunAnywhere SDK
//
//  STT analytics service.
//  Tracks transcription operations and metrics.
//  Lifecycle events are handled by ManagedLifecycle.
//
//  NOTE: ⚠️ Audio length estimation assumes 16-bit PCM @ 16kHz (standard for STT).
//  Formula: audioLengthMs = (bytes / 2) / 16000 * 1000
//
//  NOTE: ⚠️ Real-Time Factor (RTF) will be 0 or undefined for streaming transcription
//  since audioLengthMs = 0 when audio is processed in chunks of unknown total length.
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
    private var totalAudioProcessed: Double = 0  // Total audio length in ms
    private var totalRealTimeFactor: Double = 0
    private let startTime = Date()
    private var lastEventTime: Date?

    // MARK: - Types

    private struct TranscriptionTracker {
        let startTime: Date
        let modelId: String
        let audioLengthMs: Double
        let audioSizeBytes: Int
        let language: String
        let isStreaming: Bool
        let sampleRate: Int
        let framework: InferenceFrameworkType
    }

    // MARK: - Initialization

    public init() {}

    // MARK: - Transcription Tracking

    /// Start tracking a transcription
    /// - Parameters:
    ///   - modelId: The STT model identifier
    ///   - audioLengthMs: Duration of audio in milliseconds
    ///   - audioSizeBytes: Size of audio data in bytes
    ///   - language: Language code for transcription
    ///   - isStreaming: Whether this is a streaming transcription
    ///   - sampleRate: Audio sample rate in Hz (default: STTConstants.defaultSampleRate)
    ///   - framework: The inference framework being used
    /// - Returns: A unique transcription ID for tracking
    public func startTranscription(
        modelId: String,
        audioLengthMs: Double,
        audioSizeBytes: Int,
        language: String,
        isStreaming: Bool = false,
        sampleRate: Int = STTConstants.defaultSampleRate,
        framework: InferenceFrameworkType = .unknown
    ) -> String {
        let id = UUID().uuidString
        activeTranscriptions[id] = TranscriptionTracker(
            startTime: Date(),
            modelId: modelId,
            audioLengthMs: audioLengthMs,
            audioSizeBytes: audioSizeBytes,
            language: language,
            isStreaming: isStreaming,
            sampleRate: sampleRate,
            framework: framework
        )

        EventPublisher.shared.track(STTEvent.transcriptionStarted(
            transcriptionId: id,
            modelId: modelId,
            audioLengthMs: audioLengthMs,
            audioSizeBytes: audioSizeBytes,
            language: language,
            isStreaming: isStreaming,
            sampleRate: sampleRate,
            framework: framework
        ))

        logger.debug("Transcription started: \(id), model: \(modelId), audio: \(String(format: "%.1f", audioLengthMs))ms, \(audioSizeBytes) bytes")
        return id
    }

    /// Track partial transcript (for streaming transcription)
    public func trackPartialTranscript(text: String) {
        let wordCount = text.split(separator: " ").count
        EventPublisher.shared.track(STTEvent.partialTranscript(text: text, wordCount: wordCount))
    }

    /// Track final transcript (for streaming transcription)
    public func trackFinalTranscript(text: String, confidence: Float) {
        EventPublisher.shared.track(STTEvent.finalTranscript(text: text, confidence: confidence))
    }

    /// Complete a transcription
    /// - Parameters:
    ///   - transcriptionId: The transcription ID from startTranscription
    ///   - text: The transcribed text
    ///   - confidence: Confidence score (0.0 to 1.0)
    public func completeTranscription(
        transcriptionId: String,
        text: String,
        confidence: Float
    ) {
        guard let tracker = activeTranscriptions.removeValue(forKey: transcriptionId) else { return }

        let endTime = Date()
        let processingTimeMs = endTime.timeIntervalSince(tracker.startTime) * 1000
        let wordCount = text.split(separator: " ").count

        // Calculate real-time factor (RTF): processing time / audio length
        // RTF < 1.0 means faster than real-time
        let realTimeFactor = tracker.audioLengthMs > 0 ? processingTimeMs / tracker.audioLengthMs : 0

        // Update metrics
        transcriptionCount += 1
        totalConfidence += confidence
        totalLatency += processingTimeMs / 1000.0
        totalAudioProcessed += tracker.audioLengthMs
        totalRealTimeFactor += realTimeFactor
        lastEventTime = endTime

        EventPublisher.shared.track(STTEvent.transcriptionCompleted(
            transcriptionId: transcriptionId,
            modelId: tracker.modelId,
            text: text,
            confidence: confidence,
            durationMs: processingTimeMs,
            audioLengthMs: tracker.audioLengthMs,
            audioSizeBytes: tracker.audioSizeBytes,
            wordCount: wordCount,
            realTimeFactor: realTimeFactor,
            language: tracker.language,
            isStreaming: tracker.isStreaming,
            sampleRate: tracker.sampleRate,
            framework: tracker.framework
        ))

        logger.debug("Transcription completed: \(transcriptionId), model: \(tracker.modelId), RTF: \(String(format: "%.3f", realTimeFactor))")
    }

    /// Track transcription failure
    public func trackTranscriptionFailed(
        transcriptionId: String,
        errorMessage: String
    ) {
        let tracker = activeTranscriptions.removeValue(forKey: transcriptionId)
        lastEventTime = Date()

        EventPublisher.shared.track(STTEvent.transcriptionFailed(
            transcriptionId: transcriptionId,
            modelId: tracker?.modelId ?? "unknown",
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
        // Average RTF only if we have transcriptions
        let avgRTF = transcriptionCount > 0 ? totalRealTimeFactor / Double(transcriptionCount) : 0

        return STTMetrics(
            totalEvents: transcriptionCount,
            startTime: startTime,
            lastEventTime: lastEventTime,
            totalTranscriptions: transcriptionCount,
            averageConfidence: transcriptionCount > 0 ? totalConfidence / Float(transcriptionCount) : 0,
            averageLatency: transcriptionCount > 0 ? totalLatency / Double(transcriptionCount) : 0,
            averageRealTimeFactor: avgRTF,
            totalAudioProcessedMs: totalAudioProcessed
        )
    }
}

// MARK: - STT Metrics

public struct STTMetrics: AnalyticsMetrics {
    public let totalEvents: Int
    public let startTime: Date
    public let lastEventTime: Date?
    public let totalTranscriptions: Int

    /// Average confidence score across all transcriptions (0.0 to 1.0)
    public let averageConfidence: Float

    /// Average processing latency in seconds
    public let averageLatency: TimeInterval

    /// Average real-time factor (processing time / audio length)
    /// - Note: Values < 1.0 indicate faster-than-real-time processing
    public let averageRealTimeFactor: Double

    /// Total audio processed in milliseconds
    public let totalAudioProcessedMs: Double

    public init(
        totalEvents: Int = 0,
        startTime: Date = Date(),
        lastEventTime: Date? = nil,
        totalTranscriptions: Int = 0,
        averageConfidence: Float = 0,
        averageLatency: TimeInterval = 0,
        averageRealTimeFactor: Double = 0,
        totalAudioProcessedMs: Double = 0
    ) {
        self.totalEvents = totalEvents
        self.startTime = startTime
        self.lastEventTime = lastEventTime
        self.totalTranscriptions = totalTranscriptions
        self.averageConfidence = averageConfidence
        self.averageLatency = averageLatency
        self.averageRealTimeFactor = averageRealTimeFactor
        self.totalAudioProcessedMs = totalAudioProcessedMs
    }
}
