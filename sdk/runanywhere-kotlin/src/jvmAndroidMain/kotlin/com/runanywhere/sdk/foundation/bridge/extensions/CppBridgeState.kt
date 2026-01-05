/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * State extension for CppBridge.
 * Provides SDK state management callbacks for C++ core.
 *
 * Follows iOS CppBridge+State.swift architecture.
 */

package com.runanywhere.sdk.foundation.bridge.extensions

/**
 * State bridge that provides SDK state management callbacks for C++ core.
 *
 * The C++ core needs state information for:
 * - Tracking SDK lifecycle (initializing, ready, error)
 * - Component state tracking (LLM, STT, TTS, VAD)
 * - Health monitoring and diagnostics
 * - Error state reporting
 *
 * Usage:
 * - Called during Phase 1 initialization in [CppBridge.initialize]
 * - Must be registered after [CppBridgePlatformAdapter] is registered
 *
 * Thread Safety:
 * - Registration is thread-safe via synchronized block
 * - All callbacks are thread-safe using atomic operations
 */
object CppBridgeState {

    /**
     * SDK state constants matching C++ RAC_STATE_* values.
     */
    object SDKState {
        /** SDK not initialized */
        const val UNINITIALIZED = 0

        /** SDK is initializing */
        const val INITIALIZING = 1

        /** SDK core is initialized (Phase 1 complete) */
        const val CORE_READY = 2

        /** SDK services are initialized (Phase 2 complete) */
        const val SERVICES_READY = 3

        /** SDK is fully ready for use */
        const val READY = 4

        /** SDK is shutting down */
        const val SHUTTING_DOWN = 5

        /** SDK encountered an error */
        const val ERROR = 6

        /**
         * Get a human-readable name for the SDK state.
         */
        fun getName(state: Int): String = when (state) {
            UNINITIALIZED -> "UNINITIALIZED"
            INITIALIZING -> "INITIALIZING"
            CORE_READY -> "CORE_READY"
            SERVICES_READY -> "SERVICES_READY"
            READY -> "READY"
            SHUTTING_DOWN -> "SHUTTING_DOWN"
            ERROR -> "ERROR"
            else -> "UNKNOWN($state)"
        }

        /**
         * Check if the state indicates the SDK is usable.
         */
        fun isUsable(state: Int): Boolean = state in CORE_READY..READY
    }

    /**
     * Component state constants matching C++ RAC_COMPONENT_STATE_* values.
     */
    object ComponentState {
        /** Component not created */
        const val NOT_CREATED = 0

        /** Component created but not loaded */
        const val CREATED = 1

        /** Component is loading model */
        const val LOADING = 2

        /** Component is ready for use */
        const val READY = 3

        /** Component is processing */
        const val PROCESSING = 4

        /** Component is unloading */
        const val UNLOADING = 5

        /** Component encountered an error */
        const val ERROR = 6

        /**
         * Get a human-readable name for the component state.
         */
        fun getName(state: Int): String = when (state) {
            NOT_CREATED -> "NOT_CREATED"
            CREATED -> "CREATED"
            LOADING -> "LOADING"
            READY -> "READY"
            PROCESSING -> "PROCESSING"
            UNLOADING -> "UNLOADING"
            ERROR -> "ERROR"
            else -> "UNKNOWN($state)"
        }
    }

    /**
     * Component type constants matching C++ RAC_COMPONENT_TYPE_* values.
     */
    object ComponentType {
        const val LLM = 0
        const val STT = 1
        const val TTS = 2
        const val VAD = 3
        const val VOICE_AGENT = 4

        /**
         * Get a human-readable name for the component type.
         */
        fun getName(type: Int): String = when (type) {
            LLM -> "LLM"
            STT -> "STT"
            TTS -> "TTS"
            VAD -> "VAD"
            VOICE_AGENT -> "VOICE_AGENT"
            else -> "UNKNOWN($type)"
        }
    }

    /**
     * Health status constants.
     */
    object HealthStatus {
        /** All systems operational */
        const val HEALTHY = 0

