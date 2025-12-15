//
//  FileManagementService.swift
//  RunAnywhere SDK
//
//  Core protocol for file management operations.
//
//  Directory Structure:
//  Documents/RunAnywhere/
//    Models/{framework}/{modelId}/[files]
//    Cache/
//    Temp/
//    Downloads/
//

import Foundation
import Files

/// Protocol defining file management capabilities
public protocol FileManagementService: AnyObject {

    // MARK: - Model Storage

    /// Get or create folder for a model: Models/{framework}/{modelId}/
    func getModelFolder(for modelId: String, framework: InferenceFramework) throws -> Folder

    /// Get model folder URL (without creating it)
    func getModelFolderURL(modelId: String, framework: InferenceFramework) throws -> URL

    /// Check if a model folder exists and has contents
    func modelFolderExists(modelId: String, framework: InferenceFramework) -> Bool

    /// Delete a model folder
    func deleteModel(modelId: String, framework: InferenceFramework) throws

    /// Get all downloaded models by framework
    func getDownloadedModels() -> [InferenceFramework: [String]]

    /// Check if a specific model is downloaded (uses storage strategy if available)
    @MainActor func isModelDownloaded(modelId: String, framework: InferenceFramework) -> Bool

    // MARK: - Download Management

    /// Get downloads folder
    func getDownloadFolder() throws -> Folder

    /// Create temp file for download
    func createTempDownloadFile(for modelId: String) throws -> File

    // MARK: - Cache

    func storeCache(key: String, data: Data) throws
    func loadCache(key: String) throws -> Data?
    func clearCache() throws

    // MARK: - Temp Files

    func cleanTempFiles() throws

    // MARK: - Storage Info

    func getAvailableSpace() -> Int64
    func getDeviceStorageInfo() -> DeviceStorageInfo
    func calculateDirectorySize(at url: URL) -> Int64
    func getBaseDirectoryURL() -> URL
}
