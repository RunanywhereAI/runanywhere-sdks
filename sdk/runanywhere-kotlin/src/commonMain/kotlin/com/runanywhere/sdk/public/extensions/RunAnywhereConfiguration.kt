package com.runanywhere.sdk.public.extensions

import com.runanywhere.sdk.data.models.ConfigurationData
import com.runanywhere.sdk.data.models.DefaultGenerationSettings
import com.runanywhere.sdk.data.models.RoutingPolicy
import com.runanywhere.sdk.events.SDKConfigurationEvent
import com.runanywhere.sdk.foundation.SDKLogger
import com.runanywhere.sdk.public.BaseRunAnywhereSDK
import com.runanywhere.sdk.public.RunAnywhereSDK

/**
 * Configuration extension APIs for RunAnywhereSDK
 * Matches iOS RunAnywhere+Configuration.swift extension
 *
 * Reference: sdk/runanywhere-swift/Sources/RunAnywhere/Public/Extensions/Configuration/RunAnywhere+Configuration.swift
 */

private val configLogger = SDKLogger("ConfigurationAPI")

/**
 * Get current default generation settings
 * Matches iOS getCurrentGenerationSettings() method
 *
 * @return DefaultGenerationSettings The current generation settings
 */
suspend fun RunAnywhereSDK.getCurrentGenerationSettings(): DefaultGenerationSettings {
    configLogger.debug("Getting current generation settings")

    // Publish event before retrieval
    events.publish(SDKConfigurationEvent.SettingsRequested)

    val settings = try {
        // Get settings from SDK's configuration data
        (this as? BaseRunAnywhereSDK)?.configurationData?.generation?.defaults ?: DefaultGenerationSettings()
    } catch (e: Exception) {
        configLogger.error("Failed to get generation settings: ${e.message}")
        // Return default settings on error
        DefaultGenerationSettings()
    }

    // Publish event after retrieval
    events.publish(SDKConfigurationEvent.SettingsRetrieved(mapOf("generation" to settings)))

    configLogger.debug("Retrieved generation settings: $settings")
    return settings
}

/**
 * Get current routing policy
 * Matches iOS getCurrentRoutingPolicy() method
 *
 * @return RoutingPolicy The current routing policy
 */
suspend fun RunAnywhereSDK.getCurrentRoutingPolicy(): RoutingPolicy {
    configLogger.debug("Getting current routing policy")

    // Publish event before retrieval
    events.publish(SDKConfigurationEvent.RoutingPolicyRequested)

    val policy = try {
        // Get policy from SDK's configuration data
        (this as? BaseRunAnywhereSDK)?.configurationData?.routing?.policy ?: RoutingPolicy.DEVICE_ONLY
    } catch (e: Exception) {
        configLogger.error("Failed to get routing policy: ${e.message}")
        // Return DEVICE_ONLY policy on error
        RoutingPolicy.DEVICE_ONLY
    }

    // Publish event after retrieval
    events.publish(SDKConfigurationEvent.RoutingPolicyRetrieved(policy.name))

    configLogger.debug("Retrieved routing policy: $policy")
    return policy
}

/**
 * Sync user preferences with backend
 * Matches iOS syncUserPreferences() method
 *
 * @throws Exception if sync fails and backend is unreachable
 */
suspend fun RunAnywhereSDK.syncUserPreferences() {
    configLogger.debug("Starting user preferences sync")

    // Publish event before sync
    events.publish(SDKConfigurationEvent.SyncStarted)

    try {
        // Sync preferences with backend
        // This would typically:
        // 1. Fetch user preferences from backend API
        // 2. Update local configuration with remote values
        // 3. Handle conflicts (local vs remote changes)

        // For Phase 2, this is a placeholder that just validates current config exists
        val config = (this as? BaseRunAnywhereSDK)?.configurationData
        if (config == null) {
            throw IllegalStateException("SDK not initialized - no configuration available")
        }

        // TODO: Implement actual backend sync when API is ready
        configLogger.warning("syncUserPreferences() is not fully implemented - backend sync pending")

        // Publish success event
        events.publish(SDKConfigurationEvent.SyncCompleted)

        configLogger.info("User preferences sync completed (placeholder implementation)")
    } catch (e: Exception) {
        configLogger.error("Failed to sync user preferences: ${e.message}")

        // Publish failure event
        events.publish(SDKConfigurationEvent.SyncFailed(e))

        // Re-throw exception to caller
        throw e
    }
}
