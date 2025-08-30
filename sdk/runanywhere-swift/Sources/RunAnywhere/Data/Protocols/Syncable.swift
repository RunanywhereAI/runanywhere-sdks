import Foundation

/// Simple protocol for entities that need syncing
public protocol Syncable {
    /// Unique identifier
    var id: String { get }

    /// When created
    var createdAt: Date { get }

    /// When last updated
    var updatedAt: Date { get set }

    /// Needs sync to network
    var syncPending: Bool { get set }

    /// Mark as updated (sets updatedAt and syncPending)
    mutating func markUpdated() -> Self

    /// Mark as synced (clears syncPending)
    mutating func markSynced() -> Self
}

/// Default implementation
public extension Syncable {
    mutating func markUpdated() -> Self {
        self.updatedAt = Date()
        self.syncPending = true
        return self
    }

    mutating func markSynced() -> Self {
        self.syncPending = false
        return self
    }
}
