/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * Services extension for CppBridge.
 * Provides service registry integration for C++ core.
 *
 * Follows iOS CppBridge+Services.swift architecture.
 */

package com.runanywhere.sdk.foundation.bridge.extensions

import com.runanywhere.sdk.foundation.errors.SDKError

/**
 * Services bridge that provides service registry integration for C++ core.
 *
 * The service registry manages the lifecycle and state of all SDK services:
 * - LLM (Large Language Model)
 * - STT (Speech-to-Text)
 * - TTS (Text-to-Speech)
 * - VAD (Voice Activity Detection)
 * - VoiceAgent (Conversational AI pipeline)
 *
 * The C++ core uses the service registry for:
 * - Querying available services and their capabilities
 * - Managing service lifecycle (create, initialize, destroy)
 * - Tracking service state and readiness
 * - Coordinating service dependencies
 *
 * Usage:
 * - Called during Phase 2 initialization in [CppBridge.initializeServices]
 * - Must be registered after [CppBridgePlatformAdapter] is registered
 *
 * Thread Safety:
 * - This object is thread-safe via synchronized blocks
 * - All callbacks are thread-safe
 */
object CppBridgeServices {

    /**
     * Service type constants matching C++ RAC_SERVICE_TYPE_* values.
     */
    object ServiceType {
        /** Unknown service type */
        const val UNKNOWN = 0

        /** LLM service */
        const val LLM = 1

        /** STT service */
        const val STT = 2

        /** TTS service */
        const val TTS = 3

        /** VAD service */
        const val VAD = 4

        /** Voice Agent service */
        const val VOICE_AGENT = 5

        /** Model registry service */
        const val MODEL_REGISTRY = 6

        /** Download manager service */
        const val DOWNLOAD_MANAGER = 7

        /** Platform service (system AI capabilities) */
        const val PLATFORM = 8

        /** Telemetry service */
        const val TELEMETRY = 9

        /** Authentication service */
        const val AUTH = 10

        /**
         * Get a human-readable name for the service type.
         */
        fun getName(type: Int): String = when (type) {
            UNKNOWN -> "UNKNOWN"
            LLM -> "LLM"
            STT -> "STT"
            TTS -> "TTS"
            VAD -> "VAD"
            VOICE_AGENT -> "VOICE_AGENT"
            MODEL_REGISTRY -> "MODEL_REGISTRY"
            DOWNLOAD_MANAGER -> "DOWNLOAD_MANAGER"
            PLATFORM -> "PLATFORM"
            TELEMETRY -> "TELEMETRY"
            AUTH -> "AUTH"
            else -> "UNKNOWN($type)"
        }

        /**
         * Get all AI service types (components that process models).
         */
        fun getAIServiceTypes(): List<Int> = listOf(LLM, STT, TTS, VAD, VOICE_AGENT)

        /**
         * Get all infrastructure service types.
         */
        fun getInfrastructureServiceTypes(): List<Int> = listOf(
            MODEL_REGISTRY, DOWNLOAD_MANAGER, PLATFORM, TELEMETRY, AUTH
        )

        /**
         * Get all service types.
         */
        fun getAllServiceTypes(): List<Int> = listOf(
            LLM, STT, TTS, VAD, VOICE_AGENT,
            MODEL_REGISTRY, DOWNLOAD_MANAGER, PLATFORM, TELEMETRY, AUTH
        )
    }

    /**
     * Service state constants matching C++ RAC_SERVICE_STATE_* values.
     */
    object ServiceState {
        /** Service not registered */
        const val NOT_REGISTERED = 0

        /** Service registered but not initialized */
        const val REGISTERED = 1

        /** Service is initializing */
        const val INITIALIZING = 2

        /** Service is ready for use */
        const val READY = 3

        /** Service is busy processing */
        const val BUSY = 4

        /** Service is paused */
        const val PAUSED = 5

        /** Service is in error state */
        const val ERROR = 6

        /** Service is shutting down */
        const val SHUTTING_DOWN = 7

        /** Service is destroyed */
        const val DESTROYED = 8

