package com.runanywhere.sdk.core.capabilities

/**
 * CapabilityProtocols.kt
 * RunAnywhere SDK
 *
 * Base protocols and types for capability abstraction.
 * Matches iOS Core/Capabilities/CapabilityProtocols.swift
 */

// MARK: - Capability State

/**
 * Represents the loading state of a capability.
 * Matches iOS CapabilityLoadingState enum.
 */
sealed class CapabilityLoadingState {
    data object Idle : CapabilityLoadingState()

    data class Loading(
        val resourceId: String,
    ) : CapabilityLoadingState()

    data class Loaded(
        val resourceId: String,
    ) : CapabilityLoadingState()

    data class Failed(
        val error: Throwable,
    ) : CapabilityLoadingState()

    override fun equals(other: Any?): Boolean {
        if (this === other) return true
        return when {
            this is Idle && other is Idle -> true
            this is Loading && other is Loading -> resourceId == other.resourceId
            this is Loaded && other is Loaded -> resourceId == other.resourceId
            this is Failed && other is Failed -> true
            else -> false
        }
    }

    override fun hashCode(): Int =
        when (this) {
            is Idle -> 0
            is Loading -> resourceId.hashCode()
            is Loaded -> resourceId.hashCode()
            is Failed -> error.hashCode()
        }
}

/**
 * Result of a capability operation with timing metadata.
 * Matches iOS CapabilityOperationResult struct.
 */
data class CapabilityOperationResult<T>(
    val value: T,
    val processingTimeMs: Double,
    val resourceId: String? = null,
)

// MARK: - Base Capability Protocol

/**
 * Base protocol for all capabilities.
 * Defines the common interface that all capabilities must implement.
 * Matches iOS Capability protocol.
 */
interface Capability<Configuration> {
    /**
     * Configure the capability
     */
    fun configure(config: Configuration)

    /**
     * Cleanup resources
     */
    suspend fun cleanup()
}

// MARK: - Model Loadable Capability

/**
 * Protocol for capabilities that load models/resources.
 * Provides a standardized interface for model lifecycle management.
 * Matches iOS ModelLoadableCapability protocol.
 */
interface ModelLoadableCapability<Configuration, Service> : Capability<Configuration> {
    /**
     * Whether a model is currently loaded
     */
    val isModelLoaded: Boolean

    /**
     * The currently loaded model/resource ID
     */
    val currentModelId: String?

    /**
     * Load a model by ID
     * @param modelId The model identifier
     */
    suspend fun loadModel(modelId: String)

    /**
     * Unload the currently loaded model
     */
    suspend fun unload()
}

// MARK: - Service Based Capability

/**
 * Protocol for capabilities that initialize a service without model loading.
 * (e.g., VAD, Speaker Diarization)
 * Matches iOS ServiceBasedCapability protocol.
 */
interface ServiceBasedCapability<Configuration, Service> : Capability<Configuration> {
    /**
     * Whether the capability is ready to use
     */
    val isReady: Boolean

    /**
     * Initialize the capability with default configuration
     */
    suspend fun initialize()

    /**
     * Initialize the capability with configuration
     */
    suspend fun initialize(config: Configuration)
}

// MARK: - Composite Capability

/**
 * Protocol for capabilities that compose multiple other capabilities.
 * (e.g., VoiceAgent which uses STT, LLM, TTS, VAD)
 * Matches iOS CompositeCapability protocol.
 */
interface CompositeCapability {
    /**
     * Whether the composite capability is fully initialized
     */
    val isReady: Boolean

    /**
     * Clean up all composed resources
     */
    suspend fun cleanup()
}

// MARK: - Capability Metrics Helper

/**
 * Helper for tracking capability operation metrics.
 * Matches iOS CapabilityMetrics struct.
 */
class CapabilityMetrics(
    val resourceId: String,
) {
    val startTime: Long = System.currentTimeMillis()

    /**
     * Get elapsed time in milliseconds
     */
    val elapsedMs: Double
        get() = (System.currentTimeMillis() - startTime).toDouble()

    /**
     * Create a result with the current metrics
     */
    fun <T> result(value: T): CapabilityOperationResult<T> =
        CapabilityOperationResult(
            value = value,
            processingTimeMs = elapsedMs,
            resourceId = resourceId,
        )
}

// MARK: - Capability Error

/**
 * Common errors for capability operations.
 * Matches iOS CapabilityError enum.
 */
sealed class CapabilityError(
    override val message: String,
    override val cause: Throwable? = null,
) : Exception(message, cause) {
    class NotInitialized(
        capability: String,
    ) : CapabilityError("$capability is not initialized")

    class ResourceNotLoaded(
        resource: String,
    ) : CapabilityError("No $resource is loaded. Call load first.")

    class LoadFailed(
        resource: String,
        cause: Throwable?,
    ) : CapabilityError("Failed to load $resource: ${cause?.message ?: "Unknown error"}", cause)

    class OperationFailed(
        operation: String,
        cause: Throwable?,
    ) : CapabilityError("$operation failed: ${cause?.message ?: "Unknown error"}", cause)

    class ProviderNotFound(
        provider: String,
    ) : CapabilityError("No $provider provider registered. Please register a provider first.")

    class CompositeComponentFailed(
        component: String,
        cause: Throwable?,
    ) : CapabilityError("$component component failed: ${cause?.message ?: "Unknown error"}", cause)
}
