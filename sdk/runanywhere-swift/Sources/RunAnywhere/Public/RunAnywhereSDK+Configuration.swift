import Foundation

// MARK: - Configuration Management APIs

extension RunAnywhereSDK {

    // MARK: - Generation Settings

    /// Set the temperature for text generation (0.0 - 2.0)
    public func setTemperature(_ value: Float) async {
        logger.info("🌡️ Setting temperature")
        await serviceContainer.configurationService.updateConfiguration { config in
            var updated = config
            updated.generation.defaults.temperature = Double(value)
            return updated
        }
        logger.info("✅ Temperature updated")
    }

    /// Set the maximum tokens for text generation
    public func setMaxTokens(_ value: Int) async {
        logger.info("🔢 Setting maxTokens")
        await serviceContainer.configurationService.updateConfiguration { config in
            var updated = config
            updated.generation.defaults.maxTokens = value
            return updated
        }
        logger.info("✅ MaxTokens updated")
    }

    /// Set the top-p sampling parameter (0.0 - 1.0)
    public func setTopP(_ value: Float) async {
        logger.info("📊 Setting topP")
        await serviceContainer.configurationService.updateConfiguration { config in
            var updated = config
            updated.generation.defaults.topP = Double(value)
            return updated
        }
        logger.info("✅ TopP updated")
    }

    /// Set the top-k sampling parameter
    public func setTopK(_ value: Int) async {
        logger.info("📊 Setting topK")
        await serviceContainer.configurationService.updateConfiguration { config in
            var updated = config
            updated.generation.defaults.topK = value
            return updated
        }
        logger.info("✅ TopK updated")
    }

    // MARK: - Logging Settings

    /// Enable or disable local analytics logging
    public func setAnalyticsLogToLocal(enabled: Bool) async {
        logger.info("Setting analytics log to local: \(enabled)")
        AnalyticsLoggingConfig.shared.logToLocal = enabled
    }

    /// Get current local analytics logging status
    public func getAnalyticsLogToLocal() -> Bool {
        return AnalyticsLoggingConfig.shared.logToLocal
    }

    /// Get current generation settings
    public func getGenerationSettings() async -> DefaultGenerationSettings {
        logger.info("📖 Getting generation settings")

        // Ensure configuration is loaded from database
        await serviceContainer.configurationService.ensureConfigurationLoaded()

        let config = await serviceContainer.configurationService.getConfiguration()

        let defaults = config?.generation.defaults ?? DefaultGenerationSettings()
        let temperature = defaults.temperature
        let maxTokens = defaults.maxTokens
        let topP = defaults.topP
        let topK = defaults.topK ?? SDKConstants.ConfigurationDefaults.topK

        logger.info("📊 Returning generation settings")

        return DefaultGenerationSettings(
            temperature: temperature,
            maxTokens: maxTokens,
            topP: topP,
            topK: topK
        )
    }

    /// Reset all user overrides to SDK defaults
    public func resetGenerationSettings() async {
        logger.info("🔄 Resetting generation settings to defaults")
        await serviceContainer.configurationService.updateConfiguration { _ in
            ConfigurationData() // Returns default configuration
        }
        logger.info("✅ Generation settings reset to defaults")
    }

    /// Sync user preferences to remote server
    public func syncUserPreferences() async {
        do {
            try await serviceContainer.configurationService.syncToCloud()
        } catch {
            // Log error but don't throw to avoid breaking the UI
            logger.error("Failed to sync preferences: \(error)")
        }
    }

    // MARK: - Routing Configuration

    /// Set whether cloud routing is enabled
    public func setCloudRoutingEnabled(_ enabled: Bool) async {
        logger.info("☁️ Setting cloud routing enabled")
        await serviceContainer.configurationService.updateConfiguration { config in
            var updated = config
            updated.routing.cloudEnabled = enabled
            return updated
        }
        logger.info("✅ Cloud routing setting updated")
    }

    /// Get whether cloud routing is enabled
    public func getCloudRoutingEnabled() async -> Bool {
        logger.info("📖 Getting cloud routing enabled setting")
        await serviceContainer.configurationService.ensureConfigurationLoaded()
        let config = await serviceContainer.configurationService.getConfiguration()
        let value = config?.routing.cloudEnabled ?? SDKConstants.ConfigurationDefaults.cloudRoutingEnabled
        logger.info("☁️ Cloud routing enabled retrieved")
        return value
    }

    /// Set privacy mode
    public func setPrivacyMode(_ mode: PrivacyMode) async {
        logger.info("🔒 Setting privacy mode")
        await serviceContainer.configurationService.updateConfiguration { config in
            var updated = config
            updated.routing.privacyMode = mode
            return updated
        }
        logger.info("✅ Privacy mode setting updated")
    }

    /// Get privacy mode
    public func getPrivacyMode() async -> PrivacyMode {
        logger.info("📖 Getting privacy mode setting")
        await serviceContainer.configurationService.ensureConfigurationLoaded()
        let config = await serviceContainer.configurationService.getConfiguration()
        let value = config?.routing.privacyMode ?? (SDKConstants.ConfigurationDefaults.privacyModeEnabled ? .strict : .standard)
        logger.info("🔒 Privacy mode retrieved")
        return value
    }

