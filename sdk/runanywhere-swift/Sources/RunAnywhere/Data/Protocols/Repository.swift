import Foundation

/// Base repository protocol for data persistence and synchronization
public protocol Repository {
    associatedtype Entity: Codable

    // MARK: - Local Operations

    func save(_ entity: Entity) async throws
    func fetch(id: String) async throws -> Entity?
    func fetchAll() async throws -> [Entity]
    func delete(id: String) async throws

    // MARK: - Sync Operations

    func fetchPendingSync() async throws -> [Entity]
    func markSynced(_ ids: [String]) async throws
    func sync() async throws
}
