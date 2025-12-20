package com.runanywhere.sdk.features.vad

import com.runanywhere.sdk.events.EventPublisher
import com.runanywhere.sdk.foundation.SDKLogger
import com.runanywhere.sdk.models.enums.InferenceFramework
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock

/**
 * VAD analytics service for tracking voice activity detection.
 * Mirrors iOS VADAnalyticsService actor pattern.
 *
 * This service tracks VAD operations and provides aggregated metrics
 * about speech detection performance.
 *
 * Usage:
 * ```kotlin
 * val analyticsService = VADAnalyticsService()
 * analyticsService.trackInitialized(InferenceFramework.BUILT_IN)
 * analyticsService.trackSpeechStart()
 * // ... speech happens ...
 * analyticsService.trackSpeechEnd()
 * val metrics = analyticsService.getMetrics()
 * ```
 */
class VADAnalyticsService {
    // MARK: - Properties

    private val logger = SDKLogger("VADAnalytics")
    private val mutex = Mutex()

    /** Current framework being used */
    private var currentFramework: InferenceFramework = InferenceFramework.BUILT_IN

    /** Speech segment tracking - start time in epoch millis */
    private var speechStartTime: Long? = null

    /** Total number of speech segments detected */
    private var totalSpeechSegments: Int = 0

    /** Total duration of all speech segments in milliseconds */
    private var totalSpeechDurationMs: Double = 0.0

    /** When tracking started (epoch millis) */
    private val startTime: Long = System.currentTimeMillis()

    /** When the last event occurred (epoch millis) */
    private var lastEventTime: Long? = null

    // MARK: - Lifecycle Tracking

    /**
     * Track VAD initialization
     * @param framework The inference framework being used
     */
    suspend fun trackInitialized(framework: InferenceFramework) {
        mutex.withLock {
            currentFramework = framework
            lastEventTime = System.currentTimeMillis()
        }

        EventPublisher.track(VADEvent.Initialized(framework = framework))
        logger.debug("VAD initialized with framework: ${framework.value}")
    }

    /**
     * Track VAD initialization failure
     * @param error Error description
     * @param framework The inference framework that was attempted
     */
    suspend fun trackInitializationFailed(
        error: String,
        framework: InferenceFramework,
    ) {
        mutex.withLock {
            currentFramework = framework
            lastEventTime = System.currentTimeMillis()
        }

        EventPublisher.track(VADEvent.InitializationFailed(error = error, framework = framework))
    }

    /**
     * Track VAD cleanup
     */
    suspend fun trackCleanedUp() {
        mutex.withLock {
            lastEventTime = System.currentTimeMillis()
        }

        EventPublisher.track(VADEvent.CleanedUp)
    }

    // MARK: - Detection Tracking

    /**
     * Track VAD started processing
     */
    suspend fun trackStarted() {
        mutex.withLock {
            lastEventTime = System.currentTimeMillis()
        }

        EventPublisher.track(VADEvent.Started)
    }

    /**
     * Track VAD stopped processing
     */
    suspend fun trackStopped() {
        mutex.withLock {
            lastEventTime = System.currentTimeMillis()
        }

        EventPublisher.track(VADEvent.Stopped)
    }

    /**
     * Track speech detected (start of speech/voice activity)
     */
    suspend fun trackSpeechStart() {
        mutex.withLock {
            speechStartTime = System.currentTimeMillis()
            lastEventTime = speechStartTime
        }

        EventPublisher.track(VADEvent.SpeechStarted)
    }

    /**
     * Track speech ended (silence detected after speech)
     */
    suspend fun trackSpeechEnd() {
        val durationMs: Double

        mutex.withLock {
            val start = speechStartTime ?: return
            val endTime = System.currentTimeMillis()
            durationMs = (endTime - start).toDouble()
            speechStartTime = null

            // Update metrics
            totalSpeechSegments++
            totalSpeechDurationMs += durationMs
            lastEventTime = endTime
        }

        EventPublisher.track(VADEvent.SpeechEnded(durationMs = durationMs))
    }

