import Foundation

/// Remote data source for syncing model information to the backend
/// Note: Fetching model assignments is handled by ModelAssignmentService
public actor RemoteModelInfoDataSource: RemoteDataSource {
    public typealias Entity = ModelInfo

    private let apiClient: APIClient?
    private let logger = SDKLogger(category: "RemoteModelInfoDataSource")

    public init(apiClient: APIClient?) {
        self.apiClient = apiClient
    }

    // MARK: - DataSource Protocol

    public func isAvailable() async -> Bool {
        apiClient != nil
    }

    public func validateConfiguration() async throws {
        guard apiClient != nil else {
            throw DataSourceError.networkUnavailable
        }
    }

    // MARK: - RemoteDataSource Protocol (minimal implementation)

    public func fetch(id _: String) async throws -> ModelInfo? {
        // Not implemented - model fetching is handled by ModelAssignmentService
        nil
    }

    // swiftlint:disable:next prefer_concrete_types avoid_any_type
    public func fetchAll(_: [String: Any]? = nil) async throws -> [ModelInfo] {
        // Not implemented - model fetching is handled by ModelAssignmentService
        []
    }

    public func save(_ entity: ModelInfo) async throws -> ModelInfo {
        // Not implemented - models are saved locally and synced via syncBatch
        entity
    }

    public func delete(id _: String) async throws {
        // Not implemented
    }

    public func testConnection() async throws -> Bool {
        apiClient != nil
    }

    // MARK: - Sync Support

    /// Sync batch marks models as synced locally.
    /// Note: SDK does not POST models to backend - models are created via web dashboard
    /// and fetched via ModelAssignmentService. This just marks local models as "synced".
    public func syncBatch(_ batch: [ModelInfo]) async throws -> [String] {
        // SDK is read-only for models - just mark as synced locally
        let syncedIds = batch.map { $0.id }

        if !syncedIds.isEmpty {
            logger.debug("Marked \(syncedIds.count) models as synced (local-only)")
        }

        return syncedIds
    }
}
