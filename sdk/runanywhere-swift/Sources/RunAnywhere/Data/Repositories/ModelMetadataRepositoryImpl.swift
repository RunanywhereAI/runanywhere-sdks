import Foundation
import GRDB

/// Repository for managing model metadata - minimal implementation
public actor ModelMetadataRepositoryImpl: Repository, ModelMetadataRepository {
    public typealias Entity = ModelMetadataData

    private let databaseManager: DatabaseManager
    private let apiClient: APIClient?
    private let logger = SDKLogger(category: "ModelMetadataRepository")

    // MARK: - Initialization

    public init(databaseManager: DatabaseManager, apiClient: APIClient?) {
        self.databaseManager = databaseManager
        self.apiClient = apiClient
    }

    // MARK: - Repository Implementation

    public func save(_ entity: ModelMetadataData) async throws {
        var entityToSave = entity
        _ = entityToSave.markUpdated()

        try databaseManager.write { db in
            try entityToSave.save(db)
        }

        logger.info("Model metadata saved: \(entity.id)")
    }

    public func fetch(id: String) async throws -> ModelMetadataData? {
        return try databaseManager.read { db in
            try ModelMetadataData.fetchOne(db, key: id)
        }
    }

    public func fetchAll() async throws -> [ModelMetadataData] {
        let data = try databaseManager.read { db in
            try ModelMetadataData
                .order(Column("updatedAt").desc)
                .fetchAll(db)
        }

        logger.info("Found \(data.count) model metadata in database")
        return data
    }

    public func delete(id: String) async throws {
        try databaseManager.write { db in
            _ = try ModelMetadataData.deleteOne(db, key: id)
        }

        logger.info("Model metadata deleted: \(id)")
    }

    // MARK: - Sync Support (for Repository protocol)

    public func fetchPendingSync() async throws -> [ModelMetadataData] {
        return try databaseManager.read { db in
            try ModelMetadataData
                .filter(Column("syncPending") == true)
                .fetchAll(db)
        }
    }

    private func markSynced(_ ids: [String]) async throws {
        try databaseManager.write { db in
            for id in ids {
                if var data = try ModelMetadataData.fetchOne(db, key: id) {
                    _ = data.markSynced()
                    try data.update(db)
                }
            }
        }

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
            estimatedMemory: metadata.estimatedMemory,
            contextLength: metadata.contextLength,
            downloadSize: metadata.downloadSize,
            checksum: metadata.checksum,
            author: metadata.author,
            license: metadata.license,
            description: metadata.description,
            tags: metadata.tags,
            createdAt: metadata.createdAt,
            downloadedAt: metadata.downloadedAt,
            lastUsed: Date(),
            usageCount: metadata.usageCount + 1,
            supportsThinking: metadata.supportsThinking,
            thinkingOpenTag: metadata.thinkingOpenTag,
            thinkingCloseTag: metadata.thinkingCloseTag,
            updatedAt: Date(),
            syncPending: true
        )

        try await save(updatedMetadata)
    }

    /// Update thinking support
    public func updateThinkingSupport(
        for modelId: String,
        supportsThinking: Bool,
        thinkingTagPattern: ThinkingTagPattern?
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
            estimatedMemory: metadata.estimatedMemory,
            contextLength: metadata.contextLength,
            downloadSize: metadata.downloadSize,
            checksum: metadata.checksum,
            author: metadata.author,
            license: metadata.license,
            description: metadata.description,
            tags: metadata.tags,
            createdAt: metadata.createdAt,
            downloadedAt: metadata.downloadedAt,
            lastUsed: metadata.lastUsed,
            usageCount: metadata.usageCount,
            supportsThinking: supportsThinking,
            thinkingOpenTag: thinkingTagPattern?.openingTag,
            thinkingCloseTag: thinkingTagPattern?.closingTag,
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

            // Reconstruct thinking tag pattern
            let thinkingTagPattern: ThinkingTagPattern? = {
                if metadata.supportsThinking,
                   let openTag = metadata.thinkingOpenTag,
                   let closeTag = metadata.thinkingCloseTag {
                    return ThinkingTagPattern(openingTag: openTag, closingTag: closeTag)
                }
                return metadata.supportsThinking ? ThinkingTagPattern.defaultPattern : nil
            }()

            return ModelInfo(
                id: metadata.id,
                name: metadata.name,
                format: format,
                localPath: modelURL,
                estimatedMemory: metadata.estimatedMemory,
                contextLength: metadata.contextLength,
                downloadSize: metadata.downloadSize,
                checksum: metadata.checksum,
                compatibleFrameworks: framework != nil ? [framework!] : [],
                preferredFramework: framework,
                metadata: ModelInfoMetadata(
                    author: metadata.author,
                    license: metadata.license,
                    tags: metadata.tags,
                    description: metadata.description
                ),
                supportsThinking: metadata.supportsThinking,
                thinkingTagPattern: thinkingTagPattern
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
            estimatedMemory: metadata.estimatedMemory,
            contextLength: metadata.contextLength,
            downloadSize: metadata.downloadSize,
            checksum: metadata.checksum,
            author: metadata.author,
            license: metadata.license,
            description: metadata.description,
            tags: metadata.tags,
            createdAt: metadata.createdAt,
            downloadedAt: isDownloaded ? Date() : metadata.downloadedAt,
            lastUsed: metadata.lastUsed,
            usageCount: metadata.usageCount,
            supportsThinking: metadata.supportsThinking,
            thinkingOpenTag: metadata.thinkingOpenTag,
            thinkingCloseTag: metadata.thinkingCloseTag,
            updatedAt: Date(),
            syncPending: true
        )

        try await save(updatedMetadata)
        logger.info("Updated download status for model \(modelId): \(isDownloaded)")
    }
}