        /**
         * Get a human-readable name for the service state.
         */
        fun getName(state: Int): String = when (state) {
            NOT_REGISTERED -> "NOT_REGISTERED"
            REGISTERED -> "REGISTERED"
            INITIALIZING -> "INITIALIZING"
            READY -> "READY"
            BUSY -> "BUSY"
            PAUSED -> "PAUSED"
            ERROR -> "ERROR"
            SHUTTING_DOWN -> "SHUTTING_DOWN"
            DESTROYED -> "DESTROYED"
            else -> "UNKNOWN($state)"
        }

        /**
         * Check if the state indicates the service is usable.
         */
        fun isUsable(state: Int): Boolean = state == READY

        /**
         * Check if the state indicates the service is operational (usable or busy).
         */
        fun isOperational(state: Int): Boolean = state == READY || state == BUSY
    }

    /**
     * Service capability flags.
     */
    object ServiceCapability {
        /** Service supports streaming output */
        const val STREAMING = 1

        /** Service supports cancellation */
        const val CANCELLATION = 2

        /** Service supports progress reporting */
        const val PROGRESS_REPORTING = 4

        /** Service supports batch processing */
        const val BATCH_PROCESSING = 8

        /** Service supports offline mode */
        const val OFFLINE = 16

        /** Service supports on-device processing */
        const val ON_DEVICE = 32

        /** Service supports cloud processing */
        const val CLOUD = 64

        /** Service supports real-time processing */
        const val REAL_TIME = 128

        /**
         * Check if capabilities include a specific flag.
         */
        fun hasCapability(capabilities: Int, flag: Int): Boolean = (capabilities and flag) != 0

        /**
         * Get a list of capability names from a capability flags value.
         */
        fun getCapabilityNames(capabilities: Int): List<String> {
            val names = mutableListOf<String>()
            if (hasCapability(capabilities, STREAMING)) names.add("STREAMING")
            if (hasCapability(capabilities, CANCELLATION)) names.add("CANCELLATION")
            if (hasCapability(capabilities, PROGRESS_REPORTING)) names.add("PROGRESS_REPORTING")
            if (hasCapability(capabilities, BATCH_PROCESSING)) names.add("BATCH_PROCESSING")
            if (hasCapability(capabilities, OFFLINE)) names.add("OFFLINE")
            if (hasCapability(capabilities, ON_DEVICE)) names.add("ON_DEVICE")
            if (hasCapability(capabilities, CLOUD)) names.add("CLOUD")
            if (hasCapability(capabilities, REAL_TIME)) names.add("REAL_TIME")
            return names
        }
    }

    @Volatile
    private var isRegistered: Boolean = false

    @Volatile
    private var isInitialized: Boolean = false

    private val lock = Any()

    /**
     * Registry of service information.
     */
    private val serviceRegistry = mutableMapOf<Int, ServiceInfo>()

    /**
     * Tag for logging.
     */
    private const val TAG = "CppBridgeServices"

    /**
     * Optional listener for service registry events.
     * Set this before calling [register] to receive events.
     */
    @Volatile
    var servicesListener: ServicesListener? = null

    /**
     * Service information data class.
     *
     * @param serviceType The service type (see [ServiceType])
     * @param state The current service state (see [ServiceState])
     * @param capabilities Bitfield of service capabilities (see [ServiceCapability])
     * @param version Service version string
     * @param lastError Last error message, or null if no error
     * @param lastErrorCode Last error code, or 0 if no error
     * @param metadata Additional service metadata
     */
    data class ServiceInfo(
        val serviceType: Int,
        val state: Int,
        val capabilities: Int,
        val version: String,
        val lastError: String?,
        val lastErrorCode: Int,
        val metadata: Map<String, String>
    ) {
        /**
         * Check if the service is ready for use.
         */
        fun isReady(): Boolean = ServiceState.isUsable(state)

        /**
         * Check if the service is operational.
         */
        fun isOperational(): Boolean = ServiceState.isOperational(state)

        /**
         * Get the service type name.
         */
        fun getTypeName(): String = ServiceType.getName(serviceType)

        /**
         * Get the state name.
         */
        fun getStateName(): String = ServiceState.getName(state)

        /**
         * Check if the service has a specific capability.
         */
        fun hasCapability(capability: Int): Boolean =
            ServiceCapability.hasCapability(capabilities, capability)

        /**
         * Get list of capability names.
         */
        fun getCapabilityNames(): List<String> =
            ServiceCapability.getCapabilityNames(capabilities)

        /**
         * Convert to JSON string for C++ interop.
         */
        fun toJson(): String {
            return buildString {
                append("{")
                append("\"service_type\":$serviceType,")
                append("\"state\":$state,")
                append("\"capabilities\":$capabilities,")
                append("\"version\":\"${escapeJsonString(version)}\",")
                lastError?.let { append("\"last_error\":\"${escapeJsonString(it)}\",") }
                append("\"last_error_code\":$lastErrorCode,")
                append("\"metadata\":{")
                metadata.entries.forEachIndexed { index, entry ->
                    if (index > 0) append(",")
                    append("\"${escapeJsonString(entry.key)}\":\"${escapeJsonString(entry.value)}\"")
                }
                append("}")
                append("}")
            }
        }
    }

