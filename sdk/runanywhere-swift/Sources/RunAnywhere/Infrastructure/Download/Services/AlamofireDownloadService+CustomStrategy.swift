import Foundation

// MARK: - Custom Strategy Support

extension AlamofireDownloadService {

    /// Register a custom download strategy from host app
    public func registerStrategy(_ strategy: DownloadStrategy) {
        customStrategies.insert(strategy, at: 0) // Custom strategies have priority
        logger.info("Registered custom download strategy")
    }

    /// Refresh strategies from framework adapters (call after registering new adapters)
    public func refreshStrategies() {
        autoRegisterStrategies()
    }

    /// Auto-discover and register strategies from service providers
    func autoRegisterStrategies() {
        // Download strategies are registered directly by service providers
        // No auto-discovery needed since adapters are removed
        logger.info("[DEBUG] Download strategies are registered directly by service providers")
    }

    /// Find a custom strategy for the model
    /// Checks both manually registered strategies and ModuleRegistry strategies
    @MainActor
    func findCustomStrategy(for model: ModelInfo) -> DownloadStrategy? {
        // First check manually registered custom strategies (host app priority)
        for strategy in customStrategies where strategy.canHandle(model: model) {
            return strategy
        }

        // Then check ModuleRegistry for module-provided strategies
        if let strategy = ModuleRegistry.shared.downloadStrategy(for: model) {
            return strategy
        }

        return nil
    }

    /// Helper to download using a custom strategy
    func downloadModelWithCustomStrategy(_ model: ModelInfo, strategy: DownloadStrategy) async throws -> DownloadTask {
        logger.info("Using custom strategy for model: \(model.id)")

        // Track download started
        EventPublisher.shared.track(ModelEvent.downloadStarted(modelId: model.id))

        let taskId = UUID().uuidString
        let downloadStartTime = Date()
        let (progressStream, progressContinuation) = AsyncStream<DownloadProgress>.makeStream()

        // Create download task
        let task = DownloadTask(
            id: taskId,
            modelId: model.id,
            progress: progressStream,
            result: Task {
                defer {
                    progressContinuation.finish()
                }

                do {
                    let destinationFolder = try getDestinationFolder(for: model.id, framework: model.preferredFramework)

                    let resultURL = try await strategy.download(
                        model: model,
                        to: destinationFolder,
                        progressHandler: { progress in
                            progressContinuation.yield(DownloadProgress(
                                bytesDownloaded: Int64(progress * Double(model.downloadSize ?? 100)),
                                totalBytes: Int64(model.downloadSize ?? 100),
                                state: .downloading
                            ))

                            // Progress updates are for UI only - analytics tracks start/complete only
                        }
                    )

                    // Update progress to completed
                    progressContinuation.yield(DownloadProgress(
                        bytesDownloaded: Int64(model.downloadSize ?? 100),
                        totalBytes: Int64(model.downloadSize ?? 100),
                        state: .completed
                    ))

                    // Update model with local path in registry
                    var updatedModel = model
                    updatedModel.localPath = resultURL
                    ServiceContainer.shared.modelRegistry.updateModel(updatedModel)

                    // Save metadata persistently
                    do {
                        let modelInfoService = await ServiceContainer.shared.modelInfoService
                        try await modelInfoService.saveModel(updatedModel)
                        self.logger.info("Model metadata saved successfully for: \(model.id)")
                    } catch {
                        self.logger.error("Failed to save model metadata for \(model.id): \(error)")
                        // Continue with download completion, but log the error
                    }

                    // Track download completed
                    let durationMs = Date().timeIntervalSince(downloadStartTime) * 1000
                    EventPublisher.shared.track(ModelEvent.downloadCompleted(
                        modelId: model.id,
                        durationMs: durationMs,
                        sizeBytes: model.downloadSize ?? 0
                    ))

                    self.logger.info("Custom strategy download completed", metadata: [
                        "modelId": model.id,
                        "localPath": resultURL.path
                    ])

                    return resultURL
                } catch {
                    // Track download failed
                    EventPublisher.shared.track(ModelEvent.downloadFailed(
                        modelId: model.id,
                        error: error.localizedDescription
                    ))

                    progressContinuation.yield(DownloadProgress(
                        bytesDownloaded: 0,
                        totalBytes: Int64(model.downloadSize ?? 0),
                        state: .failed(error)
                    ))
                    throw error
                }
            }
        )

        return task
    }

    /// Helper to get destination folder for a model
    func getDestinationFolder(for modelId: String, framework: InferenceFramework? = nil) throws -> URL {
        if let framework = framework {
            return try ModelPathUtils.getModelFolder(modelId: modelId, framework: framework)
        } else {
            return try ModelPathUtils.getModelFolder(modelId: modelId)
        }
    }
}
