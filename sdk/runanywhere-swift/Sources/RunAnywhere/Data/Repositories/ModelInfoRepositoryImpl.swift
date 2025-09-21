import Foundation
import GRDB

/// Repository for managing model information
/// Implements both Repository for basic CRUD and ModelInfoRepository for model-specific operations
public actor ModelInfoRepositoryImpl: Repository, ModelInfoRepository {
    public typealias Entity = ModelInfo
    public typealias RemoteDS = RemoteModelInfoDataSource

    // Core dependencies
    private let databaseManager: DatabaseManager
    private let apiClient: APIClient?
    private let logger = SDKLogger(category: "ModelInfoRepository")

    // Data sources for model-specific operations
    private let _remoteDataSource: RemoteModelInfoDataSource
    private let localDataSource: LocalModelInfoDataSource

    // Expose remote data source for sync coordinator
    public nonisolated var remoteDataSource: RemoteModelInfoDataSource? {
        return _remoteDataSource
    }

    // MARK: - Initialization

    public init(databaseManager: DatabaseManager, apiClient: APIClient?) {
        self.databaseManager = databaseManager
        self.apiClient = apiClient
        self._remoteDataSource = RemoteModelInfoDataSource(apiClient: apiClient)
        self.localDataSource = LocalModelInfoDataSource(databaseManager: databaseManager)
    }

    // MARK: - Repository Protocol Implementation

    public func save(_ entity: ModelInfo) async throws {
        try await localDataSource.store(entity)
        logger.debug("Saved model: \(entity.id)")
    }

    public func fetch(id: String) async throws -> ModelInfo? {
        return try await localDataSource.load(id: id)
    }

    public func fetchAll() async throws -> [ModelInfo] {
        return try await localDataSource.loadAll()
    }

    public func delete(id: String) async throws {
        try await localDataSource.remove(id: id)
        logger.debug("Deleted model: \(id)")
    }

    // MARK: - Sync Support (for Repository protocol)

    public func fetchPendingSync() async throws -> [ModelInfo] {
        return try await localDataSource.loadPendingSync()
    }

    public func markSynced(_ ids: [String]) async throws {
        try await localDataSource.markSynced(ids)
    }

    // MARK: - ModelMetadataRepository Protocol Implementation

    public func fetchByFramework(_ framework: LLMFramework) async throws -> [ModelInfo] {
        return try await localDataSource.findByFramework(framework)
    }

    public func fetchByCategory(_ category: ModelCategory) async throws -> [ModelInfo] {
        return try await localDataSource.findByCategory(category)
    }

    public func fetchDownloaded() async throws -> [ModelInfo] {
        return try await localDataSource.findDownloaded()
    }

    public func updateDownloadStatus(_ modelId: String, localPath: URL?) async throws {
        try await localDataSource.updateDownloadStatus(modelId, localPath: localPath)
        logger.debug("Updated download status for model: \(modelId)")
    }

    public func updateLastUsed(for modelId: String) async throws {
        try await localDataSource.updateLastUsed(modelId)
        logger.debug("Updated last used for model: \(modelId)")
    }

    // MARK: - Remote Data Fetching

    /// Fetch models from backend API and merge with local data
    public func fetchFromBackend() async throws -> [ModelInfo] {
        logger.info("🚀 Starting fetchFromBackend()")

        guard apiClient != nil else {
            logger.warning("⚠️ API client not available, using local models only")
            return try await localDataSource.loadAll()
        }

        logger.info("📡 API client is available, proceeding with remote fetch...")

        do {
            // Fetch models from remote
            logger.info("📥 Calling _remoteDataSource.fetchAll()...")
            print("🔍 ModelInfoRepo: About to call remoteDataSource.fetchAll()")
            let remoteModels = try await _remoteDataSource.fetchAll()
            print("📊 ModelInfoRepo: Backend returned \(remoteModels.count) models")
            logger.info("📊 Received \(remoteModels.count) models from backend")

            // Store them locally for offline access
            logger.info("💾 Caching models locally...")
            for model in remoteModels {
                try await localDataSource.store(model)
                logger.debug("  - Cached: \(model.name)")
            }

            logger.info("✅ Successfully fetched and cached \(remoteModels.count) models from backend")
            return remoteModels
        } catch {
            logger.error("❌ Failed to fetch models from backend: \(error)")
            logger.error("  Error type: \(type(of: error))")
            logger.error("  Error details: \(error.localizedDescription)")

            // Fall back to local models if remote fetch fails
            logger.info("🔄 Falling back to locally cached models")
            return try await localDataSource.loadAll()
        }
    }

    /// Fetch single model from backend
    public func fetchModelFromBackend(id: String) async throws -> ModelInfo? {
        logger.info("Fetching model \(id) from backend API")

        do {
            if let model = try await _remoteDataSource.fetch(id: id) {
                // Store locally for offline access
                try await localDataSource.store(model)
                return model
            }
            return nil
        } catch {
            logger.error("Failed to fetch model \(id) from backend: \(error.localizedDescription)")
            // Fall back to local
            return try await localDataSource.load(id: id)
        }
    }

    // MARK: - Debug Support
    // Mock data population removed - now handled by MockNetworkService in development mode

}