    /// Set the routing policy
    public func setRoutingPolicy(_ policy: RoutingPolicy) async {
        logger.info("🛣️ Setting routing policy")
        await serviceContainer.configurationService.updateConfiguration { config in
            var updated = config
            updated.routing.policy = policy
            return updated
        }
        logger.info("✅ Routing policy updated")
    }

    /// Get the routing policy
    public func getRoutingPolicy() async -> RoutingPolicy {
        logger.info("📖 Getting routing policy")
        await serviceContainer.configurationService.ensureConfigurationLoaded()
        let config = await serviceContainer.configurationService.getConfiguration()
        let value = config?.routing.policy ?? SDKConstants.ConfigurationDefaults.routingPolicy
        logger.info("🛣️ Routing policy retrieved")
        return value
    }

    // MARK: - API Configuration

    /// Set the API key
    public func setApiKey(_ apiKey: String?) async {
        logger.info("🔑 Setting API key")
        await serviceContainer.configurationService.updateConfiguration { config in
            var updated = config
            updated.apiKey = apiKey
            return updated
        }
        logger.info("✅ API key updated")
    }

    /// Get the API key
    public func getApiKey() async -> String? {
        logger.info("📖 Getting API key")
        await serviceContainer.configurationService.ensureConfigurationLoaded()
        let config = await serviceContainer.configurationService.getConfiguration()
        logger.info("🔑 API key retrieved")
        return config?.apiKey
    }

    // MARK: - Analytics Configuration (Internal)

    /// Set whether analytics is enabled
    internal func setAnalyticsEnabled(_ enabled: Bool) async {
        logger.info("📊 Setting analytics enabled")

        do {
            try await ensureInitialized()
        } catch {
            logger.warning("⚠️ SDK not initialized, cannot set analytics setting")
            return
        }

        await serviceContainer.configurationService.updateConfiguration { config in
            var updated = config
            updated.analytics.enabled = enabled
            return updated
        }
        logger.info("✅ Analytics enabled setting updated")
    }

    /// Get whether analytics is enabled
    internal func getAnalyticsEnabled() async -> Bool {
        logger.info("📖 Getting analytics enabled setting")

        do {
            try await ensureInitialized()
        } catch {
            logger.warning("⚠️ SDK not initialized, returning default analytics setting")
            return SDKConstants.ConfigurationDefaults.analyticsEnabled
        }

        await serviceContainer.configurationService.ensureConfigurationLoaded()
        let config = await serviceContainer.configurationService.getConfiguration()
        let value = config?.analytics.enabled ?? SDKConstants.ConfigurationDefaults.analyticsEnabled
        logger.info("📊 Analytics enabled retrieved: \(value)")
        return value
    }

    /// Set the analytics level
    internal func setAnalyticsLevel(_ level: AnalyticsLevel) async {
        logger.info("📊 Setting analytics level")

        do {
            try await ensureInitialized()
        } catch {
            logger.warning("⚠️ SDK not initialized, cannot set analytics level")
            return
        }

        await serviceContainer.configurationService.updateConfiguration { config in
            var updated = config
            updated.analytics.level = level
            return updated
        }
        logger.info("✅ Analytics level updated")
    }

    /// Get the analytics level
    internal func getAnalyticsLevel() async -> AnalyticsLevel {
        logger.info("📖 Getting analytics level")

        do {
            try await ensureInitialized()
        } catch {
            logger.warning("⚠️ SDK not initialized, returning default analytics level")
            return SDKConstants.ConfigurationDefaults.analyticsLevel
        }

        await serviceContainer.configurationService.ensureConfigurationLoaded()
        let config = await serviceContainer.configurationService.getConfiguration()
        let value = config?.analytics.level ?? SDKConstants.ConfigurationDefaults.analyticsLevel
        logger.info("📊 Analytics level retrieved: \(value)")
        return value
    }

    /// Set whether live metrics are enabled
    internal func setEnableLiveMetrics(_ enabled: Bool) async {
        logger.info("📊 Setting enable live metrics")

        do {
            try await ensureInitialized()
        } catch {
            logger.warning("⚠️ SDK not initialized, cannot set live metrics")
            return
        }

        await serviceContainer.configurationService.updateConfiguration { config in
            var updated = config
            updated.analytics.liveMetricsEnabled = enabled
            return updated
        }
        logger.info("✅ Enable live metrics setting updated")
    }

    /// Get whether live metrics are enabled
    internal func getEnableLiveMetrics() async -> Bool {
        logger.info("📖 Getting enable live metrics setting")
        await serviceContainer.configurationService.ensureConfigurationLoaded()
        let config = await serviceContainer.configurationService.getConfiguration()
        let value = config?.analytics.liveMetricsEnabled ?? SDKConstants.ConfigurationDefaults.enableLiveMetrics
        logger.info("📊 Enable live metrics retrieved: \(value)")
        return value
    }
}
