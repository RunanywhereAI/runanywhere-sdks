package com.runanywhere.sdk.events

import kotlinx.coroutines.flow.*
import kotlin.random.Random
import com.runanywhere.sdk.foundation.currentTimeMillis

/**
 * Event correlation utilities for tracking related events
 * Provides request ID generation and event correlation functionality
 */
object EventCorrelation {

    /**
     * Generate a unique request/session ID for event correlation
     */
    fun generateRequestId(): String {
        val timestamp = currentTimeMillis() / 1000 // Convert to seconds
        val random = Random.nextInt(1000, 9999)
        return "req_${timestamp}_$random"
    }

    /**
     * Generate a unique session ID for event correlation
     */
    fun generateSessionId(): String {
        val timestamp = currentTimeMillis() / 1000 // Convert to seconds
        val random = Random.nextInt(1000, 9999)
        return "session_${timestamp}_$random"
    }
}

/**
 * Enhanced SDKEvent interface with correlation support
 */
interface CorrelatedSDKEvent : SDKEvent {
    val requestId: String?
    override val sessionId: String?
    val correlationId: String?
}

/**
 * Base implementation with correlation support
 */
abstract class CorrelatedBaseSDKEvent(
    override val category: EventCategory,
    override val requestId: String? = null,
    override val sessionId: String? = null,
    override val correlationId: String? = null,
    override val timestamp: Long = currentTimeMillis(),
    override val id: String = generateEventId(),
    override val destination: EventDestination = EventDestination.ALL
) : CorrelatedSDKEvent {
    override val type: String get() = this::class.simpleName ?: "Unknown"
    override val properties: Map<String, String>
        get() = buildMap {
            requestId?.let { put("requestId", it) }
            sessionId?.let { put("sessionId", it) }
            correlationId?.let { put("correlationId", it) }
        }
}

/**
 * Event filter utilities for correlation
 */
object EventFilters {

    /**
     * Filter events by request ID
     */
    fun <T : SDKEvent> Flow<T>.filterByRequestId(requestId: String): Flow<T> {
        return filter { event ->
            when (event) {
                is CorrelatedSDKEvent -> event.requestId == requestId
                is SDKGenerationEvent.Started -> event.generationSessionId == requestId
                is SDKGenerationEvent.SessionStarted -> event.generationSessionId == requestId
                is SDKGenerationEvent.SessionEnded -> event.generationSessionId == requestId
                else -> false
            }
        }
    }

    /**
     * Filter events by session ID
     */
    fun <T : SDKEvent> Flow<T>.filterBySessionId(sessionId: String): Flow<T> {
        return filter { event ->
            when (event) {
                is CorrelatedSDKEvent -> event.sessionId == sessionId
                is SDKGenerationEvent.SessionStarted -> event.generationSessionId == sessionId
                is SDKGenerationEvent.SessionEnded -> event.generationSessionId == sessionId
                is SDKGenerationEvent.Started -> event.generationSessionId == sessionId
                // Also check SDKEvent.sessionId for events that have it set
                else -> event.sessionId == sessionId
            }
        }
    }

    /**
     * Filter events by correlation ID
     */
    fun <T : SDKEvent> Flow<T>.filterByCorrelationId(correlationId: String): Flow<T> {
        return filter { event ->
            when (event) {
                is CorrelatedSDKEvent -> event.correlationId == correlationId
                else -> false
            }
        }
    }

    /**
     * Filter events by time range
     */
    fun <T : SDKEvent> Flow<T>.filterByTimeRange(
        startTime: Long,
        endTime: Long
    ): Flow<T> {
        return filter { event ->
            event.timestamp >= startTime && event.timestamp <= endTime
        }
    }

    /**
     * Filter events by category
     */
    fun <T : SDKEvent> Flow<T>.filterByCategory(category: EventCategory): Flow<T> {
        return filter { event ->
            event.category == category
        }
    }
}

/**
 * Event correlation extensions for EventBus
 */
fun EventBus.getEventsForRequest(requestId: String): Flow<SDKEvent> {
    return events.run { EventFilters.run { filterByRequestId(requestId) } }
}

fun EventBus.getEventsForSession(sessionId: String): Flow<SDKEvent> {
    return events.run { EventFilters.run { filterBySessionId(sessionId) } }
}

fun EventBus.getEventsForCorrelation(correlationId: String): Flow<SDKEvent> {
    return events.run { EventFilters.run { filterByCorrelationId(correlationId) } }
}

fun EventBus.getEventsInTimeRange(startTime: Long, endTime: Long): Flow<SDKEvent> {
    return events.run { EventFilters.run { filterByTimeRange(startTime, endTime) } }
}

fun EventBus.getEventsByCategory(category: EventCategory): Flow<SDKEvent> {
    return events.run { EventFilters.run { filterByCategory(category) } }
}
