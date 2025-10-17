package com.runanywhere.sdk.data.network

import com.runanywhere.sdk.data.network.models.APIEndpoint
import com.runanywhere.sdk.foundation.SDKLogger
import com.runanywhere.sdk.network.CircuitBreaker

/**
 * NetworkService wrapper that adds circuit breaker protection
 * Provides automatic failure detection and recovery for network operations
 * Prevents cascading failures when backend services are experiencing issues
 */
class CircuitBreakerNetworkService(
    private val delegate: NetworkService,
    private val circuitBreaker: CircuitBreaker
) : NetworkService {

    private val logger = SDKLogger("CircuitBreakerNetworkService")

    /**
     * POST request with JSON payload and typed response - with circuit breaker protection
     */
    override suspend fun <T : Any, R : Any> post(
        endpoint: APIEndpoint,
        payload: T,
        requiresAuth: Boolean
    ): R {
        return circuitBreaker.execute {
            delegate.post(endpoint, payload, requiresAuth)
        }
    }

    /**
     * GET request with typed response - with circuit breaker protection
     */
    override suspend fun <R : Any> get(
        endpoint: APIEndpoint,
        requiresAuth: Boolean
    ): R {
        return circuitBreaker.execute {
            delegate.get(endpoint, requiresAuth)
        }
    }

    /**
     * POST request with raw data payload - with circuit breaker protection
     */
    override suspend fun postRaw(
        endpoint: APIEndpoint,
        payload: ByteArray,
        requiresAuth: Boolean
    ): ByteArray {
        return circuitBreaker.execute {
            logger.debug("Circuit breaker executing POST to: ${endpoint.url}")
            delegate.postRaw(endpoint, payload, requiresAuth)
        }
    }

    /**
     * GET request with raw data response - with circuit breaker protection
     */
    override suspend fun getRaw(
        endpoint: APIEndpoint,
        requiresAuth: Boolean
    ): ByteArray {
        return circuitBreaker.execute {
            logger.debug("Circuit breaker executing GET to: ${endpoint.url}")
            delegate.getRaw(endpoint, requiresAuth)
        }
    }

    /**
     * Get circuit breaker status for monitoring
     */
    fun getCircuitBreakerStatus() = circuitBreaker.getStatus()

    /**
     * Reset circuit breaker manually (for admin/testing purposes)
     */
    suspend fun resetCircuitBreaker() {
        logger.info("Manually resetting circuit breaker")
        circuitBreaker.reset()
    }

    /**
     * Force circuit breaker open (for maintenance mode)
     */
    suspend fun forceCircuitBreakerOpen() {
        logger.warn("Manually opening circuit breaker")
        circuitBreaker.forceOpen()
    }
}

/**
 * Extension functions for typed requests with circuit breaker protection
 */
suspend inline fun <reified T : Any, reified R : Any> CircuitBreakerNetworkService.postTyped(
    endpoint: APIEndpoint,
    payload: T,
    requiresAuth: Boolean = true
): R {
    // The circuit breaker protection is already applied in the base method
    return this.post(endpoint, payload, requiresAuth)
}

suspend inline fun <reified R : Any> CircuitBreakerNetworkService.getTyped(
    endpoint: APIEndpoint,
    requiresAuth: Boolean = true
): R {
    // The circuit breaker protection is already applied in the base method
    return this.get(endpoint, requiresAuth)
}
