package com.runanywhere.sdk.core.capabilities

import com.runanywhere.sdk.events.EventPublisher
import com.runanywhere.sdk.events.SDKEvent
import com.runanywhere.sdk.features.llm.LLMEvent
import com.runanywhere.sdk.features.tts.TTSEvent
import com.runanywhere.sdk.features.vad.VADEvent
import com.runanywhere.sdk.foundation.SDKLogger
import com.runanywhere.sdk.foundation.currentTimeMillis
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock

/**
 * Actor-like class that wraps ModelLifecycleManager with integrated event tracking.
 *
 * Lifecycle events (load, unload) are published directly to EventPublisher,
 * which routes them to both public EventBus and Analytics automatically.
 *
 * One-to-one translation from iOS ManagedLifecycle.swift.
 *
 * @param ServiceType The type of service being managed
 */
class ManagedLifecycle<ServiceType : Any>(
    private val lifecycle: ModelLifecycleManager<ServiceType>,
    private val resourceType: CapabilityResourceType,
    loggerCategory: String,
) {
    private val logger = SDKLogger(loggerCategory)
    private val mutex = Mutex()

    // Metrics
    private var loadCount = 0
    private var totalLoadTime: Long = 0
    private val startTime = currentTimeMillis()

    // MARK: - State Properties

    /** Whether a resource is currently loaded */
    suspend fun isLoaded(): Boolean = lifecycle.isLoaded()

    /** The currently loaded resource ID */
    suspend fun currentResourceId(): String? = lifecycle.currentResourceId()

    /** The currently loaded service */
    suspend fun currentService(): ServiceType? = lifecycle.currentService()

    /** Current loading state */
    suspend fun state(): CapabilityLoadingState = lifecycle.state()

    // MARK: - Configuration

    /** Set configuration for loading */
    suspend fun configure(config: ComponentConfiguration?) {
        lifecycle.configure(config)
    }

    // MARK: - Lifecycle Operations

    /**
     * Load a resource with automatic event tracking.
     *
     * @param resourceId The resource to load
     * @return The loaded service
     */
    suspend fun load(resourceId: String): ServiceType {
        val loadStartTime = currentTimeMillis()
        logger.info("Loading ${resourceType.displayName}: $resourceId")

        // Track load started
        trackEvent(LifecycleEventType.LOAD_STARTED, resourceId)

        return try {
            val service = lifecycle.load(resourceId)
            val loadTime = currentTimeMillis() - loadStartTime

            // Track load completed
            trackEvent(LifecycleEventType.LOAD_COMPLETED, resourceId, loadTime.toDouble())

            // Update metrics
            mutex.withLock {
                loadCount++
                totalLoadTime += loadTime
            }

            logger.info("Loaded ${resourceType.displayName}: $resourceId in ${loadTime}ms")
            service
        } catch (e: Exception) {
            val loadTime = currentTimeMillis() - loadStartTime

            // Track load failed
            trackEvent(LifecycleEventType.LOAD_FAILED, resourceId, loadTime.toDouble(), e)

            logger.error("Failed to load ${resourceType.displayName}: $e")
            throw e
        }
    }

    /**
     * Unload the currently loaded resource.
     */
    suspend fun unload() {
        val resourceId = lifecycle.currentResourceId()
        if (resourceId != null) {
            logger.info("Unloading ${resourceType.displayName}: $resourceId")
            lifecycle.unload()
            trackEvent(LifecycleEventType.UNLOADED, resourceId)
        } else {
            lifecycle.unload()
        }
    }

    /**
     * Reset all state.
     */
    suspend fun reset() {
        val resourceId = lifecycle.currentResourceId()
        if (resourceId != null) {
            trackEvent(LifecycleEventType.UNLOADED, resourceId)
        }
        lifecycle.reset()
    }

    /**
     * Get service or throw if not loaded.
     */
    suspend fun requireService(): ServiceType = lifecycle.requireService()

    /**
     * Track an operation error.
     */
    fun trackOperationError(
        error: Throwable,
        operation: String,
    ) {
        // EventPublisher.shared.track(ErrorEvent.error(...))
        // Note: ErrorEvent would need to be defined to match iOS
        logger.error("Operation $operation failed: ${error.message}")
    }

    /**
     * Get current resource ID with fallback.
     */
    suspend fun resourceIdOrUnknown(): String = lifecycle.currentResourceId() ?: "unknown"

    // MARK: - Metrics

    /**
     * Get current lifecycle metrics.
     */
    suspend fun getLifecycleMetrics(): ModelLifecycleMetrics =
        mutex.withLock {
            val avgLoadTime = if (loadCount > 0) totalLoadTime.toDouble() / loadCount else 0.0

            ModelLifecycleMetrics(
                totalEvents = loadCount,
                startTime = startTime,
                lastEventTime = null,
                totalLoads = loadCount,
                successfulLoads = loadCount,
                failedLoads = 0,
                averageLoadTimeMs = avgLoadTime,
                totalUnloads = 0,
                totalDownloads = 0,
                successfulDownloads = 0,
                failedDownloads = 0,
                totalBytesDownloaded = 0,
            )
        }

    // MARK: - Private Event Tracking

    private enum class LifecycleEventType {
        LOAD_STARTED,
        LOAD_COMPLETED,
        LOAD_FAILED,
        UNLOADED,
    }

    private fun trackEvent(
        type: LifecycleEventType,
        resourceId: String,
        durationMs: Double? = null,
        error: Throwable? = null,
    ) {
        // Create the appropriate event based on resource type
        val event = createEvent(type, resourceId, durationMs, error)

        // Track via EventPublisher - routes to both EventBus and Analytics
        EventPublisher.track(event)
    }

    private fun createEvent(
        type: LifecycleEventType,
        resourceId: String,
        durationMs: Double?,
        error: Throwable?,
    ): SDKEvent =
        when (resourceType) {
            CapabilityResourceType.LLM_MODEL -> createLLMEvent(type, resourceId, durationMs, error)
            CapabilityResourceType.STT_MODEL -> createSTTEvent(type, resourceId, durationMs, error)
            CapabilityResourceType.TTS_VOICE -> createTTSEvent(type, resourceId, durationMs, error)
            CapabilityResourceType.VAD_MODEL -> createVADEvent(type, resourceId, durationMs, error)
            CapabilityResourceType.DIARIZATION_MODEL -> createModelEvent(type, resourceId, durationMs, error)
        }

    private fun createLLMEvent(
        type: LifecycleEventType,
        resourceId: String,
        durationMs: Double?,
        error: Throwable?,
    ): LLMEvent =
        when (type) {
            LifecycleEventType.LOAD_STARTED -> LLMEvent.ModelLoadStarted(modelId = resourceId)
            LifecycleEventType.LOAD_COMPLETED ->
                LLMEvent.ModelLoadCompleted(
                    modelId = resourceId,
                    durationMs = durationMs ?: 0.0,
                )
            LifecycleEventType.LOAD_FAILED ->
                LLMEvent.ModelLoadFailed(
                    modelId = resourceId,
                    error = error?.message ?: "Unknown error",
                )
            LifecycleEventType.UNLOADED -> LLMEvent.ModelUnloaded(modelId = resourceId)
        }

    private fun createSTTEvent(
        type: LifecycleEventType,
        resourceId: String,
        durationMs: Double?,
        error: Throwable?,
    ): SDKEvent {
        // STTEvent would need model lifecycle events added to match iOS
        // For now, use generic model event
        return createModelEvent(type, resourceId, durationMs, error)
    }

    private fun createTTSEvent(
        type: LifecycleEventType,
        resourceId: String,
        durationMs: Double?,
        error: Throwable?,
    ): TTSEvent =
        when (type) {
            LifecycleEventType.LOAD_STARTED -> TTSEvent.ModelLoadStarted(voiceId = resourceId)
            LifecycleEventType.LOAD_COMPLETED ->
                TTSEvent.ModelLoadCompleted(
                    voiceId = resourceId,
                    durationMs = durationMs ?: 0.0,
                )
            LifecycleEventType.LOAD_FAILED ->
                TTSEvent.ModelLoadFailed(
                    voiceId = resourceId,
                    error = error?.message ?: "Unknown error",
                )
            LifecycleEventType.UNLOADED -> TTSEvent.ModelUnloaded(voiceId = resourceId)
        }

    private fun createVADEvent(
        type: LifecycleEventType,
        resourceId: String,
        durationMs: Double?,
        error: Throwable?,
    ): VADEvent =
        when (type) {
            LifecycleEventType.LOAD_STARTED -> VADEvent.ModelLoadStarted(modelId = resourceId)
            LifecycleEventType.LOAD_COMPLETED ->
                VADEvent.ModelLoadCompleted(
                    modelId = resourceId,
                    durationMs = durationMs ?: 0.0,
                )
            LifecycleEventType.LOAD_FAILED ->
                VADEvent.ModelLoadFailed(
                    modelId = resourceId,
                    error = error?.message ?: "Unknown error",
                )
            LifecycleEventType.UNLOADED -> VADEvent.ModelUnloaded(modelId = resourceId)
        }

    private fun createModelEvent(
        type: LifecycleEventType,
        resourceId: String,
        durationMs: Double?,
        error: Throwable?,
    ): SDKEvent {
        // Use LLMEvent as a generic model event for now
        // TODO: Create dedicated ModelEvent class when needed
        return when (type) {
            LifecycleEventType.LOAD_STARTED -> LLMEvent.ModelLoadStarted(modelId = resourceId)
            LifecycleEventType.LOAD_COMPLETED ->
                LLMEvent.ModelLoadCompleted(
                    modelId = resourceId,
                    durationMs = durationMs ?: 0.0,
                )
            LifecycleEventType.LOAD_FAILED ->
                LLMEvent.ModelLoadFailed(
                    modelId = resourceId,
                    error = error?.message ?: "Unknown error",
                )
            LifecycleEventType.UNLOADED -> LLMEvent.ModelUnloaded(modelId = resourceId)
        }
    }
}

// MARK: - Convenience Extension for Resource Type

/** Display name for resource type used in logging */
private val CapabilityResourceType.displayName: String
    get() =
        when (this) {
            CapabilityResourceType.LLM_MODEL -> "LLM model"
            CapabilityResourceType.STT_MODEL -> "STT model"
            CapabilityResourceType.TTS_VOICE -> "TTS voice"
            CapabilityResourceType.VAD_MODEL -> "VAD model"
            CapabilityResourceType.DIARIZATION_MODEL -> "Diarization model"
        }
