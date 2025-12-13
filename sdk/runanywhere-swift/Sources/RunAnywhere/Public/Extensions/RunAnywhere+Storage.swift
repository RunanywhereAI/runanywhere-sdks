//
//  RunAnywhere+Storage.swift
//  RunAnywhere SDK
//
//  Public API for storage operations.
//  Events are tracked via EventPublisher.
//

import Foundation

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
