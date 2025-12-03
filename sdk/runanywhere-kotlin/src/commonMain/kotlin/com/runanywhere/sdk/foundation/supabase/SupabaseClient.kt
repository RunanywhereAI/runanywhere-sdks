package com.runanywhere.sdk.foundation.supabase

import com.runanywhere.sdk.data.models.SDKEnvironment
import com.runanywhere.sdk.data.network.models.DevAnalyticsSubmissionRequest
import com.runanywhere.sdk.data.network.models.DevAnalyticsSubmissionResponse
import com.runanywhere.sdk.data.network.models.DevDeviceRegistrationRequest
import com.runanywhere.sdk.data.network.models.DevDeviceRegistrationResponse
import com.runanywhere.sdk.foundation.SDKLogger
import io.ktor.client.*
import io.ktor.client.call.*
import io.ktor.client.plugins.*
import io.ktor.client.plugins.contentnegotiation.*
import io.ktor.client.request.*
import io.ktor.client.statement.*
import io.ktor.http.*
import io.ktor.serialization.kotlinx.json.*
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.Json

/**
 * Internal Supabase configuration
 * Matches iOS SupabaseConfig
 *
 * Reference: sdk/runanywhere-swift/Sources/RunAnywhere/Public/Configuration/SDKEnvironment.swift:72
 */
internal data class SupabaseConfig(
    val projectUrl: String,
    val anonKey: String
) {
    companion object {
        /**
         * Get Supabase configuration for the given environment
         * Auto-configured based on environment - user does NOT pass this
         *
         * Matches iOS: SupabaseConfig.configuration(for:)
         */
        fun configuration(environment: SDKEnvironment): SupabaseConfig? {
            return when (environment) {
                SDKEnvironment.DEVELOPMENT -> {
                    // Development mode: Use RunAnywhere's public Supabase for dev analytics
                    // Note: Anon key is safe to include in client code - data access is controlled by RLS policies
                    SupabaseConfig(
                        projectUrl = "https://fhtgjtxuoikwwouxqzrn.supabase.co",
                        anonKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImZodGdqdHh1b2lrd3dvdXhxenJuIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjExOTkwNzIsImV4cCI6MjA3Njc3NTA3Mn0.aIssX-t8CIqt8zoctNhMS8fm3wtH-DzsQiy9FunqD9E"
                    )
                }
                SDKEnvironment.STAGING, SDKEnvironment.PRODUCTION -> {
                    // Production/Staging: No Supabase, use traditional backend
                    null
                }
            }
        }
    }
}

/**
 * HTTP client wrapper for Supabase REST API
 *
 * Handles development mode analytics and device registration
 * Reference: iOS SDK uses URLSession for Supabase REST API calls
 */
internal class SupabaseClient(private val config: SupabaseConfig) {

    private val logger = SDKLogger("SupabaseClient")

    private val httpClient = HttpClient {
        install(ContentNegotiation) {
            json(Json {
                ignoreUnknownKeys = true
                prettyPrint = true
                isLenient = true
            })
        }

        // Add timeout to prevent blocking generation when offline
        // Development analytics should never block user functionality
        install(HttpTimeout) {
            requestTimeoutMillis = 5000  // 5 second timeout
            connectTimeoutMillis = 3000  // 3 second connect timeout
            socketTimeoutMillis = 5000   // 5 second socket timeout
        }
    }

