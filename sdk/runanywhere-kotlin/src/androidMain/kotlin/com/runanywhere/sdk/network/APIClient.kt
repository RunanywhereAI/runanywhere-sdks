package com.runanywhere.sdk.network

import android.content.Context
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import com.runanywhere.sdk.data.models.SDKError
import com.runanywhere.sdk.foundation.SDKLogger
import com.runanywhere.sdk.services.auth.AuthenticationService
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.serialization.json.Json
import java.io.File
import java.io.FileOutputStream
import java.net.HttpURLConnection
import java.net.URL

/**
 * API Client
 * One-to-one translation from iOS Swift Actor APIClient to Kotlin with thread-safety
 * Handles HTTP operations with authentication, logging, and error handling
 * Using simplified HTTP implementation for core functionality
 */
class APIClient(
    private val context: Context,
    private val baseURL: String,
    private val authenticationService: AuthenticationService? = null
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
     * Equivalent to iOS: func post<T: Encodable, R: Decodable>(_ endpoint: APIEndpoint, _ payload: T, requiresAuth: Bool) async throws -> R
     */
    override suspend fun <T, R> post(endpoint: String, payload: T, requiresAuth: Boolean): R = mutex.withLock {
        logger.debug("POST request to: $endpoint, requiresAuth: $requiresAuth")

        try {
            val url = URL("$baseURL/$endpoint")
            val connection = url.openConnection() as HttpURLConnection

            connection.requestMethod = "POST"
            connection.doOutput = true
            connection.setRequestProperty("Content-Type", "application/json")

            if (requiresAuth) {
                addAuthHeader(connection)
            }

            // Serialize and send payload
            val jsonPayload = jsonSerializer.encodeToString(kotlinx.serialization.serializer(), payload)
            connection.outputStream.use { it.write(jsonPayload.toByteArray()) }

            // Handle response
            if (connection.responseCode !in 200..299) {
                throw SDKError.NetworkError("HTTP ${connection.responseCode}: ${connection.responseMessage}")
            }

            val responseJson = connection.inputStream.bufferedReader().use { it.readText() }
            val result = jsonSerializer.decodeFromString<R>(kotlinx.serialization.serializer(), responseJson)

            logger.debug("POST request successful: $endpoint")
            return result

        } catch (e: Exception) {
            logger.error("POST request failed: $endpoint - ${e.message}")
            throw when (e) {
                is SDKError -> e
                else -> SDKError.NetworkError("POST request failed: ${e.message}")
            }
        }
    }

    /**
     * GET request with typed response
     * Equivalent to iOS: func get<R: Decodable>(_ endpoint: APIEndpoint, requiresAuth: Bool) async throws -> R
     */
    override suspend fun <R> get(endpoint: String, requiresAuth: Boolean): R = mutex.withLock {
        logger.debug("GET request to: $endpoint, requiresAuth: $requiresAuth")

        try {
            val url = URL("$baseURL/$endpoint")
            val connection = url.openConnection() as HttpURLConnection

            connection.requestMethod = "GET"
            connection.setRequestProperty("Content-Type", "application/json")

            if (requiresAuth) {
                addAuthHeader(connection)
            }

            // Handle response
            if (connection.responseCode !in 200..299) {
                throw SDKError.NetworkError("HTTP ${connection.responseCode}: ${connection.responseMessage}")
            }

            val responseJson = connection.inputStream.bufferedReader().use { it.readText() }
            val result = jsonSerializer.decodeFromString<R>(kotlinx.serialization.serializer(), responseJson)

            logger.debug("GET request successful: $endpoint")
            return result

        } catch (e: Exception) {
            logger.error("GET request failed: $endpoint - ${e.message}")
            throw when (e) {
                is SDKError -> e
                else -> SDKError.NetworkError("GET request failed: ${e.message}")
            }
        }
    }

    /**
     * POST request with raw data payload
     * Equivalent to iOS: func postRaw(_ endpoint: APIEndpoint, _ payload: Data, requiresAuth: Bool) async throws -> Data
     */
    override suspend fun postRaw(endpoint: String, payload: ByteArray, requiresAuth: Boolean): ByteArray = mutex.withLock {
        logger.debug("POST raw request to: $endpoint, size: ${payload.size} bytes")

        try {
            val url = URL("$baseURL/$endpoint")
            val connection = url.openConnection() as HttpURLConnection

            connection.requestMethod = "POST"
            connection.doOutput = true
            connection.setRequestProperty("Content-Type", "application/octet-stream")

            if (requiresAuth) {
                addAuthHeader(connection)
            }

            // Send payload
            connection.outputStream.use { it.write(payload) }

            // Handle response
            if (connection.responseCode !in 200..299) {
                throw SDKError.NetworkError("HTTP ${connection.responseCode}: ${connection.responseMessage}")
            }

            val result = connection.inputStream.use { it.readBytes() }
            logger.debug("POST raw request successful: $endpoint")
            return result

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
     * Equivalent to iOS: func getRaw(_ endpoint: APIEndpoint, requiresAuth: Bool) async throws -> Data
     */
    override suspend fun getRaw(endpoint: String, requiresAuth: Boolean): ByteArray = mutex.withLock {
        logger.debug("GET raw request to: $endpoint")

        try {
            val url = URL("$baseURL/$endpoint")
            val connection = url.openConnection() as HttpURLConnection

            connection.requestMethod = "GET"

            if (requiresAuth) {
                addAuthHeader(connection)
            }

            // Handle response
            if (connection.responseCode !in 200..299) {
                throw SDKError.NetworkError("HTTP ${connection.responseCode}: ${connection.responseMessage}")
            }

            val result = connection.inputStream.use { it.readBytes() }
            logger.debug("GET raw request successful: $endpoint")
            return result

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
     */
    override suspend fun <T, R> put(endpoint: String, payload: T, requiresAuth: Boolean): R = mutex.withLock {
        logger.debug("PUT request to: $endpoint")

        try {
            val url = URL("$baseURL/$endpoint")
            val connection = url.openConnection() as HttpURLConnection

            connection.requestMethod = "PUT"
            connection.doOutput = true
            connection.setRequestProperty("Content-Type", "application/json")

            if (requiresAuth) {
                addAuthHeader(connection)
            }

            // Serialize and send payload
            val jsonPayload = jsonSerializer.encodeToString(kotlinx.serialization.serializer(), payload)
            connection.outputStream.use { it.write(jsonPayload.toByteArray()) }

            // Handle response
            if (connection.responseCode !in 200..299) {
                throw SDKError.NetworkError("HTTP ${connection.responseCode}: ${connection.responseMessage}")
            }

            val responseJson = connection.inputStream.bufferedReader().use { it.readText() }
            val result = jsonSerializer.decodeFromString<R>(kotlinx.serialization.serializer(), responseJson)

            logger.debug("PUT request successful: $endpoint")
            return result

        } catch (e: Exception) {
            logger.error("PUT request failed: $endpoint - ${e.message}")
            throw when (e) {
                is SDKError -> e
                else -> SDKError.NetworkError("PUT request failed: ${e.message}")
            }
        }
    }

    /**
     * DELETE request
     */
    override suspend fun delete(endpoint: String, requiresAuth: Boolean) = mutex.withLock {
        logger.debug("DELETE request to: $endpoint")

        try {
            val url = URL("$baseURL/$endpoint")
            val connection = url.openConnection() as HttpURLConnection

            connection.requestMethod = "DELETE"

            if (requiresAuth) {
                addAuthHeader(connection)
            }

            // Handle response
            if (connection.responseCode !in 200..299) {
                throw SDKError.NetworkError("HTTP ${connection.responseCode}: ${connection.responseMessage}")
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
            val connection = URL(url).openConnection() as HttpURLConnection
            connection.requestMethod = "GET"

            if (connection.responseCode !in 200..299) {
                throw SDKError.NetworkError("HTTP ${connection.responseCode}: ${connection.responseMessage}")
            }

            val contentLength = connection.contentLength
            val file = File(destinationPath)
            file.parentFile?.mkdirs()

            FileOutputStream(file).use { outputStream ->
                connection.inputStream.use { inputStream ->
                    val buffer = ByteArray(8192)
                    var bytesRead = 0
                    var totalBytesRead = 0

                    while (inputStream.read(buffer).also { bytesRead = it } != -1) {
                        outputStream.write(buffer, 0, bytesRead)
                        totalBytesRead += bytesRead

                        if (contentLength > 0) {
                            val progress = totalBytesRead.toFloat() / contentLength
                            progressCallback?.invoke(progress)
                        }
                    }
                }
            }

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
        return try {
            val connectivityManager = context.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
            val network = connectivityManager.activeNetwork
            val capabilities = connectivityManager.getNetworkCapabilities(network)

            capabilities != null && (
                capabilities.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) ||
                capabilities.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR) ||
                capabilities.hasTransport(NetworkCapabilities.TRANSPORT_ETHERNET)
            )
        } catch (e: Exception) {
            logger.error("Failed to check network availability - ${e.message}")
            false
        }
    }

    /**
     * Get network type
     */
    override suspend fun getNetworkType(): String {
        return try {
            val connectivityManager = context.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
            val network = connectivityManager.activeNetwork
            val capabilities = connectivityManager.getNetworkCapabilities(network)

            when {
                capabilities == null -> "none"
                capabilities.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) -> "wifi"
                capabilities.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR) -> "cellular"
                capabilities.hasTransport(NetworkCapabilities.TRANSPORT_ETHERNET) -> "ethernet"
                else -> "unknown"
            }
        } catch (e: Exception) {
            logger.error("Failed to get network type - ${e.message}")
            "unknown"
        }
    }

    // Private helper methods

    private suspend fun addAuthHeader(connection: HttpURLConnection) {
        try {
            val token = authenticationService?.getAccessToken()
            if (token != null) {
                connection.setRequestProperty("Authorization", "Bearer $token")
            }
        } catch (e: Exception) {
            logger.warn("Failed to add auth header: ${e.message}")
            // Continue without auth - the server will handle the unauthorized request
        }
    }
}