        /** Some issues detected but functional */
        const val DEGRADED = 1

        /** Critical issues, functionality impaired */
        const val UNHEALTHY = 2

        /**
         * Get a human-readable name for the health status.
         */
        fun getName(status: Int): String = when (status) {
            HEALTHY -> "HEALTHY"
            DEGRADED -> "DEGRADED"
            UNHEALTHY -> "UNHEALTHY"
            else -> "UNKNOWN($status)"
        }
    }

    @Volatile
    private var isRegistered: Boolean = false

    @Volatile
    private var sdkState: Int = SDKState.UNINITIALIZED

    @Volatile
    private var healthStatus: Int = HealthStatus.HEALTHY

    @Volatile
    private var lastError: String? = null

    @Volatile
    private var lastErrorCode: Int = 0

    private val lock = Any()

    /**
     * Component states storage.
     */
    private val componentStates = mutableMapOf<Int, Int>()

    /**
     * Component error messages.
     */
    private val componentErrors = mutableMapOf<Int, String>()

    /**
     * Tag for logging.
     */
    private const val TAG = "CppBridgeState"

    /**
     * Optional listener for state change events.
     * Set this before calling [register] to receive events.
     */
    @Volatile
    var stateListener: StateListener? = null

    /**
     * Listener interface for state change events.
     */
    interface StateListener {
        /**
         * Called when the SDK state changes.
         *
         * @param previousState The previous SDK state
         * @param newState The new SDK state
         */
        fun onSDKStateChanged(previousState: Int, newState: Int)

        /**
         * Called when a component state changes.
         *
         * @param componentType The component type (see [ComponentType])
         * @param previousState The previous component state
         * @param newState The new component state
         */
        fun onComponentStateChanged(componentType: Int, previousState: Int, newState: Int)

        /**
         * Called when the health status changes.
         *
         * @param previousStatus The previous health status
         * @param newStatus The new health status
         */
        fun onHealthStatusChanged(previousStatus: Int, newStatus: Int)

        /**
         * Called when an error occurs.
         *
         * @param errorCode The error code
         * @param errorMessage The error message
         */
        fun onError(errorCode: Int, errorMessage: String)
    }

    /**
     * Register the state callbacks with C++ core.
     *
     * This must be called during SDK initialization, after [CppBridgePlatformAdapter.register].
     * It is safe to call multiple times; subsequent calls are no-ops.
     */
    fun register() {
        synchronized(lock) {
            if (isRegistered) {
                return
            }

            // Initialize component states
            initializeComponentStates()

            // Register the state callbacks with C++ via JNI
            // TODO: Call native registration
            // nativeSetStateCallbacks()

            isRegistered = true

            CppBridgePlatformAdapter.logCallback(
                CppBridgePlatformAdapter.LogLevel.DEBUG,
                TAG,
                "State callbacks registered. SDK State: ${SDKState.getName(sdkState)}"
            )
        }
    }

    /**
     * Check if the state callbacks are registered.
     */
    fun isRegistered(): Boolean = isRegistered

    /**
     * Get the current SDK state.
     */
    fun getSDKState(): Int = sdkState

    /**
     * Check if the SDK is ready for use.
     */
    fun isReady(): Boolean = SDKState.isUsable(sdkState)

    // ========================================================================
    // STATE CALLBACKS
    // ========================================================================

    /**
     * Get the SDK state callback.
     *
     * @return The current SDK state (see [SDKState])
     *
     * NOTE: This function is called from JNI. Do not capture any state.
     */
    @JvmStatic
    fun getSDKStateCallback(): Int {
        return sdkState
    }