    /**
     * Register device with Supabase (development mode)
     *
     * Endpoint: POST {projectUrl}/rest/v1/sdk_devices
     * Uses UPSERT resolution strategy (merge-duplicates)
     */
    suspend fun registerDevice(request: DevDeviceRegistrationRequest): Result<Unit> = withContext(Dispatchers.IO) {
        try {
            logger.info("📱 [SUPABASE] Registering device with Supabase")
            logger.info("📱 [SUPABASE] Device ID: ${request.deviceId}")
            logger.info("📱 [SUPABASE] Platform: ${request.platform}")
            logger.info("📱 [SUPABASE] SDK Version: ${request.sdkVersion}")
            logger.info("📱 [SUPABASE] URL: ${config.projectUrl}/rest/v1/sdk_devices")

            val response: HttpResponse = httpClient.post("${config.projectUrl}/rest/v1/sdk_devices") {
                headers {
                    append("apikey", config.anonKey)
                    append("Authorization", "Bearer ${config.anonKey}")
                    append("Content-Type", "application/json")
                    append("Prefer", "resolution=merge-duplicates") // UPSERT
                }
                contentType(ContentType.Application.Json)
                setBody(request)
            }

            logger.info("📱 [SUPABASE] Response status: ${response.status.value}")

            if (response.status.isSuccess()) {
                logger.info("✅ Device registered successfully with Supabase")
                return@withContext Result.success(Unit)
            } else {
                val errorBody = response.bodyAsText()
                logger.warning("⚠️ Device registration failed: ${response.status} - $errorBody")
                return@withContext Result.failure(Exception("Device registration failed: ${response.status}"))
            }

        } catch (e: Exception) {
            logger.warning("⚠️ Device registration failed (non-critical): ${e.message}")
            return@withContext Result.failure(e)
        }
    }

    /**
     * Submit generation analytics to Supabase (development mode)
     *
     * Endpoint: POST {projectUrl}/rest/v1/sdk_generation_analytics
     * Matches iOS: Just check HTTP status, don't parse response
     */
    suspend fun submitAnalytics(request: DevAnalyticsSubmissionRequest): Result<Unit> =
        withContext(Dispatchers.IO) {
        try {
            logger.info("📊 [SUPABASE] ========== Submitting Analytics to Supabase ==========")
            logger.info("📊 [SUPABASE] Generation ID: ${request.generationId}")
            logger.info("📊 [SUPABASE] Device ID: ${request.deviceId}")
            logger.info("📊 [SUPABASE] Model ID: ${request.modelId}")
            logger.info("📊 [SUPABASE] Build Token: ${request.buildToken}")
            logger.info("📊 [SUPABASE] SDK Version: ${request.sdkVersion}")
            logger.info("📊 [SUPABASE] Timestamp: ${request.timestamp}")
            logger.info("📊 [SUPABASE] URL: ${config.projectUrl}/rest/v1/sdk_generation_analytics")
            logger.info("📊 [SUPABASE] Performance: TTFT=${request.timeToFirstTokenMs}ms, TPS=${request.tokensPerSecond}, Total=${request.totalGenerationTimeMs}ms")
            logger.info("📊 [SUPABASE] Tokens: input=${request.inputTokens}, output=${request.outputTokens}")
            logger.info("📊 [SUPABASE] Execution Target: ${request.executionTarget}")

            // Make POST request and get raw HTTP response (like iOS)
            val httpResponse = httpClient.post(
                "${config.projectUrl}/rest/v1/sdk_generation_analytics"
            ) {
                headers {
                    append("apikey", config.anonKey)
                    append("Authorization", "Bearer ${config.anonKey}")
                    append("Content-Type", "application/json")
                }
                contentType(ContentType.Application.Json)
                setBody(request)
            }

            logger.info("📊 [SUPABASE] Response HTTP Status: ${httpResponse.status.value}")

            // Check HTTP status code (matches iOS behavior exactly)
            if (httpResponse.status == HttpStatusCode.OK || httpResponse.status == HttpStatusCode.Created) {
                logger.debug("📊 Analytics submitted successfully to Supabase (HTTP ${httpResponse.status.value})")
                return@withContext Result.success(Unit)
            } else {
                // Log detailed error information
                val responseBody = try {
                    httpResponse.bodyAsText()
                } catch (e: Exception) {
                    "Unable to read response body: ${e.message}"
                }
                val errorMsg = "Analytics submission failed with HTTP ${httpResponse.status.value}"
                logger.warning("⚠️ $errorMsg")
                logger.warning("⚠️ Response body: $responseBody")
                return@withContext Result.failure(Exception("$errorMsg - Response: $responseBody"))
            }

        } catch (e: Exception) {
            logger.warning("⚠️ Failed to submit analytics to Supabase: ${e.message}")
            // Fail silently - don't disrupt SDK operations
            return@withContext Result.failure(e)
        }
    }

    /**
     * Close HTTP client resources
     */
    fun close() {
        httpClient.close()
    }
}
