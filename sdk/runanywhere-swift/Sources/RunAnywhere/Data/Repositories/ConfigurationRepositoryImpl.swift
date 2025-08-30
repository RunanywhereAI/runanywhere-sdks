import Foundation
import GRDB

/// Repository for managing SDK configuration data
/// Implements both Repository for basic CRUD and ConfigurationRepository for config-specific operations
public actor ConfigurationRepositoryImpl: Repository, ConfigurationRepository {
    public typealias Entity = ConfigurationData

    // Core dependencies
    private let databaseManager: DatabaseManager
    private let apiClient: APIClient?
    private let syncManager: SyncManager?
    private let logger = SDKLogger(category: "ConfigurationRepository")

    // Data sources for configuration-specific operations
    private let remoteDataSource: RemoteConfigurationDataSource
    private let localDataSource: LocalConfigurationDataSource

    // MARK: - Initialization

    public init(databaseManager: DatabaseManager, apiClient: APIClient?) {
        self.databaseManager = databaseManager
        self.apiClient = apiClient
        self.syncManager = apiClient != nil ? SyncManager(apiClient: apiClient) : nil
        self.remoteDataSource = RemoteConfigurationDataSource(apiClient: apiClient)
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
                .order(ConfigurationData.Columns.updatedAt.desc)
                .fetchAll(db)
        }
    }

    public func delete(id: String) async throws {
        try databaseManager.write { db in
            _ = try ConfigurationData.deleteOne(db, key: id)
        }
        logger.debug("Deleted configuration: \(id)")
    }

    // Override sync to use sync manager
    public func syncIfNeeded() async throws {
        guard let syncManager = syncManager else { return }

        let pending = try await fetchPendingSync()
        for entity in pending {
            await syncManager.queueForSync(entityId: entity.id)
        }
    }

    // MARK: - ConfigurationRepository Protocol Implementation

    public func fetchRemoteConfiguration(apiKey: String) async throws -> ConfigurationData? {
        do {
            return try await remoteDataSource.fetchConfiguration(apiKey: apiKey)
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
