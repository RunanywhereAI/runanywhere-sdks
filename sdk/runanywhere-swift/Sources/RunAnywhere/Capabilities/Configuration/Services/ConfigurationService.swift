import Foundation

/// Simple service for managing SDK configuration using repository pattern
public actor ConfigurationService: ConfigurationServiceProtocol {
    private let logger = SDKLogger(category: "ConfigurationService")
    private let configRepository: any ConfigurationRepository
    private var currentConfig: ConfigurationData?

    // MARK: - Initialization

    public init(configRepository: any ConfigurationRepository) {
        self.configRepository = configRepository
        logger.info("ConfigurationService created")
    }

    // MARK: - Public Methods

    public func getConfiguration() -> ConfigurationData? {
        return currentConfig
    }

    /// Ensure configuration is loaded from database
    public func ensureConfigurationLoaded() async {
        if currentConfig == nil {
            await loadConfiguration()
        }
    }

    public func updateConfiguration(_ updates: (ConfigurationData) -> ConfigurationData) async {
        guard let config = currentConfig else {
            logger.warning("No configuration loaded")
            return
        }

        let updated = updates(config)
        await saveConfiguration(updated)
    }


    public func syncToCloud() async throws {
        try await configRepository.sync()
    }

    // MARK: - Private Methods

    private func loadConfiguration() async {
        do {
            // Try to load existing configuration
            if let config = try await configRepository.fetch(id: SDKConstants.ConfigurationDefaults.configurationId) {
                self.currentConfig = config
                logger.info("Loaded configuration from database - maxTokens: \(config.generation.defaults.maxTokens), temperature: \(config.generation.defaults.temperature)")
            } else {
                // Create default configuration
                let defaultConfig = ConfigurationData()
                try await configRepository.save(defaultConfig)
                self.currentConfig = defaultConfig
                logger.info("Created default configuration - maxTokens: \(defaultConfig.generation.defaults.maxTokens)")
            }
        } catch {
            logger.error("Failed to load configuration: \(error)")
            // Use in-memory defaults
            self.currentConfig = ConfigurationData()
        }
    }

    private func saveConfiguration(_ config: ConfigurationData) async {
        do {
            try await configRepository.save(config)
            self.currentConfig = config
            logger.info("Configuration saved - maxTokens: \(config.generation.defaults.maxTokens), temperature: \(config.generation.defaults.temperature)")
        } catch {
            logger.error("Failed to save configuration: \(error)")
        }
    }

}
