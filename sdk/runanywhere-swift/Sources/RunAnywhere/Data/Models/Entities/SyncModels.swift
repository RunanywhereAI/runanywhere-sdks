import Foundation

/// Consolidated protocol for entities that can be stored in repositories and synced
/// Combines previous Syncable and RepositoryEntity protocols to eliminate duplication
public protocol RepositoryEntity: Codable {
    /// Unique identifier
    var id: String { get }

    /// When created
    var createdAt: Date { get }

    /// When last updated
    var updatedAt: Date { get set }

    /// Needs sync to network
    var syncPending: Bool { get set }

    /// Mark as updated (sets updatedAt and syncPending)
    mutating func markUpdated()

    /// Mark as synced (clears syncPending)
    mutating func markSynced()
}

/// Default implementation for sync behavior
public extension RepositoryEntity {
    mutating func markUpdated() {
        self.updatedAt = Date()
        self.syncPending = true
    }

    mutating func markSynced() {
        self.syncPending = false
    }
}
