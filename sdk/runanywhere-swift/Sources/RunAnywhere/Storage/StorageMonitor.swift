import Foundation

/// Storage monitoring service for tracking model storage and device capacity
/// This is a compatibility wrapper that delegates to the new modular storage system
public class StorageMonitor {
    public static let shared = StorageMonitor()

    // MARK: - Properties

    private let storageService: StorageService
    private let alertManager: StorageAlertManager

    /// Current storage information
    public var storageInfo: StorageInfo? {
        return storageService.storageInfo
    }

    /// Whether monitoring is active
    public var isMonitoring: Bool {
        return storageService.isMonitoring
    }

    // MARK: - Initialization

    private init() {
        self.storageService = StorageService()
        self.alertManager = StorageAlertManager()
    }

    // MARK: - Public Methods

    /// Start storage monitoring
    public func startMonitoring() {
        storageService.startMonitoring()
    }

    /// Stop storage monitoring
    public func stopMonitoring() {
        storageService.stopMonitoring()
    }

    /// Refresh storage information immediately
    public func refreshStorageInfo() async -> StorageInfo {
        return await storageService.refreshStorageInfo()
    }

    /// Get storage usage for models
    public func getModelStorageUsage() async -> ModelStorageInfo {
        return await storageService.getModelStorageUsage()
    }

    /// Check if there's enough storage for a model
    public func checkStorageAvailable(for modelSize: Int64, safetyMargin: Double = 1.2) -> StorageAvailability {
        return storageService.checkStorageAvailable(for: modelSize, safetyMargin: safetyMargin)
    }

    /// Clean up cache and temporary files
    public func cleanupCache() async throws -> CleanupResult {
        return try await storageService.cleanupCache()
    }

    /// Delete a specific model
    public func deleteModel(at path: URL) async throws -> Int64 {
        return try await storageService.deleteModel(at: path)
    }

    /// Add storage update callback
    public func addStorageCallback(_ callback: @escaping (StorageInfo) -> Void) {
        storageService.addStorageCallback(callback)
    }

    /// Add alert callback
    public func addAlertCallback(_ callback: @escaping (StorageAlert) -> Void) {
        alertManager.addAlertCallback(callback)
    }

    /// Get storage recommendations
    public func getRecommendations() -> [StorageRecommendation] {
        return storageService.getRecommendations()
    }
}
