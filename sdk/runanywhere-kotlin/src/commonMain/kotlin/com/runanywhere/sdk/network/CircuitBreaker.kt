package com.runanywhere.sdk.network

import com.runanywhere.sdk.foundation.SDKLogger
import com.runanywhere.sdk.data.models.SDKError
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.delay

/**
 * Circuit breaker pattern implementation for network resilience
 * Prevents cascading failures by temporarily disabling failing services
 * Matches enterprise-grade reliability patterns used in production systems
 */
class CircuitBreaker(
    private val failureThreshold: Int = 5,
    private val recoveryTimeoutMs: Long = 30_000, // 30 seconds
    private val halfOpenMaxCalls: Int = 3,
    private val name: String = "CircuitBreaker"
) {

    private val logger = SDKLogger("CircuitBreaker[$name]")
    private val mutex = Mutex()

    // Circuit breaker state
    private var state: CircuitBreakerState = CircuitBreakerState.CLOSED
    private var failureCount: Int = 0
    private var lastFailureTime: Long = 0
    private var halfOpenCallsCount: Int = 0

    /**
     * Execute a suspending function with circuit breaker protection
     */
    suspend fun <T> execute(operation: suspend () -> T): T {
        mutex.withLock {
            when (state) {
                CircuitBreakerState.CLOSED -> {
                    // Normal operation - allow calls
                    return executeAndHandleResult(operation)
                }

                CircuitBreakerState.OPEN -> {
                    // Circuit is open - check if we should try half-open
                    if (shouldAttemptReset()) {
                        logger.info("Circuit breaker transitioning to HALF_OPEN state")
                        state = CircuitBreakerState.HALF_OPEN
                        halfOpenCallsCount = 0
                        return executeAndHandleResult(operation)
                    } else {
                        // Still in open state - reject the call
                        val timeUntilRetry = recoveryTimeoutMs - (System.currentTimeMillis() - lastFailureTime)
                        logger.warn("Circuit breaker is OPEN, rejecting call (retry in ${timeUntilRetry}ms)")
                        throw SDKError.NetworkError("Circuit breaker is open for $name. Service temporarily unavailable.")
                    }
                }

                CircuitBreakerState.HALF_OPEN -> {
                    // Half-open state - allow limited calls to test service recovery
                    if (halfOpenCallsCount < halfOpenMaxCalls) {
                        halfOpenCallsCount++
                        return executeAndHandleResult(operation)
                    } else {
                        // Too many calls in half-open state, reject
                        logger.warn("Circuit breaker HALF_OPEN max calls reached, rejecting call")
                        throw SDKError.NetworkError("Circuit breaker is in half-open state with max calls reached for $name")
                    }
                }
            }
        }
    }

    /**
     * Execute operation and handle success/failure
     */
    private suspend fun <T> executeAndHandleResult(operation: suspend () -> T): T {
        return try {
            val result = operation()
            onSuccess()
            result
        } catch (e: Exception) {
            onFailure(e)
            throw e
        }
    }

    /**
     * Handle successful operation
     */
    private fun onSuccess() {
        when (state) {
            CircuitBreakerState.HALF_OPEN -> {
                // Successful call in half-open state - transition back to closed
                logger.info("Circuit breaker transitioning to CLOSED state after successful call")
                state = CircuitBreakerState.CLOSED
                failureCount = 0
                halfOpenCallsCount = 0
            }
            CircuitBreakerState.CLOSED -> {
                // Reset failure count on success
                if (failureCount > 0) {
                    logger.debug("Circuit breaker resetting failure count after successful call")
                    failureCount = 0
                }
            }
            CircuitBreakerState.OPEN -> {
                // This shouldn't happen, but handle gracefully
                logger.warn("Unexpected success in OPEN state")
            }
        }
    }

    /**
     * Handle failed operation
     */
    private fun onFailure(exception: Exception) {
        // Only count certain types of failures
        if (!isFailureCountable(exception)) {
            logger.debug("Exception not counted towards circuit breaker failures: ${exception.message}")
            return
        }

        failureCount++
        lastFailureTime = System.currentTimeMillis()

        logger.warn("Circuit breaker failure recorded (count: $failureCount): ${exception.message}")

        when (state) {
            CircuitBreakerState.CLOSED -> {
                if (failureCount >= failureThreshold) {
                    logger.error("Circuit breaker opening due to failure threshold reached ($failureCount >= $failureThreshold)")
                    state = CircuitBreakerState.OPEN
                }
            }
            CircuitBreakerState.HALF_OPEN -> {
                // Any failure in half-open state goes back to open
                logger.error("Circuit breaker returning to OPEN state due to failure in HALF_OPEN")
                state = CircuitBreakerState.OPEN
                halfOpenCallsCount = 0
            }
            CircuitBreakerState.OPEN -> {
                // Already open, just update failure time
                logger.debug("Circuit breaker failure recorded in OPEN state")
            }
        }
    }

    /**
     * Check if enough time has passed to attempt reset
     */
    private fun shouldAttemptReset(): Boolean {
        return System.currentTimeMillis() - lastFailureTime >= recoveryTimeoutMs
    }

    /**
     * Determine if an exception should count towards circuit breaker failures
     * Only network-related and server errors should trigger the circuit breaker
     */
    private fun isFailureCountable(exception: Exception): Boolean {
        return when (exception) {
            is SDKError.NetworkError -> {
                val message = exception.message?.lowercase() ?: ""
                // Count timeouts, connection errors, and server errors
                message.contains("timeout") ||
                message.contains("connection") ||
                message.contains("server error") ||
                message.contains("rate limit") ||
                message.contains("service unavailable")
            }
            is SDKError.InvalidAPIKey -> false  // Auth errors shouldn't trigger circuit breaker
            else -> {
                // Count general network-related exceptions
                val exceptionName = exception::class.simpleName?.lowercase() ?: ""
                exceptionName.contains("timeout") ||
                exceptionName.contains("connection") ||
                exceptionName.contains("socket") ||
                exceptionName.contains("network")
            }
        }
    }

    /**
     * Get current circuit breaker status
     */
    fun getStatus(): CircuitBreakerStatus {
        return CircuitBreakerStatus(
            state = state,
            failureCount = failureCount,
            lastFailureTime = lastFailureTime,
            halfOpenCallsCount = halfOpenCallsCount
        )
    }

    /**
     * Manually reset the circuit breaker (for testing or admin purposes)
     */
    suspend fun reset() {
        mutex.withLock {
            logger.info("Circuit breaker manually reset")
            state = CircuitBreakerState.CLOSED
            failureCount = 0
            lastFailureTime = 0
            halfOpenCallsCount = 0
        }
    }

    /**
     * Force the circuit breaker to open (for testing or maintenance)
     */
    suspend fun forceOpen() {
        mutex.withLock {
            logger.warn("Circuit breaker manually opened")
            state = CircuitBreakerState.OPEN
            lastFailureTime = System.currentTimeMillis()
        }
    }
}

