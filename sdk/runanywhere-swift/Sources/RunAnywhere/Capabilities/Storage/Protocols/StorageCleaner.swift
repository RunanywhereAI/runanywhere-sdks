import Foundation

/// Protocol for storage cleanup operations
public protocol StorageCleaner {
    /// Clean up cache and temporary files
    func cleanupCache() async throws -> CleanupResult

    /// Delete a specific model
    func deleteModel(at path: URL) async throws -> Int64

    /// Clean a specific directory
    func cleanDirectory(at url: URL) async throws -> Int64

    /// Get cache directories
    func getCacheDirectories() -> [URL]
}
