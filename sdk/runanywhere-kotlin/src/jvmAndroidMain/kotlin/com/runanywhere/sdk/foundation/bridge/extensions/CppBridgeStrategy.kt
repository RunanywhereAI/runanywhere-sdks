/*
 * Copyright 2024 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * Strategy extension for CppBridge.
 * Provides execution strategy management callbacks for C++ core.
 *
 * Follows iOS CppBridge+Strategy.swift architecture.
 */

package com.runanywhere.sdk.foundation.bridge.extensions

import java.util.concurrent.ConcurrentHashMap

/**
 * Strategy bridge that provides execution strategy management for C++ core.
 *
 * The C++ core needs strategy functionality for:
 * - Selecting execution strategy (on-device, cloud, hybrid)
 * - Managing model execution preferences per component type
 * - Handling fallback strategies when primary fails
 * - Adapting to device capabilities and network conditions
 * - Optimizing for latency, quality, or cost
 *
 * Usage:
 * - Called during Phase 2 initialization in [CppBridge.initializeServices]
 * - Must be registered after [CppBridgePlatformAdapter] and [CppBridgeModelRegistry] are registered
 *
 * Thread Safety:
 * - Registration is thread-safe via synchronized block
 * - All callbacks are thread-safe
 */
object CppBridgeStrategy {

    /**
     * Execution strategy type constants matching C++ RAC_STRATEGY_TYPE_* values.
     */
    object StrategyType {
        /** Execute on-device using local models */
        const val ON_DEVICE = 0

        /** Execute in the cloud using remote APIs */
        const val CLOUD = 1

        /** Hybrid: try on-device first, fallback to cloud */
        const val HYBRID_LOCAL_FIRST = 2

        /** Hybrid: try cloud first, fallback to on-device */
        const val HYBRID_CLOUD_FIRST = 3

        /** Automatic: SDK decides based on conditions */
        const val AUTO = 4

        /**
         * Get a human-readable name for the strategy type.
         */
        fun getName(type: Int): String = when (type) {
            ON_DEVICE -> "ON_DEVICE"
            CLOUD -> "CLOUD"
            HYBRID_LOCAL_FIRST -> "HYBRID_LOCAL_FIRST"
            HYBRID_CLOUD_FIRST -> "HYBRID_CLOUD_FIRST"
            AUTO -> "AUTO"
            else -> "UNKNOWN($type)"
        }

        /**
         * Check if the strategy type uses on-device execution.
         */
        fun usesOnDevice(type: Int): Boolean = type in listOf(ON_DEVICE, HYBRID_LOCAL_FIRST, HYBRID_CLOUD_FIRST, AUTO)

        /**
         * Check if the strategy type uses cloud execution.
         */
        fun usesCloud(type: Int): Boolean = type in listOf(CLOUD, HYBRID_LOCAL_FIRST, HYBRID_CLOUD_FIRST, AUTO)
    }

    /**
     * Strategy optimization target constants.
     */
    object OptimizationTarget {
        /** Optimize for lowest latency */
        const val LATENCY = 0

        /** Optimize for best quality */
        const val QUALITY = 1

        /** Optimize for lowest cost */
        const val COST = 2

        /** Optimize for power efficiency */
        const val POWER = 3

        /** Balanced optimization across all factors */
        const val BALANCED = 4

        /**
         * Get a human-readable name for the optimization target.
         */
        fun getName(target: Int): String = when (target) {
            LATENCY -> "LATENCY"
            QUALITY -> "QUALITY"
            COST -> "COST"
            POWER -> "POWER"
            BALANCED -> "BALANCED"
            else -> "UNKNOWN($target)"
        }
    }

    /**
     * Strategy decision reason constants.
     */
    object StrategyReason {
        /** User preference */
        const val USER_PREFERENCE = 0

        /** Model not available locally */
        const val MODEL_NOT_AVAILABLE = 1

        /** Model not downloaded */
        const val MODEL_NOT_DOWNLOADED = 2

        /** Insufficient device resources (memory, storage) */
        const val INSUFFICIENT_RESOURCES = 3

        /** Network not available */
        const val NETWORK_UNAVAILABLE = 4

        /** Cloud API quota exceeded */
        const val CLOUD_QUOTA_EXCEEDED = 5

        /** Primary strategy failed, using fallback */
        const val FALLBACK = 6

        /** Automatic decision by SDK */
        const val AUTO_DECISION = 7