    /**
     * Service dependency information.
     *
     * @param serviceType The service type
     * @param dependsOn List of service types this service depends on
     * @param optional Whether the dependency is optional
     */
    data class ServiceDependency(
        val serviceType: Int,
        val dependsOn: List<Int>,
        val optional: Boolean = false
    )

    /**
     * Listener interface for service registry events.
     */
    interface ServicesListener {
        /**
         * Called when a service is registered.
         *
         * @param serviceType The service type
         * @param serviceInfo The service information
         */
        fun onServiceRegistered(serviceType: Int, serviceInfo: ServiceInfo)

        /**
         * Called when a service is unregistered.
         *
         * @param serviceType The service type
         */
        fun onServiceUnregistered(serviceType: Int)

        /**
         * Called when a service state changes.
         *
         * @param serviceType The service type
         * @param previousState The previous state
         * @param newState The new state
         */
        fun onServiceStateChanged(serviceType: Int, previousState: Int, newState: Int)

        /**
         * Called when a service encounters an error.
         *
         * @param serviceType The service type
         * @param errorCode The error code
         * @param errorMessage The error message
         */
        fun onServiceError(serviceType: Int, errorCode: Int, errorMessage: String)

        /**
         * Called when all services are ready.
         */
        fun onAllServicesReady()
    }

    /**
     * Register the services callbacks with C++ core.
     *
     * This must be called during SDK initialization, after [CppBridgePlatformAdapter.register].
     * It is safe to call multiple times; subsequent calls are no-ops.
     */
    fun register() {
        synchronized(lock) {
            if (isRegistered) {
                return
            }

            // Initialize the service registry with known services
            initializeServiceRegistry()

            // Register the services callbacks with C++ via JNI
            // TODO: Call native registration
            // nativeSetServicesCallbacks()

            isRegistered = true

            CppBridgePlatformAdapter.logCallback(
                CppBridgePlatformAdapter.LogLevel.DEBUG,
                TAG,
                "Services callbacks registered"
            )
        }
    }

    /**
     * Check if the services callbacks are registered.
     */
    fun isRegistered(): Boolean = isRegistered

    /**
     * Initialize the service registry.
     *
     * This should be called after registration to initialize all services.
     *
     * @return 0 on success, error code on failure
     */
    fun initialize(): Int {
        synchronized(lock) {
            if (!isRegistered) {
                CppBridgePlatformAdapter.logCallback(
                    CppBridgePlatformAdapter.LogLevel.WARN,
                    TAG,
                    "Cannot initialize: not registered"
                )
                return -1
            }

            if (isInitialized) {
                return 0
            }

            CppBridgePlatformAdapter.logCallback(
                CppBridgePlatformAdapter.LogLevel.INFO,
                TAG,
                "Initializing service registry"
            )

            isInitialized = true

            CppBridgePlatformAdapter.logCallback(
                CppBridgePlatformAdapter.LogLevel.INFO,
                TAG,
                "Service registry initialized with ${serviceRegistry.size} services"
            )

            return 0
        }
    }

    // ========================================================================
    // SERVICE REGISTRY CALLBACKS
    // ========================================================================

