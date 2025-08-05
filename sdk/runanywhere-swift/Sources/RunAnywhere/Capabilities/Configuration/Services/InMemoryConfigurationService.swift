import Foundation

/// In-memory configuration service that doesn't use database persistence
/// Used as a fallback when database is unavailable or corrupted
public actor InMemoryConfigurationService: ConfigurationServiceProtocol {
    private let logger = SDKLogger(category: "InMemoryConfigurationService")
    private var currentConfig: ConfigurationData?

    // MARK: - Initialization

    public init() {
        // Initialize with default configuration
        self.currentConfig = ConfigurationData()
        logger.info("InMemoryConfigurationService created with default configuration")
    }

    // MARK: - Public Methods

    public func getConfiguration() -> ConfigurationData? {
        return currentConfig
    }

    /// Ensure configuration is loaded (always available in memory)
    public func ensureConfigurationLoaded() async {
        if currentConfig == nil {
            currentConfig = ConfigurationData()
            logger.info("Default configuration loaded in memory")
        }
    }

    public func updateConfiguration(_ updates: (ConfigurationData) -> ConfigurationData) async {
        guard let config = currentConfig else {
            logger.warning("No configuration available - creating default")
            currentConfig = ConfigurationData()
            return
        }

        let updated = updates(config)
        currentConfig = updated
        logger.info("Configuration updated in memory - maxTokens: \(updated.maxTokens), temperature: \(updated.temperature)")
    }

    public func syncToCloud() async throws {
        // No-op for in-memory service
        logger.info("Sync to cloud skipped (in-memory configuration)")
    }
}
