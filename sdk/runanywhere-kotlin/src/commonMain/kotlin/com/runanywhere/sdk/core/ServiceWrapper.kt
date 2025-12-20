package com.runanywhere.sdk.core

import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

/**
 * Service wrapper for managing service lifecycle
 * One-to-one mapping from iOS ServiceWrapper
 */
abstract class ServiceWrapper<T : Any> {
    private val scope = CoroutineScope(Dispatchers.Default + SupervisorJob())
    private val _state = MutableStateFlow(ServiceState.IDLE)
    val state: StateFlow<ServiceState> = _state.asStateFlow()

    private var service: T? = null
    private val _isInitialized = MutableStateFlow(false)
    val isInitialized: StateFlow<Boolean> = _isInitialized.asStateFlow()

    /**
     * Initialize the service
     */
    suspend fun initialize() {
        if (_state.value != ServiceState.IDLE) {
            return
        }

        _state.value = ServiceState.INITIALIZING

        try {
            service = createService()
            onServiceCreated(service!!)
            _isInitialized.value = true
            _state.value = ServiceState.READY
        } catch (e: Exception) {
            _state.value = ServiceState.ERROR
            onInitializationError(e)
            throw ServiceInitializationException("Failed to initialize service", e)
        }
    }

    /**
     * Start the service
     */
    suspend fun start() {
        if (_state.value != ServiceState.READY) {
            throw IllegalStateException("Service must be in READY state to start. Current state: ${_state.value}")
        }

        _state.value = ServiceState.STARTING

        try {
            service?.let { onServiceStart(it) }
            _state.value = ServiceState.RUNNING
        } catch (e: Exception) {
            _state.value = ServiceState.ERROR
            onStartError(e)
            throw ServiceStartException("Failed to start service", e)
        }
    }

    /**
     * Stop the service
     */
    suspend fun stop() {
        if (_state.value != ServiceState.RUNNING) {
            return
        }

        _state.value = ServiceState.STOPPING

        try {
            service?.let { onServiceStop(it) }
            _state.value = ServiceState.READY
        } catch (e: Exception) {
            _state.value = ServiceState.ERROR
            onStopError(e)
            throw ServiceStopException("Failed to stop service", e)
        }
    }

    /**
     * Cleanup and destroy the service
     */
    suspend fun cleanup() {
        when (_state.value) {
            ServiceState.RUNNING -> stop()
            else -> { /* No action needed */ }
        }

        try {
            service?.let { onServiceCleanup(it) }
            service = null
            _isInitialized.value = false
            _state.value = ServiceState.IDLE
        } catch (e: Exception) {
            onCleanupError(e)
        } finally {
            scope.cancel()
        }
    }

    /**
     * Get the wrapped service instance
     */
    fun getService(): T? = service

    /**
     * Get the wrapped service instance (throws if not initialized)
     */
    fun requireService(): T =
        service
            ?: throw IllegalStateException("Service not initialized")

    /**
     * Execute an action with the service
     */
    suspend fun <R> withService(action: suspend (T) -> R): R? = service?.let { action(it) }

    /**
     * Execute an action with the service (throws if not initialized)
     */
    suspend fun <R> requireWithService(action: suspend (T) -> R): R = action(requireService())

    // Abstract methods to be implemented by subclasses

    /**
     * Create the service instance
     */
    protected abstract suspend fun createService(): T

    /**
     * Called when service is created
     */
    protected open suspend fun onServiceCreated(service: T) {}

    /**
     * Called when service is started
     */
    protected open suspend fun onServiceStart(service: T) {}

    /**
     * Called when service is stopped
     */
    protected open suspend fun onServiceStop(service: T) {}

    /**
     * Called when service is cleaned up
     */
    protected open suspend fun onServiceCleanup(service: T) {}

    /**
     * Handle initialization errors
     */
    protected open fun onInitializationError(error: Exception) {}

    /**
     * Handle start errors
     */
    protected open fun onStartError(error: Exception) {}

    /**
     * Handle stop errors
     */
    protected open fun onStopError(error: Exception) {}

    /**
     * Handle cleanup errors
     */
    protected open fun onCleanupError(error: Exception) {}
}

/**
 * Service state enumeration
 */
enum class ServiceState {
    IDLE,
    INITIALIZING,
    READY,
    STARTING,
    RUNNING,
    STOPPING,
    ERROR,
    ;

    val isActive: Boolean
        get() = this in listOf(STARTING, RUNNING, STOPPING)

    val canStart: Boolean
        get() = this == READY

    val canStop: Boolean
        get() = this == RUNNING
}

/**
 * Service lifecycle interface
 */
interface ServiceLifecycle {
    suspend fun initialize()

    suspend fun start()

    suspend fun stop()

    suspend fun cleanup()

    fun getState(): ServiceState
}

/**
 * Service exceptions
 */
open class ServiceException(
    message: String,
    cause: Throwable? = null,
) : Exception(message, cause)

class ServiceInitializationException(
    message: String,
    cause: Throwable? = null,
) : ServiceException(message, cause)

class ServiceStartException(
    message: String,
    cause: Throwable? = null,
) : ServiceException(message, cause)

class ServiceStopException(
    message: String,
    cause: Throwable? = null,
) : ServiceException(message, cause)
