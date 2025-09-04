package com.runanywhere.sdk.analytics

import java.util.UUID

/**
 * Analytics event data class
 */
data class AnalyticsEvent(
    val name: String,
    val properties: Map<String, Any>,
    val timestamp: Long = System.currentTimeMillis(),
    val sessionId: String
)

/**
 * Analytics tracker for SDK usage metrics
 */
class AnalyticsTracker {
    private val events = mutableListOf<AnalyticsEvent>()
    private val sessionId = UUID.randomUUID().toString()

    companion object {
        private const val SDK_VERSION = "1.0.0"
    }

    /**
     * Track an analytics event
     */
    fun track(eventName: String, properties: Map<String, Any> = emptyMap()) {
        val currentTime = System.currentTimeMillis()
        val enrichedProperties = mutableMapOf<String, Any>().apply {
            putAll(properties)
            put("session_id", sessionId)
            put("timestamp", currentTime)
            put("platform", "android")
            put("sdk_version", SDK_VERSION)
        }

        val event = AnalyticsEvent(
            name = eventName,
            properties = enrichedProperties,
            timestamp = currentTime,
            sessionId = sessionId
        )

        events.add(event)

        // Send to backend if online
        if (shouldSendEvents()) {
            sendEvents()
        }
    }

    /**
     * Track performance metrics
     */
    fun trackPerformance(operation: String, duration: Long) {
        track(
            "performance_metric", mapOf(
                "operation" to operation,
                "duration_ms" to duration
            )
        )
    }

    /**
     * Track error occurrence
     */
    fun trackError(error: Throwable) {
        track(
            "error_occurred", mapOf(
                "error_type" to (error::class.simpleName ?: "Unknown"),
                "error_message" to (error.message ?: "No message"),
                "stack_trace" to error.stackTraceToString().take(500)
            )
        )
    }

    private fun shouldSendEvents(): Boolean {
        // Check if we should batch send events
        return events.size >= 10 ||
                (events.isNotEmpty() && System.currentTimeMillis() - events.last().timestamp > 60000)
    }

    private fun sendEvents() {
        // TODO: Implement actual sending to analytics backend
        // For now, just clear old events
        if (events.size > 100) {
            events.clear()
        }
    }
}