    /**
     * Set the SDK state callback.
     *
     * Called by C++ core when SDK state changes.
     *
     * @param state The new SDK state (see [SDKState])
     *
     * NOTE: This function is called from JNI. Do not capture any state.
     */
    @JvmStatic
    fun setSDKStateCallback(state: Int) {
        val previousState = sdkState
        if (state != previousState) {
            sdkState = state

            CppBridgePlatformAdapter.logCallback(
                CppBridgePlatformAdapter.LogLevel.INFO,
                TAG,
                "SDK state changed: ${SDKState.getName(previousState)} -> ${SDKState.getName(state)}"
            )

            // Notify listener
            try {
                stateListener?.onSDKStateChanged(previousState, state)
            } catch (e: Exception) {
                CppBridgePlatformAdapter.logCallback(
                    CppBridgePlatformAdapter.LogLevel.WARN,
                    TAG,
                    "Error in state listener: ${e.message}"
                )
            }
        }
    }

    /**
     * Get a component state callback.
     *
     * @param componentType The component type (see [ComponentType])
     * @return The component state (see [ComponentState])
     *
     * NOTE: This function is called from JNI. Do not capture any state.
     */
    @JvmStatic
    fun getComponentStateCallback(componentType: Int): Int {
        return synchronized(lock) {
            componentStates[componentType] ?: ComponentState.NOT_CREATED
        }
    }

    /**
     * Set a component state callback.
     *
     * Called by C++ core when a component state changes.
     *
     * @param componentType The component type (see [ComponentType])
     * @param state The new component state (see [ComponentState])
     *
     * NOTE: This function is called from JNI. Do not capture any state.
     */
    @JvmStatic
    fun setComponentStateCallback(componentType: Int, state: Int) {
        val previousState: Int
        synchronized(lock) {
            previousState = componentStates[componentType] ?: ComponentState.NOT_CREATED
            componentStates[componentType] = state

            // Clear error if state is not ERROR
            if (state != ComponentState.ERROR) {
                componentErrors.remove(componentType)
            }
        }

        if (state != previousState) {
            CppBridgePlatformAdapter.logCallback(
                CppBridgePlatformAdapter.LogLevel.DEBUG,
                TAG,
                "Component ${ComponentType.getName(componentType)} state changed: " +
                    "${ComponentState.getName(previousState)} -> ${ComponentState.getName(state)}"
            )

            // Notify listener
            try {
                stateListener?.onComponentStateChanged(componentType, previousState, state)
            } catch (e: Exception) {
                CppBridgePlatformAdapter.logCallback(
                    CppBridgePlatformAdapter.LogLevel.WARN,
                    TAG,
                    "Error in state listener onComponentStateChanged: ${e.message}"
                )
            }

            // Update health status based on component states
            updateHealthStatus()
        }
    }

    /**
     * Set component error callback.
     *
     * Called by C++ core when a component encounters an error.
     *
     * @param componentType The component type (see [ComponentType])
     * @param errorCode The error code
     * @param errorMessage The error message
     *
     * NOTE: This function is called from JNI. Do not capture any state.
     */
    @JvmStatic
    fun setComponentErrorCallback(componentType: Int, errorCode: Int, errorMessage: String) {
        synchronized(lock) {
            componentStates[componentType] = ComponentState.ERROR
            componentErrors[componentType] = errorMessage
        }

        CppBridgePlatformAdapter.logCallback(
            CppBridgePlatformAdapter.LogLevel.ERROR,
            TAG,
            "Component ${ComponentType.getName(componentType)} error: [$errorCode] $errorMessage"
        )

        // Notify listener
        try {
            stateListener?.onError(errorCode, "Component ${ComponentType.getName(componentType)}: $errorMessage")
        } catch (e: Exception) {
            CppBridgePlatformAdapter.logCallback(
                CppBridgePlatformAdapter.LogLevel.WARN,
                TAG,
                "Error in state listener onError: ${e.message}"
            )
        }

        updateHealthStatus()
    }

    /**
     * Get the health status callback.
     *
     * @return The current health status (see [HealthStatus])
     *
     * NOTE: This function is called from JNI. Do not capture any state.
     */
    @JvmStatic
    fun getHealthStatusCallback(): Int {
        return healthStatus
    }

