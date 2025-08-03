import Foundation
import Files

/// Simplified file manager using Files library for all file operations
public class SimplifiedFileManager {

    // MARK: - Properties

    private let baseFolder: Folder
    private let logger = SDKLogger(category: "SimplifiedFileManager")

    // MARK: - Initialization

    public init() throws {
        // Create base RunAnywhere folder in Documents
        self.baseFolder = try Folder.documents!.createSubfolderIfNeeded(withName: "RunAnywhere")

        // Create basic directory structure
        try createDirectoryStructure()
    }

    private func createDirectoryStructure() throws {
        // Create main folders
        _ = try baseFolder.createSubfolderIfNeeded(withName: "Models")
        _ = try baseFolder.createSubfolderIfNeeded(withName: "Cache")
        _ = try baseFolder.createSubfolderIfNeeded(withName: "Temp")
        _ = try baseFolder.createSubfolderIfNeeded(withName: "Downloads")
    }

    // MARK: - Model Storage

    /// Get or create folder for a specific model
    public func getModelFolder(for modelId: String) throws -> Folder {
        let modelsFolder = try baseFolder.subfolder(named: "Models")
        return try modelsFolder.createSubfolderIfNeeded(withName: modelId)
    }

    /// Get or create folder for a specific model with framework
    public func getModelFolder(for modelId: String, framework: LLMFramework) throws -> Folder {
        let modelsFolder = try baseFolder.subfolder(named: "Models")
        let frameworkFolder = try modelsFolder.createSubfolderIfNeeded(withName: framework.rawValue)
        return try frameworkFolder.createSubfolderIfNeeded(withName: modelId)
    }

    /// Store model file
    public func storeModel(data: Data, modelId: String, format: ModelFormat) throws -> URL {
        let modelFolder = try getModelFolder(for: modelId)
        let fileName = "\(modelId).\(format.rawValue)"

        let file = try modelFolder.createFile(named: fileName, contents: data)
        logger.info("Stored model \(modelId) at: \(file.path)")

        return URL(fileURLWithPath: file.path)
    }

    /// Store model file with framework
    public func storeModel(data: Data, modelId: String, format: ModelFormat, framework: LLMFramework) throws -> URL {
        let modelFolder = try getModelFolder(for: modelId, framework: framework)
        let fileName = "\(modelId).\(format.rawValue)"

        let file = try modelFolder.createFile(named: fileName, contents: data)
        logger.info("Stored model \(modelId) in \(framework.rawValue) at: \(file.path)")

        return URL(fileURLWithPath: file.path)
    }

    /// Load model data
    public func loadModel(modelId: String, format: ModelFormat) throws -> Data {
        let modelFolder = try getModelFolder(for: modelId)
        let fileName = "\(modelId).\(format.rawValue)"

        let file = try modelFolder.file(named: fileName)
        return try file.read()
    }

    /// Check if model exists
    public func modelExists(modelId: String, format: ModelFormat) -> Bool {
        do {
            let modelFolder = try getModelFolder(for: modelId)
            let fileName = "\(modelId).\(format.rawValue)"
            return modelFolder.containsFile(named: fileName)
        } catch {
            return false
        }
    }

    /// Delete model
    public func deleteModel(modelId: String) throws {
        let modelFolder = try getModelFolder(for: modelId)
        try modelFolder.delete()
        logger.info("Deleted model: \(modelId)")
    }

    // MARK: - Download Management

    /// Get download folder
    public func getDownloadFolder() throws -> Folder {
        return try baseFolder.subfolder(named: "Downloads")
    }

    /// Create temporary download file
    public func createTempDownloadFile(for modelId: String) throws -> File {
        let downloadFolder = try getDownloadFolder()
        let tempFileName = "\(modelId)_\(UUID().uuidString).tmp"
        return try downloadFolder.createFile(named: tempFileName)
    }

    /// Move downloaded file to model storage
    public func moveDownloadToStorage(tempFile: File, modelId: String, format: ModelFormat) throws -> URL {
        // Read file data
        let data = try tempFile.read()

        // Store in models folder
        let url = try storeModel(data: data, modelId: modelId, format: format)

        // Delete temp file
        try tempFile.delete()

        return url
    }

    // MARK: - Cache Management

    /// Store cache data
    public func storeCache(key: String, data: Data) throws {
        let cacheFolder = try baseFolder.subfolder(named: "Cache")
        _ = try cacheFolder.createFile(named: "\(key).cache", contents: data)
        logger.debug("Stored cache for key: \(key)")
    }

