//
//  FileManagementService.swift
//  RunAnywhere SDK
//
//  Core service protocol for file management operations
//  Defines the interface for file operations, model storage, and storage management
//

import Foundation
import Files

/// Protocol defining file management service capabilities
/// Implementations provide file operations, model storage, cache management, and storage analysis
public protocol FileManagementService: AnyObject {

    // MARK: - Directory Access

    /// Get the base RunAnywhere folder
    func getBaseFolder() -> Folder

    /// Get base directory URL
    func getBaseDirectoryURL() -> URL

    // MARK: - Model Storage Operations

    /// Get or create folder for a specific model
    /// - Parameter modelId: The model identifier
    /// - Returns: The model's folder
    /// - Throws: Error if folder cannot be created
    func getModelFolder(for modelId: String) throws -> Folder

    /// Get or create folder for a specific model with framework
    /// - Parameters:
    ///   - modelId: The model identifier
    ///   - framework: The LLM framework
    /// - Returns: The model's folder
    /// - Throws: Error if folder cannot be created
    func getModelFolder(for modelId: String, framework: InferenceFramework) throws -> Folder

    /// Store model data to storage
    /// - Parameters:
    ///   - data: The model data to store
    ///   - modelId: The model identifier
    ///   - format: The model format
    /// - Returns: URL to the stored model
    /// - Throws: Error if storage fails
    func storeModel(data: Data, modelId: String, format: ModelFormat) throws -> URL

    /// Store model data with framework specification
    /// - Parameters:
    ///   - data: The model data to store
    ///   - modelId: The model identifier
    ///   - format: The model format
    ///   - framework: The LLM framework
    /// - Returns: URL to the stored model
    /// - Throws: Error if storage fails
    func storeModel(data: Data, modelId: String, format: ModelFormat, framework: InferenceFramework) throws -> URL

    /// Load model data from storage
    /// - Parameters:
    ///   - modelId: The model identifier
    ///   - format: The model format
    /// - Returns: The model data
    /// - Throws: Error if loading fails
    func loadModel(modelId: String, format: ModelFormat) throws -> Data

    /// Check if a model exists in storage
    /// - Parameters:
    ///   - modelId: The model identifier
    ///   - format: The model format
    /// - Returns: True if the model exists
    func modelExists(modelId: String, format: ModelFormat) -> Bool

    /// Delete a model from storage
    /// - Parameter modelId: The model identifier to delete
    /// - Throws: Error if deletion fails
    func deleteModel(modelId: String) throws

    /// Find model file by searching all possible locations
    /// - Parameters:
    ///   - modelId: The model identifier
    ///   - expectedPath: Optional expected path to check first
    /// - Returns: URL to the model file, or nil if not found
    func findModelFile(modelId: String, expectedPath: String?) -> URL?

    /// Get URL for model file
    /// - Parameters:
    ///   - modelId: The model identifier
    ///   - format: The model format
    /// - Returns: URL to the model file
    /// - Throws: Error if model file not found
    func getModelURL(modelId: String, format: ModelFormat) throws -> URL

    // MARK: - Download Management

    /// Get download folder
    /// - Returns: The download folder
    /// - Throws: Error if folder cannot be accessed
    func getDownloadFolder() throws -> Folder

    /// Create temporary download file
    /// - Parameter modelId: The model identifier
    /// - Returns: A temporary file for downloading
    /// - Throws: Error if file creation fails
    func createTempDownloadFile(for modelId: String) throws -> File

    /// Move downloaded file to model storage
    /// - Parameters:
    ///   - tempFile: The temporary downloaded file
    ///   - modelId: The model identifier
    ///   - format: The model format
    /// - Returns: URL to the final model location
    /// - Throws: Error if move fails
    func moveDownloadToStorage(tempFile: File, modelId: String, format: ModelFormat) throws -> URL

    // MARK: - Cache Management

    /// Store data in cache
    /// - Parameters:
    ///   - key: The cache key
    ///   - data: The data to cache
    /// - Throws: Error if storage fails
    func storeCache(key: String, data: Data) throws

    /// Load data from cache
    /// - Parameter key: The cache key
    /// - Returns: Cached data, or nil if not found
    /// - Throws: Error if loading fails
    func loadCache(key: String) throws -> Data?

    /// Clear all cache
    /// - Throws: Error if clearing fails
    func clearCache() throws

    // MARK: - Temporary Files

    /// Clean temporary files
    /// - Throws: Error if cleaning fails
    func cleanTempFiles() throws

    // MARK: - Storage Information

    /// Get total storage size used by the app
    /// - Returns: Total size in bytes
    func getTotalStorageSize() -> Int64

    /// Get model storage size
    /// - Returns: Model storage size in bytes
    func getModelStorageSize() -> Int64

    /// Get all stored models
    /// - Returns: Array of stored model information
    func getAllStoredModels() -> [ModelFileInfo]

    /// Get available storage space
    /// - Returns: Available space in bytes
    func getAvailableSpace() -> Int64

    /// Get device storage information
    /// - Returns: Device storage details
    func getDeviceStorageInfo() -> DeviceStorageInfo

    // MARK: - File Metadata

    /// Get file creation date
    /// - Parameter url: The file URL
    /// - Returns: Creation date, or nil if not available
    func getFileCreationDate(at url: URL) -> Date?

    /// Get file last access/modification date
    /// - Parameter url: The file URL
    /// - Returns: Last access date, or nil if not available
    func getFileAccessDate(at url: URL) -> Date?

    /// Get file size
    /// - Parameter url: The file URL
    /// - Returns: File size in bytes, or nil if not available
    func getFileSize(at url: URL) -> Int64?

    /// Calculate the total size of a directory
    /// - Parameter url: The directory URL
    /// - Returns: Total size in bytes
    func calculateDirectorySize(at url: URL) -> Int64
}
