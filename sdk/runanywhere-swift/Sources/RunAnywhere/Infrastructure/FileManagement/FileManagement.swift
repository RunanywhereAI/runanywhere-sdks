//
//  FileManagement.swift
//  RunAnywhere SDK
//
//  Public entry point for file management operations.
//

import Foundation

/// Public entry point for file management
public final class FileManagement {

    // MARK: - Shared Instance

    public static let shared = FileManagement()

    // MARK: - Properties

    private let fileManager: SimplifiedFileManager
    private let logger = SDKLogger(category: "FileManagement")

    // MARK: - Initialization

    public convenience init() {
        do {
            let fileManager = try SimplifiedFileManager()
            self.init(fileManager: fileManager)
        } catch {
            fatalError("Failed to initialize FileManagement: \(error)")
        }
    }

    internal init(fileManager: SimplifiedFileManager) {
        self.fileManager = fileManager
    }

    // MARK: - Public API

    /// Access the underlying file manager
    public var service: SimplifiedFileManager {
        return fileManager
    }

    /// Base directory URL
    public var baseDirectory: URL {
        return fileManager.getBaseDirectoryURL()
    }

    /// Available storage space in bytes
    public var availableSpace: Int64 {
        return fileManager.getAvailableSpace()
    }

    /// Device storage information
    public var deviceStorage: DeviceStorageInfo {
        return fileManager.getDeviceStorageInfo()
    }

    // MARK: - Model Operations

    /// Check if a model is downloaded
    @MainActor
    public func isModelDownloaded(modelId: String, framework: InferenceFramework) -> Bool {
        return fileManager.isModelDownloaded(modelId: modelId, framework: framework)
    }

    /// Get model folder URL
    public func getModelFolderURL(modelId: String, framework: InferenceFramework) throws -> URL {
        return try fileManager.getModelFolderURL(modelId: modelId, framework: framework)
    }

    /// Delete a model
    public func deleteModel(modelId: String, framework: InferenceFramework) throws {
        try fileManager.deleteModel(modelId: modelId, framework: framework)
        logger.info("Deleted model: \(modelId)")
    }

    /// Get all downloaded models
    public func getDownloadedModels() -> [InferenceFramework: [String]] {
        return fileManager.getDownloadedModels()
    }

    // MARK: - Cache Operations

    public func clearCache() throws {
        try fileManager.clearCache()
        logger.info("Cache cleared")
    }

    public func cleanTempFiles() throws {
        try fileManager.cleanTempFiles()
        logger.info("Temp files cleaned")
    }

    // MARK: - Storage Analysis

    /// Create a storage analyzer
    public func createStorageAnalyzer(with modelRegistry: ModelRegistry) -> StorageAnalyzer {
        return DefaultStorageAnalyzer(fileManager: fileManager, modelRegistry: modelRegistry)
    }
}