        /** Device battery low */
        const val LOW_BATTERY = 8

        /**
         * Get a human-readable name for the decision reason.
         */
        fun getName(reason: Int): String = when (reason) {
            USER_PREFERENCE -> "USER_PREFERENCE"
            MODEL_NOT_AVAILABLE -> "MODEL_NOT_AVAILABLE"
            MODEL_NOT_DOWNLOADED -> "MODEL_NOT_DOWNLOADED"
            INSUFFICIENT_RESOURCES -> "INSUFFICIENT_RESOURCES"
            NETWORK_UNAVAILABLE -> "NETWORK_UNAVAILABLE"
            CLOUD_QUOTA_EXCEEDED -> "CLOUD_QUOTA_EXCEEDED"
            FALLBACK -> "FALLBACK"
            AUTO_DECISION -> "AUTO_DECISION"
            LOW_BATTERY -> "LOW_BATTERY"
            else -> "UNKNOWN($reason)"
        }
    }

    /**
     * Component type constants for strategy configuration.
     */
    object ComponentType {
        /** LLM component */
        const val LLM = 0

        /** STT component */
        const val STT = 1

        /** TTS component */
        const val TTS = 2

        /** VAD component */
        const val VAD = 3

        /** Voice Agent (combined pipeline) */
        const val VOICE_AGENT = 4

        /** Embedding component */
        const val EMBEDDING = 5

        /**
         * Get a human-readable name for the component type.
         */
        fun getName(type: Int): String = when (type) {
            LLM -> "LLM"
            STT -> "STT"
            TTS -> "TTS"
            VAD -> "VAD"
            VOICE_AGENT -> "VOICE_AGENT"
            EMBEDDING -> "EMBEDDING"
            else -> "UNKNOWN($type)"
        }
    }

    @Volatile
    private var isRegistered: Boolean = false

    private val lock = Any()

    /**
     * Tag for logging.
     */
    private const val TAG = "CppBridgeStrategy"

    /**
     * Global default strategy.
     */
    @Volatile
    private var defaultStrategy: Int = StrategyType.AUTO

    /**
     * Global optimization target.
     */
    @Volatile
    private var optimizationTarget: Int = OptimizationTarget.BALANCED

    /**
     * Per-component strategy configuration.
     */
    private val componentStrategies = ConcurrentHashMap<Int, Int>()

    /**
     * Per-component optimization targets.
     */
    private val componentOptimizations = ConcurrentHashMap<Int, Int>()

    /**
     * Strategy capability flags.
     */
    private val strategyCapabilities = ConcurrentHashMap<Int, StrategyCapabilities>()

    /**
     * Optional listener for strategy events.
     * Set this before calling [register] to receive events.
     */
    @Volatile
    var strategyListener: StrategyListener? = null

    /**
     * Optional provider for device capabilities.
     * Set this to customize capability detection.
     */
    @Volatile
    var capabilityProvider: CapabilityProvider? = null

    /**
     * Strategy capabilities data class.
     */
    data class StrategyCapabilities(
        val supportsOnDevice: Boolean = true,
        val supportsCloud: Boolean = true,
        val hasLocalModel: Boolean = false,
        val hasNetworkAccess: Boolean = true,
        val availableMemoryMB: Long = 0,
        val availableStorageMB: Long = 0,
        val batteryLevel: Int = 100,
        val isCharging: Boolean = false
    ) {
        /**
         * Check if on-device execution is viable.
         */
        fun canExecuteOnDevice(): Boolean {
            return supportsOnDevice && hasLocalModel && availableMemoryMB > 100
        }

        /**
         * Check if cloud execution is viable.
         */
        fun canExecuteOnCloud(): Boolean {
            return supportsCloud && hasNetworkAccess
        }
    }

    /**
     * Strategy decision result data class.
     */
    data class StrategyDecision(
        val strategy: Int,
        val reason: Int,
        val componentType: Int,
        val canFallback: Boolean,
        val fallbackStrategy: Int?
    ) {
        /**
         * Get the strategy name.
         */
        fun getStrategyName(): String = StrategyType.getName(strategy)

        /**
         * Get the reason name.
         */
        fun getReasonName(): String = StrategyReason.getName(reason)

        /**
         * Get the component name.
         */
        fun getComponentName(): String = ComponentType.getName(componentType)
    }

