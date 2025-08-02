import Foundation

/// Main storage service coordinating all storage operations
public class StorageService: StorageMonitoring {

    // MARK: - Properties

    public private(set) var isMonitoring = false
    private let analyzer: StorageAnalyzerImpl
    private let cleaner: StorageCleanerImpl
    private let deviceMonitor: DeviceStorageMonitor
    private let alertManager: StorageAlertManager
    private let logger = SDKLogger(category: "StorageService")

    private let queue = DispatchQueue(label: "com.runanywhere.sdk.storageservice", qos: .utility)
    private var monitoringTimer: Timer?
    private let updateInterval: TimeInterval = 60.0 // Update every minute

    // Storage information
    public private(set) var storageInfo: StorageInfo?

    // Callbacks
    private var storageCallbacks: [(StorageInfo) -> Void] = []

    // MARK: - Initialization

    public init() {
        self.analyzer = StorageAnalyzerImpl()
        self.cleaner = StorageCleanerImpl()
        self.deviceMonitor = DeviceStorageMonitor()
        self.alertManager = StorageAlertManager()
    }

    // MARK: - StorageMonitoring Protocol

    public func startMonitoring() {
        queue.async { [weak self] in
            guard let self = self, !self.isMonitoring else { return }

            self.isMonitoring = true
            self.logger.info("Started storage monitoring")

            // Initial update
            Task {
                await self.updateStorageInfo()
            }

            // Start periodic updates
            DispatchQueue.main.async {
                self.monitoringTimer = Timer.scheduledTimer(withTimeInterval: self.updateInterval, repeats: true) { _ in
                    Task {
                        await self.updateStorageInfo()
                    }
                }
            }
        }
    }

    public func stopMonitoring() {
        queue.async { [weak self] in
            guard let self = self else { return }

            self.isMonitoring = false
            DispatchQueue.main.async {
                self.monitoringTimer?.invalidate()
                self.monitoringTimer = nil
            }
            self.logger.info("Stopped storage monitoring")
        }
    }

    public func getStorageInfo() async -> StorageInfo {
        if let info = storageInfo {
            return info
        }
        return await updateStorageInfo()
    }

    // MARK: - Public Methods

    /// Refresh storage information immediately
    public func refreshStorageInfo() async -> StorageInfo {
        return await updateStorageInfo()
    }

    /// Get model storage usage
    public func getModelStorageUsage() async -> ModelStorageInfo {
        return await analyzer.getModelStorageUsage()
    }

    /// Check if there's enough storage for a model
    public func checkStorageAvailable(for modelSize: Int64, safetyMargin: Double = 1.2) -> StorageAvailability {
        return analyzer.checkStorageAvailable(for: modelSize, safetyMargin: safetyMargin)
    }

    /// Clean up cache and temporary files
    public func cleanupCache() async throws -> CleanupResult {
        return try await cleaner.cleanupCache()
    }

    /// Delete a specific model
    public func deleteModel(at path: URL) async throws -> Int64 {
        let size = try await cleaner.deleteModel(at: path)

        // Update storage info
        await updateStorageInfo()

        return size
    }

    /// Add storage update callback
    public func addStorageCallback(_ callback: @escaping (StorageInfo) -> Void) {
        queue.async { [weak self] in
            self?.storageCallbacks.append(callback)
        }
    }

    /// Get storage recommendations
    public func getRecommendations() -> [StorageRecommendation] {
        guard let info = storageInfo else { return [] }
        return analyzer.getRecommendations(for: info)
    }

    // MARK: - Private Methods

    @discardableResult
    private func updateStorageInfo() async -> StorageInfo {
        do {
            // Gather all storage information
            let appStorage = try await analyzer.calculateAppStorageUsage()
            let deviceStorage = deviceMonitor.getDeviceStorageInfo()
            let modelStorage = await analyzer.getModelStorageUsage()
            let cacheSize = await analyzer.calculateCacheSize()
            let storedModels = await analyzer.scanForModels()

            let info = StorageInfo(
                appStorage: appStorage,
                deviceStorage: deviceStorage,
                modelStorage: modelStorage,
                cacheSize: cacheSize,
                storedModels: storedModels,
                lastUpdated: Date()
            )

            queue.sync {
                self.storageInfo = info
            }

            // Check for alerts
            let alerts = alertManager.checkStorageAlerts(info: info)
            for alert in alerts {
                logger.info("Storage alert: \(alert.message)")
            }

            // Notify callbacks
            for callback in storageCallbacks {
                callback(info)
            }

            return info
        } catch {
            logger.error("Failed to update storage info: \(error)")
            return StorageInfo.empty
        }
    }

    // MARK: - Health Check

    /// Check if the storage service is healthy and operational
    public func isHealthy() async -> Bool {
        // Basic health check - ensure storage is accessible
        do {
            _ = try await analyzer.analyzeStorage()
            return true
        } catch {
            return false
        }
    }
}
