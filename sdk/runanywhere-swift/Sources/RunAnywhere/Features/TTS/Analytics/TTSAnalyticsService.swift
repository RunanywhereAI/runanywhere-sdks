//
//  TTSAnalyticsService.swift
//  RunAnywhere SDK
//
//  TTS analytics service - THIN WRAPPER over C++ rac_tts_analytics_*.
//  Delegates all state management and metrics calculation to C++.
//  Swift handles: type conversion, event emission, logging.
//

import CRACommons
import Foundation

// MARK: - TTS Analytics Service

/// TTS analytics service for tracking synthesis operations.
/// Thin wrapper over C++ rac_tts_analytics_* functions.
public actor TTSAnalyticsService {

    // MARK: - Properties

    private let logger = SDKLogger(category: "TTSAnalytics")
    private var handle: rac_tts_analytics_handle_t?

    // MARK: - Initialization

    public init() {
        var analyticsHandle: rac_tts_analytics_handle_t?
        let result = rac_tts_analytics_create(&analyticsHandle)
        if result == RAC_SUCCESS {
            self.handle = analyticsHandle
        } else {
            logger.error("Failed to create TTS analytics handle: \(result)")
        }
    }

    deinit {
        if let analyticsHandle = handle {
            rac_tts_analytics_destroy(analyticsHandle)
        }
    }

    // MARK: - Synthesis Tracking

    /// Start tracking a synthesis
    public func startSynthesis(
        text: String,
        voice: String,
        sampleRate: Int = Int(RAC_TTS_DEFAULT_SAMPLE_RATE),
        framework: InferenceFramework = .unknown
    ) -> String {
        guard let analyticsHandle = handle else {
            logger.error("Analytics handle not initialized")
            return UUID().uuidString
        }

        var synthesisIdPtr: UnsafeMutablePointer<CChar>?
        let cFramework = framework.toCFramework()
        let characterCount = text.count

        let result = text.withCString { textPtr in
            voice.withCString { voicePtr in
                rac_tts_analytics_start_synthesis(
                    analyticsHandle,
                    textPtr,
                    voicePtr,
                    Int32(sampleRate),
                    cFramework,
                    &synthesisIdPtr
                )
            }
        }

        let synthesisId: String
        if result == RAC_SUCCESS, let ptr = synthesisIdPtr {
            synthesisId = String(cString: ptr)
            rac_free(ptr)
        } else {
            synthesisId = UUID().uuidString
            logger.error("Failed to start synthesis in C++: \(result)")
        }

        // Emit Swift event
        EventPublisher.shared.track(TTSEvent.synthesisStarted(
            synthesisId: synthesisId,
            modelId: voice,
            characterCount: characterCount,
            sampleRate: sampleRate,
            framework: framework
        ))

        logger.debug("Synthesis started: \(synthesisId), voice: \(voice), \(characterCount) characters")
        return synthesisId
    }

    /// Track synthesis chunk (analytics only, for streaming synthesis)
    public func trackSynthesisChunk(synthesisId: String, chunkSize: Int) {
        guard let analyticsHandle = handle else { return }

        _ = synthesisId.withCString { idPtr in
            rac_tts_analytics_track_synthesis_chunk(analyticsHandle, idPtr, Int32(chunkSize))
        }

        EventPublisher.shared.track(TTSEvent.synthesisChunk(
            synthesisId: synthesisId,
            chunkSize: chunkSize
        ))
    }

    /// Complete a synthesis
    public func completeSynthesis(
        synthesisId: String,
        audioDurationMs: Double,
        audioSizeBytes: Int
    ) {
        guard let analyticsHandle = handle else { return }

        _ = synthesisId.withCString { idPtr in
            rac_tts_analytics_complete_synthesis(analyticsHandle, idPtr, audioDurationMs, Int32(audioSizeBytes))
        }

        logger.debug("Synthesis completed: \(synthesisId)")

        // Emit Swift event with basic info (C++ tracks detailed metrics)
        EventPublisher.shared.track(TTSEvent.synthesisCompleted(
            synthesisId: synthesisId,
            modelId: "",  // C++ tracks this
            characterCount: 0,  // C++ tracks this
            audioDurationMs: audioDurationMs,
            audioSizeBytes: audioSizeBytes,
            processingDurationMs: 0,  // C++ calculates
            charactersPerSecond: 0,  // C++ calculates
            sampleRate: Int(RAC_TTS_DEFAULT_SAMPLE_RATE),
            framework: .unknown
        ))
    }

    /// Track synthesis failure
    public func trackSynthesisFailed(
        synthesisId: String,
        error: Error
    ) {
        guard let analyticsHandle = handle else { return }

        let sdkError = SDKError.from(error, category: .tts)
        let errorCode = CommonsErrorMapping.fromSDKError(sdkError)

        _ = synthesisId.withCString { idPtr in
            sdkError.message.withCString { msgPtr in
                rac_tts_analytics_track_synthesis_failed(analyticsHandle, idPtr, errorCode, msgPtr)
            }
        }

        EventPublisher.shared.track(TTSEvent.synthesisFailed(
            synthesisId: synthesisId,
            modelId: "unknown",
            error: sdkError
        ))
    }

    /// Track an error during TTS operations
    public func trackError(_ error: Error, operation: String, modelId: String? = nil, synthesisId: String? = nil) {
        guard let analyticsHandle = handle else { return }

        let sdkError = SDKError.from(error, category: .tts)
        let errorCode = CommonsErrorMapping.fromSDKError(sdkError)

        _ = operation.withCString { opPtr in
            sdkError.message.withCString { msgPtr in
                rac_tts_analytics_track_error(
                    analyticsHandle,
                    errorCode,
                    msgPtr,
                    opPtr,
                    modelId,
                    synthesisId
                )
            }
        }

        let errorEvent = SDKErrorEvent.ttsError(
            error: sdkError,
            modelId: modelId,
            synthesisId: synthesisId,
            operation: operation
        )
        EventPublisher.shared.track(errorEvent)
    }

    // MARK: - Metrics

    public func getMetrics() -> TTSMetrics {
        guard let analyticsHandle = handle else {
            return TTSMetrics()
        }

        var cMetrics = rac_tts_metrics_t()
        let result = rac_tts_analytics_get_metrics(analyticsHandle, &cMetrics)

        guard result == RAC_SUCCESS else {
            logger.error("Failed to get metrics: \(result)")
            return TTSMetrics()
        }

        return TTSMetrics(
            totalEvents: Int(cMetrics.total_events),
            startTime: Date(timeIntervalSince1970: Double(cMetrics.start_time_ms) / 1000.0),
            lastEventTime: cMetrics.last_event_time_ms > 0
                ? Date(timeIntervalSince1970: Double(cMetrics.last_event_time_ms) / 1000.0)
                : nil,
            totalSyntheses: Int(cMetrics.total_syntheses),
            averageCharactersPerSecond: cMetrics.average_characters_per_second,
            averageProcessingTimeMs: cMetrics.average_processing_time_ms,
            averageAudioDurationMs: cMetrics.average_audio_duration_ms,
            totalCharactersProcessed: Int(cMetrics.total_characters_processed),
            totalAudioSizeBytes: cMetrics.total_audio_size_bytes
        )
    }
}

