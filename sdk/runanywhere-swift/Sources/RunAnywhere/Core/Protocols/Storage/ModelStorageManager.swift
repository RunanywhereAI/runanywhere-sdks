import Foundation

/// Protocol for model storage management
public protocol ModelStorageManager {
    /// Get storage directory for models
    /// - Returns: URL to models directory
    func getModelsDirectory() -> URL

    /// Get path for a specific model
    /// - Parameter modelId: Model identifier
    /// - Returns: Path where model should be stored
    func getModelPath(for modelId: String) -> URL

    /// Check if model exists locally
    /// - Parameter modelId: Model identifier
    /// - Returns: Whether model exists
    func modelExists(_ modelId: String) -> Bool

    /// Get model size on disk
    /// - Parameter modelId: Model identifier
    /// - Returns: Size in bytes
    func getModelSize(_ modelId: String) -> Int64?

    /// Delete a model
    /// - Parameter modelId: Model identifier
    func deleteModel(_ modelId: String) async throws

    /// Get available storage space
    /// - Returns: Available space in bytes
    func getAvailableSpace() -> Int64

    /// List all stored models
    /// - Returns: Array of stored model identifiers
    func listStoredModels() -> [String]

    /// Clean up temporary files
    func cleanupTemporaryFiles() async throws

    /// Move model from temporary to permanent storage
    /// - Parameters:
    ///   - temporaryPath: Temporary file path
    ///   - modelId: Model identifier
    /// - Returns: Final storage path
    func moveToStorage(from temporaryPath: URL, modelId: String) async throws -> URL
}