    /**
     * Get service info callback.
     *
     * Returns service information as JSON string for a given service type.
     *
     * @param serviceType The service type to look up
     * @return JSON-encoded service information, or null if not found
     *
     * NOTE: This function is called from JNI. Do not capture any state.
     */
    @JvmStatic
    fun getServiceInfoCallback(serviceType: Int): String? {
        val service = synchronized(lock) {
            serviceRegistry[serviceType]
        } ?: return null

        return service.toJson()
    }

    /**
     * Register service callback.
     *
     * Registers or updates a service in the registry.
     *
     * @param serviceType The service type
     * @param serviceInfoJson JSON-encoded service information
     * @return true if registered successfully, false otherwise
     *
     * NOTE: This function is called from JNI. Do not capture any state.
     */
    @JvmStatic
    fun registerServiceCallback(serviceType: Int, serviceInfoJson: String): Boolean {
        return try {
            val serviceInfo = parseServiceInfoJson(serviceType, serviceInfoJson)
            val previousService: ServiceInfo?

            synchronized(lock) {
                previousService = serviceRegistry[serviceType]
                serviceRegistry[serviceType] = serviceInfo
            }

            CppBridgePlatformAdapter.logCallback(
                CppBridgePlatformAdapter.LogLevel.DEBUG,
                TAG,
                "Service registered: ${serviceInfo.getTypeName()} (${serviceInfo.getStateName()})"
            )

            // Notify listener
            try {
                if (previousService == null) {
                    servicesListener?.onServiceRegistered(serviceType, serviceInfo)
                } else if (previousService.state != serviceInfo.state) {
                    servicesListener?.onServiceStateChanged(
                        serviceType,
                        previousService.state,
                        serviceInfo.state
                    )
                }

                // Check if all services are ready
                checkAllServicesReady()
            } catch (e: Exception) {
                CppBridgePlatformAdapter.logCallback(
                    CppBridgePlatformAdapter.LogLevel.WARN,
                    TAG,
                    "Error in services listener: ${e.message}"
                )
            }

            true
        } catch (e: Exception) {
            CppBridgePlatformAdapter.logCallback(
                CppBridgePlatformAdapter.LogLevel.ERROR,
                TAG,
                "Failed to register service: ${e.message}"
            )
            false
        }
    }

    /**
     * Unregister service callback.
     *
     * Removes a service from the registry.
     *
     * @param serviceType The service type to remove
     * @return true if removed, false if not found
     *
     * NOTE: This function is called from JNI. Do not capture any state.
     */
    @JvmStatic
    fun unregisterServiceCallback(serviceType: Int): Boolean {
        val removed = synchronized(lock) {
            serviceRegistry.remove(serviceType)
        }

        if (removed != null) {
            CppBridgePlatformAdapter.logCallback(
                CppBridgePlatformAdapter.LogLevel.DEBUG,
                TAG,
                "Service unregistered: ${ServiceType.getName(serviceType)}"
            )

            // Notify listener
            try {
                servicesListener?.onServiceUnregistered(serviceType)
            } catch (e: Exception) {
                CppBridgePlatformAdapter.logCallback(
                    CppBridgePlatformAdapter.LogLevel.WARN,
                    TAG,
                    "Error in services listener onServiceUnregistered: ${e.message}"
                )
            }

            return true
        }

        return false
    }

    /**
     * Get service state callback.
     *
     * Returns the current state of a service.
     *
     * @param serviceType The service type
     * @return The service state, or [ServiceState.NOT_REGISTERED] if not found
     *
     * NOTE: This function is called from JNI. Do not capture any state.
     */
    @JvmStatic
    fun getServiceStateCallback(serviceType: Int): Int {
        return synchronized(lock) {
            serviceRegistry[serviceType]?.state ?: ServiceState.NOT_REGISTERED
        }
    }