/**
 * Circuit breaker states
 */
enum class CircuitBreakerState {
    CLOSED,    // Normal operation
    OPEN,      // Blocking all calls due to failures
    HALF_OPEN  // Testing if service has recovered
}

/**
 * Circuit breaker status for monitoring
 */
data class CircuitBreakerStatus(
    val state: CircuitBreakerState,
    val failureCount: Int,
    val lastFailureTime: Long,
    val halfOpenCallsCount: Int
) {
    val isHealthy: Boolean
        get() = state == CircuitBreakerState.CLOSED && failureCount == 0

    val timeUntilRetryMs: Long
        get() = if (state == CircuitBreakerState.OPEN) {
            maxOf(0, 30_000 - (System.currentTimeMillis() - lastFailureTime))
        } else {
            0
        }
}

/**
 * Circuit breaker registry for managing multiple circuit breakers
 */
object CircuitBreakerRegistry {
    private val circuitBreakers = mutableMapOf<String, CircuitBreaker>()
    private val logger = SDKLogger("CircuitBreakerRegistry")

    /**
     * Get or create a circuit breaker for a service
     */
    fun getOrCreate(
        name: String,
        failureThreshold: Int = 5,
        recoveryTimeoutMs: Long = 30_000,
        halfOpenMaxCalls: Int = 3
    ): CircuitBreaker {
        return circuitBreakers.getOrPut(name) {
            logger.info("Creating new circuit breaker for service: $name")
            CircuitBreaker(
                failureThreshold = failureThreshold,
                recoveryTimeoutMs = recoveryTimeoutMs,
                halfOpenMaxCalls = halfOpenMaxCalls,
                name = name
            )
        }
    }

    /**
     * Get all circuit breaker statuses
     */
    fun getAllStatuses(): Map<String, CircuitBreakerStatus> {
        return circuitBreakers.mapValues { it.value.getStatus() }
    }

    /**
     * Reset all circuit breakers
     */
    suspend fun resetAll() {
        logger.info("Resetting all circuit breakers")
        circuitBreakers.values.forEach { it.reset() }
    }

    /**
     * Remove a circuit breaker from registry
     */
    fun remove(name: String) {
        circuitBreakers.remove(name)
        logger.info("Removed circuit breaker: $name")
    }
}