// MARK: - TTS Metrics

public struct TTSMetrics: AnalyticsMetrics {
    public let totalEvents: Int
    public let startTime: Date
    public let lastEventTime: Date?
    public let totalSyntheses: Int

    /// Average synthesis speed (characters processed per second)
    public let averageCharactersPerSecond: Double

    /// Average processing time in milliseconds
    public let averageProcessingTimeMs: Double

    /// Average audio duration in milliseconds
    public let averageAudioDurationMs: Double

    /// Total characters processed across all syntheses
    public let totalCharactersProcessed: Int

    /// Total audio size generated in bytes
    public let totalAudioSizeBytes: Int64

    public init(
        totalEvents: Int = 0,
        startTime: Date = Date(),
        lastEventTime: Date? = nil,
        totalSyntheses: Int = 0,
        averageCharactersPerSecond: Double = 0,
        averageProcessingTimeMs: Double = 0,
        averageAudioDurationMs: Double = 0,
        totalCharactersProcessed: Int = 0,
        totalAudioSizeBytes: Int64 = 0
    ) {
        self.totalEvents = totalEvents
        self.startTime = startTime
        self.lastEventTime = lastEventTime
        self.totalSyntheses = totalSyntheses
        self.averageCharactersPerSecond = averageCharactersPerSecond
        self.averageProcessingTimeMs = averageProcessingTimeMs
        self.averageAudioDurationMs = averageAudioDurationMs
        self.totalCharactersProcessed = totalCharactersProcessed
        self.totalAudioSizeBytes = totalAudioSizeBytes
    }
}