    /**
     * Track VAD paused
     */
    suspend fun trackPaused() {
        mutex.withLock {
            lastEventTime = System.currentTimeMillis()
        }

        EventPublisher.track(VADEvent.Paused)
    }

    /**
     * Track VAD resumed
     */
    suspend fun trackResumed() {
        mutex.withLock {
            lastEventTime = System.currentTimeMillis()
        }

        EventPublisher.track(VADEvent.Resumed)
    }

    // MARK: - Model Lifecycle (for model-based VAD like Silero)

    /**
     * Track model load started (for model-based VAD like Silero)
     * @param modelId Model identifier
     * @param modelSizeBytes Size of the model in bytes (optional)
     * @param framework The inference framework being used
     */
    suspend fun trackModelLoadStarted(
        modelId: String,
        modelSizeBytes: Long = 0,
        framework: InferenceFramework,
    ) {
        mutex.withLock {
            currentFramework = framework
            lastEventTime = System.currentTimeMillis()
        }

        EventPublisher.track(
            VADEvent.ModelLoadStarted(
                modelId = modelId,
                modelSizeBytes = modelSizeBytes,
                framework = framework,
            ),
        )
    }

    /**
     * Track model load completed
     * @param modelId Model identifier
     * @param durationMs Time taken to load the model in milliseconds
     * @param modelSizeBytes Size of the model in bytes (optional)
     */
    suspend fun trackModelLoadCompleted(
        modelId: String,
        durationMs: Double,
        modelSizeBytes: Long = 0,
    ) {
        val framework: InferenceFramework
        mutex.withLock {
            lastEventTime = System.currentTimeMillis()
            framework = currentFramework
        }

        EventPublisher.track(
            VADEvent.ModelLoadCompleted(
                modelId = modelId,
                durationMs = durationMs,
                modelSizeBytes = modelSizeBytes,
                framework = framework,
            ),
        )
    }

    /**
     * Track model load failed
     * @param modelId Model identifier
     * @param error Error description
     */
    suspend fun trackModelLoadFailed(
        modelId: String,
        error: String,
    ) {
        val framework: InferenceFramework
        mutex.withLock {
            lastEventTime = System.currentTimeMillis()
            framework = currentFramework
        }

        EventPublisher.track(
            VADEvent.ModelLoadFailed(
                modelId = modelId,
                error = error,
                framework = framework,
            ),
        )
    }

    /**
     * Track model unloaded
     * @param modelId Model identifier
     */
    suspend fun trackModelUnloaded(modelId: String) {
        mutex.withLock {
            lastEventTime = System.currentTimeMillis()
        }

        EventPublisher.track(VADEvent.ModelUnloaded(modelId = modelId))
    }

    // MARK: - Metrics

    /**
     * Get current VAD analytics metrics
     * @return VADMetrics with aggregated statistics
     */
    suspend fun getMetrics(): VADMetrics =
        mutex.withLock {
            VADMetrics(
                totalEvents = totalSpeechSegments,
                startTime = startTime,
                lastEventTime = lastEventTime,
                totalSpeechSegments = totalSpeechSegments,
                totalSpeechDurationMs = totalSpeechDurationMs,
                averageSpeechDurationMs =
                    if (totalSpeechSegments > 0) {
                        totalSpeechDurationMs / totalSpeechSegments
                    } else {
                        -1.0 // -1 indicates N/A, matching iOS
                    },
                framework = currentFramework,
            )
        }

    /**
     * Reset metrics (useful for testing or session reset)
     */
    suspend fun resetMetrics() {
        mutex.withLock {
            totalSpeechSegments = 0
            totalSpeechDurationMs = 0.0
            speechStartTime = null
            lastEventTime = null
        }
    }
}
