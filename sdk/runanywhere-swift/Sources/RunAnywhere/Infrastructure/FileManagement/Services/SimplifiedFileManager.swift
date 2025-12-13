// swiftlint:disable file_length
import Files
import Foundation

/// Individual model file information (distinct from aggregate ModelStorageInfo)
public struct ModelFileInfo {
    let modelId: String
    let format: ModelFormat
    let size: Int64
    let framework: LLMFramework?
}

/// Simplified file manager using Files library for all file operations
/// Implements FileManagementService protocol
public class SimplifiedFileManager: FileManagementService { // swiftlint:disable:this type_body_length

    // MARK: - Properties

    private let baseFolder: Folder
    private let logger = SDKLogger(category: "SimplifiedFileManager")

    // MARK: - Initialization

    public init() throws {
        // Create base RunAnywhere folder in Documents
        guard let documentsFolder = Folder.documents else {
            throw RunAnywhereError.storageError("Unable to access documents directory")
        }
        self.baseFolder = try documentsFolder.createSubfolderIfNeeded(withName: "RunAnywhere")

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
        let modelFolderURL = try ModelPathUtils.getModelFolder(modelId: modelId)
        return try createFolderIfNeeded(at: modelFolderURL)
    }

    /// Get or create folder for a specific model with framework
    public func getModelFolder(for modelId: String, framework: LLMFramework) throws -> Folder {
        let modelFolderURL = try ModelPathUtils.getModelFolder(modelId: modelId, framework: framework)
        return try createFolderIfNeeded(at: modelFolderURL)
    }

    /// Helper to create folder at URL if needed
    private func createFolderIfNeeded(at url: URL) throws -> Folder {
        let path = url.path
        if FileManager.default.fileExists(atPath: path) {
            return try Folder(path: path)
        } else {
            // Create the folder with intermediate directories
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true, attributes: nil)
            return try Folder(path: path)
        }
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
        let modelsFolderURL = try ModelPathUtils.getModelsDirectory()
        let modelsFolder = try Folder(path: modelsFolderURL.path)

        // Check framework-specific folders
        for frameworkFolder in modelsFolder.subfolders where LLMFramework.allCases.contains(where: { $0.rawValue == frameworkFolder.name }) {
            if frameworkFolder.containsSubfolder(named: modelId) {
                let modelFolder = try frameworkFolder.subfolder(named: modelId)
                try modelFolder.delete()

                // Remove metadata
                Task {
                    let modelInfoService = await ServiceContainer.shared.modelInfoService
                    try? await modelInfoService.removeModel(modelId)
                }

                logger.info("Deleted model: \(modelId) from framework: \(frameworkFolder.name)")
                return
            }
        }

        // Check direct model folder (legacy)
        if modelsFolder.containsSubfolder(named: modelId) {
            let modelFolder = try modelsFolder.subfolder(named: modelId)
            try modelFolder.delete()

            // Remove metadata
            Task {
                let modelInfoService = await ServiceContainer.shared.modelInfoService
                try? await modelInfoService.removeModel(modelId)
            }

            logger.info("Deleted model: \(modelId)")
            return
        }

        throw RunAnywhereError.modelNotFound(modelId)
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
        guard let modelsFolderURL = try? ModelPathUtils.getModelsDirectory(),
              let modelsFolder = try? Folder(path: modelsFolderURL.path) else { return 0 }

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
    public func getAllStoredModels() -> [ModelFileInfo] {
        guard let modelsFolderURL = try? ModelPathUtils.getModelsDirectory(),
              let modelsFolder = try? Folder(path: modelsFolderURL.path) else { return [] }

        var models: [ModelFileInfo] = []

        // First check direct model folders (legacy structure)
        for modelFolder in modelsFolder.subfolders {
            // Skip framework folders
            if LLMFramework.allCases.contains(where: { $0.rawValue == modelFolder.name }) {
                continue
            }

            let modelId = modelFolder.name
            // Try to find model files
            if let modelInfo = detectModelInFolder(modelFolder) {
                models.append(ModelFileInfo(
                    modelId: modelId,
                    format: modelInfo.format,
                    size: modelInfo.size,
                    framework: nil
                ))
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
                let folderURL = URL(fileURLWithPath: modelFolder.path)

                // Try to use framework-specific storage strategy if available
                if let storageStrategy = getStorageStrategy(for: frameworkType),
                   let modelInfo = storageStrategy.detectModel(in: folderURL) {
                    models.append(ModelFileInfo(
                        modelId: modelId,
                        format: modelInfo.format,
                        size: modelInfo.size,
                        framework: frameworkType
                    ))
                    logger.debug("Detected \(frameworkType.rawValue) model \(modelId) using storage strategy")
                } else {
                    // Fallback to generic detection for frameworks without storage strategies
                    if let modelInfo = detectModelInFolder(modelFolder) {
                        models.append(ModelFileInfo(
                            modelId: modelId,
                            format: modelInfo.format,
                            size: modelInfo.size,
                            framework: frameworkType
                        ))
                    }
                }
            }
        }

        return models
    }

