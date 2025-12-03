package com.runanywhere.sdk.data.network.services

import com.runanywhere.sdk.core.SDKConstants
import com.runanywhere.sdk.data.models.TelemetryBatch
import com.runanywhere.sdk.data.models.TelemetryData
import com.runanywhere.sdk.data.network.models.APIEndpoint
import com.runanywhere.sdk.foundation.SDKLogger
import com.runanywhere.sdk.services.AuthenticationService
import io.ktor.client.*
import io.ktor.client.call.*
import io.ktor.client.plugins.contentnegotiation.*
import io.ktor.client.request.*
import io.ktor.client.statement.*
import io.ktor.http.*
import io.ktor.serialization.kotlinx.json.*
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.Json

/**
 * Network service for analytics operations.
 * Matches Swift SDK's RemoteTelemetryDataSource.swift
 *
 * Handles production analytics API calls with proper authentication and error handling.
 */
internal class AnalyticsNetworkService(
    private val httpClient: HttpClient,
    private val baseURL: String,
    private val apiKey: String,
    private val authenticationService: AuthenticationService? = null
) {
    private val logger = SDKLogger("AnalyticsNetworkService")

    private val json = Json {
        ignoreUnknownKeys = true
        prettyPrint = false
        isLenient = true
        encodeDefaults = false
    }

    /**
     * Submit batch of telemetry events to production backend
     * Matches Swift SDK's submitBatch() in RemoteTelemetryDataSource.swift
     *
     * @param batch Telemetry batch to submit
     * @return Result indicating success or failure
     */
    suspend fun submitTelemetryBatch(batch: TelemetryBatch): Result<Unit> = withContext(Dispatchers.IO) {
        runCatching {
            logger.debug("Submitting telemetry batch with ${batch.events.size} events to ${APIEndpoint.telemetry.url}")

            val url = buildFullUrl(APIEndpoint.telemetry)

            val response: HttpResponse = httpClient.post(url) {
                contentType(ContentType.Application.Json)
                
                // Add authentication header
                addAuthHeaders()

                // Add SDK headers
                headers {
                    append("X-SDK-Client", "kotlin")
                    append("X-SDK-Version", getSDKVersion())
                    append("X-Platform", getPlatform())
                }

                setBody(batch)
            }

            if (response.status.isSuccess()) {
                logger.debug("✅ Successfully submitted telemetry batch (HTTP ${response.status.value})")
                Result.success(Unit)
            } else {
                val errorBody = try {
                    response.bodyAsText()
                } catch (e: Exception) {
                    "Unable to read response body: ${e.message}"
                }
                val errorMsg = "Telemetry batch submission failed with HTTP ${response.status.value}"
                logger.warning("⚠️ $errorMsg")
                logger.warning("⚠️ Response body: $errorBody")
                Result.failure(Exception("$errorMsg - Response: $errorBody"))
            }
        }.getOrElse { exception ->
            logger.warning("⚠️ Failed to submit telemetry batch: ${exception.message}")
            Result.failure(exception)
        }
    }

    /**
     * Submit single telemetry event
     * Matches Swift SDK's TelemetryService.trackEvent()
     *
     * @param event Telemetry event to submit
     * @return Result indicating success or failure
     */
    suspend fun submitTelemetryEvent(event: TelemetryData): Result<Unit> = withContext(Dispatchers.IO) {
        runCatching {
            // Create a batch with single event
            val batch = TelemetryBatch(
                events = listOf(event),
                deviceId = event.deviceId,
                sessionId = event.sessionId,
                sdkVersion = event.sdkVersion,
                appVersion = event.appVersion
            )
            submitTelemetryBatch(batch).getOrThrow()
        }
    }

    /**
     * Register device for analytics tracking
     * Used for device registration in production mode
     *
     * @param deviceInfo Device information to register
     * @return Result with device registration response
     */
    suspend fun registerDevice(deviceInfo: Map<String, Any>): Result<DeviceRegistrationResponse> = withContext(Dispatchers.IO) {
        runCatching {
            logger.debug("Registering device for analytics tracking")

            val url = buildFullUrl(APIEndpoint.registerDevice)

            val response: DeviceRegistrationResponse = httpClient.post(url) {
                contentType(ContentType.Application.Json)
                
                // Add authentication header
                addAuthHeaders()

                setBody(deviceInfo)
            }.body()

            logger.debug("✅ Device registered successfully: ${response.deviceId}")
            Result.success(response)
        }.getOrElse { exception ->
            logger.warning("⚠️ Device registration failed: ${exception.message}")
            Result.failure(exception)
        }
    }

    /**
     * Add authentication headers to request
     * Uses Bearer token if available, falls back to API key
     */
    private suspend fun HttpRequestBuilder.addAuthHeaders() {
        try {
            // Try to get Bearer token from authentication service
            val authToken = authenticationService?.getAccessToken()
            
            if (authToken != null) {
                headers {
                    append(HttpHeaders.Authorization, "Bearer $authToken")
                }
                logger.debug("Using Bearer token for analytics request")
            } else {
                // Fallback to API key
                headers {
                    append("X-API-Key", apiKey)
                }
                logger.debug("Using API key for analytics request")
            }
        } catch (e: Exception) {
            logger.warning("Failed to add auth headers: ${e.message}")
            // Still proceed with API key fallback
            headers {
                append("X-API-Key", apiKey)
            }
        }
    }

    /**
     * Build full URL from endpoint
     */
    private fun buildFullUrl(endpoint: APIEndpoint): String {
        return if (endpoint.url.startsWith("http")) {
            endpoint.url
        } else {
            "$baseURL${if (!endpoint.url.startsWith("/")) "/" else ""}${endpoint.url}"
        }
    }

    /**
     * Get SDK version
     */
    private fun getSDKVersion(): String {
        return SDKConstants.SDK_VERSION
    }

    /**
     * Get platform identifier
     */
    private fun getPlatform(): String {
        return try {
            // Try to detect platform
            when {
                System.getProperty("java.vm.name")?.contains("Android", ignoreCase = true) == true -> "android"
                else -> "jvm"
            }
        } catch (e: Exception) {
            "unknown"
        }
    }

    /**
     * Close HTTP client resources
     */
    fun close() {
        // Don't close shared HttpClient - it's managed elsewhere
    }
}

/**
 * Device registration response
 * Matches Swift SDK's DeviceRegistrationResponse
 */
@kotlinx.serialization.Serializable
data class DeviceRegistrationResponse(
    val deviceId: String,
    val registered: Boolean,
    val timestamp: Long? = null
)

