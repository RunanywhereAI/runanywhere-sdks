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

    // MARK: - Sync Support (actual implementation)

    public func syncBatch(_ batch: [ModelInfo]) async throws -> [String] {
        guard let apiClient = apiClient else {
            throw DataSourceError.notAvailable
        }

        var syncedIds: [String] = []

        for modelInfo in batch {
            do {
                let _: ModelInfo = try await apiClient.post(
                    .models,
                    modelInfo,
                    requiresAuth: true
                )
                syncedIds.append(modelInfo.id)
            } catch {
                logger.error("Failed to sync model \(modelInfo.id): \(error)")
            }
        }

        if !syncedIds.isEmpty {
            logger.info("Synced \(syncedIds.count) of \(batch.count) models")
        }

        return syncedIds
    }
}