    /// Detect model format and size in a folder
    private func detectModelInFolder(_ folder: Folder) -> (format: ModelFormat, size: Int64)? {
        // Check for single model files
        for file in folder.files {
            if let format = ModelFormat(from: file.extension ?? "") {
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
    public func calculateDirectorySize(at url: URL) -> Int64 {
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

    /// Get device storage information (total, free, used space)
    public func getDeviceStorageInfo() -> DeviceStorageInfo {
        do {
            let homeURL = URL(fileURLWithPath: NSHomeDirectory())
            let attributes = try FileManager.default.attributesOfFileSystem(forPath: homeURL.path)

            let totalSpace = (attributes[.systemSize] as? Int64) ?? 0
            let freeSpace = (attributes[.systemFreeSize] as? Int64) ?? 0
            let usedSpace = totalSpace - freeSpace

            return DeviceStorageInfo(totalSpace: totalSpace, freeSpace: freeSpace, usedSpace: usedSpace)
        } catch {
            logger.error("Failed to get device storage info: \(error)")
            return DeviceStorageInfo(totalSpace: 0, freeSpace: 0, usedSpace: 0)
        }
    }

    /// Get file creation date
    public func getFileCreationDate(at url: URL) -> Date? {
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            return attributes[.creationDate] as? Date
        } catch {
            return nil
        }
    }

    /// Get file last access/modification date
    public func getFileAccessDate(at url: URL) -> Date? {
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            return attributes[.modificationDate] as? Date
        } catch {
            return nil
        }
    }

    /// Get file size
    public func getFileSize(at url: URL) -> Int64? {
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            return attributes[.size] as? Int64
        } catch {
            return nil
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
    public func findModelFile(modelId: String, expectedPath: String? = nil) -> URL? { // swiftlint:disable:this cyclomatic_complexity
        // If expected path exists and is valid, return it
        if let expectedPath = expectedPath,
           FileManager.default.fileExists(atPath: expectedPath) {
            return URL(fileURLWithPath: expectedPath)
        }

        guard let modelsFolderURL = try? ModelPathUtils.getModelsDirectory(),
              let modelsFolder = try? Folder(path: modelsFolderURL.path) else { return nil }

        // Search in framework-specific folders first
        for frameworkFolder in modelsFolder.subfolders {
            if let frameworkType = LLMFramework.allCases.first(where: { $0.rawValue == frameworkFolder.name }) {
                if frameworkFolder.containsSubfolder(named: modelId) {
                    if let modelFolder = try? frameworkFolder.subfolder(named: modelId) {
                        let folderURL = URL(fileURLWithPath: modelFolder.path)

                        // Try to use framework-specific storage strategy if available
                        if let storageStrategy = getStorageStrategy(for: frameworkType) {
                            if let modelPath = storageStrategy.findModelPath(modelId: modelId, in: folderURL) {
                                logger.info("Found model \(modelId) using \(frameworkType.rawValue) storage strategy at: \(modelPath.path)")
                                return modelPath
                            }
                        }

                        // Fallback to generic search for single files
                        for file in modelFolder.files {
                            if ModelFormat(from: file.extension ?? "") != nil,
                               file.nameExcludingExtension == modelId || file.name.contains(modelId) {
                                logger.info("Found model \(modelId) at: \(file.path)")
                                return URL(fileURLWithPath: file.path)
                            }
                        }

                        // If no single file found, check if it's a directory-based model
                        // Return the folder path only if it contains actual model files
                        if FileManager.default.fileExists(atPath: folderURL.path) {
                            // Validate the folder contains model files (not just an empty/incomplete download)
                            let folderContents = modelFolder.files
                            let hasOnnxFiles = folderContents.contains { $0.extension == "onnx" }
                            let hasGgufFiles = folderContents.contains { $0.extension == "gguf" }
                            let hasBinFiles = folderContents.contains { $0.extension == "bin" }

                            if hasOnnxFiles || hasGgufFiles || hasBinFiles {
                                logger.info("Found directory-based model \(modelId) at: \(folderURL.path)")
                                return folderURL
                            } else {
                                logger.warning("Model folder exists but contains no valid model files: \(folderURL.path)")
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

    /// Get storage strategy for a framework
    private func getStorageStrategy(for framework: LLMFramework) -> ModelStorageStrategy? {
        // Storage strategies are now provided directly by service providers via download strategies
        // Return nil to use default storage behavior
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
