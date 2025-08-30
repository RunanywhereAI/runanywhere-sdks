import Foundation

/// Simple configuration service with fallback system: DB → Consumer → SDK Defaults
public actor ConfigurationService: ConfigurationServiceProtocol {
    private let logger = SDKLogger(category: "ConfigurationService")
    private let configRepository: ConfigurationRepositoryImpl
    private let syncCoordinator: SyncCoordinator?

    private var currentConfig: ConfigurationData?

    // MARK: - Initialization

    public init(configRepository: ConfigurationRepositoryImpl, syncCoordinator: SyncCoordinator?) {
        self.configRepository = configRepository
        self.syncCoordinator = syncCoordinator
        logger.info("ConfigurationService created")
    }

    // MARK: - Public Methods

    public func getConfiguration() -> ConfigurationData? {
        return currentConfig
    }

    /// Load configuration on app launch with simple fallback: Remote → DB → Consumer → Defaults
    public func loadConfigurationOnLaunch(apiKey: String) async -> ConfigurationData {
        // Step 1: Try to fetch remote configuration
        if let remoteConfig = try? await configRepository.fetchRemoteConfiguration(apiKey: apiKey) {
            logger.info("Remote configuration loaded, saving to DB")
            // Save to DB and use as current config
            try? await configRepository.save(remoteConfig)
            currentConfig = remoteConfig
            return remoteConfig
        }

        // Step 2: Try to load from DB
        if let dbConfig = try? await configRepository.fetch(id: SDKConstants.ConfigurationDefaults.configurationId) {
            logger.info("Using DB configuration")
            currentConfig = dbConfig
            return dbConfig
        }

        // Step 3: Try consumer configuration
        if let consumerConfig = try? await configRepository.getConsumerConfiguration() {
            logger.info("Using consumer configuration fallback")
            currentConfig = consumerConfig
            return consumerConfig
        }

        // Step 4: Use SDK defaults
        logger.info("Using SDK default configuration")
        let defaultConfig = configRepository.getSDKDefaultConfiguration()
        currentConfig = defaultConfig
        return defaultConfig
    }

    /// Ensure configuration is loaded
    public func ensureConfigurationLoaded() async {
        if currentConfig == nil {
            currentConfig = await loadConfigurationOnLaunch(apiKey: "")
        }
    }

    /// Set consumer configuration override
    public func setConsumerConfiguration(_ config: ConfigurationData) async throws {
        try await configRepository.setConsumerConfiguration(config)
        logger.info("Consumer configuration saved")
    }

    public func updateConfiguration(_ updates: (ConfigurationData) -> ConfigurationData) async {
        guard let config = currentConfig else {
            logger.warning("No configuration loaded")
            return
        }

        var updated = updates(config)
        do {
            // Mark as updated and save
            _ = updated.markUpdated()
            try await configRepository.save(updated)

            // Trigger sync in background through coordinator
            if let syncCoordinator = syncCoordinator {
                Task {
                    try? await syncCoordinator.sync(configRepository)
                }
            }

            currentConfig = updated
            logger.info("Configuration updated, saved to DB and queued for sync")
        } catch {
            logger.error("Failed to save configuration: \(error)")
        }
    }

    public func syncToCloud() async throws {
        // Sync through coordinator
        if let syncCoordinator = syncCoordinator {
            try await syncCoordinator.sync(configRepository)
        }
    }

    // MARK: - Required protocol methods (simplified)

    public func loadConfigurationWithFallback(apiKey: String) async -> ConfigurationData {
        return await loadConfigurationOnLaunch(apiKey: apiKey)
    }

    public func clearCache() async throws {
        // No cache to clear
    }

    public func startBackgroundSync(apiKey: String) async {
        // No background sync
    }
}