    /**
     * Listener interface for strategy events.
     */
    interface StrategyListener {
        /**
         * Called when the default strategy changes.
         *
         * @param previousStrategy The previous strategy
         * @param newStrategy The new strategy
         */
        fun onDefaultStrategyChanged(previousStrategy: Int, newStrategy: Int)

        /**
         * Called when a component strategy changes.
         *
         * @param componentType The component type
         * @param previousStrategy The previous strategy
         * @param newStrategy The new strategy
         */
        fun onComponentStrategyChanged(componentType: Int, previousStrategy: Int, newStrategy: Int)

        /**
         * Called when a strategy decision is made.
         *
         * @param decision The strategy decision
         */
        fun onStrategyDecision(decision: StrategyDecision)

        /**
         * Called when a fallback is triggered.
         *
         * @param componentType The component type
         * @param failedStrategy The strategy that failed
         * @param fallbackStrategy The fallback strategy
         * @param reason The failure reason
         */
        fun onFallbackTriggered(componentType: Int, failedStrategy: Int, fallbackStrategy: Int, reason: String)
    }

    /**
     * Provider interface for device capability detection.
     */
    interface CapabilityProvider {
        /**
         * Get current device capabilities.
         *
         * @return Current capabilities
         */
        fun getCapabilities(): StrategyCapabilities

        /**
         * Check if network is available.
         *
         * @return true if network is available
         */
        fun isNetworkAvailable(): Boolean

        /**
         * Get available memory in MB.
         *
         * @return Available memory in MB
         */
        fun getAvailableMemoryMB(): Long

        /**
         * Get battery level (0-100).
         *
         * @return Battery level percentage
         */
        fun getBatteryLevel(): Int

        /**
         * Check if device is charging.
         *
         * @return true if charging
         */
        fun isCharging(): Boolean
    }

    /**
     * Register the strategy callbacks with C++ core.
     *
     * This must be called during SDK initialization, after [CppBridgePlatformAdapter.register].
     * It is safe to call multiple times; subsequent calls are no-ops.
     */
    fun register() {
        synchronized(lock) {
            if (isRegistered) {
                return
            }

            // Initialize default component strategies
            initializeDefaultStrategies()

            // Register the strategy callbacks with C++ via JNI
            // TODO: Call native registration
            // nativeSetStrategyCallbacks()

            isRegistered = true

            CppBridgePlatformAdapter.logCallback(
                CppBridgePlatformAdapter.LogLevel.DEBUG,
                TAG,
                "Strategy callbacks registered. Default: ${StrategyType.getName(defaultStrategy)}"
            )
        }
    }

    /**
     * Check if the strategy callbacks are registered.
     */
    fun isRegistered(): Boolean = isRegistered

    // ========================================================================
    // STRATEGY CALLBACKS
    // ========================================================================

    /**
     * Get strategy callback.
     *
     * Returns the current strategy for a component.
     *
     * @param componentType The component type (see [ComponentType])
     * @return The strategy type (see [StrategyType])
     *
     * NOTE: This function is called from JNI. Do not capture any state.
     */
    @JvmStatic
    fun getStrategyCallback(componentType: Int): Int {
        return componentStrategies.getOrDefault(componentType, defaultStrategy)
    }

    /**
     * Set strategy callback.
     *
     * Sets the strategy for a component.
     *
     * @param componentType The component type (see [ComponentType])
     * @param strategy The strategy type (see [StrategyType])
     * @return 0 on success, error code on failure
     *
     * NOTE: This function is called from JNI. Do not capture any state.
     */
    @JvmStatic
    fun setStrategyCallback(componentType: Int, strategy: Int): Int {
        val previousStrategy = componentStrategies.put(componentType, strategy) ?: defaultStrategy

        CppBridgePlatformAdapter.logCallback(
            CppBridgePlatformAdapter.LogLevel.DEBUG,
            TAG,
            "Strategy set: ${ComponentType.getName(componentType)} = ${StrategyType.getName(strategy)}"
        )

        // Notify listener
        try {
            if (previousStrategy != strategy) {
                strategyListener?.onComponentStrategyChanged(componentType, previousStrategy, strategy)
            }
        } catch (e: Exception) {
            CppBridgePlatformAdapter.logCallback(
                CppBridgePlatformAdapter.LogLevel.WARN,
                TAG,
                "Error in strategy listener: ${e.message}"
            )
        }

        return 0
    }

    /**
     * Get default strategy callback.
     *
     * @return The default strategy type
     *
     * NOTE: This function is called from JNI. Do not capture any state.
     */
    @JvmStatic
    fun getDefaultStrategyCallback(): Int {
        return defaultStrategy
    }

