import Foundation

/// Manages storage alerts and notifications
public class StorageAlertManager {

    // MARK: - Properties

    private let logger = SDKLogger(category: "StorageAlertManager")
    private var alertCallbacks: [(StorageAlert) -> Void] = []
    private var recentAlerts: [StorageAlert] = []
    private let maxRecentAlerts = 50

    // Storage thresholds
    private let warningThreshold: Double = 0.90 // 90% full
    private let criticalThreshold: Double = 0.95 // 95% full
    private let modelSpaceThreshold: Double = 0.20 // Models using >20% of device storage

    // MARK: - Public Methods

    /// Check storage info for alerts
    public func checkStorageAlerts(info: StorageInfo) -> [StorageAlert] {
        var alerts: [StorageAlert] = []

        // Check device storage
        let deviceUsageRatio = Double(info.deviceStorage.usedSpace) / Double(info.deviceStorage.totalSpace)

        if deviceUsageRatio > criticalThreshold {
            let alert = createAlert(
                type: .critical,
                message: "Device storage critical: \(Int(deviceUsageRatio * 100))% full"
            )
            alerts.append(alert)
        } else if deviceUsageRatio > warningThreshold {
            let alert = createAlert(
                type: .warning,
                message: "Device storage warning: \(Int(deviceUsageRatio * 100))% full"
            )
            alerts.append(alert)
        }

        // Check if models take up too much space
        let modelsRatio = Double(info.modelStorage.totalSize) / Double(info.deviceStorage.totalSpace)
        if modelsRatio > modelSpaceThreshold {
            let alert = createAlert(
                type: .info,
                message: "Models using \(Int(modelsRatio * 100))% of device storage"
            )
            alerts.append(alert)
        }

        // Check cache size
        if info.cacheSize > 2_000_000_000 { // 2GB
            let formatter = ByteCountFormatter()
            formatter.countStyle = .binary
            let cacheString = formatter.string(fromByteCount: info.cacheSize)

            let alert = createAlert(
                type: .warning,
                message: "Large cache size: \(cacheString)"
            )
            alerts.append(alert)
        }

        // Notify callbacks
        for alert in alerts {
            notifyAlert(alert)
        }

        return alerts
    }

    /// Add alert callback
    public func addAlertCallback(_ callback: @escaping (StorageAlert) -> Void) {
        alertCallbacks.append(callback)
    }

    /// Remove all alert callbacks
    public func removeAllCallbacks() {
        alertCallbacks.removeAll()
    }

    /// Get recent alerts
    public func getRecentAlerts(count: Int = 10) -> [StorageAlert] {
        return Array(recentAlerts.prefix(count))
    }

    /// Clear recent alerts
    public func clearRecentAlerts() {
        recentAlerts.removeAll()
    }

    /// Check if alert should be suppressed (to avoid spam)
    public func shouldSuppressAlert(_ alert: StorageAlert) -> Bool {
        // Check if similar alert was sent recently (within 5 minutes)
        let recentCutoff = Date().addingTimeInterval(-300)

        return recentAlerts.contains { recentAlert in
            recentAlert.type == alert.type &&
            recentAlert.message == alert.message &&
            recentAlert.timestamp > recentCutoff
        }
    }

    // MARK: - Private Methods

    private func createAlert(type: StorageAlertType, message: String) -> StorageAlert {
        let alert = StorageAlert(
            type: type,
            message: message,
            timestamp: Date()
        )

        // Log the alert
        switch type {
        case .info:
            logger.info("Storage alert: \(message)")
        case .warning:
            logger.warning("Storage warning: \(message)")
        case .critical:
            logger.error("Storage critical: \(message)")
        }

        return alert
    }

    private func notifyAlert(_ alert: StorageAlert) {
        // Add to recent alerts
        recentAlerts.insert(alert, at: 0)
        if recentAlerts.count > maxRecentAlerts {
            recentAlerts = Array(recentAlerts.prefix(maxRecentAlerts))
        }

        // Notify callbacks unless suppressed
        if !shouldSuppressAlert(alert) {
            for callback in alertCallbacks {
                callback(alert)
            }
        }
    }
}