    /**
     * Set service state callback.
     *
     * Updates the state of a service.
     *
     * @param serviceType The service type
     * @param state The new state
     * @return true if updated, false if service not found
     *
     * NOTE: This function is called from JNI. Do not capture any state.
     */
    @JvmStatic
    fun setServiceStateCallback(serviceType: Int, state: Int): Boolean {
        val previousState: Int
        val updated: Boolean

        synchronized(lock) {
            val service = serviceRegistry[serviceType]
            if (service == null) {
                return false
            }

            previousState = service.state
            if (previousState == state) {
                return true // No change needed
            }

            serviceRegistry[serviceType] = service.copy(state = state)
            updated = true
        }

        if (updated) {
            CppBridgePlatformAdapter.logCallback(
                CppBridgePlatformAdapter.LogLevel.DEBUG,
                TAG,
                "Service state updated: ${ServiceType.getName(serviceType)} " +
                    "${ServiceState.getName(previousState)} -> ${ServiceState.getName(state)}"
            )

            // Notify listener
            try {
                servicesListener?.onServiceStateChanged(serviceType, previousState, state)

                // Check if all services are ready
                if (state == ServiceState.READY) {
                    checkAllServicesReady()
                }
            } catch (e: Exception) {
                CppBridgePlatformAdapter.logCallback(
                    CppBridgePlatformAdapter.LogLevel.WARN,
                    TAG,
                    "Error in services listener onServiceStateChanged: ${e.message}"
                )
            }
        }

        return true
    }

    /**
     * Set service error callback.
     *
     * Updates the error state of a service.
     *
     * @param serviceType The service type
     * @param errorCode The error code
     * @param errorMessage The error message
     *
     * NOTE: This function is called from JNI. Do not capture any state.
     */
    @JvmStatic
    fun setServiceErrorCallback(serviceType: Int, errorCode: Int, errorMessage: String) {
        synchronized(lock) {
            val service = serviceRegistry[serviceType] ?: return
            serviceRegistry[serviceType] = service.copy(
                state = ServiceState.ERROR,
                lastError = errorMessage,
                lastErrorCode = errorCode
            )
        }

        CppBridgePlatformAdapter.logCallback(
            CppBridgePlatformAdapter.LogLevel.ERROR,
            TAG,
            "Service error: ${ServiceType.getName(serviceType)} (code: $errorCode): $errorMessage"
        )

        // Notify listener
        try {
            servicesListener?.onServiceError(serviceType, errorCode, errorMessage)
            servicesListener?.onServiceStateChanged(
                serviceType,
                ServiceState.READY,
                ServiceState.ERROR
            )
        } catch (e: Exception) {
            CppBridgePlatformAdapter.logCallback(
                CppBridgePlatformAdapter.LogLevel.WARN,
                TAG,
                "Error in services listener: ${e.message}"
            )
        }
    }

    /**
     * Get all services callback.
     *
     * Returns all registered services as JSON array.
     *
     * @return JSON-encoded array of service information
     *
     * NOTE: This function is called from JNI. Do not capture any state.
     */
    @JvmStatic
    fun getAllServicesCallback(): String {
        val services = synchronized(lock) {
            serviceRegistry.values.toList()
        }

        return buildString {
            append("[")
            services.forEachIndexed { index, service ->
                if (index > 0) append(",")
                append(service.toJson())
            }
            append("]")
        }
    }

    /**
     * Get ready services callback.
     *
     * Returns all ready services as JSON array.
     *
     * @return JSON-encoded array of ready service information
     *
     * NOTE: This function is called from JNI. Do not capture any state.
     */
    @JvmStatic
    fun getReadyServicesCallback(): String {
        val services = synchronized(lock) {
            serviceRegistry.values.filter { it.isReady() }
        }

        return buildString {
            append("[")
            services.forEachIndexed { index, service ->
                if (index > 0) append(",")
                append(service.toJson())
            }
            append("]")
        }
    }

    /**
     * Is service ready callback.
     *
     * @param serviceType The service type to check
     * @return true if the service is ready, false otherwise
     *
     * NOTE: This function is called from JNI. Do not capture any state.
     */
    @JvmStatic
    fun isServiceReadyCallback(serviceType: Int): Boolean {
        return synchronized(lock) {
            serviceRegistry[serviceType]?.isReady() ?: false
        }
    }

    /**
     * Get service capabilities callback.
     *
     * @param serviceType The service type
     * @return The service capabilities bitfield, or 0 if not found
     *
     * NOTE: This function is called from JNI. Do not capture any state.
     */
    @JvmStatic
    fun getServiceCapabilitiesCallback(serviceType: Int): Int {
        return synchronized(lock) {
            serviceRegistry[serviceType]?.capabilities ?: 0
        }
    }

