import Foundation
import GRDB

/// Repository for managing SDK configuration data
public actor ConfigurationRepositoryImpl: Repository, ConfigurationRepository {
    public typealias Entity = ConfigurationData

    private let databaseManager: DatabaseManager
    private let apiClient: APIClient?
    private let logger = SDKLogger(category: "ConfigurationRepository")

    // MARK: - Initialization

    public init(databaseManager: DatabaseManager, apiClient: APIClient?) {
        self.databaseManager = databaseManager
        self.apiClient = apiClient
    }

    // MARK: - Repository Implementation

    public func save(_ entity: ConfigurationData) async throws {
        let record = mapToRecord(entity)

        try databaseManager.write { db in
            try record.save(db)
        }

        logger.info("Configuration saved: \(entity.id)")
    }

    public func fetch(id: String) async throws -> ConfigurationData? {
        let record = try databaseManager.read { db in
            try ConfigurationRecord.fetchOne(db, key: id)
        }

        return try record.map { try mapToEntity($0) }
    }

    public func fetchAll() async throws -> [ConfigurationData] {
        let records = try databaseManager.read { db in
            try ConfigurationRecord
                .order(ConfigurationRecord.Columns.updatedAt.desc)
                .fetchAll(db)
        }

        logger.info("Found \(records.count) configurations in database")

        return try records.map { try mapToEntity($0) }
    }

    public func delete(id: String) async throws {
        try databaseManager.write { db in
            _ = try ConfigurationRecord.deleteOne(db, key: id)
        }

        logger.info("Configuration deleted: \(id)")
    }

    public func fetchPendingSync() async throws -> [ConfigurationData] {
        let records = try databaseManager.read { db in
            try ConfigurationRecord
                .filter(ConfigurationRecord.Columns.syncPending == true)
                .fetchAll(db)
        }

        return try records.map { try mapToEntity($0) }
    }

    public func markSynced(_ ids: [String]) async throws {
        try databaseManager.write { db in
            for id in ids {
                if var record = try ConfigurationRecord.fetchOne(db, key: id) {
                    record.syncPending = false
                    record.updatedAt = Date()
                    try record.update(db)
                }
            }
        }

        logger.info("Marked \(ids.count) configurations as synced")
    }

    public func sync() async throws {
        guard let apiClient = apiClient else {
            logger.warning("API client not available for sync")
            return
        }

        let pending = try await fetchPendingSync()
        guard !pending.isEmpty else {
            return
        }

        // For now, just log - actual sync would be implemented later
        logger.info("Would sync \(pending.count) configurations")

        // Example sync implementation:
        // let response = try await apiClient.post(.syncConfiguration, pending)
        // try await markSynced(response.syncedIds)
    }

    // MARK: - ConfigurationRepository Protocol Methods

    public func fetchByKey(_ key: String) async throws -> ConfigurationData? {
        // For now, just return the default configuration if key matches
        if key == "default" {
            return try await fetch(id: "default")
        }
        return nil
    }

    public func updatePartial(_ id: String, updates: (ConfigurationData) -> ConfigurationData) async throws {
        guard let existing = try await fetch(id: id) else {
            throw RepositoryError.entityNotFound(id)
        }

        let updated = updates(existing)
        try await save(updated.markUpdated())
    }

    // MARK: - Mapping Functions

    private func mapToRecord(_ entity: ConfigurationData) -> ConfigurationRecord {
        // Map the composed configuration to flat record structure
        let privacyMode = entity.routing.privacyMode.rawValue
        let telemetryConsent = entity.analytics.enabled ?
            (entity.analytics.level == .detailed ? SDKConstants.TelemetryDefaults.consentDetailed : SDKConstants.TelemetryDefaults.consentAnonymous) :
            SDKConstants.TelemetryDefaults.consentNone

        return ConfigurationRecord(
            id: entity.id,
            apiKey: entity.apiKey,
            baseURL: SDKConstants.DatabaseDefaults.apiBaseURL,
            modelCacheSize: SDKConstants.ModelDefaults.defaultModelCacheSize,
            maxMemoryUsageMB: SDKConstants.ModelDefaults.defaultMaxMemoryUsageMB,
            privacyMode: privacyMode,
            telemetryConsent: telemetryConsent,
            createdAt: entity.createdAt,
            updatedAt: entity.updatedAt,
            syncPending: entity.syncPending
        )
    }

    private func mapToEntity(_ record: ConfigurationRecord) throws -> ConfigurationData {
        // Map flat record structure back to composed configuration
        let privacyMode = PrivacyMode(rawValue: record.privacyMode) ?? .standard
        let analyticsEnabled = record.telemetryConsent != SDKConstants.TelemetryDefaults.consentNone
        let analyticsLevel: AnalyticsLevel = record.telemetryConsent == SDKConstants.TelemetryDefaults.consentDetailed ? .detailed : .basic

        // Create routing configuration
        let routing = RoutingConfiguration(
            policy: .automatic, // Default for now, could be stored separately
            cloudEnabled: true,
            privacyMode: privacyMode
        )

        // Create analytics configuration
        let analytics = AnalyticsConfiguration(
            enabled: analyticsEnabled,
            level: analyticsLevel,
            liveMetricsEnabled: true
        )

        // Create generation configuration with defaults
        let generation = GenerationConfiguration()

        // Create storage configuration with defaults
        let storage = StorageConfiguration(
            maxCacheSize: Int64(record.maxMemoryUsageMB) * 1024 * 1024
        )

        return ConfigurationData(
            id: record.id,
            routing: routing,
            analytics: analytics,
            generation: generation,
            storage: storage,
            apiKey: record.apiKey,
            allowUserOverride: true,
            createdAt: record.createdAt,
            updatedAt: record.updatedAt,
            syncPending: record.syncPending
        )
    }
}
