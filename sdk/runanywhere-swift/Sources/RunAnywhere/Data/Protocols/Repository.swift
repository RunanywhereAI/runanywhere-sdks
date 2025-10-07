import Foundation

/// Base repository protocol for data persistence
/// Minimal interface - sync handled by SyncCoordinator
public protocol Repository {
    associatedtype Entity: Codable
    associatedtype RemoteDS: RemoteDataSource where RemoteDS.Entity == Entity

    // MARK: - Core CRUD Operations

    func save(_ entity: Entity) async throws
    func fetch(id: String) async throws -> Entity?
    func fetchAll() async throws -> [Entity]
    func delete(id: String) async throws

    // MARK: - Sync Support

    /// Get the remote data source for syncing
    var remoteDataSource: RemoteDS? { get }
}

/// Extension for repositories with RepositoryEntity entities
/// Provides minimal sync support - actual sync logic in SyncCoordinator
public extension Repository where Entity: RepositoryEntity {

    /// Fetch entities pending sync
    func fetchPendingSync() async throws -> [Entity] {
        let all = try await fetchAll()
        return all.filter { $0.syncPending }
    }

    /// Mark entities as synced
    func markSynced(_ ids: [String]) async throws {
        for id in ids {
            if var entity = try await fetch(id: id) {
                entity.markSynced()
                try await save(entity)
            }
        }
    }
}