    /// Load cache data
    public func loadCache(key: String) throws -> Data? {
        let cacheFolder = try baseFolder.subfolder(named: "Cache")
        guard cacheFolder.containsFile(named: "\(key).cache") else { return nil }

        let file = try cacheFolder.file(named: "\(key).cache")
        return try file.read()
    }

    /// Clear all cache
    public func clearCache() throws {
        let cacheFolder = try baseFolder.subfolder(named: "Cache")
        for file in cacheFolder.files {
            try file.delete()
        }
        logger.info("Cleared all cache")
    }

    // MARK: - Temporary Files

    /// Clean temporary files
    public func cleanTempFiles() throws {
        let tempFolder = try baseFolder.subfolder(named: "Temp")
        for file in tempFolder.files {
            try file.delete()
        }
        logger.info("Cleaned temporary files")
    }

    // MARK: - Storage Information

    /// Get total storage size
    public func getTotalStorageSize() -> Int64 {
        var totalSize: Int64 = 0

        // Calculate size recursively
        for file in baseFolder.files.recursive {
            if let attributes = try? FileManager.default.attributesOfItem(atPath: file.path),
               let fileSize = attributes[.size] as? NSNumber {
                totalSize += fileSize.int64Value
            }
        }

        return totalSize
    }

    /// Get model storage size
    public func getModelStorageSize() -> Int64 {
        guard let modelsFolder = try? baseFolder.subfolder(named: "Models") else { return 0 }

        var totalSize: Int64 = 0
        for file in modelsFolder.files.recursive {
            if let attributes = try? FileManager.default.attributesOfItem(atPath: file.path),
               let fileSize = attributes[.size] as? NSNumber {
                totalSize += fileSize.int64Value
            }
        }

        return totalSize
    }

    /// Get all stored models
    public func getAllStoredModels() -> [(modelId: String, format: ModelFormat, size: Int64)] {
        guard let modelsFolder = try? baseFolder.subfolder(named: "Models") else { return [] }

        var models: [(String, ModelFormat, Int64)] = []

        for modelFolder in modelsFolder.subfolders {
            let modelId = modelFolder.name

            for file in modelFolder.files {
                if let format = ModelFormat(rawValue: file.extension ?? "") {
                    var fileSize: Int64 = 0
                    if let attributes = try? FileManager.default.attributesOfItem(atPath: file.path),
                       let size = attributes[.size] as? NSNumber {
                        fileSize = size.int64Value
                    }
                    models.append((modelId, format, fileSize))
                }
            }
        }

        return models
    }

    /// Get available space
    public func getAvailableSpace() -> Int64 {
        let fileURL = URL(fileURLWithPath: baseFolder.path)

        do {
            let values = try fileURL.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
            return values.volumeAvailableCapacityForImportantUsage ?? 0
        } catch {
            logger.error("Failed to get available space: \(error)")
            return 0
        }
    }

    // MARK: - Path Helpers

    /// Get URL for model file
    public func getModelURL(modelId: String, format: ModelFormat) throws -> URL {
        let modelFolder = try getModelFolder(for: modelId)
        let fileName = "\(modelId).\(format.rawValue)"
        let file = try modelFolder.file(named: fileName)
        return URL(fileURLWithPath: file.path)
    }

    /// Get base directory URL
    public func getBaseDirectoryURL() -> URL {
        return URL(fileURLWithPath: baseFolder.path)
    }
}

// MARK: - Extension for Model Format

extension ModelFormat {
    init?(from extension: String) {
        switch `extension`.lowercased() {
        case "gguf": self = .gguf
        case "onnx": self = .onnx
        case "mlmodelc", "mlmodel": self = .mlmodel
        case "mlpackage": self = .mlpackage
        case "tflite": self = .tflite
        case "safetensors": self = .mlx
        default: return nil
        }
    }
}

// MARK: - Convenience Extensions

extension SimplifiedFileManager {

    /// Create subfolder if needed
    private func createSubfolderIfNeeded(in parent: Folder, named name: String) throws -> Folder {
        if parent.containsSubfolder(named: name) {
            return try parent.subfolder(named: name)
        } else {
            return try parent.createSubfolder(named: name)
        }
    }
}

// MARK: - Files Extension Helper

extension Folder {
    /// Create subfolder if it doesn't exist
    func createSubfolderIfNeeded(withName name: String) throws -> Folder {
        if containsSubfolder(named: name) {
            return try subfolder(named: name)
        } else {
            return try createSubfolder(named: name)
        }
    }
}