    /**
     * Has service callback.
     *
     * @param serviceType The service type to check
     * @return true if the service exists in the registry
     *
     * NOTE: This function is called from JNI. Do not capture any state.
     */
    @JvmStatic
    fun hasServiceCallback(serviceType: Int): Boolean {
        return synchronized(lock) {
            serviceRegistry.containsKey(serviceType)
        }
    }

    /**
     * Get service count callback.
     *
     * @return The number of registered services
     *
     * NOTE: This function is called from JNI. Do not capture any state.
     */
    @JvmStatic
    fun getServiceCountCallback(): Int {
        return synchronized(lock) {
            serviceRegistry.size
        }
    }

    // ========================================================================
    // JNI NATIVE DECLARATIONS
    // ========================================================================

    /**
     * Native method to set the services callbacks with C++ core.
     *
     * Registers all service registry callbacks with C++ core.
     *
     * C API: rac_services_set_callbacks(...)
     */
    @JvmStatic
    private external fun nativeSetServicesCallbacks()

    /**
     * Native method to unset the services callbacks.
     *
     * Called during shutdown to clean up native resources.
     *
     * C API: rac_services_set_callbacks(nullptr)
     */
    @JvmStatic
    private external fun nativeUnsetServicesCallbacks()

    /**
     * Native method to initialize the service registry.
     *
     * @return 0 on success, error code on failure
     *
     * C API: rac_services_initialize()
     */
    @JvmStatic
    external fun nativeInitialize(): Int

    /**
     * Native method to shutdown the service registry.
     *
     * @return 0 on success, error code on failure
     *
     * C API: rac_services_shutdown()
     */
    @JvmStatic
    external fun nativeShutdown(): Int

    /**
     * Native method to get a service from the C++ registry.
     *
     * @param serviceType The service type
     * @return JSON-encoded service info, or null if not found
     *
     * C API: rac_services_get(service_type)
     */
    @JvmStatic
    external fun nativeGet(serviceType: Int): String?

    /**
     * Native method to register a service with the C++ registry.
     *
     * @param serviceType The service type
     * @param serviceInfoJson JSON-encoded service information
     * @return 0 on success, error code on failure
     *
     * C API: rac_services_register(service_type, service_info)
     */
    @JvmStatic
    external fun nativeRegister(serviceType: Int, serviceInfoJson: String): Int

    /**
     * Native method to start a service.
     *
     * @param serviceType The service type
     * @return 0 on success, error code on failure
     *
     * C API: rac_services_start(service_type)
     */
    @JvmStatic
    external fun nativeStart(serviceType: Int): Int

    /**
     * Native method to stop a service.
     *
     * @param serviceType The service type
     * @return 0 on success, error code on failure
     *
     * C API: rac_services_stop(service_type)
     */
    @JvmStatic
    external fun nativeStop(serviceType: Int): Int

    // ========================================================================
    // LIFECYCLE MANAGEMENT
    // ========================================================================

    /**
     * Unregister the services callbacks and clean up resources.
     *
     * Called during SDK shutdown.
     */
    fun unregister() {
        synchronized(lock) {
            if (!isRegistered) {
                return
            }

            // TODO: Call native unregistration
            // nativeUnsetServicesCallbacks()

            servicesListener = null
            serviceRegistry.clear()
            isInitialized = false
            isRegistered = false
        }
    }

    // ========================================================================
    // PUBLIC UTILITY METHODS
    // ========================================================================

    /**
     * Get a service by type.
     *
     * @param serviceType The service type
     * @return The service information, or null if not found
     */
    fun getService(serviceType: Int): ServiceInfo? {
        return synchronized(lock) {
            serviceRegistry[serviceType]
        }
    }

    /**
     * Get all registered services.
     *
     * @return List of all service information
     */
    fun getAllServices(): List<ServiceInfo> {
        return synchronized(lock) {
            serviceRegistry.values.toList()
        }
    }

    /**
     * Get all ready services.
     *
     * @return List of ready service information
     */
    fun getReadyServices(): List<ServiceInfo> {
        return synchronized(lock) {
            serviceRegistry.values.filter { it.isReady() }
        }
    }

    /**
     * Get all AI services.
     *
     * @return List of AI service information (LLM, STT, TTS, VAD, VoiceAgent)
     */
    fun getAIServices(): List<ServiceInfo> {
        return synchronized(lock) {
            serviceRegistry.values.filter { it.serviceType in ServiceType.getAIServiceTypes() }
        }
    }

