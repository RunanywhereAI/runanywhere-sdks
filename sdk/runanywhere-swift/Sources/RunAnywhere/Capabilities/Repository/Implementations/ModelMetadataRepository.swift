import Foundation

/// Repository for managing model metadata
public actor ModelMetadataRepository: Repository {
    public typealias Entity = ModelMetadataData

    private let database: DatabaseCore
    private let apiClient: APIClient?
    private let logger = SDKLogger(category: "ModelMetadataRepository")
    private let tableName = "model_metadata"

    // MARK: - Initialization

    public init(database: DatabaseCore, apiClient: APIClient?) {
        self.database = database
        self.apiClient = apiClient
    }

    // MARK: - Repository Implementation

    public func save(_ entity: ModelMetadataData) async throws {
        let data = try JSONEncoder().encode(entity)
        let json = String(data: data, encoding: .utf8) ?? "{}"

        try await database.execute("""
            INSERT OR REPLACE INTO \(tableName) (id, data, updated_at, sync_pending)
            VALUES (?, ?, ?, ?)
        """, parameters: [entity.id, json, entity.updatedAt, entity.syncPending ? 1 : 0])

        logger.info("Model metadata saved: \(entity.id)")
    }

    public func fetch(id: String) async throws -> ModelMetadataData? {
        let results = try await database.query("""
            SELECT data FROM \(tableName) WHERE id = ?
        """, parameters: [id])

        guard let row = results.first,
              let json = row["data"] as? String,
              let data = json.data(using: .utf8) else {
            return nil
        }

        return try JSONDecoder().decode(ModelMetadataData.self, from: data)
    }

    public func fetchAll() async throws -> [ModelMetadataData] {
        let results = try await database.query("""
            SELECT data FROM \(tableName) ORDER BY updated_at DESC
        """, parameters: [])

        return results.compactMap { row in
            guard let json = row["data"] as? String,
                  let data = json.data(using: .utf8) else {
                return nil
            }

            return try? JSONDecoder().decode(ModelMetadataData.self, from: data)
        }
    }

    public func delete(id: String) async throws {
        try await database.execute("""
            DELETE FROM \(tableName) WHERE id = ?
        """, parameters: [id])

        logger.info("Model metadata deleted: \(id)")
    }

    public func fetchPendingSync() async throws -> [ModelMetadataData] {
        let results = try await database.query("""
            SELECT data FROM \(tableName) WHERE sync_pending = 1
        """, parameters: [])

        return results.compactMap { row in
            guard let json = row["data"] as? String,
                  let data = json.data(using: .utf8) else {
                return nil
            }

            return try? JSONDecoder().decode(ModelMetadataData.self, from: data)
        }
    }

    public func markSynced(_ ids: [String]) async throws {
        try await database.transaction { db in
            for id in ids {
                try await db.execute("""
                    UPDATE \(self.tableName) SET sync_pending = 0 WHERE id = ?
                """, parameters: [id])
            }
        }

        logger.info("Marked \(ids.count) model metadata as synced")
    }

    public func sync() async throws {
        guard let apiClient = apiClient else {
            logger.warning("API client not available for sync")
            return
        }

        let pending = try await fetchPendingSync()
        guard !pending.isEmpty else {
            return
        }

        logger.info("Syncing \(pending.count) model metadata")

        // For v1, implement basic sync
        struct ModelMetadataSyncRequest: Codable {
            let models: [ModelMetadataData]
        }

        struct ModelMetadataSyncResponse: Codable {
            let syncedIds: [String]
        }

        do {
            let request = ModelMetadataSyncRequest(models: pending)
            let response: ModelMetadataSyncResponse = try await apiClient.post(.syncModelMetadata, request)
            try await markSynced(response.syncedIds)
            logger.info("Model metadata sync completed")
        } catch {
            logger.error("Model metadata sync failed: \(error)")
            throw RepositoryError.syncFailure("Model metadata sync failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Model-specific Operations

    /// Save model metadata from ModelInfo
    public func saveModelMetadata(_ model: ModelInfo) async throws {
        let metadata = ModelMetadataData(from: model)
        try await save(metadata)

        // Trigger sync for important model metadata
        Task {
            try? await sync()
        }
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

        return allMetadata.compactMap { metadata in
            // Check if file exists
            let localURL = URL(fileURLWithPath: metadata.localPath)
            guard FileManager.default.fileExists(atPath: localURL.path) else {
                logger.warning("Model file missing for \(metadata.id), removing metadata")
                Task {
                    try? await delete(id: metadata.id)
                }
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
                localPath: localURL,
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
}
