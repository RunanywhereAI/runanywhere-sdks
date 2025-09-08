package com.runanywhere.sdk.data.network

import com.runanywhere.sdk.data.network.models.APIEndpoint

/**
 * Network service interface - equivalent to iOS NetworkService protocol
 */
interface NetworkService {
    /**
     * Perform a POST request to the specified endpoint
     */
    suspend fun postRaw(
        endpoint: APIEndpoint,
        payload: ByteArray,
        requiresAuth: Boolean = true
    ): ByteArray

    /**
     * Perform a GET request to the specified endpoint
     */
    suspend fun getRaw(
        endpoint: APIEndpoint,
        requiresAuth: Boolean = true
    ): ByteArray
}
