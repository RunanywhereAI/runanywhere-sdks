package com.runanywhere.sdk.data.network

import com.runanywhere.sdk.data.network.models.APIEndpoint
import com.runanywhere.sdk.foundation.SDKLogger
import com.runanywhere.sdk.network.APIClient
import kotlinx.serialization.json.Json
import kotlinx.serialization.encodeToString
import kotlinx.serialization.decodeFromString
import kotlinx.serialization.serializer
import kotlinx.serialization.serializerOrNull

/**
 * Enhanced NetworkService implementation that provides both generic and raw data methods
 * Bridges the gap between the enhanced NetworkService interface and APIClient
 */
class NetworkServiceImpl(
    private val apiClient: APIClient
) : NetworkService {

    private val logger = SDKLogger("NetworkServiceImpl")

    private val jsonSerializer = Json {
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
        requiresAuth: Boolean
    ): R {
        throw UnsupportedOperationException("Use postTyped extension function with reified types instead")
    }

    /**
     * GET request with typed response
     * Note: This implementation requires extension functions with reified types for actual usage
     */
    override suspend fun <R : Any> get(
        endpoint: APIEndpoint,
        requiresAuth: Boolean
    ): R {
        throw UnsupportedOperationException("Use getTyped extension function with reified types instead")
    }

    /**
     * POST request with raw data payload
     */
    override suspend fun postRaw(
        endpoint: APIEndpoint,
        payload: ByteArray,
        requiresAuth: Boolean
    ): ByteArray {
        logger.debug("POST raw request to: ${endpoint.url}")

        return try {
            apiClient.postRaw(
                endpoint = endpoint.url,
                payload = payload,
                requiresAuth = requiresAuth
            )
        } catch (e: Exception) {
            logger.error("POST raw request failed: ${endpoint.url} - ${e.message}")
            throw e
        }
    }

    /**
     * GET request with raw data response
     */
    override suspend fun getRaw(
        endpoint: APIEndpoint,
        requiresAuth: Boolean
    ): ByteArray {
        logger.debug("GET raw request from: ${endpoint.url}")

        return try {
            apiClient.getRaw(
                endpoint = endpoint.url,
                requiresAuth = requiresAuth
            )
        } catch (e: Exception) {
            logger.error("GET raw request failed: ${endpoint.url} - ${e.message}")
            throw e
        }
    }
}

/**
 * Extension functions for reified type support
 * These provide type-safe API calls with actual JSON serialization/deserialization
 */
suspend inline fun <reified T : Any, reified R : Any> NetworkService.postTyped(
    endpoint: APIEndpoint,
    payload: T,
    requiresAuth: Boolean = true
): R {
    val jsonSerializer = Json {
        ignoreUnknownKeys = true
        isLenient = true
        encodeDefaults = false
    }

    // Serialize payload to JSON
    val jsonPayload = jsonSerializer.encodeToString(payload)

    // Make raw request
    val responseBytes = this.postRaw(
        endpoint = endpoint,
        payload = jsonPayload.encodeToByteArray(),
        requiresAuth = requiresAuth
    )

    // Deserialize response
    val responseString = responseBytes.decodeToString()
    return jsonSerializer.decodeFromString(responseString)
}

suspend inline fun <reified R : Any> NetworkService.getTyped(
    endpoint: APIEndpoint,
    requiresAuth: Boolean = true
): R {
    val jsonSerializer = Json {
        ignoreUnknownKeys = true
        isLenient = true
    }

    // Make raw request
    val responseBytes = this.getRaw(
        endpoint = endpoint,
        requiresAuth = requiresAuth
    )

    // Deserialize response
    val responseString = responseBytes.decodeToString()
    return jsonSerializer.decodeFromString(responseString)
}
