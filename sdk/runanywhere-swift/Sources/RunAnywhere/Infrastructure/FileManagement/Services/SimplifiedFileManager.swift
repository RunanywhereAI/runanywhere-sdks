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
internal class SimplifiedFileManager {

    // MARK: - Shared Instance

    /// Shared file manager instance
    internal static let shared: SimplifiedFileManager = {
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

    internal init() throws {
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
    internal func getModelFolder(for modelId: String, framework: InferenceFramework) throws -> Folder {
        let modelFolderURL = try CppBridge.ModelPaths.getModelFolder(modelId: modelId, framework: framework)
        return try createFolderIfNeeded(at: modelFolderURL)
    }

    /// Check if a model folder exists and contains files
    internal func modelFolderExists(modelId: String, framework: InferenceFramework) -> Bool {
        return CppBridge.FileManager.modelFolderHasContents(modelId: modelId, framework: framework)
    }

    /// Get the model folder URL (without creating it)
    internal func getModelFolderURL(modelId: String, framework: InferenceFramework) throws -> URL {
        return try CppBridge.ModelPaths.getModelFolder(modelId: modelId, framework: framework)
    }

    /// Delete a model folder and all its contents
    internal func deleteModel(modelId: String, framework: InferenceFramework) throws {
        guard CppBridge.FileManager.deleteModel(modelId: modelId, framework: framework) else {
            throw SDKException.fileManagement(.deleteFailed, "Failed to delete model: \(modelId)")
        }
        logger.info("Deleted model: \(modelId) from \(framework.wireString)")
    }

    // MARK: - Model Discovery

    /// Get all downloaded models organized by framework.
    /// Reconciles the registry through the generated discovery result, then
    /// groups the registered models by framework.
    internal func getDownloadedModels() async -> [InferenceFramework: [String]] {
        _ = await CppBridge.ModelRegistry.shared.discoverDownloadedModels()

        let models = await CppBridge.ModelRegistry.shared.getByFrameworks(
            InferenceFramework.knownCases
        )

        var result: [InferenceFramework: [String]] = [:]
        for model in models {
            result[model.framework, default: []].append(model.id)
        }
        return result
    }

    /// Check if a specific model is downloaded
    @MainActor
    internal func isModelDownloaded(modelId: String, framework: InferenceFramework) -> Bool {
        return CppBridge.FileManager.modelFolderHasContents(modelId: modelId, framework: framework)
    }

    // MARK: - Download Management

    internal func getDownloadFolder() throws -> Folder {
        return try baseFolder.subfolder(named: "Downloads")
    }

    internal func createTempDownloadFile(for modelId: String) throws -> File {
        let downloadFolder = try getDownloadFolder()
        let tempFileName = "\(modelId)_\(UUID().uuidString).tmp"
        return try downloadFolder.createFile(named: tempFileName)
    }

    // MARK: - Cache Management

    internal func storeCache(key: String, data: Data) throws {
        let cacheFolder = try baseFolder.subfolder(named: "Cache")
        _ = try cacheFolder.createFile(named: "\(key).cache", contents: data)
    }

    internal func loadCache(key: String) throws -> Data? {
        let cacheFolder = try baseFolder.subfolder(named: "Cache")
        guard cacheFolder.containsFile(named: "\(key).cache") else { return nil }
        return try cacheFolder.file(named: "\(key).cache").read()
    }

    internal func clearCache() throws {
        guard CppBridge.FileManager.clearCache() else {
            throw SDKException.fileManagement(.deleteFailed, "Failed to clear cache")
        }
        logger.info("Cleared cache")
    }

    // MARK: - Temp Files

    internal func cleanTempFiles() throws {
        guard CppBridge.FileManager.clearTemp() else {
            throw SDKException.fileManagement(.deleteFailed, "Failed to clean temp files")
        }
        logger.info("Cleaned temp files")
    }

    // MARK: - Storage Info

    internal func calculateDirectorySize(at url: URL) -> Int64 {
        return CppBridge.FileManager.calculateDirectorySize(at: url)
    }

    internal func getBaseDirectoryURL() -> URL {
        return URL(fileURLWithPath: baseFolder.path)
    }

    // MARK: - Private Helpers

    private func createFolderIfNeeded(at url: URL) throws -> Folder {
        if !FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true, attributes: nil)
        }
        return try Folder(path: url.path)
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
