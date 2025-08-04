import Foundation

/// Persisted SDK configuration data
public struct ConfigurationData: RepositoryEntity {
    public let id: String
    public let settings: [String: String]
    public let updatedAt: Date
    public let syncPending: Bool

    public init(
        id: String = UUID().uuidString,
        settings: [String: String],
        updatedAt: Date = Date(),
        syncPending: Bool = true
    ) {
        self.id = id
        self.settings = settings
        self.updatedAt = updatedAt
        self.syncPending = syncPending
    }
}
