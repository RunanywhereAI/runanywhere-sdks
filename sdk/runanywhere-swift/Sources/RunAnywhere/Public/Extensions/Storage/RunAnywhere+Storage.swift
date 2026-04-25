//
//  RunAnywhere+Storage.swift
//  RunAnywhere SDK
//
//  Public API for storage and download operations.
//

import Foundation

// MARK: - Model Download API

public extension RunAnywhere {

    /// Download a model by ID with progress tracking
    ///
    /// ```swift
    /// for await progress in try await RunAnywhere.downloadModel("my-model-id") {
    ///     print("Progress: \(Int(progress.overallProgress * 100))%")
    /// }
    /// ```
    static func downloadModel(_ modelId: String) async throws -> AsyncStream<DownloadProgress> {
        let logger = SDKLogger(category: "RunAnywhere.Download")
        let models = try await availableModels()
        logger.info("Available models count: \(models.count)")
        for candidate in models where candidate.id == modelId {
            logger.info("Found model \(candidate.id) with framework: \(candidate.framework.wireString) (\(candidate.framework.displayName))")
        }
        guard let model = models.first(where: { $0.id == modelId }) else {
            throw SDKError.general(.modelNotFound, "Model not found: \(modelId)")
        }

        let task = try await DownloadAdapter.shared.downloadModel(model)
        return task.progress
    }

    /// Download a model with a completion handler
    static func downloadModel(
        _ modelId: String,
        progressHandler: @escaping (Double) -> Void
    ) async throws {
        let progressStream = try await downloadModel(modelId)

        for await progress in progressStream {
            progressHandler(progress.overallProgress)
            if progress.stage == .completed {
                break
            }
        }
    }

    /// Cancel an active model download.
    static func cancelDownload(_ modelId: String) {
        DownloadAdapter.shared.cancelDownload(taskId: modelId)
    }
}

// MARK: - Storage Extensions

public extension RunAnywhere {

    /// Get storage information
    /// Business logic is in C++ via CppBridge.Storage
    static func getStorageInfo() async -> StorageInfo {
        return await CppBridge.Storage.shared.analyzeStorage()
    }

    /// Check if storage is available for a model download
    static func checkStorageAvailable(for modelSize: Int64, safetyMargin: Double = 0.1) -> StorageAvailability {
        return CppBridge.Storage.shared.checkStorageAvailable(modelSize: modelSize, safetyMargin: safetyMargin)
    }

    /// Get storage metrics for a specific model
    static func getModelStorageMetrics(modelId: String, framework: InferenceFramework) async -> ModelStorageMetrics? {
        return await CppBridge.Storage.shared.getModelStorageMetrics(modelId: modelId, framework: framework)
    }

    /// Clear cache
    static func clearCache() async throws {
        try SimplifiedFileManager.shared.clearCache()
        // Emit via C++ event system
        CppBridge.Events.emitStorageCacheCleared(freedBytes: 0)
    }

    /// Clean temporary files
    static func cleanTempFiles() async throws {
        try SimplifiedFileManager.shared.cleanTempFiles()
        // Emit via C++ event system
        CppBridge.Events.emitStorageTempCleaned(freedBytes: 0)
    }

    /// Delete a stored model
    /// - Parameters:
    ///   - modelId: The model identifier
    ///   - framework: The framework the model belongs to
    static func deleteStoredModel(_ modelId: String, framework: InferenceFramework) async throws {
        try SimplifiedFileManager.shared.deleteModel(modelId: modelId, framework: framework)
        // Mark the model as not downloaded (localPath: nil)
        try await CppBridge.ModelRegistry.shared.updateDownloadStatus(modelId: modelId, localPath: nil)
        // Emit via C++ event system
        CppBridge.Events.emitModelDeleted(modelId: modelId)
    }

    /// Delete a stored model by ID while preserving its registry entry.
    static func deleteModel(_ modelId: String) async throws {
        let models = try await availableModels()
        guard let model = models.first(where: { $0.id == modelId }) else {
            throw SDKError.general(.modelNotFound, "Model not found: \(modelId)")
        }
        try await deleteStoredModel(modelId, framework: model.framework)
    }

    /// Delete all downloaded models while keeping catalog entries registered.
    static func deleteAllModels() async throws {
        let models = try await availableModels()
        for model in models where model.localPath != nil {
            try await deleteStoredModel(model.id, framework: model.framework)
        }
    }

    /// Get base directory URL
    static func getBaseDirectoryURL() -> URL {
        SimplifiedFileManager.shared.getBaseDirectoryURL()
    }

    /// Get all downloaded models
    static func getDownloadedModels() -> [InferenceFramework: [String]] {
        SimplifiedFileManager.shared.getDownloadedModels()
    }

    /// Check if a model is downloaded
    @MainActor
    static func isModelDownloaded(_ modelId: String, framework: InferenceFramework) -> Bool {
        SimplifiedFileManager.shared.isModelDownloaded(modelId: modelId, framework: framework)
    }
}
