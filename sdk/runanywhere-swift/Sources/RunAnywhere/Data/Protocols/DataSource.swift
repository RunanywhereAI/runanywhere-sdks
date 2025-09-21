import Foundation

/// Base protocol for all data sources
public protocol DataSource: Actor {
    /// The type of entity this data source handles
    associatedtype Entity: Codable

    /// Check if the data source is available and healthy
    func isAvailable() async -> Bool

    /// Validate the data source configuration
    func validateConfiguration() async throws
}

/// Helper for remote operations with timeout
public struct RemoteOperationHelper: Sendable {
    private let timeout: TimeInterval

    public init(timeout: TimeInterval = 10.0) {
        self.timeout = timeout
    }

    public func withTimeout<R>(_ operation: @escaping () async throws -> R) async throws -> R {
        return try await withThrowingTaskGroup(of: R.self) { group in
            // Add main operation
            group.addTask {
                try await operation()
            }

            // Add timeout task
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(self.timeout * 1_000_000_000))
                throw DataSourceError.networkUnavailable
            }

            // Return first completed task
            guard let result = try await group.next() else {
                throw DataSourceError.operationFailed(
                    NSError(domain: "RemoteOperationHelper", code: -1)
                )
            }

            group.cancelAll()
            return result
        }
    }
}

/// Protocol for remote data sources that fetch data from network APIs
public protocol RemoteDataSource: DataSource {
    /// Fetch a single entity by identifier
    func fetch(id: String) async throws -> Entity?

    /// Fetch multiple entities with optional filtering
    func fetchAll(filter: [String: Any]?) async throws -> [Entity]

    /// Save entity to remote source
    func save(_ entity: Entity) async throws -> Entity

    /// Delete entity from remote source
    func delete(id: String) async throws

    /// Test network connectivity and authentication
    func testConnection() async throws -> Bool

    /// Sync a batch of entities to the remote source
    /// Returns successfully synced entity IDs
    func syncBatch(_ batch: [Entity]) async throws -> [String]
}

/// Protocol for local data sources that store data locally (database, file system, etc.)
public protocol LocalDataSource: DataSource {
    /// Load entity from local storage
    func load(id: String) async throws -> Entity?

    /// Load all entities from local storage
    func loadAll() async throws -> [Entity]

    /// Store entity in local storage
    func store(_ entity: Entity) async throws

    /// Remove entity from local storage
    func remove(id: String) async throws

    /// Clear all data from local storage
    func clear() async throws

    /// Get storage health information
    func getStorageInfo() async throws -> DataSourceStorageInfo
}

/// Information about local storage status
public struct DataSourceStorageInfo: Codable, Sendable {
    public let totalSpace: Int64?
    public let availableSpace: Int64?
    public let usedSpace: Int64?
    public let entityCount: Int
    public let lastUpdated: Date

    public init(
        totalSpace: Int64? = nil,
        availableSpace: Int64? = nil,
        usedSpace: Int64? = nil,
        entityCount: Int = 0,
        lastUpdated: Date = Date()
    ) {
        self.totalSpace = totalSpace
        self.availableSpace = availableSpace
        self.usedSpace = usedSpace
        self.entityCount = entityCount
        self.lastUpdated = lastUpdated
    }
}

/// Errors that can occur in data sources
public enum DataSourceError: LocalizedError {
    case notAvailable
    case configurationInvalid(String)
    case networkUnavailable
    case authenticationFailed
    case storageUnavailable
    case entityNotFound(String)
    case operationFailed(Error)
    case notFound
    case fetchFailed(String)

    public var errorDescription: String? {
        switch self {
        case .notAvailable:
            return "Data source is not available"
        case .configurationInvalid(let message):
            return "Invalid configuration: \(message)"
        case .networkUnavailable:
            return "Network is unavailable"
        case .authenticationFailed:
            return "Authentication failed"
        case .storageUnavailable:
            return "Local storage is unavailable"
        case .entityNotFound(let id):
            return "Entity not found: \(id)"
        case .operationFailed(let error):
            return "Operation failed: \(error.localizedDescription)"
        case .notFound:
            return "Resource not found"
        case .fetchFailed(let message):
            return "Fetch failed: \(message)"
        }
    }
}
