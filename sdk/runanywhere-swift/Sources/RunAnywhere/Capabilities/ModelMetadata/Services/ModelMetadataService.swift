//
//  ModelMetadataService.swift
//  RunAnywhere SDK
//
//  Service layer for model metadata management
//

import Foundation

/// Service for managing model metadata
public actor ModelMetadataService {
    private let logger = SDKLogger(category: "ModelMetadataService")
    private let modelMetadataRepository: any ModelMetadataRepository
    private let syncCoordinator: SyncCoordinator?

    // MARK: - Initialization

    public init(modelMetadataRepository: any ModelMetadataRepository, syncCoordinator: SyncCoordinator?) {
        self.modelMetadataRepository = modelMetadataRepository
        self.syncCoordinator = syncCoordinator
        logger.info("ModelMetadataService initialized")
    }

    // MARK: - Public Methods

    /// Save model metadata
    public func saveModel(_ model: ModelInfo) async throws {
        try await modelMetadataRepository.saveModelMetadata(model)
        logger.info("Model metadata saved: \(model.id)")
    }

    /// Get model metadata by ID
    public func getModel(by modelId: String) async throws -> ModelMetadataData? {
        return try await modelMetadataRepository.fetchByModelId(modelId)
    }

    /// Load all stored models
    public func loadStoredModels() async throws -> [ModelInfo] {
        return try await modelMetadataRepository.loadStoredModels()
    }

    /// Load models for specific frameworks
    public func loadModels(for frameworks: [LLMFramework]) async throws -> [ModelInfo] {
        // Load all models and filter by framework
        let allModels = try await modelMetadataRepository.loadStoredModels()
        return allModels.filter { model in
            model.compatibleFrameworks.contains { frameworks.contains($0) }
        }
    }

    /// Update model last used date
    public func updateLastUsed(for modelId: String) async throws {
        try await modelMetadataRepository.updateLastUsed(for: modelId)
        logger.debug("Updated last used date for model: \(modelId)")
    }

    /// Update thinking support for a model
    public func updateThinkingSupport(
        for modelId: String,
        supportsThinking: Bool,
        thinkingTagPattern: ThinkingTagPattern?
    ) async throws {
        try await modelMetadataRepository.updateThinkingSupport(
            for: modelId,
            supportsThinking: supportsThinking,
            thinkingTagPattern: thinkingTagPattern
        )
        logger.info("Updated thinking support for model: \(modelId)")
    }

    /// Remove model metadata
    public func removeModel(_ modelId: String) async throws {
        try await modelMetadataRepository.delete(id: modelId)
        logger.info("Removed model metadata: \(modelId)")
    }

    /// Get downloaded models
    public func getDownloadedModels() async throws -> [ModelMetadataData] {
        return try await modelMetadataRepository.fetchDownloaded()
    }

    /// Update download status
    public func updateDownloadStatus(
        _ modelId: String,
        isDownloaded: Bool
    ) async throws {
        try await modelMetadataRepository.updateDownloadStatus(modelId, isDownloaded: isDownloaded)
        logger.info("Updated download status for model \(modelId): \(isDownloaded)")
    }

    /// Get models by framework
    public func getModels(for framework: LLMFramework) async throws -> [ModelMetadataData] {
        return try await modelMetadataRepository.fetchByFramework(framework)
    }

    /// Force sync model metadata
    public func syncModelMetadata() async throws {
        if let syncCoordinator = syncCoordinator,
           let repository = modelMetadataRepository as? ModelMetadataRepositoryImpl {
            try await syncCoordinator.sync(repository)
            logger.info("Model metadata sync triggered")
        }
    }

    // MARK: - Analytics Integration

    /// Track model usage
    public func trackModelUsage(
        modelId: String,
        tokensGenerated: Int,
        duration: TimeInterval
    ) async throws {
        // Update usage statistics
        try await updateLastUsed(for: modelId)

        // Could also update token count if we add that field
        logger.debug("Tracked usage for model \(modelId): \(tokensGenerated) tokens in \(duration)s")
    }

    // MARK: - Helpers

    /// Check if model exists locally
    public func isModelDownloaded(_ modelId: String) async -> Bool {
        guard let metadata = try? await getModel(by: modelId) else {
            return false
        }

        // Check if model has a local path and it exists
        if !metadata.localPath.isEmpty {
            return FileManager.default.fileExists(atPath: metadata.localPath)
        }

        return false
    }

    /// Get total storage used by models
    public func getTotalModelStorage() async throws -> Int64 {
        let downloadedModels = try await getDownloadedModels()

        var totalSize: Int64 = 0
        for model in downloadedModels {
            if !model.localPath.isEmpty,
               let attributes = try? FileManager.default.attributesOfItem(atPath: model.localPath),
               let fileSize = attributes[.size] as? NSNumber {
                totalSize += fileSize.int64Value
            }
        }

        return totalSize
    }
}
