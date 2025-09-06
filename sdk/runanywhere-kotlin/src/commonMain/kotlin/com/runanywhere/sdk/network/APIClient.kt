package com.runanywhere.sdk.network

import com.runanywhere.sdk.data.models.SDKError
import com.runanywhere.sdk.foundation.SDKLogger
import com.runanywhere.sdk.services.AuthenticationService
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.serialization.json.Json
import kotlinx.serialization.serializer
import kotlinx.serialization.encodeToString
import kotlinx.serialization.decodeFromString

/**
 * Common API Client implementation
 * Handles HTTP operations with authentication, logging, and error handling
 */
class APIClient(
    internal val baseURL: String,
    internal val httpClient: HttpClient,
    internal val authenticationService: AuthenticationService? = null,
    private val networkChecker: NetworkChecker? = null
) : NetworkService {

    private val logger = SDKLogger("APIClient")
    private val mutex = Mutex()

    private val jsonSerializer = Json {
        ignoreUnknownKeys = true
        isLenient = true
        encodeDefaults = false
        prettyPrint = false
        coerceInputValues = true
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
    ): ByteArray = mutex.withLock {
        logger.debug("POST raw request to: $endpoint, size: ${payload.size} bytes")

        try {
            val headers = mutableMapOf("Content-Type" to "application/octet-stream")
            if (requiresAuth) {
                addAuthHeader(headers)
            }

            val response = httpClient.post(
                url = "$baseURL/$endpoint",
                body = payload,
                headers = headers
            )

            if (!response.isSuccessful) {
                throw SDKError.NetworkError("HTTP ${response.statusCode}")
            }

            logger.debug("POST raw request successful: $endpoint")
            return response.body

        } catch (e: Exception) {
            logger.error("POST raw request failed: $endpoint - ${e.message}")
            throw when (e) {
                is SDKError -> e
                else -> SDKError.NetworkError("POST raw request failed: ${e.message}")
            }
        }
    }

    /**
     * GET request with raw data response
     */
    override suspend fun getRaw(endpoint: String, requiresAuth: Boolean): ByteArray =
        mutex.withLock {
            logger.debug("GET raw request to: $endpoint")

            try {
                val headers = mutableMapOf<String, String>()
                if (requiresAuth) {
                    addAuthHeader(headers)
                }

                val response = httpClient.get(
                    url = "$baseURL/$endpoint",
                    headers = headers
                )

                if (!response.isSuccessful) {
                    throw SDKError.NetworkError("HTTP ${response.statusCode}")
                }

                logger.debug("GET raw request successful: $endpoint")
                return response.body

            } catch (e: Exception) {
                logger.error("GET raw request failed: $endpoint - ${e.message}")
                throw when (e) {
                    is SDKError -> e
                    else -> SDKError.NetworkError("GET raw request failed: ${e.message}")
                }
            }
        }

    /**
     * PUT request with JSON payload and typed response
     * Note: For actual usage, create extension functions with reified types
     */
    override suspend fun <T, R> put(endpoint: String, payload: T, requiresAuth: Boolean): R {
        throw UnsupportedOperationException("Use putJson extension function instead")
    }

    /**
     * DELETE request
     */
    override suspend fun delete(endpoint: String, requiresAuth: Boolean) = mutex.withLock {
        logger.debug("DELETE request to: $endpoint")

        try {
            val headers = mutableMapOf<String, String>()
            if (requiresAuth) {
                addAuthHeader(headers)
            }

            val response = httpClient.delete(
                url = "$baseURL/$endpoint",
                headers = headers
            )

            if (!response.isSuccessful) {
                throw SDKError.NetworkError("HTTP ${response.statusCode}")
            }

            logger.debug("DELETE request successful: $endpoint")

        } catch (e: Exception) {
            logger.error("DELETE request failed: $endpoint - ${e.message}")
            throw when (e) {
                is SDKError -> e
                else -> SDKError.NetworkError("DELETE request failed: ${e.message}")
            }
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
            val data = httpClient.download(
                url = url,
                headers = emptyMap(),
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

    // Private helper methods

    private suspend fun addAuthHeader(headers: MutableMap<String, String>) {
        try {
            val token = authenticationService?.getAccessToken()
            if (token != null) {
                headers["Authorization"] = "Bearer $token"
            }
        } catch (e: Exception) {
            logger.warn("Failed to add auth header: ${e.message}")
            // Continue without auth - the server will handle the unauthorized request
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
    val headers = mutableMapOf("Content-Type" to "application/json")

    // Use the HttpClient directly for PUT since we don't have putRaw
    val response = (this as? APIClient)?.let { client ->
        client.httpClient.put(
            url = "${client.baseURL}/$endpoint",
            body = jsonPayload.encodeToByteArray(),
            headers = if (requiresAuth) {
                val token = client.authenticationService?.getAccessToken()
                if (token != null) headers["Authorization"] = "Bearer $token"
                headers
            } else headers
        )
    } ?: throw IllegalStateException("Invalid APIClient")

    if (!response.isSuccessful) {
        throw SDKError.NetworkError("HTTP ${response.statusCode}")
    }

    return jsonSerializer.decodeFromString(response.body.decodeToString())
}
