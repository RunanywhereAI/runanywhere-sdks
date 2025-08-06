import Foundation
import GRDB

/// Repository for managing model metadata
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
        let record = try mapToRecord(entity)

        try databaseManager.write { db in
            try record.save(db)
        }

        logger.info("Model metadata saved: \(entity.id)")
    }

    public func fetch(id: String) async throws -> ModelMetadataData? {
        let record = try databaseManager.read { db in
            try ModelMetadataRecord.fetchOne(db, key: id)
        }

        return try record.map { try mapToEntity($0) }
    }

    public func fetchAll() async throws -> [ModelMetadataData] {
        let records = try databaseManager.read { db in
            try ModelMetadataRecord
                .order(ModelMetadataRecord.Columns.updatedAt.desc)
                .fetchAll(db)
        }

        logger.info("Found \(records.count) model metadata in database")

        return try records.map { try mapToEntity($0) }
    }

    public func delete(id: String) async throws {
        try databaseManager.write { db in
            _ = try ModelMetadataRecord.deleteOne(db, key: id)
        }

        logger.info("Model metadata deleted: \(id)")
    }

    public func fetchPendingSync() async throws -> [ModelMetadataData] {
        let records = try databaseManager.read { db in
            try ModelMetadataRecord
                .filter(ModelMetadataRecord.Columns.syncPending == true)
                .fetchAll(db)
        }

        return try records.map { try mapToEntity($0) }
    }

    public func markSynced(_ ids: [String]) async throws {
        try databaseManager.write { db in
            for id in ids {
                if var record = try ModelMetadataRecord.fetchOne(db, key: id) {
                    record.syncPending = false
                    record.updatedAt = Date()
                    try record.update(db)
                }
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

    // MARK: - ModelMetadataRepository Protocol Methods

    public func fetchByModelId(_ modelId: String) async throws -> ModelMetadataData? {
        // In this implementation, model ID is the same as the primary key
        return try await fetch(id: modelId)
    }

    public func fetchByFramework(_ framework: LLMFramework) async throws -> [ModelMetadataData] {
        let records = try databaseManager.read { db in
            try ModelMetadataRecord
                .filter(ModelMetadataRecord.Columns.framework == framework.rawValue)
                .order(ModelMetadataRecord.Columns.updatedAt.desc)
                .fetchAll(db)
        }

        return try records.map { try mapToEntity($0) }
    }

    public func fetchDownloaded() async throws -> [ModelMetadataData] {
        let records = try databaseManager.read { db in
            try ModelMetadataRecord
                .filter(ModelMetadataRecord.Columns.isDownloaded == true)
                .order(ModelMetadataRecord.Columns.updatedAt.desc)
                .fetchAll(db)
        }

        return try records.compactMap { record in
            let metadata = try mapToEntity(record)
            // Double-check file existence
            let fileExists = FileManager.default.fileExists(atPath: metadata.localPath)
            return fileExists ? metadata : nil
        }
    }

    public func updateDownloadStatus(_ modelId: String, isDownloaded: Bool) async throws {
        guard var record = try databaseManager.read({ db in
            try ModelMetadataRecord.fetchOne(db, key: modelId)
        }) else {
            logger.warning("Model metadata not found: \(modelId)")
            return
        }

        try databaseManager.write { db in
            record.isDownloaded = isDownloaded
            record.downloadDate = isDownloaded ? Date() : nil
            if !isDownloaded {
                record.localPath = nil
            }
            record.updatedAt = Date()
            record.syncPending = true
            try record.update(db)
        }

        logger.info("Updated download status for model \(modelId): \(isDownloaded)")
    }

    // MARK: - Mapping Functions

    private func mapToRecord(_ entity: ModelMetadataData) throws -> ModelMetadataRecord {
        // Create capabilities JSON
        let capabilities: [String: Any] = [
            "contextLength": entity.contextLength,
            "supportsThinking": entity.supportsThinking,
            "thinkingOpenTag": entity.thinkingOpenTag as Any,
            "thinkingCloseTag": entity.thinkingCloseTag as Any,
            "author": entity.author as Any,
            "license": entity.license as Any,
            "description": entity.description as Any,
            "tags": entity.tags
        ]

        let capabilitiesData = try JSONSerialization.data(withJSONObject: capabilities)

        return ModelMetadataRecord(
            id: entity.id,
            name: entity.name,
            format: entity.format,
            framework: entity.framework,
            sizeBytes: entity.estimatedMemory,
            quantization: nil, // Could be extracted from name or stored separately
            version: SDKConstants.DatabaseDefaults.modelVersion,
            sha256Hash: entity.checksum,
            capabilities: capabilitiesData,
            requirements: nil, // Could be added later
            downloadURL: nil, // Not stored in entity
            localPath: entity.localPath.isEmpty ? nil : entity.localPath,
            isDownloaded: !entity.localPath.isEmpty && entity.downloadedAt != Date(timeIntervalSince1970: 0),
            downloadDate: entity.downloadedAt == Date(timeIntervalSince1970: 0) ? nil : entity.downloadedAt,
            lastUsedAt: entity.lastUsed,
            useCount: entity.usageCount,
            totalTokensGenerated: 0, // Not tracked in entity
            createdAt: entity.downloadedAt, // Use download date as created date
            updatedAt: entity.updatedAt,
            syncPending: entity.syncPending
        )
    }

    private func mapToEntity(_ record: ModelMetadataRecord) throws -> ModelMetadataData {
        // Parse capabilities JSON
        var contextLength = SDKConstants.ModelDefaults.defaultContextLength
        var supportsThinking = false
        var thinkingOpenTag: String?
        var thinkingCloseTag: String?
        var author: String?
        var license: String?
        var description: String?
        var tags: [String] = []

        if let capabilities = try? JSONSerialization.jsonObject(with: record.capabilities) as? [String: Any] {
            contextLength = capabilities["contextLength"] as? Int ?? SDKConstants.ModelDefaults.defaultContextLength
            supportsThinking = capabilities["supportsThinking"] as? Bool ?? false
            thinkingOpenTag = capabilities["thinkingOpenTag"] as? String
            thinkingCloseTag = capabilities["thinkingCloseTag"] as? String
            author = capabilities["author"] as? String
            license = capabilities["license"] as? String
            description = capabilities["description"] as? String
            tags = capabilities["tags"] as? [String] ?? []
        }

        return ModelMetadataData(
            id: record.id,
            name: record.name,
            format: record.format,
            framework: record.framework,
            localPath: record.localPath ?? "",
            estimatedMemory: record.sizeBytes,
            contextLength: contextLength,
            downloadSize: nil, // Could be stored in capabilities
            checksum: record.sha256Hash,
            author: author,
            license: license,
            description: description,
            tags: tags,
            downloadedAt: record.downloadDate ?? Date(timeIntervalSince1970: 0),
            lastUsed: record.lastUsedAt,
            usageCount: record.useCount,
            supportsThinking: supportsThinking,
            thinkingOpenTag: thinkingOpenTag,
            thinkingCloseTag: thinkingCloseTag,
            updatedAt: record.updatedAt,
            syncPending: record.syncPending
        )
    }
}
