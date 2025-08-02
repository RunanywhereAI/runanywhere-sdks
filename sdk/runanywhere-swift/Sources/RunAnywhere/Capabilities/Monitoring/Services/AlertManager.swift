//
//  AlertManager.swift
//  RunAnywhere SDK
//
//  Manages performance alerts
//

import Foundation

/// Manages performance alerts and notifications
internal class AlertManager {
    private let logger = SDKLogger(category: "AlertManager")
    private var alerts: [PerformanceAlert] = []
    private var alertCallbacks: [(PerformanceAlert) -> Void] = []
    private let queue = DispatchQueue(label: "com.runanywhere.sdk.alertmanager")
    private let alertRetentionTime: TimeInterval = 300 // 5 minutes

    /// Performance thresholds
    private let thresholds: PerformanceThresholds

    init(thresholds: PerformanceThresholds = .default) {
        self.thresholds = thresholds
    }

    /// Check system metrics and create alerts if needed
    func checkSystemHealth(metrics: LiveMetrics) {
        queue.async { [weak self] in
            guard let self = self else { return }

            let memoryUsageRatio = Double(metrics.memoryUsage) / Double(ProcessInfo.processInfo.physicalMemory)

            // Check memory threshold
            if memoryUsageRatio > self.thresholds.maxMemoryUsage {
                self.createAlert(
                    type: .highMemoryUsage,
                    severity: .warning,
                    message: "Memory usage at \(Int(memoryUsageRatio * 100))%"
                )
            }

            // Check CPU threshold
            if metrics.cpuUsage > self.thresholds.maxCPUUsage {
                self.createAlert(
                    type: .highCPUUsage,
                    severity: .warning,
                    message: "CPU usage at \(Int(metrics.cpuUsage * 100))%"
                )
            }

            // Check thermal state
            if metrics.thermalState == .serious || metrics.thermalState == .critical {
                self.createAlert(
                    type: .thermalThrottle,
                    severity: .critical,
                    message: "Device thermal state: \(self.thermalStateString(metrics.thermalState))"
                )
            }
        }
    }

    /// Check generation performance and create alerts if needed
    func checkGenerationPerformance(_ summary: GenerationSummary) {
        queue.async { [weak self] in
            guard let self = self else { return }

            // Check tokens per second
            if summary.tokensPerSecond < self.thresholds.minTokensPerSecond {
                self.createAlert(
                    type: .lowPerformance,
                    severity: .info,
                    message: "Low token generation speed: \(String(format: "%.1f", summary.tokensPerSecond)) tokens/sec"
                )
            }

            // Check latency
            if summary.timeToFirstToken > self.thresholds.maxLatency {
                self.createAlert(
                    type: .highLatency,
                    severity: .warning,
                    message: "High latency: \(String(format: "%.2f", summary.timeToFirstToken))s to first token"
                )
            }
        }
    }

    /// Create a memory warning alert
    func createMemoryWarning() {
        queue.async { [weak self] in
            self?.createAlert(
                type: .memoryWarning,
                severity: .critical,
                message: "System memory warning received"
            )
        }
    }

    /// Add a callback for alerts
    func addAlertCallback(_ callback: @escaping (PerformanceAlert) -> Void) {
        queue.async { [weak self] in
            self?.alertCallbacks.append(callback)
        }
    }

    /// Get all current alerts
    func getAllAlerts() -> [PerformanceAlert] {
        queue.sync {
            return alerts
        }
    }

    /// Get recent alerts within time range
    func getRecentAlerts(withinTimeRange timeRange: TimeInterval) -> [PerformanceAlert] {
        queue.sync {
            let cutoff = Date().addingTimeInterval(-timeRange)
            return alerts.filter { $0.timestamp > cutoff }
        }
    }

    // MARK: - Private Methods

    private func createAlert(type: AlertType, severity: AlertSeverity, message: String) {
        let alert = PerformanceAlert(
            type: type,
            severity: severity,
            message: message
        )

        alerts.append(alert)

        // Clean up old alerts
        let cutoff = Date().addingTimeInterval(-alertRetentionTime)
        alerts = alerts.filter { $0.timestamp > cutoff }

        // Notify callbacks
        for callback in alertCallbacks {
            callback(alert)
        }

        // Log alert
        switch severity {
        case .info:
            logger.info("Performance alert: \(message)")
        case .warning:
            logger.warning("Performance warning: \(message)")
        case .critical:
            logger.error("Performance critical: \(message)")
        }
    }

    private func thermalStateString(_ state: ProcessInfo.ThermalState) -> String {
        switch state {
        case .nominal: return "Nominal"
        case .fair: return "Fair"
        case .serious: return "Serious"
        case .critical: return "Critical"
        @unknown default: return "Unknown"
        }
    }
}
