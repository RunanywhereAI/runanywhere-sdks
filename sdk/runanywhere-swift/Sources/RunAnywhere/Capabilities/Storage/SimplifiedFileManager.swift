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

    // MARK: - Public Access

    /// Get the base RunAnywhere folder
    public func getBaseFolder() -> Folder {
        return baseFolder
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
        let modelsFolder = try baseFolder.subfolder(named: "Models")

        // Check framework-specific folders
        for frameworkFolder in modelsFolder.subfolders {
            if LLMFramework.allCases.contains(where: { $0.rawValue == frameworkFolder.name }) {
                if frameworkFolder.containsSubfolder(named: modelId) {
                    let modelFolder = try frameworkFolder.subfolder(named: modelId)
                    try modelFolder.delete()

                    // Remove metadata
                    Task {
                        if let dataSyncService = await ServiceContainer.shared.dataSyncService {
                            try? await dataSyncService.removeModelMetadata(modelId)
                        }
                    }

                    logger.info("Deleted model: \(modelId) from framework: \(frameworkFolder.name)")
                    return
                }
            }
        }

        // Check direct model folder (legacy)
        if modelsFolder.containsSubfolder(named: modelId) {
            let modelFolder = try modelsFolder.subfolder(named: modelId)
            try modelFolder.delete()

            // Remove metadata
            Task {
                if let dataSyncService = await ServiceContainer.shared.dataSyncService {
                    try? await dataSyncService.removeModelMetadata(modelId)
                }
            }

            logger.info("Deleted model: \(modelId)")
            return
        }

        throw SDKError.modelNotFound(modelId)
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
    public func getAllStoredModels() -> [(modelId: String, format: ModelFormat, size: Int64, framework: LLMFramework?)] {
        guard let modelsFolder = try? baseFolder.subfolder(named: "Models") else { return [] }

        var models: [(String, ModelFormat, Int64, LLMFramework?)] = []

        // First check direct model folders (legacy structure)
        for modelFolder in modelsFolder.subfolders {
            // Skip framework folders
            if LLMFramework.allCases.contains(where: { $0.rawValue == modelFolder.name }) {
                continue
            }

            let modelId = modelFolder.name
            // Try to find model files
            if let modelInfo = detectModelInFolder(modelFolder) {
                models.append((modelId, modelInfo.format, modelInfo.size, nil))
            }
        }

        // Then check framework-specific folders
        for frameworkFolder in modelsFolder.subfolders {
            // Only process framework folders
            guard let frameworkType = LLMFramework.allCases.first(where: { $0.rawValue == frameworkFolder.name }) else {
                continue
            }

            for modelFolder in frameworkFolder.subfolders {
                let modelId = modelFolder.name

                // Generic handling for all model types
                if let modelInfo = detectModelInFolder(modelFolder) {
                    models.append((modelId, modelInfo.format, modelInfo.size, frameworkType))
                }
            }
        }

        return models
    }

    /// Detect model format and size in a folder
    private func detectModelInFolder(_ folder: Folder) -> (format: ModelFormat, size: Int64)? {
        // Check for single model files
        for file in folder.files {
            if let format = ModelFormat(rawValue: file.extension ?? "") {
                var fileSize: Int64 = 0
                if let attributes = try? FileManager.default.attributesOfItem(atPath: file.path),
                   let size = attributes[.size] as? NSNumber {
                    fileSize = size.int64Value
                }
                return (format, fileSize)
            }
        }

        // If no single model file, assume it's a directory-based model
        // Just calculate total size and return default format
        let totalSize = calculateDirectorySize(at: URL(fileURLWithPath: folder.path))
        if totalSize > 0 {
            // Default to mlmodel for directory-based models
            return (.mlmodel, totalSize)
        }

        return nil
    }

    /// Calculate the total size of a directory including all subdirectories and files
    private func calculateDirectorySize(at url: URL) -> Int64 {
        var totalSize: Int64 = 0

        if let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey], options: []) {
            for case let fileURL as URL in enumerator {
                if let fileSize = try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                    totalSize += Int64(fileSize)
                }
            }
        }

        return totalSize
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

    /// Find model file by searching all possible locations
    public func findModelFile(modelId: String, expectedPath: String? = nil) -> URL? {
        // If expected path exists and is valid, return it
        if let expectedPath = expectedPath,
           FileManager.default.fileExists(atPath: expectedPath) {
            return URL(fileURLWithPath: expectedPath)
        }

        guard let modelsFolder = try? baseFolder.subfolder(named: "Models") else { return nil }

        // Search in framework-specific folders first
        for frameworkFolder in modelsFolder.subfolders {
            if LLMFramework.allCases.contains(where: { $0.rawValue == frameworkFolder.name }) {
                if frameworkFolder.containsSubfolder(named: modelId) {
                    if let modelFolder = try? frameworkFolder.subfolder(named: modelId) {
                        // Look for any model file in the folder
                        for file in modelFolder.files {
                            if ModelFormat(from: file.extension ?? "") != nil,
                               file.nameExcludingExtension == modelId || file.name.contains(modelId) {
                                logger.info("Found model \(modelId) at: \(file.path)")
                                return URL(fileURLWithPath: file.path)
                            }
                        }
                    }
                }
            }
        }

        // Search in direct model folders (legacy)
        if modelsFolder.containsSubfolder(named: modelId) {
            if let modelFolder = try? modelsFolder.subfolder(named: modelId) {
                for file in modelFolder.files {
                    if ModelFormat(from: file.extension ?? "") != nil,
                       file.nameExcludingExtension == modelId || file.name.contains(modelId) {
                        logger.info("Found model \(modelId) at: \(file.path)")
                        return URL(fileURLWithPath: file.path)
                    }
                }
            }
        }

        logger.warning("Model file not found for: \(modelId)")
        return nil
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
