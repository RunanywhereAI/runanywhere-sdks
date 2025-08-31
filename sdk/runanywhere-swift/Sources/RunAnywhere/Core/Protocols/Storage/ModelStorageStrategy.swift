import Foundation

/// Protocol for custom model storage strategies that handle both downloading and file management
/// This extends the DownloadStrategy concept to include file discovery and management
public protocol ModelStorageStrategy: DownloadStrategy {

    /// Find the model file/folder in storage
    /// - Parameters:
    ///   - modelId: The model identifier
    ///   - modelFolder: The folder where the model is stored
    /// - Returns: URL to the model (could be a file or folder depending on the model type)
    func findModelPath(modelId: String, in modelFolder: URL) -> URL?

    /// Detect if a model exists in the given folder
    /// - Parameters:
    ///   - modelFolder: The folder to check
    /// - Returns: Model information if found, nil otherwise
    func detectModel(in modelFolder: URL) -> (format: ModelFormat, size: Int64)?

    /// Check if the model storage is valid (all required files present)
    /// - Parameters:
    ///   - modelFolder: The folder containing the model
    /// - Returns: true if the model storage is valid
    func isValidModelStorage(at modelFolder: URL) -> Bool

    /// Get display information for the model
    /// - Parameters:
    ///   - modelFolder: The folder containing the model
    /// - Returns: Human-readable information about the model storage
    func getModelStorageInfo(at modelFolder: URL) -> ModelStorageDetails?
}

/// Information about model storage details
public struct ModelStorageDetails {
    public let format: ModelFormat
    public let totalSize: Int64
    public let fileCount: Int
    public let primaryFile: String? // Main file for single-file models, nil for multi-file
    public let isDirectoryBased: Bool

    public init(
        format: ModelFormat,
        totalSize: Int64,
        fileCount: Int,
        primaryFile: String? = nil,
        isDirectoryBased: Bool = false
    ) {
        self.format = format
        self.totalSize = totalSize
        self.fileCount = fileCount
        self.primaryFile = primaryFile
        self.isDirectoryBased = isDirectoryBased
    }
}

/// Default implementation for simple single-file models
public extension ModelStorageStrategy {

    func findModelPath(modelId: String, in modelFolder: URL) -> URL? {
        // Default: look for a single file with the model ID
        let fileManager = FileManager.default
        do {
            let files = try fileManager.contentsOfDirectory(at: modelFolder, includingPropertiesForKeys: nil)
            for file in files {
                let fileName = file.lastPathComponent
                if fileName.contains(modelId) {
                    return file
                }
            }
        } catch {
            return nil
        }
        return nil
    }

    func detectModel(in modelFolder: URL) -> (format: ModelFormat, size: Int64)? {
        // Default: detect single file models
        let fileManager = FileManager.default
        do {
            let files = try fileManager.contentsOfDirectory(at: modelFolder, includingPropertiesForKeys: [.fileSizeKey])
            for file in files {
                let ext = file.pathExtension.lowercased()
                if let format = ModelFormat(rawValue: ext) {
                    let size = try file.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                    return (format, Int64(size))
                }
            }
        } catch {
            return nil
        }
        return nil
    }

    func isValidModelStorage(at modelFolder: URL) -> Bool {
        // Default: check if at least one model file exists
        return detectModel(in: modelFolder) != nil
    }

    func getModelStorageInfo(at modelFolder: URL) -> ModelStorageDetails? {
        guard let modelInfo = detectModel(in: modelFolder) else { return nil }

        let fileManager = FileManager.default
        let files = (try? fileManager.contentsOfDirectory(at: modelFolder, includingPropertiesForKeys: nil)) ?? []

        return ModelStorageDetails(
            format: modelInfo.format,
            totalSize: modelInfo.size,
            fileCount: files.count,
            primaryFile: files.first?.lastPathComponent,
            isDirectoryBased: false
        )
    }
}
