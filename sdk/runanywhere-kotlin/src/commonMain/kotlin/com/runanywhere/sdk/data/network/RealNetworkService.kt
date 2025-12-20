package com.runanywhere.sdk.data.network

import com.runanywhere.sdk.data.models.SDKError
import com.runanywhere.sdk.data.network.models.APIEndpoint
import com.runanywhere.sdk.foundation.SDKLogger
import kotlinx.coroutines.delay
import kotlinx.serialization.decodeFromString
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import kotlin.math.pow
import kotlin.random.Random

/**
 * Real NetworkService implementation that makes actual HTTP calls
 * Replaces MockNetworkService with production-ready networking
 * Matches iOS APIClient functionality with authentication, retry logic, and error handling
 */
class RealNetworkService(
    private val httpClient: HttpClient,
    private val baseURL: String,
    private val authenticationService: AuthenticationService? = null,
    private val maxRetryAttempts: Int = 3,
    private val baseDelayMs: Long = 1000,
) : NetworkService {
    private val logger = SDKLogger("RealNetworkService")

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
     * Execute HTTP request with retry logic and exponential backoff
     * Matches iOS APIClient implementation patterns
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
                val headers = buildHeaders(endpoint, requiresAuth, payload)

                logger.debug("$method request to: $url (attempt ${attempt + 1}/$maxRetryAttempts)")

                val response =
                    when (method) {
                        "GET" -> httpClient.get(url, headers)
                        "POST" -> httpClient.post(url, payload ?: ByteArray(0), headers)
                        else -> throw IllegalArgumentException("Unsupported HTTP method: $method")
                    }

                if (response.isSuccessful) {
                    logger.debug("$method request successful: $url")
                    return response.body
                } else {
                    val error = handleHttpError(response, endpoint, method)

                    // Retry only on specific error conditions
                    if (shouldRetry(response.statusCode, attempt)) {
                        lastException = error
                        attempt++
                        if (attempt < maxRetryAttempts) {
                            val delayMs = calculateBackoffDelay(attempt)
                            logger.warn("$method request failed with ${response.statusCode}, retrying in ${delayMs}ms")
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
     * Build full URL from endpoint
     */
    private fun buildFullUrl(endpoint: APIEndpoint): String =
        if (endpoint.url.startsWith("http")) {
            endpoint.url
        } else {
            "$baseURL${if (!endpoint.url.startsWith("/")) "/" else ""}${endpoint.url}"
        }

    /**
     * Build headers for the request with authentication
     * Matches iOS APIClient header patterns
     */
    private suspend fun buildHeaders(
        endpoint: APIEndpoint,
        requiresAuth: Boolean,
        payload: ByteArray?,
    ): Map<String, String> {
        val headers =
            mutableMapOf<String, String>(
                "Content-Type" to "application/json",
                "Accept" to "application/json",
                "User-Agent" to "RunAnywhere-Kotlin-SDK/0.1.0",
                "X-SDK-Client" to "RunAnywhereKotlinSDK",
                "X-SDK-Version" to "0.1.0",
                "X-Platform" to "Kotlin",
            )

        // Set content type based on payload
        if (payload != null) {
            headers["Content-Type"] = if (isJsonPayload(payload)) "application/json" else "application/octet-stream"
        }

        // Add authentication header
        if (requiresAuth) {
            addAuthHeader(headers, endpoint)
        }

        return headers
    }

    /**
     * Add authentication header based on endpoint type
     * Matches iOS authentication patterns
     */
    private suspend fun addAuthHeader(
        headers: MutableMap<String, String>,
        endpoint: APIEndpoint,
    ) {
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
                        headers["Authorization"] = "Bearer $token"
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
     * Check if payload appears to be JSON
     */
    private fun isJsonPayload(payload: ByteArray): Boolean {
        if (payload.isEmpty()) return false
        val firstChar = payload[0].toInt().toChar()
        return firstChar == '{' || firstChar == '['
    }

    /**
     * Handle HTTP errors and create appropriate SDKError
     * Matches iOS error handling patterns
     */
    private fun handleHttpError(
        response: HttpResponse,
        endpoint: APIEndpoint,
        method: String,
    ): SDKError {
        val responseBody =
            try {
                response.body.decodeToString()
            } catch (e: Exception) {
                null
            }

        // Log detailed error info for debugging
        logger.error("HTTP ${response.statusCode} for $method ${endpoint.url}${if (responseBody != null) ": $responseBody" else ""}")

        return when (response.statusCode) {
            401 -> SDKError.InvalidAPIKey("Authentication failed for $method ${endpoint.url}")
            403 -> SDKError.InvalidAPIKey("Access forbidden for $method ${endpoint.url}")
            404 -> SDKError.NetworkError("Endpoint not found: $method ${endpoint.url}")
            408 -> SDKError.NetworkError("Request timeout for $method ${endpoint.url}")
            422 ->
                SDKError.NetworkError(
                    "Validation error for $method ${endpoint.url}${if (responseBody != null) ": $responseBody" else ""}",
                )
            429 -> SDKError.NetworkError("Rate limit exceeded for $method ${endpoint.url}")
            in 500..599 -> SDKError.NetworkError("Server error ${response.statusCode} for $method ${endpoint.url}")
            else -> SDKError.NetworkError("HTTP ${response.statusCode} for $method ${endpoint.url}")
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
     * Matches iOS retry patterns
     */
    private fun calculateBackoffDelay(attempt: Int): Long {
        val exponentialDelay = baseDelayMs * (2.0.pow(attempt - 1)).toLong()
        val jitter = Random.nextLong(0, exponentialDelay / 4) // Add up to 25% jitter
        return (exponentialDelay + jitter).coerceAtMost(30000) // Cap at 30 seconds
    }
}

/**
 * Extension functions for reified type support with RealNetworkService
 * These provide type-safe API calls with actual JSON serialization/deserialization
 */
suspend inline fun <reified T : Any, reified R : Any> RealNetworkService.postTyped(
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

suspend inline fun <reified R : Any> RealNetworkService.getTyped(
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