    /**
     * Set default strategy callback.
     *
     * @param strategy The default strategy type
     *
     * NOTE: This function is called from JNI. Do not capture any state.
     */
    @JvmStatic
    fun setDefaultStrategyCallback(strategy: Int) {
        val previousStrategy = defaultStrategy
        defaultStrategy = strategy

        CppBridgePlatformAdapter.logCallback(
            CppBridgePlatformAdapter.LogLevel.DEBUG,
            TAG,
            "Default strategy set: ${StrategyType.getName(strategy)}"
        )

        // Notify listener
        try {
            if (previousStrategy != strategy) {
                strategyListener?.onDefaultStrategyChanged(previousStrategy, strategy)
            }
        } catch (e: Exception) {
            CppBridgePlatformAdapter.logCallback(
                CppBridgePlatformAdapter.LogLevel.WARN,
                TAG,
                "Error in strategy listener: ${e.message}"
            )
        }
    }

    /**
     * Get optimization target callback.
     *
     * @param componentType The component type (see [ComponentType])
     * @return The optimization target (see [OptimizationTarget])
     *
     * NOTE: This function is called from JNI. Do not capture any state.
     */
    @JvmStatic
    fun getOptimizationTargetCallback(componentType: Int): Int {
        return componentOptimizations.getOrDefault(componentType, optimizationTarget)
    }

    /**
     * Set optimization target callback.
     *
     * @param componentType The component type (see [ComponentType])
     * @param target The optimization target (see [OptimizationTarget])
     *
     * NOTE: This function is called from JNI. Do not capture any state.
     */
    @JvmStatic
    fun setOptimizationTargetCallback(componentType: Int, target: Int) {
        componentOptimizations[componentType] = target

        CppBridgePlatformAdapter.logCallback(
            CppBridgePlatformAdapter.LogLevel.DEBUG,
            TAG,
            "Optimization target set: ${ComponentType.getName(componentType)} = ${OptimizationTarget.getName(target)}"
        )
    }

    /**
     * Decide strategy callback.
     *
     * Makes a strategy decision based on current conditions.
     *
     * @param componentType The component type (see [ComponentType])
     * @param modelId The model ID (optional)
     * @return JSON-encoded strategy decision
     *
     * NOTE: This function is called from JNI. Do not capture any state.
     */
    @JvmStatic
    fun decideStrategyCallback(componentType: Int, modelId: String?): String {
        val decision = makeStrategyDecision(componentType, modelId)

        // Notify listener
        try {
            strategyListener?.onStrategyDecision(decision)
        } catch (e: Exception) {
            CppBridgePlatformAdapter.logCallback(
                CppBridgePlatformAdapter.LogLevel.WARN,
                TAG,
                "Error in strategy listener: ${e.message}"
            )
        }

        return buildString {
            append("{")
            append("\"strategy\":${decision.strategy},")
            append("\"reason\":${decision.reason},")
            append("\"component_type\":${decision.componentType},")
            append("\"can_fallback\":${decision.canFallback},")
            append("\"fallback_strategy\":${decision.fallbackStrategy ?: "null"}")
            append("}")
        }
    }

    /**
     * Report strategy failure callback.
     *
     * Reports a strategy execution failure and triggers fallback if available.
     *
     * @param componentType The component type
     * @param failedStrategy The strategy that failed
     * @param errorMessage The error message
     * @return The fallback strategy, or -1 if no fallback available
     *
     * NOTE: This function is called from JNI. Do not capture any state.
     */
    @JvmStatic
    fun reportStrategyFailureCallback(componentType: Int, failedStrategy: Int, errorMessage: String): Int {
        CppBridgePlatformAdapter.logCallback(
            CppBridgePlatformAdapter.LogLevel.WARN,
            TAG,
            "Strategy failed: ${ComponentType.getName(componentType)} ${StrategyType.getName(failedStrategy)} - $errorMessage"
        )

        // Determine fallback
        val fallback = determineFallbackStrategy(componentType, failedStrategy)

        if (fallback >= 0) {
            CppBridgePlatformAdapter.logCallback(
                CppBridgePlatformAdapter.LogLevel.INFO,
                TAG,
                "Falling back to: ${StrategyType.getName(fallback)}"
            )

            // Notify listener
            try {
                strategyListener?.onFallbackTriggered(componentType, failedStrategy, fallback, errorMessage)
            } catch (e: Exception) {
                CppBridgePlatformAdapter.logCallback(
                    CppBridgePlatformAdapter.LogLevel.WARN,
                    TAG,
                    "Error in strategy listener: ${e.message}"
                )
            }
        }

        return fallback
    }

