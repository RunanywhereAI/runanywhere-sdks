package com.runanywhere.sdk.analytics

import kotlin.random.Random

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
    private val sessionId = generateUUID()
    private val sdkVersion = "1.0.0"

    /**
     * Track an analytics event
     */
    fun track(eventName: String, properties: Map<String, Any> = emptyMap()) {
        val currentTime = System.currentTimeMillis()
        val enrichedProperties = mutableMapOf<String, Any>().apply {
            putAll(properties)
            put("session_id", sessionId)
            put("timestamp", currentTime)
            put("platform", getPlatformName())
            put("sdk_version", sdkVersion)
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

    private fun getPlatformName(): String {
        // This will need platform-specific implementation
        return "multiplatform"
    }

    private fun generateUUID(): String {
        val chars = "0123456789abcdef"
        return buildString {
            repeat(8) { append(chars.random()) }
            append('-')
            repeat(4) { append(chars.random()) }
            append('-')
            append('4') // Version 4 UUID
            repeat(3) { append(chars.random()) }
            append('-')
            append(listOf('8', '9', 'a', 'b').random()) // Variant
            repeat(3) { append(chars.random()) }
            append('-')
            repeat(12) { append(chars.random()) }
        }
    }
}
