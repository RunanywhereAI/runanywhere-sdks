import Foundation
import GRDB

/// Repository for managing telemetry data using DataSource pattern
public actor TelemetryRepositoryImpl: Repository, TelemetryRepository {
    public typealias Entity = TelemetryData
    public typealias RemoteDS = RemoteTelemetryDataSource

    private let logger = SDKLogger(category: "TelemetryRepository")

    // Data sources for telemetry operations
    private let localDataSource: LocalTelemetryDataSource
    private let _remoteDataSource: RemoteTelemetryDataSource

    // Expose remote data source for sync coordinator
    public nonisolated var remoteDataSource: RemoteTelemetryDataSource? {
        return _remoteDataSource
    }

    // MARK: - Initialization

    public init(databaseManager: DatabaseManager, apiClient: APIClient?, environment: SDKEnvironment = .development) {
        self.localDataSource = LocalTelemetryDataSource(databaseManager: databaseManager)
        self._remoteDataSource = RemoteTelemetryDataSource(apiClient: apiClient, environment: environment)
        // Note: Can't use logger in actor init - will log on first operation
    }

    // MARK: - Repository Implementation

    public func save(_ entity: TelemetryData) async throws {
        try await localDataSource.store(entity)
        logger.debug("Saved telemetry event: \(entity.id)")
    }

    public func fetch(id: String) async throws -> TelemetryData? {
        return try await localDataSource.load(id: id)
    }

    public func fetchAll() async throws -> [TelemetryData] {
        return try await localDataSource.loadAll()
    }

    public func delete(id: String) async throws {
        try await localDataSource.remove(id: id)
    }

    // MARK: - Sync Support (for Repository protocol)

    public func fetchPendingSync() async throws -> [TelemetryData] {
        return try await localDataSource.loadPendingSync()
    }

    public func markSynced(_ ids: [String]) async throws {
        try await localDataSource.markSynced(ids)
        logger.debug("Marked \(ids.count) telemetry events as synced")
    }

    // MARK: - TelemetryRepository Protocol Methods

    /// Track an event
    public func trackEvent(_ type: TelemetryEventType, properties: [String: String]) async throws {
        let event = TelemetryData(
            eventType: type.rawValue,
            properties: properties
        )

        try await save(event)
    }

    public func fetchByDateRange(from: Date, to: Date) async throws -> [TelemetryData] {
        // Use local data source with filtering
        let allEvents = try await localDataSource.loadAll()
        let filteredEvents = allEvents.filter { event in
            event.timestamp >= from && event.timestamp <= to
        }
        return filteredEvents.sorted { $0.timestamp > $1.timestamp }
    }

    public func fetchUnsent() async throws -> [TelemetryData] {
        return try await localDataSource.loadPendingSync()
    }

    public func markAsSent(_ ids: [String]) async throws {
        try await markSynced(ids)
        logger.info("Marked \(ids.count) telemetry events as sent")
    }

    public func cleanup(olderThan date: Date) async throws {
        try await localDataSource.deleteOldEvents(before: date)
    }
}
