import Foundation

// MARK: - Configuration Extensions
// These methods provide read-only access to current SDK configuration

public extension RunAnywhere {

    /// Get current generation settings (read-only access via configuration)
    /// - Returns: Current generation settings
    static func getCurrentGenerationSettings() async -> DefaultGenerationSettings? {
        events.publish(SDKConfigurationEvent.settingsRequested)

        let settings = RunAnywhere.configurationData?.generation.defaults

        if let settings = settings {
            events.publish(SDKConfigurationEvent.settingsRetrieved(settings: settings))
        }
        return settings
    }

    /// Get current routing policy
    /// - Returns: Current routing policy
    static func getCurrentRoutingPolicy() async -> RoutingPolicy {
        events.publish(SDKConfigurationEvent.routingPolicyRequested)

        let policy = RunAnywhere.configurationData?.routing.policy ?? .automatic

        events.publish(SDKConfigurationEvent.routingPolicyRetrieved(policy: policy))
        return policy
    }

    /// Sync user preferences (placeholder - would sync with remote configuration)
    static func syncUserPreferences() async throws {
        events.publish(SDKConfigurationEvent.syncRequested)

        do {
            // Use the configuration service for syncing
            try await RunAnywhere.serviceContainer.configurationService.syncToCloud()
            events.publish(SDKConfigurationEvent.syncCompleted)
        } catch {
            events.publish(SDKConfigurationEvent.syncFailed(error))
            throw error
        }
    }
}
