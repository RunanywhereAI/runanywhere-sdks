//
//  VADAnalyticsService.swift
//  RunAnywhere SDK
//
//  VAD analytics service.
//  Tracks VAD operations and metrics.
//

import Foundation

// MARK: - VAD Analytics Service

/// VAD analytics service for tracking voice activity detection.
public actor VADAnalyticsService {

    // MARK: - Properties

    private let logger = SDKLogger(category: "VADAnalytics")

    /// Current framework being used
    private var currentFramework: InferenceFrameworkType = .builtIn

    /// Speech segment tracking
    private var speechStartTime: Date?

    /// Metrics
    private var totalSpeechSegments = 0
    private var totalSpeechDurationMs: Double = 0
    private let startTime = Date()
    private var lastEventTime: Date?

    // MARK: - Initialization

    public init() {}

    // MARK: - Lifecycle Tracking

    /// Track VAD initialization
    public func trackInitialized(framework: InferenceFrameworkType) {
        currentFramework = framework
        lastEventTime = Date()

        EventPublisher.shared.track(VADEvent.initialized(framework: framework))
        logger.debug("VAD initialized with framework: \(framework.rawValue)")
    }

    /// Track VAD initialization failure
    public func trackInitializationFailed(error: String, framework: InferenceFrameworkType) {
        currentFramework = framework
        lastEventTime = Date()

        EventPublisher.shared.track(VADEvent.initializationFailed(error: error, framework: framework))
    }

    /// Track VAD cleanup
    public func trackCleanedUp() {
        lastEventTime = Date()
        EventPublisher.shared.track(VADEvent.cleanedUp)
    }

    // MARK: - Detection Tracking

    /// Track VAD started
    public func trackStarted() {
        lastEventTime = Date()
        EventPublisher.shared.track(VADEvent.started)
    }

    /// Track VAD stopped
    public func trackStopped() {
        lastEventTime = Date()
        EventPublisher.shared.track(VADEvent.stopped)
    }

    /// Track speech detected (start of speech/voice activity)
    public func trackSpeechStart() {
        speechStartTime = Date()
        lastEventTime = Date()

        EventPublisher.shared.track(VADEvent.speechStarted)
    }

    /// Track speech ended (silence detected after speech)
    public func trackSpeechEnd() {
        guard let startTime = speechStartTime else { return }

        let endTime = Date()
        let durationMs = endTime.timeIntervalSince(startTime) * 1000
        speechStartTime = nil

        // Update metrics
        totalSpeechSegments += 1
        totalSpeechDurationMs += durationMs
        lastEventTime = endTime

        EventPublisher.shared.track(VADEvent.speechEnded(durationMs: durationMs))
    }

    /// Track paused
    public func trackPaused() {
        lastEventTime = Date()
        EventPublisher.shared.track(VADEvent.paused)
    }

    /// Track resumed
    public func trackResumed() {
        lastEventTime = Date()
        EventPublisher.shared.track(VADEvent.resumed)
    }

    // MARK: - Model Lifecycle (for model-based VAD)

    /// Track model load started (for model-based VAD like Silero)
    public func trackModelLoadStarted(modelId: String, modelSizeBytes: Int64 = 0, framework: InferenceFrameworkType) {
        currentFramework = framework
        lastEventTime = Date()

        EventPublisher.shared.track(VADEvent.modelLoadStarted(
            modelId: modelId,
            modelSizeBytes: modelSizeBytes,
            framework: framework
        ))
    }

    /// Track model load completed
    public func trackModelLoadCompleted(modelId: String, durationMs: Double, modelSizeBytes: Int64 = 0) {
        lastEventTime = Date()

        EventPublisher.shared.track(VADEvent.modelLoadCompleted(
            modelId: modelId,
            durationMs: durationMs,
            modelSizeBytes: modelSizeBytes,
            framework: currentFramework
        ))
    }

    /// Track model load failed
    public func trackModelLoadFailed(modelId: String, error: String) {
        lastEventTime = Date()

        EventPublisher.shared.track(VADEvent.modelLoadFailed(
            modelId: modelId,
            error: error,
            framework: currentFramework
        ))
    }

    /// Track model unloaded
    public func trackModelUnloaded(modelId: String) {
        lastEventTime = Date()

        EventPublisher.shared.track(VADEvent.modelUnloaded(modelId: modelId))
    }

    // MARK: - Metrics

    public func getMetrics() -> VADMetrics {
        VADMetrics(
            totalEvents: totalSpeechSegments,
            startTime: startTime,
            lastEventTime: lastEventTime,
            totalSpeechSegments: totalSpeechSegments,
            totalSpeechDurationMs: totalSpeechDurationMs,
            averageSpeechDurationMs: totalSpeechSegments > 0 ? totalSpeechDurationMs / Double(totalSpeechSegments) : -1,
            framework: currentFramework
        )
    }
}
