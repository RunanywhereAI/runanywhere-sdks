import Foundation

/// Protocol for storage analysis operations
public protocol StorageAnalyzer {
    /// Get model storage usage information
    func getModelStorageUsage() async -> ModelStorageInfo

    /// Check storage availability for a model
    func checkStorageAvailable(for modelSize: Int64, safetyMargin: Double) -> StorageAvailability

    /// Get storage recommendations
    func getRecommendations(for storageInfo: StorageInfo) -> [StorageRecommendation]

    /// Calculate size at URL
    func calculateSize(at url: URL) async throws -> Int64
}
