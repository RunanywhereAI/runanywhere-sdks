import Files
import Foundation

/// File manager for RunAnywhere SDK
///
/// Directory Structure:
/// ```
/// Documents/RunAnywhere/
///   Models/
///     {framework}/          # e.g., "onnx", "llamacpp"
///       {modelId}/          # e.g., "sherpa-onnx-whisper-tiny.en"
///         [model files]     # Single file or directory with multiple files
///   Cache/
///   Temp/
///   Downloads/
/// ```
public class SimplifiedFileManager {

    // MARK: - Shared Instance

    /// Shared file manager instance
    public static let shared: SimplifiedFileManager = {
        do {
            return try SimplifiedFileManager()
        } catch {
            fatalError("Failed to initialize SimplifiedFileManager: \(error)")
        }
    }()

    // MARK: - Properties

    private let baseFolder: Folder
    private let logger = SDKLogger(category: "FileManager")

    // MARK: - Initialization

    public init() throws {
        guard let documentsFolder = Folder.documents else {
            throw SDKException.fileManagement(.permissionDenied, "Unable to access documents directory")
        }
        self.baseFolder = try documentsFolder.createSubfolderIfNeeded(withName: "RunAnywhere")
        try createDirectoryStructure()
    }

    private func createDirectoryStructure() throws {
        guard CppBridge.FileManager.createDirectoryStructure() else {
            throw SDKException.fileManagement(.directoryCreationFailed, "Failed to create directory structure via C++ bridge")
        }
    }

    // MARK: - Model Folder Access

    /// Get the model folder path: Models/{framework}/{modelId}/
    public func getModelFolder(for modelId: String, framework: InferenceFramework) throws -> Folder {
        let modelFolderURL = try CppBridge.ModelPaths.getModelFolder(modelId: modelId, framework: framework)
        return try createFolderIfNeeded(at: modelFolderURL)
    }

    /// Check if a model folder exists and contains files
    public func modelFolderExists(modelId: String, framework: InferenceFramework) -> Bool {
        return CppBridge.FileManager.modelFolderHasContents(modelId: modelId, framework: framework)
    }

    /// Get the model folder URL (without creating it)
    public func getModelFolderURL(modelId: String, framework: InferenceFramework) throws -> URL {
        return try CppBridge.ModelPaths.getModelFolder(modelId: modelId, framework: framework)
    }

    /// Delete a model folder and all its contents
    public func deleteModel(modelId: String, framework: InferenceFramework) throws {
        guard CppBridge.FileManager.deleteModel(modelId: modelId, framework: framework) else {
            throw SDKException.fileManagement(.deleteFailed, "Failed to delete model: \(modelId)")
        }
        logger.info("Deleted model: \(modelId) from \(framework.wireString)")
    }

    // MARK: - Model Discovery

    /// Get all downloaded models organized by framework
    /// Returns: Dictionary of [framework: [modelId]]
    public func getDownloadedModels() -> [InferenceFramework: [String]] {
        var result: [InferenceFramework: [String]] = [:]

        guard let modelsURL = try? CppBridge.ModelPaths.getModelsDirectory(),
              let contents = try? FileManager.default.contentsOfDirectory(at: modelsURL, includingPropertiesForKeys: [.isDirectoryKey]) else {
            return result
        }

        for frameworkFolder in contents {
            // Check if it's a known framework folder
            guard let framework = InferenceFramework.knownCases.first(where: { $0.wireString == frameworkFolder.lastPathComponent }),
                  isDirectory(at: frameworkFolder) else {
                continue
            }

            // Get model folders within this framework
            let dirContents = try? FileManager.default.contentsOfDirectory(
                at: frameworkFolder,
                includingPropertiesForKeys: [.isDirectoryKey]
            )
            guard let modelFolders = dirContents else {
                continue
            }

            var modelIds: [String] = []
            for modelFolder in modelFolders {
                if isDirectory(at: modelFolder) && folderExistsAndHasContents(at: modelFolder) {
                    modelIds.append(modelFolder.lastPathComponent)
                }
            }

            if !modelIds.isEmpty {
                result[framework] = modelIds
            }
        }

        return result
    }

    /// Check if a specific model is downloaded
    @MainActor
    public func isModelDownloaded(modelId: String, framework: InferenceFramework) -> Bool {
        return CppBridge.FileManager.modelFolderHasContents(modelId: modelId, framework: framework)
    }

    // MARK: - Download Management

    public func getDownloadFolder() throws -> Folder {
        return try baseFolder.subfolder(named: "Downloads")
    }

    public func createTempDownloadFile(for modelId: String) throws -> File {
        let downloadFolder = try getDownloadFolder()
        let tempFileName = "\(modelId)_\(UUID().uuidString).tmp"
        return try downloadFolder.createFile(named: tempFileName)
    }

    // MARK: - Cache Management

    public func storeCache(key: String, data: Data) throws {
        let cacheFolder = try baseFolder.subfolder(named: "Cache")
        _ = try cacheFolder.createFile(named: "\(key).cache", contents: data)
    }

    public func loadCache(key: String) throws -> Data? {
        let cacheFolder = try baseFolder.subfolder(named: "Cache")
        guard cacheFolder.containsFile(named: "\(key).cache") else { return nil }
        return try cacheFolder.file(named: "\(key).cache").read()
    }

    public func clearCache() throws {
        guard CppBridge.FileManager.clearCache() else {
            throw SDKException.fileManagement(.deleteFailed, "Failed to clear cache")
        }
        logger.info("Cleared cache")
    }

    // MARK: - Temp Files

    public func cleanTempFiles() throws {
        guard CppBridge.FileManager.clearTemp() else {
            throw SDKException.fileManagement(.deleteFailed, "Failed to clean temp files")
        }
        logger.info("Cleaned temp files")
    }

    // MARK: - Storage Info

    public func calculateDirectorySize(at url: URL) -> Int64 {
        return CppBridge.FileManager.calculateDirectorySize(at: url)
    }

    public func getBaseDirectoryURL() -> URL {
        return URL(fileURLWithPath: baseFolder.path)
    }

    // MARK: - Private Helpers

    private func createFolderIfNeeded(at url: URL) throws -> Folder {
        if !FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true, attributes: nil)
        }
        return try Folder(path: url.path)
    }

    private func isDirectory(at url: URL) -> Bool {
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) && isDir.boolValue
    }

    private func folderExistsAndHasContents(at url: URL) -> Bool {
        guard isDirectory(at: url),
              let contents = try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil),
              !contents.isEmpty else {
            return false
        }
        return true
    }
}

// MARK: - Folder Extension

extension Folder {
    func createSubfolderIfNeeded(withName name: String) throws -> Folder {
        if containsSubfolder(named: name) {
            return try subfolder(named: name)
        }
        return try createSubfolder(named: name)
    }
}