    /**
     * Get capabilities callback.
     *
     * Returns current device capabilities as JSON.
     *
     * @return JSON-encoded capabilities
     *
     * NOTE: This function is called from JNI. Do not capture any state.
     */
    @JvmStatic
    fun getCapabilitiesCallback(): String {
        val caps = getCurrentCapabilities()

        return buildString {
            append("{")
            append("\"supports_on_device\":${caps.supportsOnDevice},")
            append("\"supports_cloud\":${caps.supportsCloud},")
            append("\"has_local_model\":${caps.hasLocalModel},")
            append("\"has_network_access\":${caps.hasNetworkAccess},")
            append("\"available_memory_mb\":${caps.availableMemoryMB},")
            append("\"available_storage_mb\":${caps.availableStorageMB},")
            append("\"battery_level\":${caps.batteryLevel},")
            append("\"is_charging\":${caps.isCharging}")
            append("}")
        }
    }

    /**
     * Update capabilities callback.
     *
     * Updates cached capabilities for a component.
     *
     * @param componentType The component type
     * @param capabilitiesJson JSON-encoded capabilities
     *
     * NOTE: This function is called from JNI. Do not capture any state.
     */
    @JvmStatic
    fun updateCapabilitiesCallback(componentType: Int, capabilitiesJson: String) {
        try {
            val caps = parseCapabilitiesJson(capabilitiesJson)
            strategyCapabilities[componentType] = caps

            CppBridgePlatformAdapter.logCallback(
                CppBridgePlatformAdapter.LogLevel.DEBUG,
                TAG,
                "Capabilities updated for ${ComponentType.getName(componentType)}"
            )
        } catch (e: Exception) {
            CppBridgePlatformAdapter.logCallback(
                CppBridgePlatformAdapter.LogLevel.WARN,
                TAG,
                "Failed to parse capabilities: ${e.message}"
            )
        }
    }

    /**
     * Check if strategy is available callback.
     *
     * @param componentType The component type
     * @param strategy The strategy to check
     * @return true if the strategy is available
     *
     * NOTE: This function is called from JNI. Do not capture any state.
     */
    @JvmStatic
    fun isStrategyAvailableCallback(componentType: Int, strategy: Int): Boolean {
        val caps = strategyCapabilities[componentType] ?: getCurrentCapabilities()

        return when (strategy) {
            StrategyType.ON_DEVICE -> caps.canExecuteOnDevice()
            StrategyType.CLOUD -> caps.canExecuteOnCloud()
            StrategyType.HYBRID_LOCAL_FIRST, StrategyType.HYBRID_CLOUD_FIRST -> {
                caps.canExecuteOnDevice() || caps.canExecuteOnCloud()
            }
            StrategyType.AUTO -> true
            else -> false
        }
    }

    // ========================================================================
    // JNI NATIVE DECLARATIONS
    // ========================================================================

    /**
     * Native method to set the strategy callbacks with C++ core.
     *
     * C API: rac_strategy_set_callbacks(...)
     */
    @JvmStatic
    private external fun nativeSetStrategyCallbacks()

    /**
     * Native method to unset the strategy callbacks.
     *
     * C API: rac_strategy_set_callbacks(nullptr)
     */
    @JvmStatic
    private external fun nativeUnsetStrategyCallbacks()

    /**
     * Native method to get the current strategy from C++ core.
     *
     * C API: rac_strategy_get(component_type)
     */
    @JvmStatic
    external fun nativeGet(componentType: Int): Int

    /**
     * Native method to set the strategy in C++ core.
     *
     * C API: rac_strategy_set(component_type, strategy)
     */
    @JvmStatic
    external fun nativeSet(componentType: Int, strategy: Int): Int

    /**
     * Native method to decide strategy in C++ core.
     *
     * C API: rac_strategy_decide(component_type, model_id)
     */
    @JvmStatic
    external fun nativeDecide(componentType: Int, modelId: String?): String

    // ========================================================================
    // LIFECYCLE MANAGEMENT
    // ========================================================================

