package com.runanywhere.sdk.routing

/**
 * Configuration for routing decisions
 * Controls the behavior of the routing service
 */
data class RoutingConfiguration(
    // Routing preferences
    var preferOnDevice: Boolean = true,
    var allowCloudFallback: Boolean = true,
    var enableHybridMode: Boolean = false,

    // Cost controls
    var maxCloudCostPerRequest: Float = 0.01f, // $0.01 per request
    var monthlyCloudBudget: Float = 10.0f, // $10 per month

    // Privacy controls
    var privacyThreshold: Float = 0.7f, // 0-1, higher = more strict
    var alwaysOnDeviceForPII: Boolean = true,

    // Performance controls
    var latencyThresholdMs: Long = 1000L, // 1 second
    var qualityThreshold: Float = 0.8f, // 0-1, minimum acceptable quality

    // Model preferences
    var preferredOnDeviceModels: List<String> = emptyList(),
    var preferredCloudModels: List<String> = emptyList(),

    // Advanced options
    var enableAdaptiveRouting: Boolean = true, // Learn from usage patterns
    var enableCostOptimization: Boolean = true,
    var enableLatencyOptimization: Boolean = true,

    // Testing/debugging
    var forceTarget: RoutingTarget? = null // Force all requests to specific target
) {

    companion object {
        /**
         * Create a privacy-focused configuration
         */
        fun privacyFirst(): RoutingConfiguration {
            return RoutingConfiguration(
                preferOnDevice = true,
                allowCloudFallback = false,
                privacyThreshold = 1.0f,
                alwaysOnDeviceForPII = true
            )
        }

        /**
         * Create a performance-focused configuration
         */
        fun performanceFirst(): RoutingConfiguration {
            return RoutingConfiguration(
                preferOnDevice = false,
                allowCloudFallback = true,
                latencyThresholdMs = 500L,
                enableLatencyOptimization = true
            )
        }

        /**
         * Create a cost-optimized configuration
         */
        fun costOptimized(): RoutingConfiguration {
            return RoutingConfiguration(
                preferOnDevice = true,
                maxCloudCostPerRequest = 0.001f,
                monthlyCloudBudget = 5.0f,
                enableCostOptimization = true
            )
        }

        /**
         * Create a balanced configuration (default)
         */
        fun balanced(): RoutingConfiguration {
            return RoutingConfiguration()
        }
    }

    /**
     * Validate configuration
     */
    fun validate(): Boolean {
        return privacyThreshold in 0f..1f &&
                qualityThreshold in 0f..1f &&
                maxCloudCostPerRequest >= 0f &&
                monthlyCloudBudget >= 0f &&
                latencyThresholdMs > 0
    }
}
