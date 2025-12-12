//
//  FileManagement.swift
//  RunAnywhere SDK
//
//  Public entry point for the FileManagement capability
//  Provides access to file operations, storage management, and model file handling
//

import Foundation

/// Public entry point for the FileManagement capability
/// Provides simplified access to file operations, storage analysis, and model storage management
public final class FileManagement {

    // MARK: - Shared Instance

    /// Shared singleton instance for convenient access
    public static let shared = FileManagement()

    // MARK: - Properties

    private let fileManager: SimplifiedFileManager
    private let logger = SDKLogger(category: "FileManagement")

    // MARK: - Initialization

    /// Initialize with default file manager
    public convenience init() {
        do {
            let fileManager = try SimplifiedFileManager()
            self.init(fileManager: fileManager)
        } catch {
            fatalError("Failed to initialize FileManagement: \(error)")
        }
    }

    /// Initialize with custom file manager (for testing or customization)
    /// - Parameter fileManager: The file manager to use
    internal init(fileManager: SimplifiedFileManager) {
        self.fileManager = fileManager
        logger.debug("FileManagement initialized")
    }

    // MARK: - Public API

    /// Access the underlying file manager service
    /// Provides low-level file operations
    public var service: SimplifiedFileManager {
        return fileManager
    }

    /// Get storage analyzer for analyzing storage usage
    /// - Parameter modelRegistry: The model registry to use for analysis
    /// - Returns: A configured storage analyzer
    public func createStorageAnalyzer(with modelRegistry: ModelRegistry) -> StorageAnalyzer {
        return DefaultStorageAnalyzer(fileManager: fileManager, modelRegistry: modelRegistry)
    }

    // MARK: - Convenience Methods

    /// Get base directory URL for RunAnywhere files
    public var baseDirectory: URL {
        return fileManager.getBaseDirectoryURL()
    }

    /// Get available storage space in bytes
    public var availableSpace: Int64 {
        return fileManager.getAvailableSpace()
    }

    /// Get device storage information
    public var deviceStorage: DeviceStorageInfo {
        return fileManager.getDeviceStorageInfo()
    }

    /// Get total size of all stored files
    public var totalStorageSize: Int64 {
        return fileManager.getTotalStorageSize()
    }

    /// Get all stored models
    public var storedModels: [ModelFileInfo] {
        return fileManager.getAllStoredModels()
    }

    // MARK: - Model Operations

    /// Find model file by ID
    /// - Parameters:
    ///   - modelId: The model identifier
    ///   - expectedPath: Optional expected path to check first
    /// - Returns: URL to the model file, or nil if not found
    public func findModel(id modelId: String, expectedPath: String? = nil) -> URL? {
        return fileManager.findModelFile(modelId: modelId, expectedPath: expectedPath)
    }

    /// Delete a model
    /// - Parameter modelId: The model identifier to delete
    /// - Throws: Error if deletion fails
    public func deleteModel(id modelId: String) throws {
        try fileManager.deleteModel(modelId: modelId)
    }

    /// Check if a model exists
    /// - Parameters:
    ///   - modelId: The model identifier
    ///   - format: The model format
    /// - Returns: True if the model exists
    public func modelExists(id modelId: String, format: ModelFormat) -> Bool {
        return fileManager.modelExists(modelId: modelId, format: format)
    }

    // MARK: - Cache Operations

    /// Clear all cache files
    /// - Throws: Error if clearing fails
    public func clearCache() throws {
        try fileManager.clearCache()
        logger.info("Cache cleared successfully")
    }

    /// Clean temporary files
    /// - Throws: Error if cleaning fails
    public func cleanTempFiles() throws {
        try fileManager.cleanTempFiles()
        logger.info("Temporary files cleaned successfully")
    }
}
