package com.runanywhere.sdk.data.network

import com.runanywhere.sdk.data.models.SDKError
import com.runanywhere.sdk.data.network.models.APIEndpoint
import com.runanywhere.sdk.foundation.SDKLogger
import io.ktor.client.request.HttpRequestBuilder
import io.ktor.client.request.get
import io.ktor.client.request.headers
import io.ktor.client.request.post
import io.ktor.client.request.setBody
import io.ktor.client.statement.bodyAsText
import io.ktor.client.statement.readBytes
import io.ktor.http.ContentType
import io.ktor.http.HttpHeaders
import io.ktor.http.append
import io.ktor.http.contentType
import io.ktor.http.isSuccess
import kotlinx.coroutines.delay
import kotlinx.serialization.json.Json
import kotlin.math.pow
import kotlin.random.Random
import io.ktor.client.HttpClient as KtorClient
import io.ktor.client.statement.HttpResponse as KtorHttpResponse

/**
 * Ktor-based NetworkService implementation for cross-platform real networking
 * Provides production-ready HTTP networking with authentication, retry logic, and error handling
 * Alternative to platform-specific implementations when Ktor is preferred
 */
class KtorNetworkService(
    private val ktorClient: KtorClient,
    private val baseURL: String,
    private val authenticationService: AuthenticationService? = null,
    private val maxRetryAttempts: Int = 3,
    private val baseDelayMs: Long = 1000,
) : NetworkService {
    private val logger = SDKLogger("KtorNetworkService")

    private val jsonSerializer =
        Json {
            ignoreUnknownKeys = true
            isLenient = true
            encodeDefaults = false
            prettyPrint = false
            coerceInputValues = true
        }

    /**
     * POST request with JSON payload and typed response
     * Note: This implementation requires extension functions with reified types for actual usage
     */
    override suspend fun <T : Any, R : Any> post(
        endpoint: APIEndpoint,
        payload: T,
        requiresAuth: Boolean,
    ): R = throw UnsupportedOperationException("Use postTyped extension function with reified types instead")

    /**
     * GET request with typed response
     * Note: This implementation requires extension functions with reified types for actual usage
     */
    override suspend fun <R : Any> get(
        endpoint: APIEndpoint,
        requiresAuth: Boolean,
    ): R = throw UnsupportedOperationException("Use getTyped extension function with reified types instead")

    /**
     * POST request with raw data payload
     */
    override suspend fun postRaw(
        endpoint: APIEndpoint,
        payload: ByteArray,
        requiresAuth: Boolean,
    ): ByteArray {
        logger.debug("POST raw request to: ${endpoint.url}")
        return executeWithRetry("POST", endpoint, payload, requiresAuth)
    }

    /**
     * GET request with raw data response
     */
    override suspend fun getRaw(
        endpoint: APIEndpoint,
        requiresAuth: Boolean,
    ): ByteArray {
        logger.debug("GET raw request from: ${endpoint.url}")
        return executeWithRetry("GET", endpoint, null, requiresAuth)
    }

    /**
     * Execute HTTP request with retry logic and exponential backoff using Ktor
     */
    private suspend fun executeWithRetry(
        method: String,
        endpoint: APIEndpoint,
        payload: ByteArray?,
        requiresAuth: Boolean,
    ): ByteArray {
        var attempt = 0
        var lastException: Exception? = null

        while (attempt < maxRetryAttempts) {
            try {
                val url = buildFullUrl(endpoint)
                logger.debug("$method request to: $url (attempt ${attempt + 1}/$maxRetryAttempts)")

                val response: KtorHttpResponse =
                    when (method) {
                        "GET" ->
                            ktorClient.get(url) {
                                setupRequest(endpoint, requiresAuth, null)
                            }
                        "POST" ->
                            ktorClient.post(url) {
                                setupRequest(endpoint, requiresAuth, payload)
                                if (payload != null) {
                                    setBody(payload)
                                }
                            }
                        else -> throw IllegalArgumentException("Unsupported HTTP method: $method")
                    }

                if (response.status.isSuccess()) {
                    logger.debug("$method request successful: $url")
                    return response.readBytes()
                } else {
                    val error = handleKtorHttpError(response, endpoint, method)

                    // Retry only on specific error conditions
                    if (shouldRetry(response.status.value, attempt)) {
                        lastException = error
                        attempt++
                        if (attempt < maxRetryAttempts) {
                            val delayMs = calculateBackoffDelay(attempt)
                            logger.warn("$method request failed with ${response.status.value}, retrying in ${delayMs}ms")
                            delay(delayMs)
                            continue
                        }
                    }

                    throw error
                }
            } catch (e: Exception) {
                lastException = e

                if (!shouldRetryException(e, attempt)) {
                    logger.error("$method request failed: ${endpoint.url} - ${e.message}")
                    throw when (e) {
                        is SDKError -> e
                        else -> SDKError.NetworkError("$method request failed: ${e.message}")
                    }
                }

                attempt++
                if (attempt < maxRetryAttempts) {
                    val delayMs = calculateBackoffDelay(attempt)
                    logger.warn("$method request failed, retrying in ${delayMs}ms: ${e.message}")
                    delay(delayMs)
                } else {
                    logger.error("$method request failed after $maxRetryAttempts attempts: ${endpoint.url}")
                    throw when (e) {
                        is SDKError -> e
                        else -> SDKError.NetworkError("$method request failed after retries: ${e.message}")
                    }
                }
            }
        }

        throw lastException ?: SDKError.NetworkError("Request failed after $maxRetryAttempts attempts")
    }

    /**
     * Setup Ktor request with headers and authentication
     */
    private suspend fun HttpRequestBuilder.setupRequest(
        endpoint: APIEndpoint,
        requiresAuth: Boolean,
        payload: ByteArray?,
    ) {
        // Set basic headers
        headers {
            append(HttpHeaders.Accept, "application/json")
            append(HttpHeaders.UserAgent, "RunAnywhere-Kotlin-SDK/0.1.0")
            append("X-SDK-Client", "RunAnywhereKotlinSDK")
            append("X-SDK-Version", "0.1.0")
            append("X-Platform", "Kotlin")
        }

        // Set content type based on payload
        if (payload != null) {
            val contentType =
                if (isJsonPayload(payload)) {
                    ContentType.Application.Json
                } else {
                    ContentType.Application.OctetStream
                }
            contentType(contentType)
        }

        // Add authentication header
        if (requiresAuth) {
            addKtorAuthHeader(endpoint)
        }
    }

    /**
     * Add authentication header for Ktor request
     */
    private suspend fun HttpRequestBuilder.addKtorAuthHeader(endpoint: APIEndpoint) {
        try {
            when {
                // Authentication endpoints - DO NOT add Authorization header
                endpoint.url.contains("/auth/sdk/authenticate") ||
                    endpoint.url.contains("/auth/sdk/refresh") ||
                    endpoint.url.contains("/auth/token") -> {
                    logger.debug("Skipping Authorization header for authentication endpoint: ${endpoint.url}")
                }
                // All other endpoints - use access token
                else -> {
                    val token = authenticationService?.getAccessToken()
                    if (token != null) {
                        headers {
                            append(HttpHeaders.Authorization, "Bearer $token")
                        }
                        logger.debug("Using access token for endpoint: ${endpoint.url}")
                    } else {
                        logger.warn("No access token available for authenticated request to: ${endpoint.url}")
                        throw SDKError.InvalidAPIKey("No access token available for authenticated request")
                    }
                }
            }
        } catch (e: Exception) {
            logger.error("Failed to add auth header for ${endpoint.url}: ${e.message}")
            if (e is SDKError) throw e
            throw SDKError.InvalidAPIKey("Authentication failed: ${e.message}")
        }
    }

    /**
     * Build full URL from endpoint
     */
    private fun buildFullUrl(endpoint: APIEndpoint): String =
        if (endpoint.url.startsWith("http")) {
            endpoint.url
        } else {
            "$baseURL${if (!endpoint.url.startsWith("/")) "/" else ""}${endpoint.url}"
        }

    /**
     * Check if payload appears to be JSON
     */
    private fun isJsonPayload(payload: ByteArray): Boolean {
        if (payload.isEmpty()) return false
        val firstChar = payload[0].toInt().toChar()
        return firstChar == '{' || firstChar == '['
    }

    /**
     * Handle Ktor HTTP errors and create appropriate SDKError
     */
    private suspend fun handleKtorHttpError(
        response: KtorHttpResponse,
        endpoint: APIEndpoint,
        method: String,
    ): SDKError {
        val responseBody =
            try {
                response.bodyAsText()
            } catch (e: Exception) {
                null
            }

        // Log detailed error info for debugging
        logger.error("HTTP ${response.status.value} for $method ${endpoint.url}${if (responseBody != null) ": $responseBody" else ""}")

        return when (response.status.value) {
            401 -> SDKError.InvalidAPIKey("Authentication failed for $method ${endpoint.url}")
            403 -> SDKError.InvalidAPIKey("Access forbidden for $method ${endpoint.url}")
            404 -> SDKError.NetworkError("Endpoint not found: $method ${endpoint.url}")
            408 -> SDKError.NetworkError("Request timeout for $method ${endpoint.url}")
            422 ->
                SDKError.NetworkError(
                    "Validation error for $method ${endpoint.url}${if (responseBody != null) ": $responseBody" else ""}",
                )
            429 -> SDKError.NetworkError("Rate limit exceeded for $method ${endpoint.url}")
            in 500..599 -> SDKError.NetworkError("Server error ${response.status.value} for $method ${endpoint.url}")
            else -> SDKError.NetworkError("HTTP ${response.status.value} for $method ${endpoint.url}")
        }
    }

    /**
     * Determine if we should retry based on HTTP status code
     */
    private fun shouldRetry(
        statusCode: Int,
        attempt: Int,
    ): Boolean {
        if (attempt >= maxRetryAttempts - 1) return false

        return when (statusCode) {
            408, 429 -> true // Timeout, Rate limit
            in 500..599 -> true // Server errors
            else -> false // Client errors should not be retried
        }
    }

    /**
     * Determine if we should retry based on exception type
     */
    private fun shouldRetryException(
        exception: Exception,
        attempt: Int,
    ): Boolean {
        if (attempt >= maxRetryAttempts - 1) return false

        return when (exception) {
            is SDKError.InvalidAPIKey -> false // Don't retry auth errors
            is SDKError.NetworkError -> {
                val message = exception.message?.lowercase() ?: ""
                message.contains("timeout") ||
                    message.contains("connection") ||
                    message.contains("network") ||
                    message.contains("host")
            }
            else -> true // Retry on other exceptions
        }
    }

    /**
     * Calculate exponential backoff delay with jitter
     */
    private fun calculateBackoffDelay(attempt: Int): Long {
        val exponentialDelay = baseDelayMs * (2.0.pow(attempt - 1)).toLong()
        val jitter = Random.nextLong(0, exponentialDelay / 4) // Add up to 25% jitter
        return (exponentialDelay + jitter).coerceAtMost(30000) // Cap at 30 seconds
    }

    /**
     * Clean up Ktor client resources
     */
    fun close() {
        ktorClient.close()
    }
}

