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
        let models = try await availableModels()
        guard let model = models.first(where: { $0.id == modelId }) else {
            throw SDKError.general(.modelNotFound, "Model not found: \(modelId)")
        }

        let task = try await Download.shared.downloadModel(model)
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
        let fileManager = RunAnywhere.serviceContainer.fileManager
        try fileManager.clearCache()
        EventPublisher.shared.track(StorageEvent.cacheCleared(freedBytes: 0))
    }

    /// Clean temporary files
    static func cleanTempFiles() async throws {
        let fileManager = RunAnywhere.serviceContainer.fileManager
        try fileManager.cleanTempFiles()
        EventPublisher.shared.track(StorageEvent.tempFilesCleaned(freedBytes: 0))
    }

    /// Delete a stored model
    /// - Parameters:
    ///   - modelId: The model identifier
    ///   - framework: The framework the model belongs to
    static func deleteStoredModel(_ modelId: String, framework: InferenceFramework) async throws {
        let fileManager = RunAnywhere.serviceContainer.fileManager
        try fileManager.deleteModel(modelId: modelId, framework: framework)
        EventPublisher.shared.track(ModelEvent.deleted(modelId: modelId))
    }

    /// Get base directory URL
    static func getBaseDirectoryURL() -> URL {
        let fileManager = RunAnywhere.serviceContainer.fileManager
        return fileManager.getBaseDirectoryURL()
    }

    /// Get all downloaded models
    static func getDownloadedModels() -> [InferenceFramework: [String]] {
        let fileManager = RunAnywhere.serviceContainer.fileManager
        return fileManager.getDownloadedModels()
    }

    /// Check if a model is downloaded
    @MainActor
    static func isModelDownloaded(_ modelId: String, framework: InferenceFramework) -> Bool {
        let fileManager = RunAnywhere.serviceContainer.fileManager
        return fileManager.isModelDownloaded(modelId: modelId, framework: framework)
    }
}
