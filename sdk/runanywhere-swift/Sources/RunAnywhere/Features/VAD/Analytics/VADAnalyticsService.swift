//
//  VADAnalyticsService.swift
//  RunAnywhere SDK
//
//  VAD analytics service - THIN WRAPPER over C++ rac_vad_analytics_*.
//  Delegates all state management and metrics calculation to C++.
//  Swift handles: type conversion, event emission, logging.
//

import CRACommons
import Foundation

// MARK: - VAD Analytics Service

/// VAD analytics service for tracking voice activity detection.
/// Thin wrapper over C++ rac_vad_analytics_* functions.
public actor VADAnalyticsService {

    // MARK: - Properties

    private let logger = SDKLogger(category: "VADAnalytics")
    private var handle: rac_vad_analytics_handle_t?
    private var currentFramework: InferenceFramework = .builtIn

    // MARK: - Initialization

    public init() {
        var analyticsHandle: rac_vad_analytics_handle_t?
        let result = rac_vad_analytics_create(&analyticsHandle)
        if result == RAC_SUCCESS {
            self.handle = analyticsHandle
        } else {
            logger.error("Failed to create VAD analytics handle: \(result)")
        }
    }

    deinit {
        if let analyticsHandle = handle {
            rac_vad_analytics_destroy(analyticsHandle)
        }
    }

    // MARK: - Lifecycle Tracking

    /// Track VAD initialization
    public func trackInitialized(framework: InferenceFramework) {
        currentFramework = framework
        guard let analyticsHandle = handle else { return }

        let cFramework = framework.toCFramework()
        _ = rac_vad_analytics_track_initialized(analyticsHandle, cFramework)

        EventPublisher.shared.track(VADEvent.initialized(framework: framework))
        logger.debug("VAD initialized with framework: \(framework.rawValue)")
    }

    /// Track VAD initialization failure
    public func trackInitializationFailed(error: Error, framework: InferenceFramework) {
        currentFramework = framework
        guard let analyticsHandle = handle else { return }

        let sdkError = SDKError.from(error, category: .vad)
        let errorCode = CommonsErrorMapping.fromSDKError(sdkError)
        let cFramework = framework.toCFramework()

        _ = sdkError.message.withCString { msgPtr in
            rac_vad_analytics_track_initialization_failed(analyticsHandle, errorCode, msgPtr, cFramework)
        }

        EventPublisher.shared.track(VADEvent.initializationFailed(
            error: sdkError,
            framework: framework
        ))
    }

    /// Track VAD cleanup
    public func trackCleanedUp() {
        guard let analyticsHandle = handle else { return }

        _ = rac_vad_analytics_track_cleaned_up(analyticsHandle)

        EventPublisher.shared.track(VADEvent.cleanedUp)
    }

    // MARK: - Detection Tracking

    /// Track VAD started
    public func trackStarted() {
        guard let analyticsHandle = handle else { return }

        _ = rac_vad_analytics_track_started(analyticsHandle)

        EventPublisher.shared.track(VADEvent.started)
    }

    /// Track VAD stopped
    public func trackStopped() {
        guard let analyticsHandle = handle else { return }

        _ = rac_vad_analytics_track_stopped(analyticsHandle)

        EventPublisher.shared.track(VADEvent.stopped)
    }

    /// Track speech detected (start of speech/voice activity)
    public func trackSpeechStart() {
        guard let analyticsHandle = handle else { return }

        _ = rac_vad_analytics_track_speech_start(analyticsHandle)

        EventPublisher.shared.track(VADEvent.speechStarted)
    }

    /// Track speech ended (silence detected after speech)
    public func trackSpeechEnd() {
        guard let analyticsHandle = handle else { return }

        _ = rac_vad_analytics_track_speech_end(analyticsHandle)

        // Get the speech duration from C++ metrics (it calculates this)
        var cMetrics = rac_vad_metrics_t()
        if rac_vad_analytics_get_metrics(analyticsHandle, &cMetrics) == RAC_SUCCESS {
            // C++ tracks the duration, we just emit the event
            // Note: For individual speech duration, we'd need C++ to provide per-segment info
            // For now, emit with 0 since C++ tracks aggregate
            EventPublisher.shared.track(VADEvent.speechEnded(durationMs: 0))
        } else {
            EventPublisher.shared.track(VADEvent.speechEnded(durationMs: 0))
        }
    }

    /// Track paused
    public func trackPaused() {
        guard let analyticsHandle = handle else { return }

        _ = rac_vad_analytics_track_paused(analyticsHandle)

        EventPublisher.shared.track(VADEvent.paused)
    }

    /// Track resumed
    public func trackResumed() {
        guard let analyticsHandle = handle else { return }

        _ = rac_vad_analytics_track_resumed(analyticsHandle)

        EventPublisher.shared.track(VADEvent.resumed)
    }

    // MARK: - Model Lifecycle (for model-based VAD)

    /// Track model load started (for model-based VAD like Silero)
    public func trackModelLoadStarted(modelId: String, modelSizeBytes: Int64 = 0, framework: InferenceFramework) {
        currentFramework = framework
        guard let analyticsHandle = handle else { return }

        let cFramework = framework.toCFramework()
        _ = modelId.withCString { idPtr in
            rac_vad_analytics_track_model_load_started(analyticsHandle, idPtr, modelSizeBytes, cFramework)
        }

        EventPublisher.shared.track(VADEvent.modelLoadStarted(
            modelId: modelId,
            modelSizeBytes: modelSizeBytes,
            framework: framework
        ))
    }

    /// Track model load completed
    public func trackModelLoadCompleted(modelId: String, durationMs: Double, modelSizeBytes: Int64 = 0) {
        guard let analyticsHandle = handle else { return }

        _ = modelId.withCString { idPtr in
            rac_vad_analytics_track_model_load_completed(analyticsHandle, idPtr, durationMs, modelSizeBytes)
        }

        EventPublisher.shared.track(VADEvent.modelLoadCompleted(
            modelId: modelId,
            durationMs: durationMs,
            modelSizeBytes: modelSizeBytes,
            framework: currentFramework
        ))
    }

    /// Track model load failed
    public func trackModelLoadFailed(modelId: String, error: Error) {
        guard let analyticsHandle = handle else { return }

        let sdkError = SDKError.from(error, category: .vad)
        let errorCode = CommonsErrorMapping.fromSDKError(sdkError)

        _ = modelId.withCString { idPtr in
            sdkError.message.withCString { msgPtr in
                rac_vad_analytics_track_model_load_failed(analyticsHandle, idPtr, errorCode, msgPtr)
            }
        }

        EventPublisher.shared.track(VADEvent.modelLoadFailed(
            modelId: modelId,
            error: sdkError,
            framework: currentFramework
        ))
    }

    /// Track model unloaded
    public func trackModelUnloaded(modelId: String) {
        guard let analyticsHandle = handle else { return }

        _ = modelId.withCString { idPtr in
            rac_vad_analytics_track_model_unloaded(analyticsHandle, idPtr)
        }

        EventPublisher.shared.track(VADEvent.modelUnloaded(modelId: modelId))
    }

    // MARK: - Metrics

    public func getMetrics() -> VADMetrics {
        guard let analyticsHandle = handle else {
            return VADMetrics()
        }

        var cMetrics = rac_vad_metrics_t()
        let result = rac_vad_analytics_get_metrics(analyticsHandle, &cMetrics)

        guard result == RAC_SUCCESS else {
            logger.error("Failed to get metrics: \(result)")
            return VADMetrics()
        }

        return VADMetrics(
            totalEvents: Int(cMetrics.total_events),
            startTime: Date(timeIntervalSince1970: Double(cMetrics.start_time_ms) / 1000.0),
            lastEventTime: cMetrics.last_event_time_ms > 0
                ? Date(timeIntervalSince1970: Double(cMetrics.last_event_time_ms) / 1000.0)
                : nil,
            totalSpeechSegments: Int(cMetrics.total_speech_segments),
            totalSpeechDurationMs: cMetrics.total_speech_duration_ms,
            averageSpeechDurationMs: cMetrics.average_speech_duration_ms,
            framework: InferenceFramework.fromCFramework(cMetrics.framework)
        )
    }
}

// Note: VADMetrics struct is defined in VADEvent.swift
