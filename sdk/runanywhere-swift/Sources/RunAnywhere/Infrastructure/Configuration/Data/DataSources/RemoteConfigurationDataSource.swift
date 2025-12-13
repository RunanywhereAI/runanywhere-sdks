import Foundation

/// Remote data source for fetching configuration from API server
public actor RemoteConfigurationDataSource: RemoteDataSource {
    public typealias Entity = ConfigurationData

    private let apiClient: APIClient?
    private let logger = SDKLogger(category: "RemoteConfigurationDataSource")
    private let operationHelper = RemoteOperationHelper(timeout: 10.0)

    public init(apiClient: APIClient?) {
        self.apiClient = apiClient
    }

    // MARK: - DataSource Protocol

    public func isAvailable() async -> Bool {
        guard apiClient != nil else {
            logger.debug("API client not configured")
            return false
        }

        do {
            return try await testConnection()
        } catch {
            logger.debug("Connection test failed: \(error)")
            return false
        }
    }

    public func validateConfiguration() async throws {
        guard apiClient != nil else {
            throw DataSourceError.configurationInvalid("API client not configured")
        }
    }

    // MARK: - RemoteDataSource Protocol

    public func fetch(id: String) async throws -> ConfigurationData? {
        guard apiClient != nil else {
            throw DataSourceError.notAvailable
        }

        logger.debug("Fetching configuration: \(id)")

        return try await operationHelper.withTimeout {
            // In a real implementation, this would be a proper endpoint call
            // For now, return nil to indicate no remote config available
            self.logger.debug("Remote configuration fetch not yet implemented")
            return nil
        }
    }

    // swiftlint:disable:next prefer_concrete_types avoid_any_type
    public func fetchAll(filter: [String: Any]?) async throws -> [ConfigurationData] {
        // Not typically used for configuration
        return []
    }

    public func save(_ entity: ConfigurationData) async throws -> ConfigurationData {
        // Configuration is typically read-only from remote
        throw DataSourceError.operationFailed(
            NSError(domain: "RemoteConfigurationDataSource", code: -1, userInfo: [
                NSLocalizedDescriptionKey: "Remote configuration save not supported"
            ])
        )
    }

    public func delete(id: String) async throws {
        // Configuration deletion is typically not supported
        throw DataSourceError.operationFailed(
            NSError(domain: "RemoteConfigurationDataSource", code: -1, userInfo: [
                NSLocalizedDescriptionKey: "Remote configuration delete not supported"
            ])
        )
    }

    public func testConnection() async throws -> Bool {
        guard apiClient != nil else {
            return false
        }

        return try await operationHelper.withTimeout {
            // Test with a simple health check
            // let _: [String: Bool] = try await apiClient.get(APIEndpoint.health)
            self.logger.debug("Remote configuration service connection test skipped (not implemented)")
            return false
        }
    }

    // MARK: - Sync Support

    public func syncBatch(_ batch: [ConfigurationData]) async throws -> [String] {
        guard let apiClient = apiClient else {
            throw DataSourceError.notAvailable
        }

        logger.info("Syncing \(batch.count) configuration items")

        var syncedIds: [String] = []

        // For configuration, we typically sync one at a time using POST to the regular endpoint
        for config in batch {
            do {
                // Use regular POST to configuration endpoint
                let _: ConfigurationData = try await apiClient.post(
                    .configuration,
                    config,
                    requiresAuth: true
                )
                syncedIds.append(config.id)
                logger.debug("Synced configuration: \(config.id)")
            } catch {
                logger.error("Failed to sync configuration \(config.id): \(error)")
                // Continue with next item
            }
        }

        logger.info("Successfully synced \(syncedIds.count) of \(batch.count) configuration items")
        return syncedIds
    }

    // MARK: - Configuration-specific methods

    /// Fetch configuration by API key
    public func fetchConfiguration(apiKey: String) async throws -> ConfigurationData {
        guard !apiKey.isEmpty else {
            logger.debug("Empty API key provided, skipping remote fetch")
            throw DataSourceError.configurationInvalid("Empty API key")
        }

        logger.info("Fetching remote configuration...")

        // Use the fetch method with API key as ID
        if let config = try await fetch(id: apiKey) {
            var updatedConfig = config
            updatedConfig.source = .remote
            return updatedConfig
        } else {
            throw DataSourceError.entityNotFound(apiKey)
        }
    }
}
