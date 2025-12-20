package com.runanywhere.sdk.core.capabilities

import com.runanywhere.sdk.foundation.SDKLogger
import kotlinx.coroutines.Job
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock

/**
 * Unified actor-like class for managing model/resource lifecycle across all capabilities.
 * Handles loading, unloading, state tracking, and concurrent access.
 *
 * One-to-one translation from iOS ModelLifecycleManager.swift.
 *
 * @param ServiceType The type of service this manager handles (e.g., LLMService, STTService)
 */
class ModelLifecycleManager<ServiceType : Any>(
    category: String,
    private val loadResource: suspend (String, ComponentConfiguration?) -> ServiceType,
    private val unloadResource: suspend (ServiceType) -> Unit
) {
    // MARK: - State

    private val mutex = Mutex()

    /** The currently loaded service */
    private var service: ServiceType? = null

    /** The ID of the currently loaded resource */
    private var loadedResourceId: String? = null

    /** In-flight loading job */
    private var inflightJob: Job? = null

    /** Configuration for loading */
    private var configuration: ComponentConfiguration? = null

    private val logger = SDKLogger(category)

    // MARK: - State Properties

    /** Whether a resource is currently loaded */
    suspend fun isLoaded(): Boolean = mutex.withLock {
        service != null
    }

    /** The currently loaded resource ID */
    suspend fun currentResourceId(): String? = mutex.withLock {
        loadedResourceId
    }

    /** The currently loaded service */
    suspend fun currentService(): ServiceType? = mutex.withLock {
        service
    }

    /** Current loading state */
    suspend fun state(): CapabilityLoadingState = mutex.withLock {
        when {
            loadedResourceId != null -> CapabilityLoadingState.Loaded(loadedResourceId!!)
            inflightJob?.isActive == true -> CapabilityLoadingState.Loading("")
            else -> CapabilityLoadingState.Idle
        }
    }

    // MARK: - Configuration

    /** Set configuration for loading */
    suspend fun configure(config: ComponentConfiguration?) {
        mutex.withLock {
            this.configuration = config
        }
    }

    // MARK: - Lifecycle Operations

    /**
     * Load a resource by ID.
     *
     * @param resourceId The resource identifier
     * @return The loaded service
     * @throws CapabilityError.LoadFailed if loading fails
     */
    suspend fun load(resourceId: String): ServiceType {
        // Check if already loaded with same ID
        mutex.withLock {
            if (loadedResourceId == resourceId && service != null) {
                logger.info("Resource already loaded: $resourceId")
                return service!!
            }
        }

        // Wait for existing load to complete (simplified - no Task.value equivalent in Kotlin)
        mutex.withLock {
            if (inflightJob?.isActive == true) {
                logger.info("Load in progress, waiting...")
                inflightJob?.join()

                // Check if the completed load was for our resource
                if (loadedResourceId == resourceId && service != null) {
                    return service!!
                }
            }
        }

        // Unload current if different
        mutex.withLock {
            val currentService = service
            if (currentService != null && loadedResourceId != resourceId) {
                logger.info("Unloading current resource before loading new one")
                unloadResource(currentService)
                service = null
                loadedResourceId = null
            }
        }

        // Perform load
        val config = mutex.withLock { configuration }

        return try {
            logger.info("Loading resource: $resourceId")
            val loadedService = loadResource(resourceId, config)

            mutex.withLock {
                service = loadedService
                loadedResourceId = resourceId
                inflightJob = null
            }

            logger.info("Resource loaded successfully: $resourceId")
            loadedService
        } catch (e: Exception) {
            mutex.withLock {
                inflightJob = null
            }
            logger.error("Failed to load resource: $e")
            throw CapabilityError.LoadFailed(resourceId, e)
        }
    }

    /**
     * Unload the currently loaded resource.
     */
    suspend fun unload() {
        val (currentService, currentResourceId) = mutex.withLock {
            Pair(service, loadedResourceId)
        }

        if (currentService == null) return

        logger.info("Unloading resource: ${currentResourceId ?: "unknown"}")
        unloadResource(currentService)

        mutex.withLock {
            service = null
            loadedResourceId = null
        }

        logger.info("Resource unloaded successfully")
    }

    /**
     * Reset all state.
     */
    suspend fun reset() {
        mutex.withLock {
            inflightJob?.cancel()
            inflightJob = null

            val currentService = service
            if (currentService != null) {
                unloadResource(currentService)
            }

            service = null
            loadedResourceId = null
            configuration = null
        }
    }

    /**
     * Get service or throw if not loaded.
     *
     * @throws CapabilityError.ResourceNotLoaded if no service is loaded
     */
    suspend fun requireService(): ServiceType {
        return mutex.withLock {
            service ?: throw CapabilityError.ResourceNotLoaded("resource")
        }
    }
}
