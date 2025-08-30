import Foundation

// MARK: - Configuration Extensions (Event-Based)
// Note: Most configuration is now handled via per-request options
// These methods provide event-driven access to runtime configuration

public extension RunAnywhere {

    /// Configuration Request Structure
    struct ConfigurationRequest {
        let temperature: Float?
        let maxTokens: Int?
        let topP: Float?
        let topK: Int?
        let routingPolicy: RoutingPolicy?
        let privacyMode: PrivacyMode?
        let analyticsEnabled: Bool?

        init(
            temperature: Float? = nil,
            maxTokens: Int? = nil,
            topP: Float? = nil,
            topK: Int? = nil,
            routingPolicy: RoutingPolicy? = nil,
            privacyMode: PrivacyMode? = nil,
            analyticsEnabled: Bool? = nil
        ) {
            self.temperature = temperature
            self.maxTokens = maxTokens
            self.topP = topP
            self.topK = topK
            self.routingPolicy = routingPolicy
            self.privacyMode = privacyMode
            self.analyticsEnabled = analyticsEnabled
        }
    }

    /// Request configuration updates (per-session configuration)
    /// - Parameter request: Configuration request with desired settings
    /// Note: This is event-driven - settings apply to the current session only
    static func requestConfiguration(_ request: ConfigurationRequest) async {
        await events.publish(SDKConfigurationEvent.updateRequested(request: request))

        // Apply configuration to current session
        // This would typically update session-level defaults used by generation options

        await events.publish(SDKConfigurationEvent.updateCompleted)
    }

    /// Get current generation settings (read-only access via configuration)
    /// - Returns: Current generation settings
    static func getCurrentGenerationSettings() async -> DefaultGenerationSettings? {
        await events.publish(SDKConfigurationEvent.settingsRequested)

        let settings = RunAnywhere._configuration?.defaultGenerationSettings

        if let settings = settings {
            await events.publish(SDKConfigurationEvent.settingsRetrieved(settings: settings))
        }
        return settings
    }

    /// Get current routing policy
    /// - Returns: Current routing policy
    static func getCurrentRoutingPolicy() async -> RoutingPolicy {
        await events.publish(SDKConfigurationEvent.routingPolicyRequested)

        let policy = RunAnywhere._configuration?.routingPolicy ?? .automatic

        await events.publish(SDKConfigurationEvent.routingPolicyRetrieved(policy: policy))
        return policy
    }

    /// Get current privacy mode
    /// - Returns: Current privacy mode
    static func getCurrentPrivacyMode() async -> PrivacyMode {
        await events.publish(SDKConfigurationEvent.privacyModeRequested)

        let mode = RunAnywhere._configuration?.privacyMode ?? .standard

        await events.publish(SDKConfigurationEvent.privacyModeRetrieved(mode: mode))
        return mode
    }

    /// Check if analytics is enabled
    /// - Returns: True if analytics is enabled
    static func isAnalyticsEnabled() async -> Bool {
        await events.publish(SDKConfigurationEvent.analyticsStatusRequested)

        let enabled = RunAnywhere._configuration?.telemetryConsent != .denied

        await events.publish(SDKConfigurationEvent.analyticsStatusRetrieved(enabled: enabled))
        return enabled
    }

    /// Sync user preferences (placeholder - would sync with remote configuration)
    static func syncUserPreferences() async throws {
        await events.publish(SDKConfigurationEvent.syncRequested)

        do {
            // Use the configuration service for syncing
            try await RunAnywhere.serviceContainer.configurationService.syncToCloud()
            await events.publish(SDKConfigurationEvent.syncCompleted)
        } catch {
            await events.publish(SDKConfigurationEvent.syncFailed(error))
            throw error
        }
    }
}

// MARK: - Convenience Configuration Extensions

public extension RunAnywhere.ConfigurationRequest {

    /// Create a performance-optimized configuration
    static func performanceOptimized() -> RunAnywhere.ConfigurationRequest {
        RunAnywhere.ConfigurationRequest(
            temperature: 0.1,
            maxTokens: 200,
            routingPolicy: .preferDevice
        )
    }

    /// Create a creativity-focused configuration
    static func creative() -> RunAnywhere.ConfigurationRequest {
        RunAnywhere.ConfigurationRequest(
            temperature: 0.9,
            topP: 0.95,
            routingPolicy: .preferCloud
        )
    }

    /// Create a privacy-focused configuration
    static func privacyFocused() -> RunAnywhere.ConfigurationRequest {
        RunAnywhere.ConfigurationRequest(
            routingPolicy: .deviceOnly,
            privacyMode: .strict,
            analyticsEnabled: false
        )
    }
}
