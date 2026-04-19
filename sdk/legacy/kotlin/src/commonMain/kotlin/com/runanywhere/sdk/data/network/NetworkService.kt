package com.runanywhere.sdk.data.network

import com.runanywhere.sdk.data.network.models.APIEndpoint

/**
 * Network service interface - equivalent to iOS NetworkService protocol
 * Enhanced with generic POST/GET methods and proper authentication support
 */
interface NetworkService {
    /**
     * POST request with JSON payload and typed response
     * Equivalent to iOS: func post<T: Encodable, R: Decodable>(_ endpoint: APIEndpoint, _ payload: T, requiresAuth: Bool) async throws -> R
     */
    suspend fun <T : Any, R : Any> post(
        endpoint: APIEndpoint,
        payload: T,
        requiresAuth: Boolean = true,
    ): R

    /**
     * GET request with typed response
     * Equivalent to iOS: func get<R: Decodable>(_ endpoint: APIEndpoint, requiresAuth: Bool) async throws -> R
     */
    suspend fun <R : Any> get(
        endpoint: APIEndpoint,
        requiresAuth: Boolean = true,
    ): R

    /**
     * POST request with raw data payload
     * Equivalent to iOS: func postRaw(_ endpoint: APIEndpoint, _ payload: Data, requiresAuth: Bool) async throws -> Data
     */
    suspend fun postRaw(
        endpoint: APIEndpoint,
        payload: ByteArray,
        requiresAuth: Boolean = true,
    ): ByteArray

    /**
     * GET request with raw data response
     * Equivalent to iOS: func getRaw(_ endpoint: APIEndpoint, requiresAuth: Bool) async throws -> Data
     */
    suspend fun getRaw(
        endpoint: APIEndpoint,
        requiresAuth: Boolean = true,
    ): ByteArray
}
