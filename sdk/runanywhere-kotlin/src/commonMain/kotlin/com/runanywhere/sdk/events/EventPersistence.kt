@file:OptIn(kotlin.time.ExperimentalTime::class)

package com.runanywhere.sdk.events

import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.*
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.datetime.Instant
import kotlinx.datetime.Clock
import kotlin.collections.mutableListOf
import com.runanywhere.sdk.foundation.currentTimeMillis

/**
 * Event persistence for debugging and analytics
 * Stores events in memory with configurable limits
 */
class EventPersistence(
    private val maxEvents: Int = 1000,
    private val enablePersistence: Boolean = true
) {

    private val mutex = Mutex()
    private val _events = mutableListOf<PersistedEvent>()
    private var _isCollecting = false

    data class PersistedEvent(
        val event: SDKEvent,
        val persistedAt: Instant = Instant.fromEpochMilliseconds(currentTimeMillis())
    )

    /**
     * Start collecting events from EventBus
     */
    fun startCollecting(scope: CoroutineScope): Job? {
        if (!enablePersistence || _isCollecting) return null

        _isCollecting = true
        return scope.launch {
            EventBus.allEvents.collect { event ->
                persistEvent(event)
            }
        }
    }

    /**
     * Stop collecting events
     */
    suspend fun stopCollecting() {
        _isCollecting = false
    }

    /**
     * Persist a single event
     */
    private suspend fun persistEvent(event: SDKEvent) {
        if (!enablePersistence) return

        mutex.withLock {
            _events.add(PersistedEvent(event))

            // Remove oldest events if we exceed the limit
            // Using removeAt(0) instead of removeFirst() for Android 14 compatibility
            while (_events.size > maxEvents) {
                _events.removeAt(0)
            }
        }
    }

    /**
     * Get all persisted events
     */
    suspend fun getAllEvents(): List<PersistedEvent> {
        return mutex.withLock {
            _events.toList()
        }
    }

    /**
     * Get events by type
     */
    suspend fun getEventsByType(eventType: SDKEventType): List<PersistedEvent> {
        return mutex.withLock {
            _events.filter { it.event.eventType == eventType }
        }
    }

    /**
     * Get events in time range
     */
    suspend fun getEventsInTimeRange(
        startTime: Long,
        endTime: Long
    ): List<PersistedEvent> {
        return mutex.withLock {
            _events.filter {
                it.event.timestamp >= startTime && it.event.timestamp <= endTime
            }
        }
    }

    /**
     * Get events for request ID
     */
    suspend fun getEventsForRequest(requestId: String): List<PersistedEvent> {
        return mutex.withLock {
            _events.filter { persistedEvent ->
                when (val event = persistedEvent.event) {
                    is CorrelatedSDKEvent -> event.requestId == requestId
                    is SDKGenerationEvent.Started -> event.sessionId == requestId
                    is SDKGenerationEvent.SessionStarted -> event.sessionId == requestId
                    is SDKGenerationEvent.SessionEnded -> event.sessionId == requestId
                    else -> false
                }
            }
        }
    }

    /**
     * Get events for session ID
     */
    suspend fun getEventsForSession(sessionId: String): List<PersistedEvent> {
        return mutex.withLock {
            _events.filter { persistedEvent ->
                when (val event = persistedEvent.event) {
                    is CorrelatedSDKEvent -> event.sessionId == sessionId
                    is SDKGenerationEvent.SessionStarted -> event.sessionId == sessionId
                    is SDKGenerationEvent.SessionEnded -> event.sessionId == sessionId
                    is SDKGenerationEvent.Started -> event.sessionId == sessionId
                    else -> false
                }
            }
        }
    }

    /**
     * Search events by text content
     */
    suspend fun searchEvents(query: String): List<PersistedEvent> {
        return mutex.withLock {
            _events.filter { persistedEvent ->
                persistedEvent.event.toString().contains(query, ignoreCase = true)
            }
        }
    }

    /**
     * Get event count by type
     */
    suspend fun getEventCountByType(): Map<SDKEventType, Int> {
        return mutex.withLock {
            _events.groupBy { it.event.eventType }
                .mapValues { it.value.size }
        }
    }

    /**
     * Clear all persisted events
     */
    suspend fun clearEvents() {
        mutex.withLock {
            _events.clear()
        }
    }

    /**
     * Get current event count
     */
    suspend fun getEventCount(): Int {
        return mutex.withLock {
            _events.size
        }
    }

    /**
     * Export events as formatted string for debugging
     */
    suspend fun exportEventsAsString(): String {
        val events = getAllEvents()
        return buildString {
            appendLine("=== SDK Event Debug Log ===")
            appendLine("Total Events: ${events.size}")
            appendLine("Generated At: ${Instant.fromEpochMilliseconds(currentTimeMillis())}")
            appendLine()

            events.forEach { persistedEvent ->
                appendLine("Timestamp: ${persistedEvent.event.timestamp}")
                appendLine("Type: ${persistedEvent.event.eventType}")
                appendLine("Event: ${persistedEvent.event}")
                appendLine("Persisted At: ${persistedEvent.persistedAt}")
                appendLine("---")
            }
        }
    }
}

/**
 * Global event persistence instance
 */
object GlobalEventPersistence {
    private var _instance: EventPersistence? = null

    fun getInstance(
        maxEvents: Int = 1000,
        enablePersistence: Boolean = true
    ): EventPersistence {
        return _instance ?: EventPersistence(maxEvents, enablePersistence).also {
            _instance = it
        }
    }

    fun isEnabled(): Boolean = _instance != null
}

/**
 * Debug utilities for event analysis
 */
object EventDebugUtils {

    /**
     * Print event statistics to console
     */
    suspend fun printEventStatistics(persistence: EventPersistence) {
        val counts = persistence.getEventCountByType()
        val total = persistence.getEventCount()

        println("=== SDK Event Statistics ===")
        println("Total Events: $total")
        counts.forEach { (type, count) ->
            val percentage = if (total > 0) (count * 100.0 / total) else 0.0
            println("$type: $count (${String.format("%.1f", percentage)}%)")
        }
        println("============================")
    }

    /**
     * Print recent events to console
     */
    suspend fun printRecentEvents(
        persistence: EventPersistence,
        count: Int = 10
    ) {
        val events = persistence.getAllEvents().takeLast(count)

        println("=== Recent SDK Events (Last $count) ===")
        events.forEach { persistedEvent ->
            println("${persistedEvent.event.timestamp} [${persistedEvent.event.eventType}] ${persistedEvent.event}")
        }
        println("=====================================")
    }
}