    /**
     * Set the health status callback.
     *
     * Called by C++ core when health status changes.
     *
     * @param status The new health status (see [HealthStatus])
     *
     * NOTE: This function is called from JNI. Do not capture any state.
     */
    @JvmStatic
    fun setHealthStatusCallback(status: Int) {
        val previousStatus = healthStatus
        if (status != previousStatus) {
            healthStatus = status

            CppBridgePlatformAdapter.logCallback(
                CppBridgePlatformAdapter.LogLevel.INFO,
                TAG,
                "Health status changed: ${HealthStatus.getName(previousStatus)} -> ${HealthStatus.getName(status)}"
            )

            // Notify listener
            try {
                stateListener?.onHealthStatusChanged(previousStatus, status)
            } catch (e: Exception) {
                CppBridgePlatformAdapter.logCallback(
                    CppBridgePlatformAdapter.LogLevel.WARN,
                    TAG,
                    "Error in state listener onHealthStatusChanged: ${e.message}"
                )
            }
        }
    }

    /**
     * Set SDK error callback.
     *
     * Called by C++ core when an error occurs.
     *
     * @param errorCode The error code
     * @param errorMessage The error message
     *
     * NOTE: This function is called from JNI. Do not capture any state.
     */
    @JvmStatic
    fun setErrorCallback(errorCode: Int, errorMessage: String) {
        lastErrorCode = errorCode
        lastError = errorMessage

        CppBridgePlatformAdapter.logCallback(
            CppBridgePlatformAdapter.LogLevel.ERROR,
            TAG,
            "SDK error: [$errorCode] $errorMessage"
        )

        // Set SDK state to ERROR if it's a critical error
        if (errorCode != 0) {
            setSDKStateCallback(SDKState.ERROR)
        }

        // Notify listener
        try {
            stateListener?.onError(errorCode, errorMessage)
        } catch (e: Exception) {
            CppBridgePlatformAdapter.logCallback(
                CppBridgePlatformAdapter.LogLevel.WARN,
                TAG,
                "Error in state listener onError: ${e.message}"
            )
        }
    }

    /**
     * Clear error callback.
     *
     * Clears the last error state.
     *
     * NOTE: This function is called from JNI. Do not capture any state.
     */
    @JvmStatic
    fun clearErrorCallback() {
        lastErrorCode = 0
        lastError = null

        CppBridgePlatformAdapter.logCallback(
            CppBridgePlatformAdapter.LogLevel.DEBUG,
            TAG,
            "Error state cleared"
        )
    }

    /**
     * Check if SDK is ready callback.
     *
     * @return true if SDK is ready for use, false otherwise
     *
     * NOTE: This function is called from JNI. Do not capture any state.
     */
    @JvmStatic
    fun isReadyCallback(): Boolean {
        return SDKState.isUsable(sdkState)
    }

    // ========================================================================
    // JNI NATIVE DECLARATIONS
    // ========================================================================

    /**
     * Native method to set the state callbacks with C++ core.
     *
     * Registers [getSDKStateCallback], [setSDKStateCallback],
     * [getComponentStateCallback], [setComponentStateCallback], etc. with C++ core.
     *
     * C API: rac_state_set_callbacks(...)
     */
    @JvmStatic
    private external fun nativeSetStateCallbacks()

    /**
     * Native method to unset the state callbacks.
     *
     * Called during shutdown to clean up native resources.
     *
     * C API: rac_state_set_callbacks(nullptr)
     */
    @JvmStatic
    private external fun nativeUnsetStateCallbacks()

    /**
     * Native method to get the C++ SDK state.
     *
     * @return The C++ SDK state
     *
     * C API: rac_get_state()
     */
    @JvmStatic
    external fun nativeGetState(): Int

    /**
     * Native method to check if C++ SDK is initialized.
     *
     * @return true if initialized, false otherwise
     *
     * C API: rac_is_initialized()
     */
    @JvmStatic
    external fun nativeIsInitialized(): Boolean

    // ========================================================================
    // LIFECYCLE MANAGEMENT
    // ========================================================================

