package com.runanywhere.sdk.network

/**
 * Network Service Protocol
 * One-to-one translation from iOS NetworkService protocol
 * Defines the contract for network operations
 */
interface NetworkService {

    /**
     * POST request with JSON payload and typed response
     * Equivalent to iOS: func post<T: Encodable, R: Decodable>(_ endpoint: APIEndpoint, _ payload: T, requiresAuth: Bool) async throws -> R
     */
    suspend fun <T, R> post(endpoint: String, payload: T, requiresAuth: Boolean = false): R

    /**
     * GET request with typed response
     * Equivalent to iOS: func get<R: Decodable>(_ endpoint: APIEndpoint, requiresAuth: Bool) async throws -> R
     */
    suspend fun <R> get(endpoint: String, requiresAuth: Boolean = false): R

    /**
     * POST request with raw data payload
     * Equivalent to iOS: func postRaw(_ endpoint: APIEndpoint, _ payload: Data, requiresAuth: Bool) async throws -> Data
     */
    suspend fun postRaw(endpoint: String, payload: ByteArray, requiresAuth: Boolean = false): ByteArray

    /**
     * GET request with raw data response
     * Equivalent to iOS: func getRaw(_ endpoint: APIEndpoint, requiresAuth: Bool) async throws -> Data
     */
    suspend fun getRaw(endpoint: String, requiresAuth: Boolean = false): ByteArray

    /**
     * PUT request with JSON payload and typed response
     * Additional method for RESTful operations
     */
    suspend fun <T, R> put(endpoint: String, payload: T, requiresAuth: Boolean = false): R

    /**
     * DELETE request
     * Additional method for RESTful operations
     */
    suspend fun delete(endpoint: String, requiresAuth: Boolean = false)

    /**
     * Download file with progress callback
     * For model downloading operations
     */
    suspend fun downloadFile(
        url: String,
        destinationPath: String,
        progressCallback: ((Float) -> Unit)? = null
    ): String

    /**
     * Check network connectivity
     * Utility method for offline handling
     */
    suspend fun isNetworkAvailable(): Boolean

    /**
     * Get network type (WiFi, Cellular, etc.)
     * For telemetry and optimization
     */
    suspend fun getNetworkType(): String
}