    /**
     * Unregister the strategy callbacks and clean up resources.
     *
     * Called during SDK shutdown.
     */
    fun unregister() {
        synchronized(lock) {
            if (!isRegistered) {
                return
            }

            // TODO: Call native unregistration
            // nativeUnsetStrategyCallbacks()

            strategyListener = null
            capabilityProvider = null
            componentStrategies.clear()
            componentOptimizations.clear()
            strategyCapabilities.clear()
            isRegistered = false
        }
    }

    // ========================================================================
    // UTILITY FUNCTIONS
    // ========================================================================

    /**
     * Get the current strategy for a component.
     *
     * @param componentType The component type
     * @return The strategy type
     */
    fun getStrategy(componentType: Int): Int {
        return getStrategyCallback(componentType)
    }

    /**
     * Set the strategy for a component.
     *
     * @param componentType The component type
     * @param strategy The strategy type
     */
    fun setStrategy(componentType: Int, strategy: Int) {
        setStrategyCallback(componentType, strategy)
    }

    /**
     * Get the default strategy.
     *
     * @return The default strategy type
     */
    fun getDefaultStrategy(): Int {
        return getDefaultStrategyCallback()
    }

    /**
     * Set the default strategy.
     *
     * @param strategy The strategy type
     */
    fun setDefaultStrategy(strategy: Int) {
        setDefaultStrategyCallback(strategy)
    }

    /**
     * Get the optimization target for a component.
     *
     * @param componentType The component type
     * @return The optimization target
     */
    fun getOptimizationTarget(componentType: Int): Int {
        return getOptimizationTargetCallback(componentType)
    }

    /**
     * Set the optimization target for a component.
     *
     * @param componentType The component type
     * @param target The optimization target
     */
    fun setOptimizationTarget(componentType: Int, target: Int) {
        setOptimizationTargetCallback(componentType, target)
    }

    /**
     * Set the global optimization target.
     *
     * @param target The optimization target
     */
    fun setGlobalOptimizationTarget(target: Int) {
        optimizationTarget = target
    }

    /**
     * Make a strategy decision for a component.
     *
     * @param componentType The component type
     * @param modelId Optional model ID
     * @return The strategy decision
     */
    fun decideStrategy(componentType: Int, modelId: String? = null): StrategyDecision {
        return makeStrategyDecision(componentType, modelId)
    }

    /**
     * Report a strategy failure.
     *
     * @param componentType The component type
     * @param failedStrategy The strategy that failed
     * @param errorMessage The error message
     * @return The fallback strategy, or null if none available
     */
    fun reportFailure(componentType: Int, failedStrategy: Int, errorMessage: String): Int? {
        val fallback = reportStrategyFailureCallback(componentType, failedStrategy, errorMessage)
        return if (fallback >= 0) fallback else null
    }

    /**
     * Check if a strategy is available for a component.
     *
     * @param componentType The component type
     * @param strategy The strategy to check
     * @return true if available
     */
    fun isStrategyAvailable(componentType: Int, strategy: Int): Boolean {
        return isStrategyAvailableCallback(componentType, strategy)
    }

    /**
     * Get current device capabilities.
     *
     * @return Current capabilities
     */
    fun getCapabilities(): StrategyCapabilities {
        return getCurrentCapabilities()
    }

    /**
     * Set capabilities for a component.
     *
     * @param componentType The component type
     * @param capabilities The capabilities
     */
    fun setCapabilities(componentType: Int, capabilities: StrategyCapabilities) {
        strategyCapabilities[componentType] = capabilities
    }

    /**
     * Set on-device-only strategy for all components.
     *
     * Useful for offline mode.
     */
    fun setOnDeviceOnly() {
        setDefaultStrategy(StrategyType.ON_DEVICE)
        for (type in listOf(
            ComponentType.LLM,
            ComponentType.STT,
            ComponentType.TTS,
            ComponentType.VAD,
            ComponentType.VOICE_AGENT,
            ComponentType.EMBEDDING
        )) {
            setStrategy(type, StrategyType.ON_DEVICE)
        }

        CppBridgePlatformAdapter.logCallback(
            CppBridgePlatformAdapter.LogLevel.INFO,
            TAG,
            "Switched to on-device only mode"
        )
    }

    /**
     * Set cloud-only strategy for all components.
     */
    fun setCloudOnly() {
        setDefaultStrategy(StrategyType.CLOUD)
        for (type in listOf(
            ComponentType.LLM,
            ComponentType.STT,
            ComponentType.TTS,
            ComponentType.VOICE_AGENT
        )) {
            setStrategy(type, StrategyType.CLOUD)
        }

        CppBridgePlatformAdapter.logCallback(
            CppBridgePlatformAdapter.LogLevel.INFO,
            TAG,
            "Switched to cloud only mode"
        )
    }

