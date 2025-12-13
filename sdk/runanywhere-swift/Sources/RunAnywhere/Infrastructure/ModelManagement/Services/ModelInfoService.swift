//
//  ModelInfoService.swift
//  RunAnywhere SDK
//
//  Service layer for model information management
//

import Foundation

/// Service for managing model information
public actor ModelInfoService {
    private let logger = SDKLogger(category: "ModelInfoService")
    private let modelInfoRepository: any ModelInfoRepository
    private let syncCoordinator: SyncCoordinator?

    /// Public access to the repository for advanced operations (like mock data population)
    public var repository: any ModelInfoRepository {
        return modelInfoRepository
    }

    // MARK: - Initialization

    public init(modelInfoRepository: any ModelInfoRepository, syncCoordinator: SyncCoordinator?) {
        self.modelInfoRepository = modelInfoRepository
        self.syncCoordinator = syncCoordinator
        logger.info("ModelInfoService initialized")
    }

    // MARK: - Public Methods

    /// Save model metadata
    public func saveModel(_ model: ModelInfo) async throws {
        try await modelInfoRepository.save(model)
        logger.info("Model metadata saved: \(model.id)")
    }

    /// Get model metadata by ID
    public func getModel(by modelId: String) async throws -> ModelInfo? {
        return try await modelInfoRepository.fetch(id: modelId)
    }

    /// Load all stored models
    public func loadStoredModels() async throws -> [ModelInfo] {
        return try await modelInfoRepository.fetchAll()
    }

    /// Load models for specific frameworks
    public func loadModels(for frameworks: [InferenceFramework]) async throws -> [ModelInfo] {
        var models: [ModelInfo] = []
        for framework in frameworks {
            let frameworkModels = try await modelInfoRepository.fetchByFramework(framework)
            models.append(contentsOf: frameworkModels)
        }
        // Remove duplicates based on model ID
        let uniqueModels = Array(Set(models))
        return uniqueModels
    }

    /// Update model last used date
    public func updateLastUsed(for modelId: String) async throws {
        try await modelInfoRepository.updateLastUsed(for: modelId)
        logger.debug("Updated last used date for model: \(modelId)")
    }

    /// Remove model metadata
    public func removeModel(_ modelId: String) async throws {
        try await modelInfoRepository.delete(id: modelId)
        logger.info("Removed model metadata: \(modelId)")
    }

    /// Get downloaded models
    public func getDownloadedModels() async throws -> [ModelInfo] {
        return try await modelInfoRepository.fetchDownloaded()
    }

    /// Update download status
    public func updateDownloadStatus(
        _ modelId: String,
        isDownloaded: Bool,
        localPath: URL? = nil
    ) async throws {
        try await modelInfoRepository.updateDownloadStatus(modelId, localPath: localPath)
        logger.info("Updated download status for model \(modelId): \(isDownloaded)")
    }

    /// Get models by framework
    public func getModels(for framework: InferenceFramework) async throws -> [ModelInfo] {
        return try await modelInfoRepository.fetchByFramework(framework)
    }

    /// Get models by category
    public func getModels(for category: ModelCategory) async throws -> [ModelInfo] {
        return try await modelInfoRepository.fetchByCategory(category)
    }

    /// Force sync model information
    public func syncModelInfo() async throws {
        if let syncCoordinator = syncCoordinator,
           let repository = modelInfoRepository as? ModelInfoRepositoryImpl {
            try await syncCoordinator.sync(repository)
            logger.info("Model info sync completed")
        } else {
            logger.debug("Sync not available for model info")
        }
    }

    /// Clear all model metadata
    public func clearAllModels() async throws {
        let models = try await modelInfoRepository.fetchAll()
        for model in models {
            try await modelInfoRepository.delete(id: model.id)
        }
        logger.info("Cleared all model metadata")
    }
}

// MARK: - ModelInfo Hashable

extension ModelInfo: Hashable {
    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    public static func == (lhs: ModelInfo, rhs: ModelInfo) -> Bool {
        return lhs.id == rhs.id
    }
}
