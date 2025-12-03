package com.runanywhere.runanywhereai.analytics

import com.runanywhere.sdk.public.BaseRunAnywhereSDK
import com.runanywhere.sdk.data.models.TelemetryData
import com.runanywhere.sdk.data.models.TelemetryEventType
import com.runanywhere.sdk.foundation.ServiceContainer
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import java.util.UUID

/**
 * Example of app-level analytics on top of SDK analytics
 * Demonstrates how to track custom events
 *
 * This is an optional layer that apps can use to track additional
 * app-specific events beyond what the SDK automatically tracks.
 */
object AppAnalytics {
    private val analyticsScope = CoroutineScope(Dispatchers.IO)
    
    // Simple session ID generator (could be improved to persist across app restarts)
    private var currentSessionId: String = UUID.randomUUID().toString()

    /**
     * Get current device ID from SDK
     */
    private fun getDeviceId(): String {
        return try {
            BaseRunAnywhereSDK.sharedDeviceId ?: "unknown"
        } catch (e: Exception) {
            "unknown"
        }
    }

    /**
     * Track when user sends a message
     * Example of custom event tracking
     */
    fun trackMessageSent(
        conversationId: String,
        messageLength: Int,
        modelId: String
    ) {
        analyticsScope.launch {
            try {
                val analyticsService = ServiceContainer.shared.analyticsService
                if (analyticsService != null) {
                    // Use SDK's analytics service to track custom events
                    // The SDK will handle batching and sending to backend
                    val event = TelemetryData(
                        id = UUID.randomUUID().toString(),
                        type = TelemetryEventType.CUSTOM_EVENT,
                        name = "message_sent",
                        properties = mapOf(
                            "conversation_id" to conversationId,
                            "message_length" to messageLength.toString(),
                            "model_id" to modelId
                        ),
                        sessionId = currentSessionId,
                        deviceId = getDeviceId(),
                        sdkVersion = com.runanywhere.sdk.core.SDKConstants.SDK_VERSION,
                        osVersion = android.os.Build.VERSION.RELEASE,
                        timestamp = System.currentTimeMillis(),
                        success = true
                    )

                    // Save event via telemetry repository (will be batched and sent)
                    ServiceContainer.shared.telemetryRepository.saveEvent(event)
                }
            } catch (e: Exception) {
                // Analytics failures should not break app functionality
                android.util.Log.w("AppAnalytics", "Failed to track message sent: ${e.message}")
            }
        }
    }

    /**
     * Track when user creates a new conversation
     */
    fun trackConversationCreated(conversationId: String) {
        analyticsScope.launch {
            try {
                val analyticsService = ServiceContainer.shared.analyticsService
                if (analyticsService != null) {
                    val event = TelemetryData(
                        id = UUID.randomUUID().toString(),
                        type = TelemetryEventType.CUSTOM_EVENT,
                        name = "conversation_created",
                        properties = mapOf(
                            "conversation_id" to conversationId
                        ),
                        sessionId = currentSessionId,
                        deviceId = getDeviceId(),
                        sdkVersion = com.runanywhere.sdk.core.SDKConstants.SDK_VERSION,
                        osVersion = android.os.Build.VERSION.RELEASE,
                        timestamp = System.currentTimeMillis(),
                        success = true
                    )

                    ServiceContainer.shared.telemetryRepository.saveEvent(event)
                }
            } catch (e: Exception) {
                android.util.Log.w("AppAnalytics", "Failed to track conversation created: ${e.message}")
            }
        }
    }

    /**
     * Track when user downloads a model
     */
    fun trackModelDownloadStarted(modelId: String, modelSize: Long) {
        analyticsScope.launch {
            try {
                val event = TelemetryData(
                    id = UUID.randomUUID().toString(),
                    type = TelemetryEventType.MODEL_DOWNLOAD_STARTED,
                    name = "model_download_started",
                    properties = mapOf(
                        "model_id" to modelId,
                        "model_size_bytes" to modelSize.toString()
                    ),
                    sessionId = currentSessionId,
                    deviceId = getDeviceId(),
                    sdkVersion = com.runanywhere.sdk.core.SDKConstants.SDK_VERSION,
                    osVersion = android.os.Build.VERSION.RELEASE,
                    timestamp = System.currentTimeMillis(),
                    success = true
                )

                ServiceContainer.shared.telemetryRepository.saveEvent(event)
            } catch (e: Exception) {
                android.util.Log.w("AppAnalytics", "Failed to track model download: ${e.message}")
            }
        }
    }
}

