//
//  RunAnywhere+Storage.swift
//  RunAnywhere SDK
//
//  Public API for storage and download operations.
//  Events are tracked via EventPublisher.
//

import Foundation

// MARK: - Model Download API

public extension RunAnywhere {

    /// Download a model by ID with progress tracking
    ///
    /// Convenience method that looks up the model and downloads it.
    ///
    /// Example:
    /// ```swift
    /// for await progress in try await RunAnywhere.downloadModel("my-model-id") {
    ///     print("Progress: \(Int(progress.overallProgress * 100))%")
    /// }
    /// ```
    ///
    /// - Parameter modelId: The model identifier to download
    /// - Returns: AsyncStream of download progress updates
    /// - Throws: RunAnywhereError.modelNotFound if model ID doesn't exist
    static func downloadModel(_ modelId: String) async throws -> AsyncStream<DownloadProgress> {
        let models = try await availableModels()
        guard let model = models.first(where: { $0.id == modelId }) else {
            throw RunAnywhereError.modelNotFound(modelId)
        }

        let task = try await Download.shared.downloadModel(model)
        return task.progress
    }

    /// Download a model with a completion handler
    ///
    /// - Parameters:
    ///   - modelId: The model identifier to download
    ///   - progressHandler: Called with progress updates (0.0 to 1.0)
    /// - Throws: RunAnywhereError.modelNotFound if model ID doesn't exist
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
    static func getStorageInfo() async -> StorageInfo {
        let storageAnalyzer = RunAnywhere.serviceContainer.storageAnalyzer
        return await storageAnalyzer.analyzeStorage()
    }

    /// Clear cache
    static func clearCache() async throws {
        do {
            let fileManager = RunAnywhere.serviceContainer.fileManager
            try fileManager.clearCache()
            EventPublisher.shared.track(StorageEvent.cacheCleared(freedBytes: 0))
        } catch {
            EventPublisher.shared.track(StorageEvent.cacheClearFailed(error: error.localizedDescription))
            throw error
        }
    }

    /// Clean temporary files
    static func cleanTempFiles() async throws {
        do {
            let fileManager = RunAnywhere.serviceContainer.fileManager
            try fileManager.cleanTempFiles()
            EventPublisher.shared.track(StorageEvent.tempFilesCleaned(freedBytes: 0))
        } catch {
            EventPublisher.shared.track(ErrorEvent.error(
                operation: "cleanTempFiles",
                message: error.localizedDescription,
                code: nil
            ))
            throw error
        }
    }

    /// Delete stored model
    static func deleteStoredModel(_ modelId: String) async throws {
        do {
            let fileManager = RunAnywhere.serviceContainer.fileManager
            try fileManager.deleteModel(modelId: modelId)
            EventPublisher.shared.track(ModelEvent.deleted(modelId: modelId))
        } catch {
            EventPublisher.shared.track(ErrorEvent.error(
                operation: "deleteModel",
                message: error.localizedDescription,
                code: nil
            ))
            throw error
        }
    }

    /// Get base directory URL
    static func getBaseDirectoryURL() -> URL {
        let fileManager = RunAnywhere.serviceContainer.fileManager
        return fileManager.getBaseFolder().url
    }
}
