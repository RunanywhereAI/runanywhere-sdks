import Foundation

/// Protocol for storage monitoring operations
public protocol StorageMonitoring {
    /// Start monitoring storage
    func startMonitoring()

    /// Stop monitoring storage
    func stopMonitoring()

    /// Get current storage information
    func getStorageInfo() async -> StorageInfo

    /// Check if monitoring is active
    var isMonitoring: Bool { get }
}
