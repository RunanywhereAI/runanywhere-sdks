import Foundation

// MARK: - Configuration Presets

/// Pre-configured settings presets for common use cases
public enum ConfigurationPreset {
    /// Creative writing - High temperature, more tokens, diverse output
    case creative

    /// Precise responses - Low temperature, focused output
    case precise

    /// Balanced - Default settings for general use
    case balanced

    /// Privacy-focused - Device-only routing, no cloud
    case privacyFocused

    /// Cloud-preferred - Prefer cloud execution for better performance
    case cloudPreferred

    /// Generate configuration for this preset
    internal func generateConfiguration(basedOn current: ConfigurationData) -> ConfigurationData {
        var config = current

        switch self {
        case .creative:
            config.generation.defaults.temperature = 0.9
            config.generation.defaults.maxTokens = 1024
            config.generation.defaults.topP = 0.95
            config.routing.policy = .automatic

        case .precise:
            config.generation.defaults.temperature = 0.3
            config.generation.defaults.maxTokens = 512
            config.generation.defaults.topP = 0.8
            config.routing.policy = .automatic

        case .balanced:
            config.generation.defaults.temperature = 0.7
            config.generation.defaults.maxTokens = 512
            config.generation.defaults.topP = 0.9
            config.routing.policy = .automatic

        case .privacyFocused:
            config.generation.defaults.temperature = 0.7
            config.generation.defaults.maxTokens = 512
            config.routing.policy = .deviceOnly

        case .cloudPreferred:
            config.generation.defaults.temperature = 0.7
            config.generation.defaults.maxTokens = 1024
            config.routing.policy = .preferCloud
        }

        config.source = .consumer
        config.updatedAt = Date()
        config.syncPending = true

        return config
    }
}

// MARK: - Configuration Extensions
// These methods provide read and write access to SDK configuration

public extension RunAnywhere {

    // MARK: - Read Configuration

    /// Get current generation settings
    /// - Returns: Current generation settings, or default if not configured
    static func getCurrentGenerationSettings() async -> DefaultGenerationSettings {
        events.publish(SDKConfigurationEvent.settingsRequested)

        let settings = RunAnywhere.configurationData?.generation.defaults ?? DefaultGenerationSettings()

        events.publish(SDKConfigurationEvent.settingsRetrieved(settings: settings))
        return settings
    }

    /// Get current routing policy
    /// - Returns: Current routing policy, defaults to .automatic
    static func getCurrentRoutingPolicy() async -> RoutingPolicy {
        events.publish(SDKConfigurationEvent.routingPolicyRequested)

        let policy = RunAnywhere.configurationData?.routing.policy ?? .automatic

        events.publish(SDKConfigurationEvent.routingPolicyRetrieved(policy: policy))
        return policy
    }

    /// Get full current configuration
    /// - Returns: Current configuration data, or default if not loaded
    static func getCurrentConfiguration() async -> ConfigurationData {
        guard let config = RunAnywhere.configurationData else {
            // Return default configuration if not loaded yet
            return ConfigurationData.sdkDefaults(apiKey: initParams?.apiKey ?? "")
        }
        return config
    }

    // MARK: - Update Configuration

    /// Apply a configuration preset
    /// - Parameter preset: The preset to apply
    /// - Throws: SDKError if SDK is not initialized
    static func updateConfiguration(preset: ConfigurationPreset) async throws {
        guard isSDKInitialized else {
            throw SDKError.notInitialized
        }

        let logger = SDKLogger(category: "RunAnywhere.Configuration")
        logger.info("Applying configuration preset: \(preset)")

        // Get current config or create default
        let currentConfig = await getCurrentConfiguration()

        // Generate new config based on preset
        let newConfig = preset.generateConfiguration(basedOn: currentConfig)

        // Store the new configuration
        RunAnywhere.configurationData = newConfig

        // Persist to configuration service
        try await serviceContainer.configurationService.setConsumerConfiguration(newConfig)

        logger.info("✅ Configuration preset applied successfully")
    }

    /// Update routing policy
    /// - Parameter policy: The routing policy to set
    /// - Throws: SDKError if SDK is not initialized
    static func setRoutingPolicy(_ policy: RoutingPolicy) async throws {
        guard isSDKInitialized else {
            throw SDKError.notInitialized
        }

        let logger = SDKLogger(category: "RunAnywhere.Configuration")
        logger.info("Setting routing policy: \(policy)")

        // Get current config or create default
        var config = await getCurrentConfiguration()

        // Update routing policy
        config.routing.policy = policy
        config.source = .consumer
        config.updatedAt = Date()
        config.syncPending = true

        // Store the updated configuration
        RunAnywhere.configurationData = config

        // Persist to configuration service
        try await serviceContainer.configurationService.setConsumerConfiguration(config)

        logger.info("✅ Routing policy updated successfully")
    }

    /// Update default generation settings
    /// - Parameter settings: The generation settings to set
    /// - Throws: SDKError if SDK is not initialized
    static func setDefaultGenerationSettings(_ settings: DefaultGenerationSettings) async throws {
        guard isSDKInitialized else {
            throw SDKError.notInitialized
        }

        let logger = SDKLogger(category: "RunAnywhere.Configuration")
        logger.info("Setting default generation settings")

        events.publish(SDKConfigurationEvent.settingsRetrieved(settings: settings))

        // Get current config or create default
        var config = await getCurrentConfiguration()

        // Update generation settings
        config.generation.defaults = settings
        config.source = .consumer
        config.updatedAt = Date()
        config.syncPending = true

        // Store the updated configuration
        RunAnywhere.configurationData = config

        // Persist to configuration service
        try await serviceContainer.configurationService.setConsumerConfiguration(config)

        logger.info("✅ Default generation settings updated successfully")
    }

    /// Update storage configuration
    /// - Parameter storage: The storage configuration to set
    /// - Throws: SDKError if SDK is not initialized
    static func setStorageConfiguration(_ storage: StorageConfiguration) async throws {
        guard isSDKInitialized else {
            throw SDKError.notInitialized
        }

        let logger = SDKLogger(category: "RunAnywhere.Configuration")
        logger.info("Setting storage configuration")

        // Get current config or create default
        var config = await getCurrentConfiguration()

        // Update storage configuration
        config.storage = storage
        config.source = .consumer
        config.updatedAt = Date()
        config.syncPending = true

        // Store the updated configuration
        RunAnywhere.configurationData = config

        // Persist to configuration service
        try await serviceContainer.configurationService.setConsumerConfiguration(config)

        logger.info("✅ Storage configuration updated successfully")
    }

    /// Sync user preferences to cloud (if in production mode)
    /// - Throws: SDKError if sync fails
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