    /**
     * Check if a service is registered.
     *
     * @param serviceType The service type
     * @return true if the service is registered
     */
    fun hasService(serviceType: Int): Boolean {
        return hasServiceCallback(serviceType)
    }

    /**
     * Check if a service is ready.
     *
     * @param serviceType The service type
     * @return true if the service is ready
     */
    fun isServiceReady(serviceType: Int): Boolean {
        return isServiceReadyCallback(serviceType)
    }

    /**
     * Check if all AI services are ready.
     *
     * @return true if all AI services are ready
     */
    fun areAIServicesReady(): Boolean {
        return synchronized(lock) {
            ServiceType.getAIServiceTypes().all { type ->
                serviceRegistry[type]?.isReady() ?: false
            }
        }
    }

    /**
     * Get the number of registered services.
     *
     * @return The service count
     */
    fun getServiceCount(): Int {
        return getServiceCountCallback()
    }

    /**
     * Register a service.
     *
     * @param serviceInfo The service information to register
     */
    fun registerService(serviceInfo: ServiceInfo) {
        registerServiceCallback(serviceInfo.serviceType, serviceInfo.toJson())
    }

    /**
     * Unregister a service.
     *
     * @param serviceType The service type to unregister
     * @return true if the service was removed, false if not found
     */
    fun unregisterService(serviceType: Int): Boolean {
        return unregisterServiceCallback(serviceType)
    }

    /**
     * Update a service's state.
     *
     * @param serviceType The service type
     * @param state The new state (see [ServiceState])
     * @return true if updated, false if service not found
     */
    fun updateServiceState(serviceType: Int, state: Int): Boolean {
        return setServiceStateCallback(serviceType, state)
    }

    /**
     * Set a service's error.
     *
     * @param serviceType The service type
     * @param errorCode The error code
     * @param errorMessage The error message
     */
    fun setServiceError(serviceType: Int, errorCode: Int, errorMessage: String) {
        setServiceErrorCallback(serviceType, errorCode, errorMessage)
    }

    /**
     * Get the service dependencies.
     *
     * @return Map of service type to its dependencies
     */
    fun getServiceDependencies(): Map<Int, ServiceDependency> {
        return mapOf(
            ServiceType.VOICE_AGENT to ServiceDependency(
                serviceType = ServiceType.VOICE_AGENT,
                dependsOn = listOf(ServiceType.LLM, ServiceType.STT, ServiceType.TTS, ServiceType.VAD)
            ),
            ServiceType.LLM to ServiceDependency(
                serviceType = ServiceType.LLM,
                dependsOn = listOf(ServiceType.MODEL_REGISTRY)
            ),
            ServiceType.STT to ServiceDependency(
                serviceType = ServiceType.STT,
                dependsOn = listOf(ServiceType.MODEL_REGISTRY)
            ),
            ServiceType.TTS to ServiceDependency(
                serviceType = ServiceType.TTS,
                dependsOn = listOf(ServiceType.MODEL_REGISTRY)
            ),
            ServiceType.VAD to ServiceDependency(
                serviceType = ServiceType.VAD,
                dependsOn = listOf(ServiceType.MODEL_REGISTRY)
            )
        )
    }

    /**
     * Check if a service's dependencies are satisfied.
     *
     * @param serviceType The service type
     * @return true if all dependencies are ready
     */
    fun areDependenciesSatisfied(serviceType: Int): Boolean {
        val dependency = getServiceDependencies()[serviceType] ?: return true

        return synchronized(lock) {
            dependency.dependsOn.all { depType ->
                val depService = serviceRegistry[depType]
                if (dependency.optional) {
                    depService == null || depService.isReady()
                } else {
                    depService?.isReady() ?: false
                }
            }
        }
    }

    /**
     * Get a state summary for diagnostics.
     *
     * @return Human-readable state summary
     */
    fun getStateSummary(): String {
        val services = synchronized(lock) { serviceRegistry.values.toList() }

        return buildString {
            append("Services Registry: registered=$isRegistered, initialized=$isInitialized\n")
            append("Services (${services.size}):\n")
            services.forEach { service ->
                append("  - ${service.getTypeName()}: ${service.getStateName()}")
                if (service.lastError != null) {
                    append(" [ERROR: ${service.lastError}]")
                }
                append("\n")
            }
        }
    }

