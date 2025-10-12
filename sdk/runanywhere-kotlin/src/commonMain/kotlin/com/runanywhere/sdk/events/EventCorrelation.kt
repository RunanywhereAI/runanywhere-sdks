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
    val sessionId: String?
    val correlationId: String?
}

/**
 * Base implementation with correlation support
 */
abstract class CorrelatedBaseSDKEvent(
    override val eventType: SDKEventType,
    override val requestId: String? = null,
    override val sessionId: String? = null,
    override val correlationId: String? = null,
    override val timestamp: Long = currentTimeMillis()
) : CorrelatedSDKEvent

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
                is SDKGenerationEvent.Started -> event.sessionId == requestId
                is SDKGenerationEvent.SessionStarted -> event.sessionId == requestId
                is SDKGenerationEvent.SessionEnded -> event.sessionId == requestId
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
                is SDKGenerationEvent.SessionStarted -> event.sessionId == sessionId
                is SDKGenerationEvent.SessionEnded -> event.sessionId == sessionId
                is SDKGenerationEvent.Started -> event.sessionId == sessionId
                else -> false
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
     * Filter events by event type
     */
    fun <T : SDKEvent> Flow<T>.filterByEventType(eventType: SDKEventType): Flow<T> {
        return filter { event ->
            event.eventType == eventType
        }
    }
}

/**
 * Event correlation extensions for EventBus
 */
fun EventBus.getEventsForRequest(requestId: String): Flow<SDKEvent> {
    return allEvents.run { EventFilters.run { filterByRequestId(requestId) } }
}

fun EventBus.getEventsForSession(sessionId: String): Flow<SDKEvent> {
    return allEvents.run { EventFilters.run { filterBySessionId(sessionId) } }
}

fun EventBus.getEventsForCorrelation(correlationId: String): Flow<SDKEvent> {
    return allEvents.run { EventFilters.run { filterByCorrelationId(correlationId) } }
}

fun EventBus.getEventsInTimeRange(startTime: Long, endTime: Long): Flow<SDKEvent> {
    return allEvents.run { EventFilters.run { filterByTimeRange(startTime, endTime) } }
}

fun EventBus.getEventsByType(eventType: SDKEventType): Flow<SDKEvent> {
    return allEvents.run { EventFilters.run { filterByEventType(eventType) } }
}
