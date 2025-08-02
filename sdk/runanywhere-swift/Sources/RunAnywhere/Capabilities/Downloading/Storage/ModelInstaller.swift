import Foundation

/// Handles installation of downloaded models
public class ModelInstaller {

    // MARK: - Properties

    private let fileManager = FileManager.default
    private let modelStorage: ModelStorageManager
    private let logger = SDKLogger(category: "ModelInstaller")

    // MARK: - Initialization

    public init(modelStorage: ModelStorageManager? = nil) {
        self.modelStorage = modelStorage ?? ServiceContainer.shared.modelStorageManager
    }

    // MARK: - Public Methods

    /// Install a downloaded model
    public func installModel(
        from downloadedURL: URL,
        modelInfo: ModelInfo,
        replaceExisting: Bool = true
    ) async throws -> URL {
        logger.info("Installing model \(modelInfo.id) from: \(downloadedURL.path)")

        // Verify the downloaded file exists
        guard fileManager.fileExists(atPath: downloadedURL.path) else {
            throw DownloadError.modelNotFound
        }

        // Get installation path
        let installPath = modelStorage.getModelPath(for: modelInfo.id)
        let installDirectory = installPath.deletingLastPathComponent()

        // Create model directory if needed
        try fileManager.createDirectory(at: installDirectory, withIntermediateDirectories: true)

        // Determine final filename
        let filename = downloadedURL.lastPathComponent
        let installedURL = installDirectory.appendingPathComponent(filename)

        // Handle existing file
        if fileManager.fileExists(atPath: installedURL.path) {
            if replaceExisting {
                logger.info("Replacing existing model at: \(installedURL.path)")
                try fileManager.removeItem(at: installedURL)
            } else {
                logger.info("Model already installed at: \(installedURL.path)")
                return installedURL
            }
        }

        // Move or copy the model file
        do {
            // Try to move first (more efficient)
            try fileManager.moveItem(at: downloadedURL, to: installedURL)
        } catch {
            // If move fails, copy and delete
            logger.debug("Move failed, copying instead: \(error)")
            try fileManager.copyItem(at: downloadedURL, to: installedURL)
            try? fileManager.removeItem(at: downloadedURL)
        }

        // Update model metadata
        await updateModelMetadata(modelInfo: modelInfo, installedURL: installedURL)

        // Verify installation
        let isValid = await verifyInstallation(modelInfo: modelInfo, at: installedURL)
        if !isValid {
            logger.error("Model installation verification failed")
            try? fileManager.removeItem(at: installedURL)
            throw DownloadError.extractionFailed("Model installation verification failed")
        }

        logger.info("Successfully installed model at: \(installedURL.path)")

        return installedURL
    }

    /// Uninstall a model
    public func uninstallModel(_ modelInfo: ModelInfo) throws {
        let installPath = modelStorage.getModelPath(for: modelInfo.id)
        let installDirectory = installPath.deletingLastPathComponent()

        if fileManager.fileExists(atPath: installDirectory.path) {
            try fileManager.removeItem(at: installDirectory)
            logger.info("Uninstalled model: \(modelInfo.id)")
        }
    }

    /// Check if model is installed
    public func isModelInstalled(_ modelInfo: ModelInfo) -> Bool {
        return modelStorage.modelExists(modelInfo.id)
    }

    /// Get installed model URL
    public func getInstalledModelURL(_ modelInfo: ModelInfo) -> URL? {
        guard isModelInstalled(modelInfo) else { return nil }

        return modelStorage.getModelPath(for: modelInfo.id)
    }

    // MARK: - Private Methods

    private func updateModelMetadata(modelInfo: ModelInfo, installedURL: URL) async {
        // Update model metadata with installation info
        var metadata = modelInfo
        metadata.localPath = installedURL
        metadata.installDate = Date()

        // Store basic metadata as a simple JSON
        let metadataURL = installedURL.deletingLastPathComponent()
            .appendingPathComponent("metadata.json")

        let basicMetadata: [String: Any] = [
            "id": metadata.id,
            "name": metadata.name,
            "installedPath": installedURL.path,
            "installDate": ISO8601DateFormatter().string(from: Date())
        ]

        if let data = try? JSONSerialization.data(withJSONObject: basicMetadata) {
            try? data.write(to: metadataURL)
        }
    }

    private func verifyInstallation(modelInfo: ModelInfo, at url: URL) async -> Bool {
        // Basic verification - file exists and has expected size
        guard fileManager.fileExists(atPath: url.path) else {
            return false
        }

        // Check file size if available
        if let expectedSize = modelInfo.downloadSize,
           let attributes = try? fileManager.attributesOfItem(atPath: url.path),
           let fileSize = attributes[.size] as? Int64 {
            // Allow small variance in size
            let sizeDifference = abs(fileSize - expectedSize)
            let allowedVariance = expectedSize / 100 // 1% variance

            if sizeDifference > allowedVariance {
                logger.warning("File size mismatch - expected: \(expectedSize), actual: \(fileSize)")
                return false
            }
        }

        return true
    }
}

// MARK: - ModelInfo Extension

extension ModelInfo {
    var installDate: Date? {
        get { additionalProperties["installDate"] as? Date }
        set { additionalProperties["installDate"] = newValue }
    }
}
