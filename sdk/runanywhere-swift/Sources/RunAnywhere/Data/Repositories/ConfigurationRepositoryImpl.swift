import Foundation
import GRDB

/// Repository for managing SDK configuration data
/// Implements both Repository for basic CRUD and ConfigurationRepository for config-specific operations
public actor ConfigurationRepositoryImpl: Repository, ConfigurationRepository {
    public typealias Entity = ConfigurationData
    public typealias RemoteDS = RemoteConfigurationDataSource

    // Core dependencies
    private let databaseManager: DatabaseManager
    private let apiClient: APIClient?
    private let logger = SDKLogger(category: "ConfigurationRepository")

    // Data sources for configuration-specific operations
    private let _remoteDataSource: RemoteConfigurationDataSource
    private let localDataSource: LocalConfigurationDataSource

    // Expose remote data source for sync coordinator
    public nonisolated var remoteDataSource: RemoteConfigurationDataSource? {
        return _remoteDataSource
    }

    // MARK: - Initialization

    public init(databaseManager: DatabaseManager, apiClient: APIClient?) {
        self.databaseManager = databaseManager
        self.apiClient = apiClient
        self._remoteDataSource = RemoteConfigurationDataSource(apiClient: apiClient)
        self.localDataSource = LocalConfigurationDataSource(databaseManager: databaseManager)
    }

    // MARK: - Repository Protocol Implementation

    public func save(_ entity: ConfigurationData) async throws {
        try databaseManager.write { db in
            try entity.save(db)
        }
        logger.debug("Saved configuration: \(entity.id)")
    }

    public func fetch(id: String) async throws -> ConfigurationData? {
        return try databaseManager.read { db in
            try ConfigurationData.fetchOne(db, key: id)
        }
    }

    public func fetchAll() async throws -> [ConfigurationData] {
        return try databaseManager.read { db in
            try ConfigurationData
                .order(Column("updatedAt").desc)
                .fetchAll(db)
        }
    }

    public func delete(id: String) async throws {
        try databaseManager.write { db in
            _ = try ConfigurationData.deleteOne(db, key: id)
        }
        logger.debug("Deleted configuration: \(id)")
    }

    // MARK: - Sync Support (for Repository protocol)

    public func fetchPendingSync() async throws -> [ConfigurationData] {
        return try databaseManager.read { db in
            try ConfigurationData
                .filter(Column("syncPending") == true)
                .fetchAll(db)
        }
    }

    public func markSynced(_ ids: [String]) async throws {
        try databaseManager.write { db in
            for id in ids {
                if var data = try ConfigurationData.fetchOne(db, key: id) {
                    data.markSynced()
                    try data.update(db)
                }
            }
        }
    }

    // MARK: - ConfigurationRepository Protocol Implementation

    public func fetchRemoteConfiguration(apiKey: String) async throws -> ConfigurationData? {
        do {
            return try await _remoteDataSource.fetchConfiguration(apiKey: apiKey)
        } catch {
            logger.debug("Remote configuration fetch failed: \(error)")
            return nil
        }
    }

    public func setConsumerConfiguration(_ config: ConfigurationData) async throws {
        try await localDataSource.saveConsumerOverride(config)
    }

    public func getConsumerConfiguration() async throws -> ConfigurationData? {
        return try await localDataSource.loadConsumerOverride()
    }

    nonisolated public func getSDKDefaultConfiguration() -> ConfigurationData {
        return ConfigurationData(
            id: SDKConstants.ConfigurationDefaults.configurationId,
            source: .defaults
        )
    }
}
