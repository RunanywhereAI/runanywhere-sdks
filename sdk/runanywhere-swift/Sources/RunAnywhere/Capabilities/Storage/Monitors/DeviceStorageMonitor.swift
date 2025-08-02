import Foundation

/// Monitors device storage information
public class DeviceStorageMonitor {

    // MARK: - Properties

    private let fileManager = FileManager.default
    private let logger = SDKLogger(category: "DeviceStorageMonitor")

    // MARK: - Public Methods

    /// Get current device storage information
    public func getDeviceStorageInfo() -> DeviceStorageInfo {
        do {
            let systemAttributes = try fileManager.attributesOfFileSystem(forPath: NSHomeDirectory())
            let totalSpace = systemAttributes[.systemSize] as? Int64 ?? 0
            let freeSpace = systemAttributes[.systemFreeSize] as? Int64 ?? 0

            return DeviceStorageInfo(
                totalSpace: totalSpace,
                freeSpace: freeSpace,
                usedSpace: totalSpace - freeSpace
            )
        } catch {
            logger.error("Failed to get device storage info: \(error)")
            return DeviceStorageInfo(totalSpace: 0, freeSpace: 0, usedSpace: 0)
        }
    }

    /// Monitor device storage changes
    public func startMonitoring(interval: TimeInterval = 60.0, callback: @escaping (DeviceStorageInfo) -> Void) -> Timer {
        let timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { _ in
            let info = self.getDeviceStorageInfo()
            callback(info)
        }

        // Initial callback
        callback(getDeviceStorageInfo())

        return timer
    }

    /// Check if device has low storage
    public func isLowStorage(threshold: Double = 0.90) -> Bool {
        let info = getDeviceStorageInfo()
        guard info.totalSpace > 0 else { return false }

        let usageRatio = Double(info.usedSpace) / Double(info.totalSpace)
        return usageRatio > threshold
    }

    /// Get formatted storage strings
    public func getFormattedStorageInfo() -> (total: String, free: String, used: String, percentage: String) {
        let info = getDeviceStorageInfo()
        let formatter = ByteCountFormatter()
        formatter.countStyle = .binary

        let total = formatter.string(fromByteCount: info.totalSpace)
        let free = formatter.string(fromByteCount: info.freeSpace)
        let used = formatter.string(fromByteCount: info.usedSpace)
        let percentage = String(format: "%.1f%%", info.usagePercentage)

        return (total: total, free: free, used: used, percentage: percentage)
    }

    /// Get available space for downloads
    public func getAvailableDownloadSpace(reserveSpace: Int64 = 500_000_000) -> Int64 {
        let info = getDeviceStorageInfo()
        let availableSpace = info.freeSpace - reserveSpace
        return max(0, availableSpace)
    }
}
