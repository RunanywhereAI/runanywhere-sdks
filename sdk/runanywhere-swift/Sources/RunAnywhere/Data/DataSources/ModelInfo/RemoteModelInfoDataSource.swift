import Foundation

/// Remote data source for fetching model information from API
public actor RemoteModelInfoDataSource: RemoteDataSource {
    public typealias Entity = ModelInfo

    private let apiClient: APIClient?
    private let logger = SDKLogger(category: "RemoteModelInfoDataSource")
    private let operationHelper = RemoteOperationHelper(timeout: 10.0)

    public init(apiClient: APIClient?) {
        self.apiClient = apiClient
    }

    // MARK: - DataSource Protocol

    public func isAvailable() async -> Bool {
        return apiClient != nil
    }

    public func validateConfiguration() async throws {
        guard apiClient != nil else {
            throw DataSourceError.networkUnavailable
        }
    }

    // MARK: - RemoteDataSource Protocol

    public func fetch(id: String) async throws -> ModelInfo? {
        guard apiClient != nil else {
            throw DataSourceError.networkUnavailable
        }

        logger.debug("Fetching model from remote: \(id)")

        // Placeholder for actual API implementation
        // In production, this would call the actual API endpoint
        return try await operationHelper.withTimeout {
            self.logger.debug("Remote model fetch not yet implemented")
            return nil
        }
    }

    // swiftlint:disable:next prefer_concrete_types avoid_any_type
    public func fetchAll(filter: [String: Any]? = nil) async throws -> [ModelInfo] {
        guard apiClient != nil else {
            throw DataSourceError.networkUnavailable
        }

        logger.debug("Fetching all models from remote")

        // Placeholder for actual API implementation
        return try await operationHelper.withTimeout {
            self.logger.debug("Remote models fetch not yet implemented")
            return []
        }
    }

    public func save(_ entity: ModelInfo) async throws -> ModelInfo {
        guard apiClient != nil else {
            throw DataSourceError.networkUnavailable
        }

        logger.debug("Pushing model to remote: \(entity.id)")

        // Placeholder for actual API implementation
        return try await operationHelper.withTimeout {
            self.logger.debug("Remote model save not yet implemented")
            return entity
        }
    }

    public func delete(id: String) async throws {
        guard apiClient != nil else {
            throw DataSourceError.networkUnavailable
        }

        logger.debug("Deleting model from remote: \(id)")

        // Placeholder for actual API implementation
        try await operationHelper.withTimeout {
            self.logger.debug("Remote model delete not yet implemented")
        }
    }

    // MARK: - Sync Support

    public func syncBatch(_ batch: [ModelInfo]) async throws -> [String] {
        guard let apiClient = apiClient else {
            throw DataSourceError.notAvailable
        }

        logger.info("Syncing \(batch.count) model info items")

        var syncedIds: [String] = []

        // For model info, we typically sync one at a time using POST to the regular endpoint
        for modelInfo in batch {
            do {
                // Use regular POST to models endpoint
                let _: ModelInfo = try await apiClient.post(
                    .models,
                    modelInfo,
                    requiresAuth: true
                )
                syncedIds.append(modelInfo.id)
                logger.debug("Synced model info: \(modelInfo.id)")
            } catch {
                logger.error("Failed to sync model info \(modelInfo.id): \(error)")
                // Continue with next item
            }
        }

        logger.info("Successfully synced \(syncedIds.count) of \(batch.count) model info items")
        return syncedIds
    }

    public func testConnection() async throws -> Bool {
        guard apiClient != nil else {
            return false
        }

        return try await operationHelper.withTimeout {
            self.logger.debug("Remote model service connection test skipped (not implemented)")
            return false
        }
    }

}
