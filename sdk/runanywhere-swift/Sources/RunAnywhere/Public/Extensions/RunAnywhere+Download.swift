import Foundation

// MARK: - Download Extensions

public extension RunAnywhere {

    /// Register a custom download strategy
    /// - Parameter strategy: The download strategy to register
    static func registerDownloadStrategy(_ strategy: DownloadStrategy) {
        // Register with the download service
        RunAnywhere.serviceContainer.downloadService.registerStrategy(strategy)
    }

    /// Download a model with progress updates
    /// - Parameter modelId: The ID of the model to download
    /// - Returns: An async stream of download progress updates
    @available(iOS 13.0, macOS 10.15, tvOS 13.0, watchOS 6.0, *)
    static func downloadModelWithProgress(_ modelId: String) async throws -> AsyncStream<DownloadProgress> {
        let logger = SDKLogger(category: "RunAnywhere.Download")

        // Get the model info
        guard let model = RunAnywhere.serviceContainer.modelRegistry.getModel(by: modelId) else {
            throw SDKError.modelNotFound(modelId)
        }

        // Check if already downloaded
        if model.isDownloaded {
            logger.info("Model \(modelId) is already downloaded")
            return AsyncStream { continuation in
                let totalBytes = model.downloadSize ?? model.memoryRequired ?? 1_000_000_000
                continuation.yield(DownloadProgress(
                    bytesDownloaded: totalBytes,
                    totalBytes: totalBytes,
                    state: .completed,
                    speed: nil,
                    estimatedTimeRemaining: nil
                ))
                continuation.finish()
            }
        }

        // Create download task
        let downloadTask = try await RunAnywhere.serviceContainer.downloadService.downloadModel(model)

        // Return progress stream
        return downloadTask.progress
    }
}
