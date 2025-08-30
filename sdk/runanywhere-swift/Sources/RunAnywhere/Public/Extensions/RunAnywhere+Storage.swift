import Foundation

// MARK: - Storage Extensions (Event-Based)

public extension RunAnywhere {

    /// Get storage information with event reporting
    /// - Returns: Storage information
    static func getStorageInfo() async -> StorageInfo {
        await events.publish(SDKStorageEvent.infoRequested)

        let storageInfo = await RunAnywhereSDK.shared.getStorageInfo()

        await events.publish(SDKStorageEvent.infoRetrieved(info: storageInfo))
        return storageInfo
    }

    /// Get stored models with event reporting
    /// - Returns: Array of stored models
    static func getStoredModels() async -> [StoredModel] {
        await events.publish(SDKStorageEvent.modelsRequested)

        let models = await RunAnywhereSDK.shared.getStoredModels()

        await events.publish(SDKStorageEvent.modelsRetrieved(models: models))
        return models
    }

    /// Clear cache with event reporting
    static func clearCache() async throws {
        await events.publish(SDKStorageEvent.clearCacheStarted)

        do {
            try await RunAnywhereSDK.shared.clearCache()
            await events.publish(SDKStorageEvent.clearCacheCompleted)
        } catch {
            await events.publish(SDKStorageEvent.clearCacheFailed(error))
            throw error
        }
    }

    /// Clean temporary files with event reporting
    static func cleanTempFiles() async throws {
        await events.publish(SDKStorageEvent.cleanTempStarted)

        do {
            try await RunAnywhereSDK.shared.cleanTempFiles()
            await events.publish(SDKStorageEvent.cleanTempCompleted)
        } catch {
            await events.publish(SDKStorageEvent.cleanTempFailed(error))
            throw error
        }
    }

    /// Delete stored model with event reporting
    /// - Parameter modelId: The model ID to delete
    static func deleteStoredModel(_ modelId: String) async throws {
        await events.publish(SDKStorageEvent.deleteModelStarted(modelId: modelId))

        do {
            try await RunAnywhereSDK.shared.deleteStoredModel(modelId)
            await events.publish(SDKStorageEvent.deleteModelCompleted(modelId: modelId))
        } catch {
            await events.publish(SDKStorageEvent.deleteModelFailed(modelId: modelId, error: error))
            throw error
        }
    }

    /// Get base directory URL
    /// - Returns: Base directory URL
    static func getBaseDirectoryURL() -> URL {
        return RunAnywhereSDK.shared.getBaseDirectoryURL()
    }
}
