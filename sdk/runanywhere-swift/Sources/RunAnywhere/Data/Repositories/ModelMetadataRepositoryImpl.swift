import Foundation
import GRDB

/// Repository for managing model metadata using DataSource pattern
public actor ModelMetadataRepositoryImpl: Repository, ModelMetadataRepository {
    public typealias Entity = ModelMetadataData

    private let databaseManager: DatabaseManager
    private let apiClient: APIClient?
    private let logger = SDKLogger(category: "ModelMetadataRepository")

    // Data sources for model metadata operations
    private let localDataSource: LocalModelMetadataDataSource
    private let remoteDataSource: RemoteModelMetadataDataSource

    // MARK: - Initialization

    public init(databaseManager: DatabaseManager, apiClient: APIClient?) {
        self.databaseManager = databaseManager
        self.apiClient = apiClient
        self.localDataSource = LocalModelMetadataDataSource(databaseManager: databaseManager)
        self.remoteDataSource = RemoteModelMetadataDataSource(apiClient: apiClient)
    }

    // MARK: - Repository Implementation

    public func save(_ entity: ModelMetadataData) async throws {
        try await localDataSource.store(entity)
        logger.info("Model metadata saved: \(entity.id)")
    }

    public func fetch(id: String) async throws -> ModelMetadataData? {
        // Try local first
        if let local = try await localDataSource.load(id: id) {
            return local
        }

        // Try remote if not found locally
        if let remote = try await remoteDataSource.fetch(id: id) {
            // Cache it locally
            try await localDataSource.store(remote)
            return remote
        }

        return nil
    }

    public func fetchAll() async throws -> [ModelMetadataData] {
        return try await localDataSource.loadAll()
    }

    public func delete(id: String) async throws {
        try await localDataSource.remove(id: id)
        logger.info("Model metadata deleted: \(id)")
    }

    // MARK: - Sync Support (for Repository protocol)

    public func fetchPendingSync() async throws -> [ModelMetadataData] {
        return try await localDataSource.loadPendingSync()
    }

    private func markSynced(_ ids: [String]) async throws {
        try await localDataSource.markSynced(ids)
        logger.info("Marked \(ids.count) model metadata as synced")
    }

    // MARK: - Model-specific Operations

    /// Save model metadata from ModelInfo
    public func saveModelMetadata(_ model: ModelInfo) async throws {
        let metadata = ModelMetadataData(from: model)
        try await save(metadata)
    }

    /// Update last used date
    public func updateLastUsed(for modelId: String) async throws {
        guard var metadata = try await fetch(id: modelId) else {
            logger.warning("Model metadata not found: \(modelId)")
            return
        }

        // Create updated metadata
        let updatedMetadata = ModelMetadataData(
            id: metadata.id,
            name: metadata.name,
            format: metadata.format,
            framework: metadata.framework,
            localPath: metadata.localPath,
            memoryRequired: metadata.memoryRequired,
            contextLength: metadata.contextLength,
            downloadSize: metadata.downloadSize,
            author: metadata.author,
            license: metadata.license,
            description: metadata.description,
            tags: metadata.tags,
            createdAt: metadata.createdAt,
            downloadedAt: metadata.downloadedAt,
            lastUsed: Date(),
            usageCount: metadata.usageCount + 1,
            supportsThinking: metadata.supportsThinking,
            updatedAt: Date(),
            syncPending: true
        )

        try await save(updatedMetadata)
    }

    /// Update thinking support
    public func updateThinkingSupport(
        for modelId: String,
        supportsThinking: Bool
    ) async throws {
        guard var metadata = try await fetch(id: modelId) else {
            logger.warning("Model metadata not found: \(modelId)")
            return
        }

        // Create updated metadata
        let updatedMetadata = ModelMetadataData(
            id: metadata.id,
            name: metadata.name,
            format: metadata.format,
            framework: metadata.framework,
            localPath: metadata.localPath,
            memoryRequired: metadata.memoryRequired,
            contextLength: metadata.contextLength,
            downloadSize: metadata.downloadSize,
            author: metadata.author,
            license: metadata.license,
            description: metadata.description,
            tags: metadata.tags,
            createdAt: metadata.createdAt,
            downloadedAt: metadata.downloadedAt,
            lastUsed: metadata.lastUsed,
            usageCount: metadata.usageCount,
            supportsThinking: supportsThinking,
            updatedAt: Date(),
            syncPending: true
        )

        try await save(updatedMetadata)
    }

    /// Load stored models as ModelInfo array
    public func loadStoredModels() async throws -> [ModelInfo] {
        let allMetadata = try await fetchAll()
        let fileManager = ServiceContainer.shared.fileManager

        return allMetadata.compactMap { metadata in
            // Use the file manager to find the model file
            guard let modelURL = fileManager.findModelFile(modelId: metadata.id, expectedPath: metadata.localPath) else {
                logger.error("Model file not found for \(metadata.id)")
                return nil
            }

            let format = ModelFormat(rawValue: metadata.format) ?? .unknown
            let framework = LLMFramework(rawValue: metadata.framework)

            // Determine category based on framework
            let category = framework != nil ? ModelCategory.from(framework: framework!) : .language

            return ModelInfo(
                id: metadata.id,
                name: metadata.name,
                category: category,
                format: format,
                localPath: modelURL,
                memoryRequired: metadata.memoryRequired,
                contextLength: metadata.contextLength,
                downloadSize: metadata.downloadSize,
                compatibleFrameworks: framework != nil ? [framework!] : [],
                preferredFramework: framework,
                metadata: ModelInfoMetadata(
                    author: metadata.author,
                    license: metadata.license,
                    tags: metadata.tags,
                    description: metadata.description
                ),
                supportsThinking: metadata.supportsThinking
            )
        }
    }

    /// Load models for specific frameworks
    public func loadModelsForFrameworks(_ frameworks: [LLMFramework]) async throws -> [ModelInfo] {
        let allModels = try await loadStoredModels()
        return allModels.filter { model in
            model.compatibleFrameworks.contains { frameworks.contains($0) }
        }
    }

    // MARK: - ModelMetadataRepository Protocol Methods

    public func fetchByModelId(_ modelId: String) async throws -> ModelMetadataData? {
        // In this implementation, model ID is the same as the primary key
        return try await fetch(id: modelId)
    }

    public func fetchByFramework(_ framework: LLMFramework) async throws -> [ModelMetadataData] {
        return try databaseManager.read { db in
            try ModelMetadataData
                .filter(Column("framework") == framework.rawValue)
                .order(Column("updatedAt").desc)
                .fetchAll(db)
        }
    }

    public func fetchDownloaded() async throws -> [ModelMetadataData] {
        let data = try databaseManager.read { db in
            try ModelMetadataData
                .filter(Column("localPath") != "")
                .order(Column("updatedAt").desc)
                .fetchAll(db)
        }

        return data.filter { metadata in
            // Double-check file existence
            let fileExists = FileManager.default.fileExists(atPath: metadata.localPath)
            return fileExists
        }
    }

    public func updateDownloadStatus(_ modelId: String, isDownloaded: Bool) async throws {
        guard var metadata = try await fetch(id: modelId) else {
            logger.warning("Model metadata not found: \(modelId)")
            return
        }

        // Create updated metadata
        let updatedMetadata = ModelMetadataData(
            id: metadata.id,
            name: metadata.name,
            format: metadata.format,
            framework: metadata.framework,
            localPath: isDownloaded ? metadata.localPath : "",
            memoryRequired: metadata.memoryRequired,
            contextLength: metadata.contextLength,
            downloadSize: metadata.downloadSize,
            author: metadata.author,
            license: metadata.license,
            description: metadata.description,
            tags: metadata.tags,
            createdAt: metadata.createdAt,
            downloadedAt: isDownloaded ? Date() : metadata.downloadedAt,
            lastUsed: metadata.lastUsed,
            usageCount: metadata.usageCount,
            supportsThinking: metadata.supportsThinking,
            updatedAt: Date(),
            syncPending: true
        )

        try await save(updatedMetadata)
        logger.info("Updated download status for model \(modelId): \(isDownloaded)")
    }
}
