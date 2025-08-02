import Foundation

/// Concrete implementation of ModelStorageManager
public class ModelStorageManagerImpl: ModelStorageManager {

    // MARK: - Properties

    private let fileManager = FileManager.default
    private let logger = SDKLogger(category: "ModelStorageManager")

    // MARK: - Initialization

    public init() {}

    // MARK: - ModelStorageManager Protocol

    public func getModelsDirectory() -> URL {
        fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Models")
    }

    public func getModelPath(for modelId: String) -> URL {
        return getModelsDirectory().appendingPathComponent("\(modelId).model")
    }

    public func modelExists(_ modelId: String) -> Bool {
        let path = getModelPath(for: modelId)
        return fileManager.fileExists(atPath: path.path)
    }

    public func getModelSize(_ modelId: String) -> Int64? {
        guard modelExists(modelId) else { return nil }

        let path = getModelPath(for: modelId)
        do {
            let attributes = try fileManager.attributesOfItem(atPath: path.path)
            return attributes[.size] as? Int64
        } catch {
            logger.error("Failed to get model size for \(modelId): \(error)")
            return nil
        }
    }

    public func deleteModel(_ modelId: String) async throws {
        let path = getModelPath(for: modelId)

        guard fileManager.fileExists(atPath: path.path) else {
            logger.warning("Model \(modelId) not found for deletion")
            return
        }

        try fileManager.removeItem(at: path)
        logger.info("Deleted model: \(modelId)")
    }

    public func getAvailableSpace() -> Int64 {
        do {
            let url = getModelsDirectory()
            let attributes = try fileManager.attributesOfFileSystem(forPath: url.path)
            return attributes[.systemFreeSize] as? Int64 ?? 0
        } catch {
            logger.error("Failed to get available space: \(error)")
            return 0
        }
    }

    public func listStoredModels() -> [String] {
        let directory = getModelsDirectory()

        do {
            let files = try fileManager.contentsOfDirectory(at: directory,
                                                          includingPropertiesForKeys: nil,
                                                          options: [])

            return files
                .filter { $0.pathExtension == "model" }
                .map { $0.deletingPathExtension().lastPathComponent }
        } catch {
            logger.error("Failed to list stored models: \(error)")
            return []
        }
    }

    public func cleanupTemporaryFiles() async throws {
        let tempDirectory = fileManager.temporaryDirectory
        let modelsDirectory = getModelsDirectory()

        // Clean up any .tmp files in the models directory
        do {
            let files = try fileManager.contentsOfDirectory(at: modelsDirectory,
                                                          includingPropertiesForKeys: nil,
                                                          options: [])

            for file in files where file.pathExtension == "tmp" {
                try fileManager.removeItem(at: file)
                logger.debug("Cleaned up temporary file: \(file.lastPathComponent)")
            }
        } catch {
            logger.warning("Failed to clean temporary files: \(error)")
        }
    }

    public func moveToStorage(from temporaryPath: URL, modelId: String) async throws -> URL {
        let finalPath = getModelPath(for: modelId)

        // Ensure models directory exists
        let modelsDirectory = getModelsDirectory()
        try fileManager.createDirectory(at: modelsDirectory, withIntermediateDirectories: true)

        // Remove existing model if it exists
        if fileManager.fileExists(atPath: finalPath.path) {
            try fileManager.removeItem(at: finalPath)
        }

        // Move to final location
        try fileManager.moveItem(at: temporaryPath, to: finalPath)
        logger.info("Moved model \(modelId) from temporary storage to: \(finalPath.path)")

        return finalPath
    }
}
