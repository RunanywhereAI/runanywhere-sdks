import Foundation

/// Implementation of storage monitoring
public class StorageMonitorImpl: StorageMonitoring {
    private var _isMonitoring = false
    private var monitoringTask: Task<Void, Never>?
    private let storageAnalyzer: StorageAnalyzerImpl

    public init(
        storageAnalyzer: StorageAnalyzerImpl = StorageAnalyzerImpl()
    ) {
        self.storageAnalyzer = storageAnalyzer
    }

    // MARK: - StorageMonitoring Protocol

    public var isMonitoring: Bool {
        return _isMonitoring
    }

    public func startMonitoring() {
        guard !_isMonitoring else { return }

        _isMonitoring = true

        // Start periodic monitoring
        monitoringTask = Task {
            while !Task.isCancelled && _isMonitoring {
                await performMonitoringCycle()

                // Wait 30 seconds before next cycle
                try? await Task.sleep(nanoseconds: 30_000_000_000)
            }
        }
    }

    public func stopMonitoring() {
        _isMonitoring = false
        monitoringTask?.cancel()
        monitoringTask = nil
    }

    public func getStorageInfo() async -> StorageInfo {
        return await storageAnalyzer.analyzeStorage()
    }

    // MARK: - Private Methods

    private func performMonitoringCycle() async {
        let storageInfo = await getStorageInfo()

        // Check for storage alerts
        await checkStorageAlerts(storageInfo)

        // Update internal state if needed
        await updateInternalState(storageInfo)
    }

    private func checkStorageAlerts(_ storageInfo: StorageInfo) async {
        // Check free space thresholds
        let freeSpaceRatio = Double(storageInfo.deviceStorage.freeSpace) / Double(storageInfo.deviceStorage.totalSpace)

        if freeSpaceRatio < 0.05 { // Less than 5% free
            await raiseStorageAlert(.criticallyLow, message: "Device storage critically low: \(freeSpaceRatio * 100)% free")
        } else if freeSpaceRatio < 0.10 { // Less than 10% free
            await raiseStorageAlert(.low, message: "Device storage low: \(freeSpaceRatio * 100)% free")
        }

        // Check app storage growth
        if storageInfo.appStorage.totalSize > 1_000_000_000 { // > 1GB
            await raiseStorageAlert(.warning, message: "App storage has grown to \(formatBytes(storageInfo.appStorage.totalSize))")
        }
    }

    private func updateInternalState(_ storageInfo: StorageInfo) async {
        // Update any internal caches or state based on storage info
        // This could include updating model recommendations, cleanup suggestions, etc.
    }

    private func raiseStorageAlert(_ severity: StorageAlertSeverity, message: String) async {
        // Log the alert
        print("Storage Alert [\(severity)]: \(message)")

        // In a real implementation, this would notify observers or call handlers
    }

    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}

// MARK: - Supporting Types

public enum StorageAlertSeverity {
    case warning
    case low
    case criticallyLow
}
