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
            throw SDKException.general(.modelNotFound, "Model not found: \(modelId)")
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

    /// Build a native download plan using canonical generated proto data.
    static func downloadPlan(_ request: RADownloadPlanRequest) async -> RADownloadPlanResult {
        await CppBridge.Download.shared.plan(request)
    }

    /// Start a native download workflow using canonical generated proto data.
    static func startDownload(_ request: RADownloadStartRequest) async -> RADownloadStartResult {
        await CppBridge.Download.shared.start(request)
    }

    /// Cancel a native download workflow using canonical generated proto data.
    static func cancelDownload(_ request: RADownloadCancelRequest) async -> RADownloadCancelResult {
        await CppBridge.Download.shared.cancel(request)
    }

    /// Resume a native download workflow using canonical generated proto data.
    static func resumeDownload(_ request: RADownloadResumeRequest) async -> RADownloadResumeResult {
        await CppBridge.Download.shared.resume(request)
    }

    /// Poll the latest native download progress as canonical generated proto data.
    static func pollDownloadProgress(_ request: RADownloadSubscribeRequest) async -> RADownloadProgress {
        await CppBridge.Download.shared.pollProgress(request)
    }

    /// Subscribe to native download progress proto events.
    static func downloadProgressEvents() -> AsyncStream<RADownloadProgress> {
        CppBridge.Download.shared.progressEvents()
    }
}

// MARK: - Storage Extensions

public extension RunAnywhere {

    /// Get storage information
    /// Business logic is in C++ via CppBridge.Storage
    static func getStorageInfo() async -> StorageInfo {
        var request = RAStorageInfoRequest()
        request.includeApp = true
        request.includeDevice = true
        request.includeModels = true
        return await getStorageInfo(request).info
    }

    /// Get storage information as the canonical generated proto result.
    static func getStorageInfo(_ request: RAStorageInfoRequest) async -> RAStorageInfoResult {
        await CppBridge.Storage.shared.info(request)
    }

    /// Check if storage is available for a model download
    static func checkStorageAvailable(for modelSize: Int64, safetyMargin: Double = 0.1) -> StorageAvailability {
        return CppBridge.Storage.shared.checkStorageAvailable(modelSize: modelSize, safetyMargin: safetyMargin)
    }

    /// Check storage availability as the canonical generated proto result.
    static func checkStorageAvailability(
        _ request: RAStorageAvailabilityRequest
    ) async -> RAStorageAvailabilityResult {
        await CppBridge.Storage.shared.availability(request)
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
        var request = RAStorageDeleteRequest()
        request.modelIds = [modelId]
        request.deleteFiles = true
        request.clearRegistryPaths_p = true
        request.unloadIfLoaded = true

        let result = await CppBridge.Storage.shared.delete(request)
        guard result.success else {
            try SimplifiedFileManager.shared.deleteModel(modelId: modelId, framework: framework)
            try await CppBridge.ModelRegistry.shared.updateDownloadStatus(modelId: modelId, localPath: nil)
            CppBridge.Events.emitModelDeleted(modelId: modelId)
            return
        }
        CppBridge.Events.emitModelDeleted(modelId: modelId)
    }

    /// Delete a stored model by ID while preserving its registry entry.
    static func deleteModel(_ modelId: String) async throws {
        var request = RAStorageDeleteRequest()
        request.modelIds = [modelId]
        request.deleteFiles = true
        request.clearRegistryPaths_p = true
        request.unloadIfLoaded = true
        let result = await deleteStorage(request)
        guard result.success else {
            throw SDKException.general(.modelNotFound, "Model not found: \(modelId)")
        }
    }

    /// Delete all downloaded models while keeping catalog entries registered.
    static func deleteAllModels() async throws {
        var request = RAStorageDeleteRequest()
        request.deleteFiles = true
        request.clearRegistryPaths_p = true
        request.unloadIfLoaded = true
        let result = await deleteStorage(request)
        guard result.success else {
            throw SDKException.general(.processingFailed, result.errorMessage)
        }
    }

    /// Build a storage delete plan as canonical generated proto data.
    static func planStorageDelete(_ request: RAStorageDeletePlanRequest) async -> RAStorageDeletePlan {
        await CppBridge.Storage.shared.deletePlan(request)
    }

    /// Execute or dry-run storage deletion as canonical generated proto data.
    static func deleteStorage(_ request: RAStorageDeleteRequest) async -> RAStorageDeleteResult {
        await CppBridge.Storage.shared.delete(request)
    }

    /// Get base directory URL
    static func getBaseDirectoryURL() -> URL {
        SimplifiedFileManager.shared.getBaseDirectoryURL()
    }

    /// Get all downloaded models
    static func getDownloadedModels() async -> [InferenceFramework: [String]] {
        await SimplifiedFileManager.shared.getDownloadedModels()
    }

    /// Check if a model is downloaded
    @MainActor
    static func isModelDownloaded(_ modelId: String, framework: InferenceFramework) -> Bool {
        SimplifiedFileManager.shared.isModelDownloaded(modelId: modelId, framework: framework)
    }
}
