package com.runanywhere.sdk.network

import com.runanywhere.sdk.data.models.SDKError
import com.runanywhere.sdk.data.network.models.APIEndpoint
import com.runanywhere.sdk.foundation.SDKLogger
import com.runanywhere.sdk.services.AuthenticationService
import kotlinx.coroutines.delay
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.serialization.json.Json
import kotlinx.serialization.serializer
import kotlinx.serialization.encodeToString
import kotlinx.serialization.decodeFromString
import kotlin.math.pow
import kotlin.random.Random

/**
 * Production API Client implementation
 * Handles HTTP operations with authentication, retry logic, logging, and comprehensive error handling
 * Provides parity with iOS APIClient functionality
 */
class APIClient(
    val baseURL: String,
    val apiKey: String,
    val httpClient: HttpClient,
    val authenticationService: AuthenticationService? = null,
    private val networkChecker: NetworkChecker? = null,
    private val maxRetryAttempts: Int = 3,
    private val baseDelayMs: Long = 1000
) : NetworkService {

    /**
     * Network request interceptor for modifying requests before sending
     */
    interface RequestInterceptor {
        suspend fun intercept(request: NetworkRequest): NetworkRequest
    }

    /**
     * Network response interceptor for modifying responses after receiving
     */
    interface ResponseInterceptor {
        suspend fun intercept(response: NetworkResponse): NetworkResponse
    }

    data class NetworkRequest(
        val url: String,
        val method: String,
        val headers: MutableMap<String, String>,
        val body: ByteArray?
    )

    data class NetworkResponse(
        val statusCode: Int,
        val headers: Map<String, List<String>>,
        val body: ByteArray,
        val isSuccessful: Boolean
    )

    private val logger = SDKLogger("APIClient")
    private val mutex = Mutex()

    private val requestInterceptors = mutableListOf<RequestInterceptor>()
    private val responseInterceptors = mutableListOf<ResponseInterceptor>()

    // Default headers that will be included in all requests
    private val defaultHeaders = mutableMapOf<String, String>(
        "Content-Type" to "application/json",
        "X-SDK-Client" to "RunAnywhereSDK-Kotlin",
        "X-SDK-Version" to "0.1.0",
        "Accept" to "application/json"
    )

    init {
        logger.info("APIClient initialized with baseURL: $baseURL")
        httpClient.setDefaultHeaders(defaultHeaders)
        httpClient.setDefaultTimeout(30000) // 30 second default timeout
    }

    private val jsonSerializer = Json {
        ignoreUnknownKeys = true
        isLenient = true
        encodeDefaults = false
        prettyPrint = false
        coerceInputValues = true
    }

    // MARK: - Public API

    /**
     * Add a request interceptor
     */
    fun addRequestInterceptor(interceptor: RequestInterceptor) {
        requestInterceptors.add(interceptor)
    }

    /**
     * Add a response interceptor
     */
    fun addResponseInterceptor(interceptor: ResponseInterceptor) {
        responseInterceptors.add(interceptor)
    }

    /**
     * Set default headers for all requests
     */
    fun setDefaultHeaders(headers: Map<String, String>) {
        defaultHeaders.putAll(headers)
        httpClient.setDefaultHeaders(defaultHeaders)
    }

    /**
     * POST request with JSON payload and typed response
     * Note: For actual usage, create extension functions with reified types
     */
    override suspend fun <T, R> post(endpoint: String, payload: T, requiresAuth: Boolean): R {
        throw UnsupportedOperationException("Use postJson extension function instead")
    }

    /**
     * GET request with typed response
     * Note: For actual usage, create extension functions with reified types
     */
    override suspend fun <R> get(endpoint: String, requiresAuth: Boolean): R {
        throw UnsupportedOperationException("Use getJson extension function instead")
    }

    /**
     * POST request with raw data payload
     */
    override suspend fun postRaw(
        endpoint: String,
        payload: ByteArray,
        requiresAuth: Boolean
    ): ByteArray = executeWithRetry("POST", endpoint, payload, requiresAuth) { request ->
        httpClient.post(
            url = request.url,
            body = request.body ?: ByteArray(0),
            headers = request.headers
        )
    }

    /**
     * GET request with raw data response
     */
    override suspend fun getRaw(endpoint: String, requiresAuth: Boolean): ByteArray =
        executeWithRetry("GET", endpoint, null, requiresAuth) { request ->
            httpClient.get(
                url = request.url,
                headers = request.headers
            )
        }

    /**
     * PUT request with JSON payload and typed response
     * Note: For actual usage, create extension functions with reified types
     */
    override suspend fun <T, R> put(endpoint: String, payload: T, requiresAuth: Boolean): R {
        throw UnsupportedOperationException("Use putJson extension function instead")
    }

    /**
     * PUT request with raw data payload
     */
    suspend fun putRaw(
        endpoint: String,
        payload: ByteArray,
        requiresAuth: Boolean = false
    ): ByteArray = executeWithRetry("PUT", endpoint, payload, requiresAuth) { request ->
        httpClient.put(
            url = request.url,
            body = request.body ?: ByteArray(0),
            headers = request.headers
        )
    }

    /**
     * DELETE request
     */
    override suspend fun delete(endpoint: String, requiresAuth: Boolean) {
        executeWithRetry("DELETE", endpoint, null, requiresAuth) { request ->
            httpClient.delete(
                url = request.url,
                headers = request.headers
            )
        }
    }

    /**
     * Download file with progress callback
     */
    override suspend fun downloadFile(
        url: String,
        destinationPath: String,
        progressCallback: ((Float) -> Unit)?
    ): String = mutex.withLock {
        logger.debug("Downloading file from: $url to: $destinationPath")

        try {
            // Check network connectivity before starting download
            if (!isNetworkAvailable()) {
                throw SDKError.NetworkError("No network connectivity available")
            }

            val data = httpClient.download(
                url = url,
                headers = defaultHeaders,
                onProgress = if (progressCallback != null) { bytesDownloaded, totalBytes ->
                    if (totalBytes > 0) {
                        progressCallback(bytesDownloaded.toFloat() / totalBytes)
                    }
                } else null
            )

            // Write to file using platform-specific file system
            writeToFile(destinationPath, data)

            progressCallback?.invoke(1.0f)
            logger.info("File downloaded successfully: $destinationPath")
            return destinationPath

        } catch (e: Exception) {
            logger.error("File download failed: $url - ${e.message}")
            throw when (e) {
                is SDKError -> e
                else -> SDKError.NetworkError("Download failed: ${e.message}")
            }
        }
    }

    /**
     * Check network connectivity
     */
    override suspend fun isNetworkAvailable(): Boolean {
        return networkChecker?.isNetworkAvailable() ?: true
    }

    /**
     * Get network type
     */
    override suspend fun getNetworkType(): String {
        return networkChecker?.getNetworkType() ?: "unknown"
    }

    // MARK: - Private Implementation

    /**
     * Execute HTTP request with retry logic and exponential backoff
     */
    private suspend fun executeWithRetry(
        method: String,
        endpoint: String,
        payload: ByteArray?,
        requiresAuth: Boolean,
        httpCall: suspend (NetworkRequest) -> HttpResponse
    ): ByteArray = mutex.withLock {
        var attempt = 0
        var lastException: Exception? = null

        logger.debug("$method request to: $endpoint, attempt: ${attempt + 1}")

        // Check network connectivity before starting
        if (!isNetworkAvailable()) {
            throw SDKError.NetworkError("No network connectivity available")
        }

        while (attempt < maxRetryAttempts) {
            try {
                // Build request
                val headers = buildHeaders(endpoint, requiresAuth, payload)
                val url = if (endpoint.startsWith("http")) endpoint else "$baseURL${if (!endpoint.startsWith("/")) "/" else ""}$endpoint"

                var request = NetworkRequest(
                    url = url,
                    method = method,
                    headers = headers,
                    body = payload
                )

                // Apply request interceptors
                for (interceptor in requestInterceptors) {
                    request = interceptor.intercept(request)
                }

                // Execute HTTP call
                val httpResponse = httpCall(request)

                // Convert to NetworkResponse and apply interceptors
                var networkResponse = NetworkResponse(
                    statusCode = httpResponse.statusCode,
                    headers = httpResponse.headers,
                    body = httpResponse.body,
                    isSuccessful = httpResponse.isSuccessful
                )

                for (interceptor in responseInterceptors) {
                    networkResponse = interceptor.intercept(networkResponse)
                }

                // Handle response
                if (networkResponse.isSuccessful) {
                    logger.debug("$method request successful: $endpoint")
                    return networkResponse.body
                } else {
                    val error = handleHttpError(networkResponse.statusCode, endpoint, method)

                    // Retry only on specific error conditions
                    if (shouldRetry(networkResponse.statusCode, attempt)) {
                        lastException = error
                        attempt++
                        if (attempt < maxRetryAttempts) {
                            val delayMs = calculateBackoffDelay(attempt)
                            logger.warn("$method request failed with ${networkResponse.statusCode}, retrying in ${delayMs}ms (attempt ${attempt + 1}/$maxRetryAttempts)")
                            delay(delayMs)
                            continue
                        }
                    }

                    throw error
                }

            } catch (e: Exception) {
                lastException = e

                // Don't retry on authentication or client errors
                if (!shouldRetryException(e, attempt)) {
                    logger.error("$method request failed: $endpoint - ${e.message}")
                    throw when (e) {
                        is SDKError -> e
                        else -> SDKError.NetworkError("$method request failed: ${e.message}")
                    }
                }

                attempt++
                if (attempt < maxRetryAttempts) {
                    val delayMs = calculateBackoffDelay(attempt)
                    logger.warn("$method request failed, retrying in ${delayMs}ms (attempt ${attempt + 1}/$maxRetryAttempts): ${e.message}")
                    delay(delayMs)
                } else {
                    logger.error("$method request failed after $maxRetryAttempts attempts: $endpoint - ${e.message}")
                    throw when (e) {
                        is SDKError -> e
                        else -> SDKError.NetworkError("$method request failed after retries: ${e.message}")
                    }
                }
            }
        }

        // Should never reach here, but handle edge case
        throw lastException ?: SDKError.NetworkError("$method request failed after $maxRetryAttempts attempts")
    }

    /**
     * Build headers for the request
     */
    private suspend fun buildHeaders(
        endpoint: String,
        requiresAuth: Boolean,
        payload: ByteArray?
    ): MutableMap<String, String> {
        val headers = defaultHeaders.toMutableMap()

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
     * Add authentication header to request
     */
    private suspend fun addAuthHeader(headers: MutableMap<String, String>, endpoint: String) {
        try {
            when {
                endpoint.contains("/auth/token") -> {
                    // For authentication endpoint, use API key
                    headers["Authorization"] = "Bearer $apiKey"
                }
                else -> {
                    // For other endpoints, use access token
                    val token = authenticationService?.getAccessToken()
                    if (token != null) {
                        headers["Authorization"] = "Bearer $token"
                    } else {
                        logger.warn("No access token available for authenticated request")
                    }
                }
            }
        } catch (e: Exception) {
            logger.warn("Failed to add auth header: ${e.message}")
            // Continue without auth - the server will handle the unauthorized request
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
     */
    private fun handleHttpError(statusCode: Int, endpoint: String, method: String): SDKError {
        return when (statusCode) {
            401 -> SDKError.InvalidAPIKey("Authentication failed for $method $endpoint")
            403 -> SDKError.InvalidAPIKey("Access forbidden for $method $endpoint")
            404 -> SDKError.NetworkError("Endpoint not found: $method $endpoint")
            408 -> SDKError.NetworkError("Request timeout for $method $endpoint")
            429 -> SDKError.NetworkError("Rate limit exceeded for $method $endpoint")
            in 500..599 -> SDKError.NetworkError("Server error $statusCode for $method $endpoint")
            else -> SDKError.NetworkError("HTTP $statusCode for $method $endpoint")
        }
    }

    /**
     * Determine if we should retry based on HTTP status code
     */
    private fun shouldRetry(statusCode: Int, attempt: Int): Boolean {
        if (attempt >= maxRetryAttempts - 1) return false

        return when (statusCode) {
            408, 429 -> true  // Timeout, Rate limit
            in 500..599 -> true  // Server errors
            else -> false  // Client errors should not be retried
        }
    }

    /**
     * Determine if we should retry based on exception type
     */
    private fun shouldRetryException(exception: Exception, attempt: Int): Boolean {
        if (attempt >= maxRetryAttempts - 1) return false

        return when (exception) {
            is SDKError.InvalidAPIKey -> false  // Don't retry auth errors
            is SDKError.NetworkError -> {
                // Retry on network connectivity issues
                val message = exception.message?.lowercase() ?: ""
                message.contains("timeout") ||
                message.contains("connection") ||
                message.contains("network") ||
                message.contains("host")
            }
            else -> true  // Retry on other exceptions
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
     * Sync device info to the backend
     */
    suspend fun syncDeviceInfo(deviceInfo: com.runanywhere.sdk.data.models.DeviceInfoData): Boolean {
        return try {
            logger.debug("Syncing device info for device: ${deviceInfo.deviceId}")

            val response: Map<String, Any> = post(
                endpoint = "/device/sync",
                payload = deviceInfo,
                requiresAuth = true
            )

            logger.info("Device info synced successfully for device: ${deviceInfo.deviceId}")
            true
        } catch (e: Exception) {
            logger.error("Failed to sync device info: ${e.message}", e)
            false
        }
    }

    private suspend fun writeToFile(path: String, data: ByteArray) {
        // This will use the platform's file system
        // Implementation will be platform-specific
        writeFileBytes(path, data)
    }
}

/**
 * Platform-specific network connectivity checker
 */
interface NetworkChecker {
    suspend fun isNetworkAvailable(): Boolean
    suspend fun getNetworkType(): String
}

/**
 * Platform-specific file writing
 */
expect suspend fun writeFileBytes(path: String, data: ByteArray)

// Extension functions with reified types for actual usage
suspend inline fun <reified T, reified R> APIClient.postJson(
    endpoint: String,
    payload: T,
    requiresAuth: Boolean = false
): R {
    val jsonSerializer = Json {
        ignoreUnknownKeys = true
        isLenient = true
        encodeDefaults = false
    }

    val jsonPayload = jsonSerializer.encodeToString(payload)
    val response = postRaw(endpoint, jsonPayload.encodeToByteArray(), requiresAuth)
    return jsonSerializer.decodeFromString(response.decodeToString())
}

suspend inline fun <reified R> APIClient.getJson(
    endpoint: String,
    requiresAuth: Boolean = false
): R {
    val jsonSerializer = Json {
        ignoreUnknownKeys = true
        isLenient = true
    }

    val response = getRaw(endpoint, requiresAuth)
    return jsonSerializer.decodeFromString(response.decodeToString())
}

suspend inline fun <reified T, reified R> APIClient.putJson(
    endpoint: String,
    payload: T,
    requiresAuth: Boolean = false
): R {
    val jsonSerializer = Json {
        ignoreUnknownKeys = true
        isLenient = true
        encodeDefaults = false
    }

    val jsonPayload = jsonSerializer.encodeToString(payload)
    val response = putRaw(endpoint, jsonPayload.encodeToByteArray(), requiresAuth)
    return jsonSerializer.decodeFromString(response.decodeToString())
}
