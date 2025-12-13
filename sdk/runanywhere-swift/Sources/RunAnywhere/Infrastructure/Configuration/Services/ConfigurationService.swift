import Foundation

/// Simple configuration service with fallback system: DB → Consumer → SDK Defaults
public actor ConfigurationService: ConfigurationServiceProtocol {
    private let logger = SDKLogger(category: "ConfigurationService")
    private let configRepository: ConfigurationRepositoryImpl?
    private let syncCoordinator: SyncCoordinator?

    private var currentConfig: ConfigurationData?

    // MARK: - Initialization

    public init(configRepository: ConfigurationRepositoryImpl?, syncCoordinator: SyncCoordinator? = nil) {
        self.configRepository = configRepository
        self.syncCoordinator = syncCoordinator
        logger.info("ConfigurationService created\(configRepository == nil ? " (Development Mode)" : "")")
    }

    // MARK: - Public Methods

    public func getConfiguration() -> ConfigurationData? {
        return currentConfig
    }

    /// Load configuration on app launch with simple fallback: Remote → DB → Consumer → Defaults
    public func loadConfigurationOnLaunch(apiKey: String) async -> ConfigurationData {
        // Development mode: Skip remote fetch and use defaults
        guard let repository = configRepository else {
            logger.info("Development mode: Using SDK defaults")
            let defaultConfig = ConfigurationData.sdkDefaults(apiKey: apiKey)
            currentConfig = defaultConfig
            return defaultConfig
        }

        // Step 1: Try to fetch remote configuration
        if let remoteConfig = try? await repository.fetchRemoteConfiguration(apiKey: apiKey) {
            logger.info("Remote configuration loaded, saving to DB")
            // Save to DB and use as current config
            try? await repository.save(remoteConfig)
            currentConfig = remoteConfig
            return remoteConfig
        }

        // Step 2: Try to load from DB
        if let dbConfig = try? await repository.fetch(id: RegistryConstants.configurationId) {
            logger.info("Using DB configuration")
            currentConfig = dbConfig
            return dbConfig
        }

        // Step 3: Try consumer configuration
        if let consumerConfig = try? await repository.getConsumerConfiguration() {
            logger.info("Using consumer configuration fallback")
            currentConfig = consumerConfig
            return consumerConfig
        }

        // Step 4: Use SDK defaults
        logger.info("Using SDK default configuration")
        let defaultConfig = repository.getSDKDefaultConfiguration()
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
        guard let repository = configRepository else {
            logger.info("Development mode: Consumer configuration not persisted")
            currentConfig = config
            return
        }
        try await repository.setConsumerConfiguration(config)
        logger.info("Consumer configuration saved")
    }

    public func updateConfiguration(_ updates: (ConfigurationData) -> ConfigurationData) async {
        guard let config = currentConfig else {
            logger.warning("No configuration loaded")
            return
        }

        var updated = updates(config)

        // Development mode: Just update in memory
        guard let repository = configRepository else {
            currentConfig = updated
            logger.info("Development mode: Configuration updated in memory")
            return
        }

        do {
            // Mark as updated and save
            updated.markUpdated()
            try await repository.save(updated)

            // Trigger sync in background through coordinator
            if let syncCoordinator = syncCoordinator {
                Task {
                    try? await syncCoordinator.sync(repository)
                }
            }

            currentConfig = updated
            logger.info("Configuration updated, saved to DB and queued for sync")
        } catch {
            logger.error("Failed to save configuration: \(error)")
        }
    }

    public func syncToCloud() async throws {
        guard let repository = configRepository else {
            logger.info("Development mode: Sync skipped")
            return
        }

        // Sync through coordinator
        if let syncCoordinator = syncCoordinator {
            try await syncCoordinator.sync(repository)
        }
    }

    // MARK: - Factory Methods

    /// Create default configuration for development mode (no backend sync)
    /// - Parameter apiKey: The API key (can be empty for dev mode)
    /// - Returns: Default configuration data
    public func createDevelopmentModeConfig(apiKey: String) -> ConfigurationData {
        let config = ConfigurationData(
            id: "dev-\(UUID().uuidString)",
            apiKey: apiKey.isEmpty ? "dev-mode" : apiKey,
            source: .defaults
        )
        return config
    }
}
