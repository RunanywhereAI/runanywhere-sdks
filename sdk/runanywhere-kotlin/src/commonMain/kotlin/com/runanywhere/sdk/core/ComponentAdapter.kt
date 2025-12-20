package com.runanywhere.sdk.core

import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

/**
 * Component adapter for adapting platform-specific components
 * One-to-one mapping from iOS ComponentAdapter
 */
abstract class ComponentAdapter<Input, Output> {
    private val _isReady = MutableStateFlow(false)
    val isReady: StateFlow<Boolean> = _isReady.asStateFlow()

    private val _state = MutableStateFlow(ComponentState.UNINITIALIZED)
    val state: StateFlow<ComponentState> = _state.asStateFlow()

    private var configuration: ComponentConfiguration? = null

    /**
     * Initialize the component adapter
     */
    suspend fun initialize(config: ComponentConfiguration? = null) {
        if (_state.value != ComponentState.UNINITIALIZED) {
            return
        }

        _state.value = ComponentState.INITIALIZING
        configuration = config

        try {
            onInitialize(config)
            _isReady.value = true
            _state.value = ComponentState.READY
        } catch (e: Exception) {
            _state.value = ComponentState.ERROR
            onError(ComponentError.InitializationError(e.message ?: "Unknown error", e))
            throw e
        }
    }

    /**
     * Adapt input to output
     */
    suspend fun adapt(input: Input): Output {
        if (!_isReady.value) {
            throw IllegalStateException("Component adapter not ready. Current state: ${_state.value}")
        }

        _state.value = ComponentState.PROCESSING

        return try {
            val output = performAdaptation(input)
            _state.value = ComponentState.READY
            output
        } catch (e: Exception) {
            _state.value = ComponentState.ERROR
            onError(ComponentError.ProcessingError(e.message ?: "Unknown error", e))
            throw e
        }
    }

    /**
     * Transform input before adaptation
     */
    open suspend fun transformInput(input: Input): Input = input

    /**
     * Transform output after adaptation
     */
    open suspend fun transformOutput(output: Output): Output = output

    /**
     * Full transformation pipeline
     */
    suspend fun transform(input: Input): Output {
        val transformedInput = transformInput(input)
        val output = adapt(transformedInput)
        return transformOutput(output)
    }

    /**
     * Cleanup the adapter
     */
    suspend fun cleanup() {
        try {
            onCleanup()
            _isReady.value = false
            _state.value = ComponentState.UNINITIALIZED
            configuration = null
        } catch (e: Exception) {
            onError(ComponentError.CleanupError(e.message ?: "Unknown error", e))
        }
    }

    /**
     * Get current configuration
     */
    fun getConfiguration(): ComponentConfiguration? = configuration

    /**
     * Update configuration
     */
    suspend fun updateConfiguration(config: ComponentConfiguration) {
        configuration = config
        onConfigurationUpdate(config)
    }

    // Abstract methods to be implemented by subclasses

    /**
     * Perform the actual adaptation
     */
    protected abstract suspend fun performAdaptation(input: Input): Output

    /**
     * Initialize the adapter
     */
    protected open suspend fun onInitialize(config: ComponentConfiguration?) {}

    /**
     * Handle configuration updates
     */
    protected open suspend fun onConfigurationUpdate(config: ComponentConfiguration) {}

    /**
     * Cleanup resources
     */
    protected open suspend fun onCleanup() {}

    /**
     * Handle errors
     */
    protected open fun onError(error: ComponentError) {}
}

/**
 * Component state
 */
enum class ComponentState {
    UNINITIALIZED,
    INITIALIZING,
    READY,
    PROCESSING,
    ERROR,
    ;

    val canProcess: Boolean
        get() = this == READY
}

/**
 * Component configuration base class
 */
open class ComponentConfiguration(
    val name: String = "",
    val version: String = "1.0.0",
    val metadata: Map<String, Any> = emptyMap(),
)

/**
 * Component errors
 */
sealed class ComponentError(
    message: String,
    cause: Throwable? = null,
) : Exception(message, cause) {
    data class InitializationError(
        override val message: String,
        override val cause: Throwable? = null,
    ) : ComponentError(message, cause)

    data class ProcessingError(
        override val message: String,
        override val cause: Throwable? = null,
    ) : ComponentError(message, cause)

    data class ConfigurationError(
        override val message: String,
        override val cause: Throwable? = null,
    ) : ComponentError(message, cause)

    data class CleanupError(
        override val message: String,
        override val cause: Throwable? = null,
    ) : ComponentError(message, cause)
}

/**
 * Adapter registry for managing component adapters
 */
object AdapterRegistry {
    private val adapters = mutableMapOf<String, ComponentAdapter<*, *>>()

    /**
     * Register an adapter
     */
    fun <I, O> register(
        key: String,
        adapter: ComponentAdapter<I, O>,
    ) {
        adapters[key] = adapter
    }

    /**
     * Get an adapter by key
     */
    @Suppress("UNCHECKED_CAST")
    fun <I, O> get(key: String): ComponentAdapter<I, O>? = adapters[key] as? ComponentAdapter<I, O>

    /**
     * Remove an adapter
     */
    fun remove(key: String): ComponentAdapter<*, *>? = adapters.remove(key)

    /**
     * Clear all adapters
     */
    fun clear() {
        adapters.clear()
    }

    /**
     * Get all registered adapter keys
     */
    fun keys(): Set<String> = adapters.keys

    /**
     * Check if an adapter is registered
     */
    fun contains(key: String): Boolean = adapters.containsKey(key)
}

/**
 * Bi-directional adapter for two-way transformations
 */
abstract class BidirectionalAdapter<A, B> {
    private val forwardAdapter =
        object : ComponentAdapter<A, B>() {
            override suspend fun performAdaptation(input: A): B = forward(input)
        }

    private val reverseAdapter =
        object : ComponentAdapter<B, A>() {
            override suspend fun performAdaptation(input: B): A = reverse(input)
        }

    /**
     * Initialize both adapters
     */
    suspend fun initialize(config: ComponentConfiguration? = null) {
        forwardAdapter.initialize(config)
        reverseAdapter.initialize(config)
    }

    /**
     * Transform A to B
     */
    suspend fun adaptForward(input: A): B = forwardAdapter.adapt(input)

    /**
     * Transform B to A
     */
    suspend fun adaptReverse(input: B): A = reverseAdapter.adapt(input)

    /**
     * Cleanup both adapters
     */
    suspend fun cleanup() {
        forwardAdapter.cleanup()
        reverseAdapter.cleanup()
    }

    // Abstract transformation methods
    protected abstract suspend fun forward(input: A): B

    protected abstract suspend fun reverse(input: B): A
}