    // ========================================================================
    // PRIVATE UTILITY FUNCTIONS
    // ========================================================================

    /**
     * Initialize the service registry with known services.
     */
    private fun initializeServiceRegistry() {
        // Register all known service types with NOT_REGISTERED state
        ServiceType.getAllServiceTypes().forEach { serviceType ->
            serviceRegistry[serviceType] = ServiceInfo(
                serviceType = serviceType,
                state = ServiceState.NOT_REGISTERED,
                capabilities = getDefaultCapabilities(serviceType),
                version = "1.0.0",
                lastError = null,
                lastErrorCode = 0,
                metadata = emptyMap()
            )
        }
    }

    /**
     * Get default capabilities for a service type.
     */
    private fun getDefaultCapabilities(serviceType: Int): Int {
        return when (serviceType) {
            ServiceType.LLM -> {
                ServiceCapability.STREAMING or
                    ServiceCapability.CANCELLATION or
                    ServiceCapability.ON_DEVICE
            }
            ServiceType.STT -> {
                ServiceCapability.STREAMING or
                    ServiceCapability.CANCELLATION or
                    ServiceCapability.ON_DEVICE or
                    ServiceCapability.REAL_TIME
            }
            ServiceType.TTS -> {
                ServiceCapability.STREAMING or
                    ServiceCapability.CANCELLATION or
                    ServiceCapability.ON_DEVICE
            }
            ServiceType.VAD -> {
                ServiceCapability.REAL_TIME or
                    ServiceCapability.ON_DEVICE
            }
            ServiceType.VOICE_AGENT -> {
                ServiceCapability.STREAMING or
                    ServiceCapability.CANCELLATION or
                    ServiceCapability.REAL_TIME or
                    ServiceCapability.ON_DEVICE
            }
            ServiceType.DOWNLOAD_MANAGER -> {
                ServiceCapability.PROGRESS_REPORTING or
                    ServiceCapability.CANCELLATION
            }
            else -> 0
        }
    }

    /**
     * Check if all required services are ready and notify listener.
     */
    private fun checkAllServicesReady() {
        val allReady = synchronized(lock) {
            ServiceType.getAIServiceTypes().all { type ->
                val service = serviceRegistry[type]
                service == null || service.isReady()
            }
        }

        if (allReady) {
            try {
                servicesListener?.onAllServicesReady()
            } catch (e: Exception) {
                CppBridgePlatformAdapter.logCallback(
                    CppBridgePlatformAdapter.LogLevel.WARN,
                    TAG,
                    "Error in services listener onAllServicesReady: ${e.message}"
                )
            }
        }
    }

    /**
     * Parse JSON string to ServiceInfo.
     */
    private fun parseServiceInfoJson(serviceType: Int, json: String): ServiceInfo {
        val cleanJson = json.trim()

        fun extractString(key: String): String? {
            val pattern = "\"$key\"\\s*:\\s*\"([^\"]*)\""
            val regex = Regex(pattern)
            return regex.find(cleanJson)?.groupValues?.get(1)
        }

        fun extractInt(key: String): Int {
            val pattern = "\"$key\"\\s*:\\s*(-?\\d+)"
            val regex = Regex(pattern)
            return regex.find(cleanJson)?.groupValues?.get(1)?.toIntOrNull() ?: 0
        }

        return ServiceInfo(
            serviceType = serviceType,
            state = extractInt("state"),
            capabilities = extractInt("capabilities"),
            version = extractString("version") ?: "1.0.0",
            lastError = extractString("last_error"),
            lastErrorCode = extractInt("last_error_code"),
            metadata = emptyMap() // Simplified - full implementation would parse nested object
        )
    }

    /**
     * Escape a string for JSON encoding.
     */
    private fun escapeJsonString(str: String): String {
        return str
            .replace("\\", "\\\\")
            .replace("\"", "\\\"")
            .replace("\n", "\\n")
            .replace("\r", "\\r")
            .replace("\t", "\\t")
    }
}
