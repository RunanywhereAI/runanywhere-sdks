//
//  STTAnalyticsService.swift
//  RunAnywhere SDK
//
//  STT analytics service - THIN WRAPPER over C++ rac_stt_analytics_*.
//  Delegates all state management and metrics calculation to C++.
//  Swift handles: type conversion, event emission, logging.
//

import CRACommons
import Foundation

// MARK: - STT Analytics Service

/// STT analytics service for tracking transcription operations.
/// Thin wrapper over C++ rac_stt_analytics_* functions.
public actor STTAnalyticsService {

    // MARK: - Properties

    private let logger = SDKLogger(category: "STTAnalytics")
    private var handle: rac_stt_analytics_handle_t?

    // MARK: - Initialization

    public init() {
        var analyticsHandle: rac_stt_analytics_handle_t?
        let result = rac_stt_analytics_create(&analyticsHandle)
        if result == RAC_SUCCESS {
            self.handle = analyticsHandle
        } else {
            logger.error("Failed to create STT analytics handle: \(result)")
        }
    }

    deinit {
        if let analyticsHandle = handle {
            rac_stt_analytics_destroy(analyticsHandle)
        }
    }

    // MARK: - Transcription Tracking

    /// Start tracking a transcription
    public func startTranscription(
        modelId: String,
        audioLengthMs: Double,
        audioSizeBytes: Int,
        language: String,
        isStreaming: Bool = false,
        sampleRate: Int = Int(RAC_STT_DEFAULT_SAMPLE_RATE),
        framework: InferenceFramework = .unknown
    ) -> String {
        guard let analyticsHandle = handle else {
            logger.error("Analytics handle not initialized")
            return UUID().uuidString
        }

        var transcriptionIdPtr: UnsafeMutablePointer<CChar>?
        let cFramework = framework.toCFramework()

        let result = modelId.withCString { modelIdPtr in
            language.withCString { langPtr in
                rac_stt_analytics_start_transcription(
                    analyticsHandle,
                    modelIdPtr,
                    audioLengthMs,
                    Int32(audioSizeBytes),
                    langPtr,
                    isStreaming ? RAC_TRUE : RAC_FALSE,
                    Int32(sampleRate),
                    cFramework,
                    &transcriptionIdPtr
                )
            }
        }

        let transcriptionId: String
        if result == RAC_SUCCESS, let ptr = transcriptionIdPtr {
            transcriptionId = String(cString: ptr)
            rac_free(ptr)
        } else {
            transcriptionId = UUID().uuidString
            logger.error("Failed to start transcription in C++: \(result)")
        }

        // Emit Swift event
        EventPublisher.shared.track(STTEvent.transcriptionStarted(
            transcriptionId: transcriptionId,
            modelId: modelId,
            audioLengthMs: audioLengthMs,
            audioSizeBytes: audioSizeBytes,
            language: language,
            isStreaming: isStreaming,
            sampleRate: sampleRate,
            framework: framework
        ))

        logger.debug("Transcription started: \(transcriptionId), model: \(modelId)")
        return transcriptionId
    }

    /// Track partial transcript (for streaming transcription)
    public func trackPartialTranscript(text: String) {
        guard let analyticsHandle = handle else { return }

        _ = text.withCString { textPtr in
            rac_stt_analytics_track_partial_transcript(analyticsHandle, textPtr)
        }

        let wordCount = text.split(separator: " ").count
        EventPublisher.shared.track(STTEvent.partialTranscript(text: text, wordCount: wordCount))
    }

    /// Track final transcript (for streaming transcription)
    public func trackFinalTranscript(text: String, confidence: Float) {
        guard let analyticsHandle = handle else { return }

        _ = text.withCString { textPtr in
            rac_stt_analytics_track_final_transcript(analyticsHandle, textPtr, confidence)
        }

        EventPublisher.shared.track(STTEvent.finalTranscript(text: text, confidence: confidence))
    }

    /// Complete a transcription
    public func completeTranscription(
        transcriptionId: String,
        text: String,
        confidence: Float
    ) {
        guard let analyticsHandle = handle else { return }

        _ = transcriptionId.withCString { idPtr in
            text.withCString { textPtr in
                rac_stt_analytics_complete_transcription(analyticsHandle, idPtr, textPtr, confidence)
            }
        }

        logger.debug("Transcription completed: \(transcriptionId)")

        // Emit Swift event with basic info (C++ tracks detailed metrics)
        let wordCount = text.split(separator: " ").count
        EventPublisher.shared.track(STTEvent.transcriptionCompleted(
            transcriptionId: transcriptionId,
            modelId: "",  // C++ tracks this
            text: text,
            confidence: confidence,
            durationMs: 0,  // C++ calculates
            audioLengthMs: 0,  // C++ tracks
            audioSizeBytes: 0,  // C++ tracks
            wordCount: wordCount,
            realTimeFactor: 0,  // C++ calculates
            language: "",  // C++ tracks
            isStreaming: false,  // C++ tracks
            sampleRate: Int(RAC_STT_DEFAULT_SAMPLE_RATE),
            framework: .unknown
        ))
    }

    /// Track transcription failure
    public func trackTranscriptionFailed(
        transcriptionId: String,
        error: Error
    ) {
        guard let analyticsHandle = handle else { return }

        let sdkError = SDKError.from(error, category: .stt)
        let errorCode = CommonsErrorMapping.fromSDKError(sdkError)

        _ = transcriptionId.withCString { idPtr in
            sdkError.message.withCString { msgPtr in
                rac_stt_analytics_track_transcription_failed(analyticsHandle, idPtr, errorCode, msgPtr)
            }
        }

        EventPublisher.shared.track(STTEvent.transcriptionFailed(
            transcriptionId: transcriptionId,
            modelId: "unknown",
            error: sdkError
        ))
    }

    /// Track language detection (analytics only)
    public func trackLanguageDetection(language: String, confidence: Float) {
        guard let analyticsHandle = handle else { return }

        _ = language.withCString { langPtr in
            rac_stt_analytics_track_language_detection(analyticsHandle, langPtr, confidence)
        }

        EventPublisher.shared.track(STTEvent.languageDetected(
            language: language,
            confidence: confidence
        ))
    }

    /// Track an error during STT operations
    public func trackError(_ error: Error, operation: String, modelId: String? = nil, transcriptionId: String? = nil) {
        guard let analyticsHandle = handle else { return }

        let sdkError = SDKError.from(error, category: .stt)
        let errorCode = CommonsErrorMapping.fromSDKError(sdkError)

        _ = operation.withCString { opPtr in
            sdkError.message.withCString { msgPtr in
                rac_stt_analytics_track_error(
                    analyticsHandle,
                    errorCode,
                    msgPtr,
                    opPtr,
                    modelId,
                    transcriptionId
                )
            }
        }

        let errorEvent = SDKErrorEvent.sttError(
            error: sdkError,
            modelId: modelId,
            transcriptionId: transcriptionId,
            operation: operation
        )
        EventPublisher.shared.track(errorEvent)
    }

    // MARK: - Metrics

    public func getMetrics() -> STTMetrics {
        guard let analyticsHandle = handle else {
            return STTMetrics()
        }

        var cMetrics = rac_stt_metrics_t()
        let result = rac_stt_analytics_get_metrics(analyticsHandle, &cMetrics)

        guard result == RAC_SUCCESS else {
            logger.error("Failed to get metrics: \(result)")
            return STTMetrics()
        }

        return STTMetrics(
            totalEvents: Int(cMetrics.total_events),
            startTime: Date(timeIntervalSince1970: Double(cMetrics.start_time_ms) / 1000.0),
            lastEventTime: cMetrics.last_event_time_ms > 0
                ? Date(timeIntervalSince1970: Double(cMetrics.last_event_time_ms) / 1000.0)
                : nil,
            totalTranscriptions: Int(cMetrics.total_transcriptions),
            averageConfidence: cMetrics.average_confidence,
            averageLatency: cMetrics.average_latency_ms / 1000.0,  // Convert ms to seconds
            averageRealTimeFactor: cMetrics.average_real_time_factor,
            totalAudioProcessedMs: cMetrics.total_audio_processed_ms
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
