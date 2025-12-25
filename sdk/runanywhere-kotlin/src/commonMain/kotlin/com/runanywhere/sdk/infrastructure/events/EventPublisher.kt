package com.runanywhere.sdk.infrastructure.events

import com.runanywhere.sdk.data.repositories.TelemetryRepository
import com.runanywhere.sdk.foundation.SDKLogger
import com.runanywhere.sdk.infrastructure.analytics.AnalyticsEvent
import com.runanywhere.sdk.infrastructure.analytics.AnalyticsQueueManager
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch

/**
 * Simple event router for the SDK.
 * Mirrors iOS EventPublisher.
 *
 * SDKEvent is the single unified event type for the entire SDK.
 * Just call `track(event)` - the router decides where to send it
 * based on the event's `destination` property:
 * - PUBLIC_ONLY → EventBus only (app developers)
 * - ANALYTICS_ONLY → AnalyticsQueueManager only (backend telemetry)
 * - ALL → Both destinations (default)
 *
 * Usage:
 * ```kotlin
 * EventPublisher.track(LLMEvent.GenerationCompleted(...))
 * ```
 */
object EventPublisher {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Default)
    private val logger = SDKLogger("EventPublisher")

    /**
     * Analytics queue for telemetry events.
     * Set during SDK initialization via [initialize].
     */
    private var analyticsEnqueuer: AnalyticsEnqueuer? = null

    /**
     * Interface for analytics queue integration.
     * Implement this to receive events destined for analytics.
     */
    fun interface AnalyticsEnqueuer {
        suspend fun enqueue(event: SDKEvent)
    }

    /**
     * Initialize with analytics queue (call during SDK startup)
     */
    fun initialize(analyticsQueue: AnalyticsEnqueuer?) {
        analyticsEnqueuer = analyticsQueue
        logger.info("Initialized with analytics queue: ${analyticsQueue != null}")
    }

    /**
     * Initialize with SDKEvent routing to AnalyticsQueueManager.
     *
     * This adapts SDKEvent to AnalyticsEvent and routes to the queue.
     * SDKEvent is the single unified event type - no separate AnalyticsEvent needed.
     *
     * @param telemetryRepository The telemetry repository (used to confirm analytics is available)
     */
    fun initializeWithSDKEventRouting(telemetryRepository: TelemetryRepository?) {
        if (telemetryRepository == null) {
            logger.warn("No telemetry repository - analytics events will not be sent")
            analyticsEnqueuer = null
            return
        }

        // Create adapter that converts SDKEvent to AnalyticsEvent for the queue
        analyticsEnqueuer =
            AnalyticsEnqueuer { sdkEvent ->
                val analyticsEvent = SDKEventAnalyticsAdapter(sdkEvent)
                AnalyticsQueueManager.enqueue(analyticsEvent)
            }

        logger.info("Initialized with SDKEvent routing to AnalyticsQueueManager")
    }

    /**
     * Track an event. Routes automatically based on event.destination.
     *
     * @param event The event to track
     */
    fun track(event: SDKEvent) {
        val destination = event.destination

        // Route to EventBus (public) if not analytics-only
        if (destination != EventDestination.ANALYTICS_ONLY) {
            EventBus.publishSDKEvent(event)
        }

        // Route to Analytics (telemetry) if not public-only
        if (destination != EventDestination.PUBLIC_ONLY) {
            analyticsEnqueuer?.let { enqueuer ->
                scope.launch {
                    try {
                        enqueuer.enqueue(event)
                    } catch (e: Exception) {
                        logger.error("Failed to enqueue event for analytics: ${e.message}")
                    }
                }
            }
        }
    }

    /**
     * Track an event asynchronously (for use in suspend contexts).
     *
     * @param event The event to track
     */
    suspend fun trackAsync(event: SDKEvent) {
        val destination = event.destination

        // Route to EventBus (public) if not analytics-only
        if (destination != EventDestination.ANALYTICS_ONLY) {
            EventBus.publishSDKEvent(event)
        }

        // Route to Analytics (telemetry) if not public-only
        if (destination != EventDestination.PUBLIC_ONLY) {
            analyticsEnqueuer?.let { enqueuer ->
                try {
                    enqueuer.enqueue(event)
                } catch (e: Exception) {
                    logger.error("Failed to enqueue event for analytics: ${e.message}")
                }
            }
        }
    }

    /**
     * Check if analytics is configured.
     */
    val isAnalyticsConfigured: Boolean
        get() = analyticsEnqueuer != null
}

/**
 * Convenience extension to track events directly.
 */
fun SDKEvent.track() = EventPublisher.track(this)

/**
 * Convenience extension to track events asynchronously.
 */
suspend fun SDKEvent.trackAsync() = EventPublisher.trackAsync(this)

/**
 * Internal adapter to wrap SDKEvent as AnalyticsEvent for the analytics queue.
 * This is the bridge between the unified SDKEvent type and the AnalyticsQueueManager.
 */
internal class SDKEventAnalyticsAdapter(
    private val sdkEvent: SDKEvent,
) : AnalyticsEvent {
    override val type: String = sdkEvent.type
    override val eventData: Any = sdkEvent.properties
    override val timestamp: Long = sdkEvent.timestamp
}