    /**
     * Set hybrid strategy (local first) for all components.
     */
    fun setHybridLocalFirst() {
        setDefaultStrategy(StrategyType.HYBRID_LOCAL_FIRST)
        for (type in listOf(
            ComponentType.LLM,
            ComponentType.STT,
            ComponentType.TTS,
            ComponentType.VOICE_AGENT
        )) {
            setStrategy(type, StrategyType.HYBRID_LOCAL_FIRST)
        }

        CppBridgePlatformAdapter.logCallback(
            CppBridgePlatformAdapter.LogLevel.INFO,
            TAG,
            "Switched to hybrid (local first) mode"
        )
    }

    /**
     * Set auto strategy for all components.
     */
    fun setAuto() {
        setDefaultStrategy(StrategyType.AUTO)
        componentStrategies.clear()

        CppBridgePlatformAdapter.logCallback(
            CppBridgePlatformAdapter.LogLevel.INFO,
            TAG,
            "Switched to auto strategy mode"
        )
    }

    /**
     * Make a strategy decision based on current conditions.
     */
    private fun makeStrategyDecision(componentType: Int, modelId: String?): StrategyDecision {
        val configuredStrategy = componentStrategies.getOrDefault(componentType, defaultStrategy)

        // If strategy is not AUTO, use it directly if available
        if (configuredStrategy != StrategyType.AUTO) {
            if (isStrategyAvailableCallback(componentType, configuredStrategy)) {
                return StrategyDecision(
                    strategy = configuredStrategy,
                    reason = StrategyReason.USER_PREFERENCE,
                    componentType = componentType,
                    canFallback = determineFallbackStrategy(componentType, configuredStrategy) >= 0,
                    fallbackStrategy = determineFallbackStrategy(componentType, configuredStrategy).takeIf { it >= 0 }
                )
            }
        }

        // Auto decision logic
        val caps = strategyCapabilities[componentType] ?: getCurrentCapabilities()

        // Check if we have a local model
        val hasLocalModel = if (modelId != null) {
            CppBridgeModelRegistry.hasModel(modelId) &&
                    CppBridgeModelRegistry.getModel(modelId)?.isReady() == true
        } else {
            caps.hasLocalModel
        }

        val decision = when {
            // Network unavailable - must use on-device
            !caps.hasNetworkAccess -> {
                if (hasLocalModel && caps.canExecuteOnDevice()) {
                    StrategyDecision(
                        strategy = StrategyType.ON_DEVICE,
                        reason = StrategyReason.NETWORK_UNAVAILABLE,
                        componentType = componentType,
                        canFallback = false,
                        fallbackStrategy = null
                    )
                } else {
                    // No fallback available
                    StrategyDecision(
                        strategy = StrategyType.ON_DEVICE,
                        reason = StrategyReason.MODEL_NOT_DOWNLOADED,
                        componentType = componentType,
                        canFallback = false,
                        fallbackStrategy = null
                    )
                }
            }

            // Low battery and not charging - prefer cloud to save power
            caps.batteryLevel < 20 && !caps.isCharging -> {
                StrategyDecision(
                    strategy = StrategyType.CLOUD,
                    reason = StrategyReason.LOW_BATTERY,
                    componentType = componentType,
                    canFallback = hasLocalModel,
                    fallbackStrategy = if (hasLocalModel) StrategyType.ON_DEVICE else null
                )
            }

            // Has local model - prefer on-device
            hasLocalModel && caps.canExecuteOnDevice() -> {
                StrategyDecision(
                    strategy = StrategyType.ON_DEVICE,
                    reason = StrategyReason.AUTO_DECISION,
                    componentType = componentType,
                    canFallback = caps.hasNetworkAccess,
                    fallbackStrategy = if (caps.hasNetworkAccess) StrategyType.CLOUD else null
                )
            }

            // No local model - use cloud
            caps.canExecuteOnCloud() -> {
                StrategyDecision(
                    strategy = StrategyType.CLOUD,
                    reason = StrategyReason.MODEL_NOT_DOWNLOADED,
                    componentType = componentType,
                    canFallback = false,
                    fallbackStrategy = null
                )
            }

            // No options available
            else -> {
                StrategyDecision(
                    strategy = StrategyType.ON_DEVICE,
                    reason = StrategyReason.INSUFFICIENT_RESOURCES,
                    componentType = componentType,
                    canFallback = false,
                    fallbackStrategy = null
                )
            }
        }

        CppBridgePlatformAdapter.logCallback(
            CppBridgePlatformAdapter.LogLevel.DEBUG,
            TAG,
            "Strategy decision: ${decision.getComponentName()} = ${decision.getStrategyName()} (${decision.getReasonName()})"
        )

        return decision
    }

