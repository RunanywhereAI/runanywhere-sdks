//
//  ModelInfoService.swift
//  RunAnywhere SDK
//
//  Service layer for model information management (in-memory)
//

import Foundation

/// Service for managing model information (in-memory storage)
public actor ModelInfoService {
    private let logger = SDKLogger(category: "ModelInfoService")

    /// In-memory storage for model metadata
    private var models: [String: ModelInfo] = [:]

    // MARK: - Initialization

    public init() {
        logger.info("ModelInfoService initialized (in-memory)")
    }

    // MARK: - Public Methods

    /// Save model metadata
    public func saveModel(_ model: ModelInfo) async throws {
        models[model.id] = model
        logger.debug("Model saved: \(model.id)")
    }

    /// Get model metadata by ID
    public func getModel(by modelId: String) async throws -> ModelInfo? {
        return models[modelId]
    }

    /// Load all stored models
    public func loadStoredModels() async throws -> [ModelInfo] {
        return Array(models.values)
    }

    /// Load models for specific frameworks
    public func loadModels(for frameworks: [InferenceFramework]) async throws -> [ModelInfo] {
        return models.values.filter { frameworks.contains($0.framework) }
    }

    /// Update model timestamp (called when model is used)
    public func updateModelTimestamp(for modelId: String) async throws {
        guard var model = models[modelId] else { return }
        model.updatedAt = Date()
        models[modelId] = model
        logger.debug("Updated timestamp for model: \(modelId)")
    }

    /// Remove model metadata
    public func removeModel(_ modelId: String) async throws {
        models.removeValue(forKey: modelId)
        logger.debug("Removed model: \(modelId)")
    }

    /// Get downloaded models
    public func getDownloadedModels() async throws -> [ModelInfo] {
        return models.values.filter { $0.isDownloaded }
    }

    /// Update download status
    public func updateDownloadStatus(
        _ modelId: String,
        isDownloaded: Bool,
        localPath: URL? = nil
    ) async throws {
        guard var model = models[modelId] else { return }
        model.localPath = localPath
        model.updatedAt = Date()
        models[modelId] = model
        logger.debug("Updated download status for model \(modelId): \(isDownloaded)")
    }

    /// Get models by framework
    public func getModels(for framework: InferenceFramework) async throws -> [ModelInfo] {
        return models.values.filter { $0.framework == framework }
    }

    /// Get models by category
    public func getModels(for category: ModelCategory) async throws -> [ModelInfo] {
        return models.values.filter { $0.category == category }
    }

    /// Sync model information - models are fetched via ModelAssignmentService
    /// This method exists for API compatibility
    public func syncModelInfo() async throws {
        // Model fetching is handled by ModelAssignmentService.fetchModelAssignments()
        // This method is kept for API compatibility
        logger.debug("syncModelInfo called - models are managed via ModelAssignmentService")
    }

    /// Clear all model metadata
    public func clearAllModels() async throws {
        models.removeAll()
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
