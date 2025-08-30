import Foundation

/// Base repository protocol for data persistence
/// Automatically handles sync for Syncable entities
public protocol Repository {
    associatedtype Entity: Codable

    // MARK: - Core Operations

    func save(_ entity: Entity) async throws
    func fetch(id: String) async throws -> Entity?
    func fetchAll() async throws -> [Entity]
    func delete(id: String) async throws
}

/// Extension for repositories with Syncable entities
public extension Repository where Entity: Syncable {

    /// Save and mark for sync
    func saveAndSync(_ entity: Entity) async throws {
        var updated = entity
        _ = updated.markUpdated()
        try await save(updated)

        // Trigger background sync if possible
        Task {
            try? await syncIfNeeded()
        }
    }

    /// Fetch entities pending sync
    func fetchPendingSync() async throws -> [Entity] {
        let all = try await fetchAll()
        return all.filter { $0.syncPending }
    }

    /// Mark entities as synced
    func markSynced(_ ids: [String]) async throws {
        for id in ids {
            if var entity = try await fetch(id: id) {
                _ = entity.markSynced()
                try await save(entity)
            }
        }
    }

    /// Override this to implement actual network sync
    func syncIfNeeded() async throws {
        // Default: no-op, subclasses can override
    }
}
