import Foundation

/// Base protocol for entities that can be stored in repositories
public protocol RepositoryEntity: Codable {
    var id: String { get }
    var updatedAt: Date { get }
    var syncPending: Bool { get }
}