    /**
     * Unregister the state callbacks and clean up resources.
     *
     * Called during SDK shutdown.
     */
    fun unregister() {
        synchronized(lock) {
            if (!isRegistered) {
                return
            }

            // TODO: Call native unregistration
            // nativeUnsetStateCallbacks()

            stateListener = null
            componentStates.clear()
            componentErrors.clear()
            lastError = null
            lastErrorCode = 0
            sdkState = SDKState.UNINITIALIZED
            healthStatus = HealthStatus.HEALTHY
            isRegistered = false
        }
    }

    // ========================================================================
    // UTILITY FUNCTIONS
    // ========================================================================

    /**
     * Initialize component states to NOT_CREATED.
     */
    private fun initializeComponentStates() {
        componentStates[ComponentType.LLM] = ComponentState.NOT_CREATED
        componentStates[ComponentType.STT] = ComponentState.NOT_CREATED
        componentStates[ComponentType.TTS] = ComponentState.NOT_CREATED
        componentStates[ComponentType.VAD] = ComponentState.NOT_CREATED
        componentStates[ComponentType.VOICE_AGENT] = ComponentState.NOT_CREATED
    }

    /**
     * Update health status based on component states.
     */
    private fun updateHealthStatus() {
        val hasErrors = synchronized(lock) {
            componentStates.values.any { it == ComponentState.ERROR }
        }

        val newStatus = when {
            sdkState == SDKState.ERROR -> HealthStatus.UNHEALTHY
            hasErrors -> HealthStatus.DEGRADED
            else -> HealthStatus.HEALTHY
        }

        if (newStatus != healthStatus) {
            setHealthStatusCallback(newStatus)
        }
    }

    /**
     * Get the last error message.
     *
     * @return The last error message, or null if no error
     */
    fun getLastError(): String? = lastError

    /**
     * Get the last error code.
     *
     * @return The last error code, or 0 if no error
     */
    fun getLastErrorCode(): Int = lastErrorCode

    /**
     * Get the state of a specific component.
     *
     * @param componentType The component type (see [ComponentType])
     * @return The component state (see [ComponentState])
     */
    fun getComponentState(componentType: Int): Int {
        return getComponentStateCallback(componentType)
    }

    /**
     * Get the error message for a component.
     *
     * @param componentType The component type
     * @return The error message, or null if no error
     */
    fun getComponentError(componentType: Int): String? {
        return synchronized(lock) {
            componentErrors[componentType]
        }
    }

    /**
     * Get the health status.
     *
     * @return The current health status (see [HealthStatus])
     */
    fun getHealthStatus(): Int = healthStatus

    /**
     * Get all component states as a map.
     *
     * @return Map of component type to state
     */
    fun getAllComponentStates(): Map<Int, Int> {
        return synchronized(lock) {
            componentStates.toMap()
        }
    }

    /**
     * Set the SDK state.
     *
     * Used internally during initialization phases.
     *
     * @param state The new SDK state
     */
    fun setState(state: Int) {
        setSDKStateCallback(state)
    }

    /**
     * Clear all error states.
     */
    fun clearErrors() {
        synchronized(lock) {
            lastError = null
            lastErrorCode = 0
            componentErrors.clear()

            // Reset any components in ERROR state to NOT_CREATED
            for (key in componentStates.keys) {
                if (componentStates[key] == ComponentState.ERROR) {
                    componentStates[key] = ComponentState.NOT_CREATED
                }
            }
        }

        updateHealthStatus()

        CppBridgePlatformAdapter.logCallback(
            CppBridgePlatformAdapter.LogLevel.DEBUG,
            TAG,
            "All error states cleared"
        )
    }

    /**
     * Get a summary of the current state.
     *
     * @return Human-readable state summary
     */
    fun getStateSummary(): String {
        return buildString {
            append("SDK State: ${SDKState.getName(sdkState)}")
            append(", Health: ${HealthStatus.getName(healthStatus)}")

            val states = getAllComponentStates()
            val ready = states.count { it.value == ComponentState.READY }
            val errors = states.count { it.value == ComponentState.ERROR }
            append(", Components: $ready ready, $errors errors")

            if (lastError != null) {
                append(", Last Error: [$lastErrorCode] $lastError")
            }
        }
    }
}