/**
 * Extension functions for reified type support with KtorNetworkService
 */
suspend inline fun <reified T : Any, reified R : Any> KtorNetworkService.postTyped(
    endpoint: APIEndpoint,
    payload: T,
    requiresAuth: Boolean = true,
): R {
    val jsonSerializer =
        Json {
            ignoreUnknownKeys = true
            isLenient = true
            encodeDefaults = false
        }

    // Serialize payload to JSON
    val jsonPayload = jsonSerializer.encodeToString(payload)

    // Make raw request
    val responseBytes =
        this.postRaw(
            endpoint = endpoint,
            payload = jsonPayload.encodeToByteArray(),
            requiresAuth = requiresAuth,
        )

    // Deserialize response
    val responseString = responseBytes.decodeToString()
    return jsonSerializer.decodeFromString(responseString)
}

suspend inline fun <reified R : Any> KtorNetworkService.getTyped(
    endpoint: APIEndpoint,
    requiresAuth: Boolean = true,
): R {
    val jsonSerializer =
        Json {
            ignoreUnknownKeys = true
            isLenient = true
        }

    // Make raw request
    val responseBytes =
        this.getRaw(
            endpoint = endpoint,
            requiresAuth = requiresAuth,
        )

    // Deserialize response
    val responseString = responseBytes.decodeToString()
    return jsonSerializer.decodeFromString(responseString)
}