    /**
     * Determine fallback strategy when primary fails.
     */
    private fun determineFallbackStrategy(componentType: Int, failedStrategy: Int): Int {
        val caps = strategyCapabilities[componentType] ?: getCurrentCapabilities()

        return when (failedStrategy) {
            StrategyType.ON_DEVICE -> {
                if (caps.canExecuteOnCloud()) StrategyType.CLOUD else -1
            }
            StrategyType.CLOUD -> {
                if (caps.canExecuteOnDevice()) StrategyType.ON_DEVICE else -1
            }
            StrategyType.HYBRID_LOCAL_FIRST -> {
                if (caps.canExecuteOnCloud()) StrategyType.CLOUD else -1
            }
            StrategyType.HYBRID_CLOUD_FIRST -> {
                if (caps.canExecuteOnDevice()) StrategyType.ON_DEVICE else -1
            }
            else -> -1
        }
    }

    /**
     * Get current capabilities from provider or defaults.
     */
    private fun getCurrentCapabilities(): StrategyCapabilities {
        val provider = capabilityProvider
        if (provider != null) {
            return provider.getCapabilities()
        }

        // Return default capabilities
        val runtime = Runtime.getRuntime()
        val availableMemoryMB = (runtime.freeMemory() + (runtime.maxMemory() - runtime.totalMemory())) / (1024 * 1024)
        val availableStorageMB = CppBridgeModelPaths.getAvailableStorage() / (1024 * 1024)

        return StrategyCapabilities(
            supportsOnDevice = true,
            supportsCloud = true,
            hasLocalModel = false, // Would need to check model registry
            hasNetworkAccess = true, // Assume true for JVM
            availableMemoryMB = availableMemoryMB,
            availableStorageMB = availableStorageMB,
            batteryLevel = 100, // JVM doesn't have battery
            isCharging = true
        )
    }

    /**
     * Initialize default strategies for all components.
     */
    private fun initializeDefaultStrategies() {
        // VAD should always be on-device for latency
        componentStrategies[ComponentType.VAD] = StrategyType.ON_DEVICE

        // Other components use auto by default
        componentStrategies[ComponentType.LLM] = StrategyType.AUTO
        componentStrategies[ComponentType.STT] = StrategyType.AUTO
        componentStrategies[ComponentType.TTS] = StrategyType.AUTO
        componentStrategies[ComponentType.VOICE_AGENT] = StrategyType.AUTO
        componentStrategies[ComponentType.EMBEDDING] = StrategyType.ON_DEVICE
    }

    /**
     * Parse capabilities JSON.
     */
    private fun parseCapabilitiesJson(json: String): StrategyCapabilities {
        fun extractBoolean(key: String): Boolean {
            val pattern = "\"$key\"\\s*:\\s*(true|false)"
            val regex = Regex(pattern)
            return regex.find(json)?.groupValues?.get(1) == "true"
        }

        fun extractLong(key: String): Long {
            val pattern = "\"$key\"\\s*:\\s*(-?\\d+)"
            val regex = Regex(pattern)
            return regex.find(json)?.groupValues?.get(1)?.toLongOrNull() ?: 0L
        }

        fun extractInt(key: String): Int {
            val pattern = "\"$key\"\\s*:\\s*(-?\\d+)"
            val regex = Regex(pattern)
            return regex.find(json)?.groupValues?.get(1)?.toIntOrNull() ?: 0
        }

        return StrategyCapabilities(
            supportsOnDevice = extractBoolean("supports_on_device"),
            supportsCloud = extractBoolean("supports_cloud"),
            hasLocalModel = extractBoolean("has_local_model"),
            hasNetworkAccess = extractBoolean("has_network_access"),
            availableMemoryMB = extractLong("available_memory_mb"),
            availableStorageMB = extractLong("available_storage_mb"),
            batteryLevel = extractInt("battery_level"),
            isCharging = extractBoolean("is_charging")
        )
    }
}
