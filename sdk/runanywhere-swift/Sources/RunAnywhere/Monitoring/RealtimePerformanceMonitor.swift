//
//  RealtimePerformanceMonitor.swift
//  RunAnywhere SDK
//
//  Real-time performance monitoring infrastructure for on-device AI
//

import Foundation
import os.log

/// Real-time performance monitoring for on-device AI inference
public class RealtimePerformanceMonitor {
    public static let shared = RealtimePerformanceMonitor()

    // MARK: - Properties

    /// Current live metrics
    public private(set) var currentMetrics = LiveMetrics()

    /// Whether monitoring is active
    public private(set) var isMonitoring = false

    /// Performance history snapshots
    public private(set) var performanceHistory: [PerformanceSnapshot] = []

    /// Active performance alerts
    public private(set) var alerts: [PerformanceAlert] = []

    // MARK: - Private Properties

    private let logger = os.Logger(subsystem: "com.runanywhere.sdk", category: "PerformanceMonitoring")
    private var monitoringTimer: Timer?
    private let updateInterval: TimeInterval = 0.1 // 100ms updates
    private let historyLimit = 300 // Keep last 30 seconds at 100ms intervals
    private let queue = DispatchQueue(label: "com.runanywhere.sdk.performancemonitor", qos: .utility)

    // Performance thresholds
    private let thresholds = PerformanceThresholds(
        maxMemoryUsage: 0.8, // 80% of available memory
        minTokensPerSecond: 10.0,
        maxLatency: 5.0,
        maxCPUUsage: 0.9 // 90% CPU
    )

    // Current generation tracking
    private var activeGeneration: GenerationTracking?

    // Callbacks for alerts
    private var alertCallbacks: [(PerformanceAlert) -> Void] = []

    // MARK: - Initialization

    private init() {
        setupSystemMonitoring()
    }

    // MARK: - Public Methods

    /// Start monitoring system performance
    public func startMonitoring() {
        queue.async { [weak self] in
            guard let self = self, !self.isMonitoring else { return }

            self.isMonitoring = true
            self.logger.info("Started real-time performance monitoring")

            // Start periodic updates on main queue for timer
            DispatchQueue.main.async {
                self.monitoringTimer = Timer.scheduledTimer(withTimeInterval: self.updateInterval, repeats: true) { _ in
                    self.queue.async {
                        self.updateMetrics()
                    }
                }
            }
        }
    }

    /// Stop monitoring
    public func stopMonitoring() {
        queue.async { [weak self] in
            guard let self = self else { return }

            self.isMonitoring = false
            DispatchQueue.main.async {
                self.monitoringTimer?.invalidate()
                self.monitoringTimer = nil
            }
            self.logger.info("Stopped real-time performance monitoring")
        }
    }

    /// Begin tracking a generation
    public func beginGeneration(framework: LLMFramework, modelInfo: ModelInfo) {
        queue.async { [weak self] in
            guard let self = self else { return }

            self.activeGeneration = GenerationTracking(
                id: UUID(),
                framework: framework,
                modelName: modelInfo.name,
                startTime: CFAbsoluteTimeGetCurrent(),
                startMemory: self.getCurrentMemoryUsage()
            )

            self.logger.debug("Started tracking generation for \(framework.rawValue) with model \(modelInfo.name)")
        }
    }

    /// Record token generation
    public func recordToken(_ token: String) {
        queue.async { [weak self] in
            guard let self = self, var generation = self.activeGeneration else { return }

            if generation.firstTokenTime == nil {
                generation.firstTokenTime = CFAbsoluteTimeGetCurrent()
                self.currentMetrics.timeToFirstToken = generation.firstTokenTime! - generation.startTime
            }

            generation.tokenCount += 1
            generation.tokensGenerated.append(token)
            self.activeGeneration = generation

            // Update live metrics
            let elapsed = CFAbsoluteTimeGetCurrent() - generation.startTime
            self.currentMetrics.currentTokensPerSecond = Double(generation.tokenCount) / elapsed
        }
    }

    /// End generation tracking
    public func endGeneration() -> GenerationSummary? {
        var summary: GenerationSummary?

        queue.sync { [weak self] in
            guard let self = self, let generation = self.activeGeneration else { return }

            let endTime = CFAbsoluteTimeGetCurrent()
            let totalTime = endTime - generation.startTime
            let endMemory = self.getCurrentMemoryUsage()

            // Create performance summary
            summary = GenerationSummary(
                id: generation.id,
                framework: generation.framework,
                modelName: generation.modelName,
                totalTime: totalTime,
                timeToFirstToken: generation.firstTokenTime.map { $0 - generation.startTime } ?? 0,
                tokenCount: generation.tokenCount,
                tokensPerSecond: Double(generation.tokenCount) / totalTime,
                memoryUsed: endMemory - generation.startMemory
            )

            // Log summary
            self.logGenerationSummary(summary!)

            // Check for performance issues
            self.checkPerformanceThresholds(summary!)

            // Clear active generation
            self.activeGeneration = nil

            // Reset current metrics
            self.currentMetrics.currentTokensPerSecond = 0
            self.currentMetrics.timeToFirstToken = 0
        }

        return summary
    }

    /// Get performance report for a time range
    public func generateReport(timeRange: TimeInterval = 300) -> PerformanceReport {
        queue.sync {
            let cutoffTime = Date().timeIntervalSince1970 - timeRange
            let relevantHistory = performanceHistory.filter { $0.timestamp.timeIntervalSince1970 > cutoffTime }

            // Calculate statistics
            let memoryUsages = relevantHistory.map { $0.memoryUsage }
            let cpuUsages = relevantHistory.map { $0.cpuUsage }

            return PerformanceReport(
                timeRange: timeRange,
                averageMemoryUsage: average(memoryUsages),
                peakMemoryUsage: memoryUsages.max() ?? 0,
                averageCPUUsage: average(cpuUsages),
                peakCPUUsage: cpuUsages.max() ?? 0,
                alertCount: alerts.filter { $0.timestamp.timeIntervalSince1970 > cutoffTime }.count,
                snapshots: relevantHistory
            )
        }
    }

    /// Add callback for performance alerts
    public func addAlertCallback(_ callback: @escaping (PerformanceAlert) -> Void) {
        queue.async { [weak self] in
            self?.alertCallbacks.append(callback)
        }
    }

    /// Get current performance metrics
    public func getCurrentMetrics() -> LiveMetrics {
        queue.sync {
            return currentMetrics
        }
    }

    /// Export performance data
    public func exportPerformanceData(format: PerformanceExportFormat) throws -> Data {
        let report = generateReport()

        switch format {
        case .json:
            return try JSONEncoder().encode(report)
        case .csv:
            return generateCSV(from: report).data(using: .utf8)!
        }
    }

    // MARK: - Private Methods

    private func setupSystemMonitoring() {
        // Monitor memory warnings
        #if os(iOS) || os(tvOS)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleMemoryWarning),
            name: UIApplication.didReceiveMemoryWarningNotification,
            object: nil
        )
        #endif

        // Monitor thermal state changes
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleThermalStateChange),
            name: ProcessInfo.thermalStateDidChangeNotification,
            object: nil
        )
    }

    private func updateMetrics() {
        // Update system metrics
        currentMetrics.memoryUsage = getCurrentMemoryUsage()
        currentMetrics.availableMemory = getAvailableMemory()
        currentMetrics.cpuUsage = getCurrentCPUUsage()
        currentMetrics.thermalState = ProcessInfo.processInfo.thermalState

        // Create snapshot
        let snapshot = PerformanceSnapshot(
            timestamp: Date(),
            memoryUsage: currentMetrics.memoryUsage,
            cpuUsage: currentMetrics.cpuUsage,
            activeFramework: activeGeneration?.framework
        )

        // Update history
        performanceHistory.append(snapshot)
        if performanceHistory.count > historyLimit {
            performanceHistory.removeFirst()
        }

        // Check for issues
        checkSystemHealth()
    }

    private func getCurrentMemoryUsage() -> Int64 {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4

        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(
                    mach_task_self_,
                    task_flavor_t(MACH_TASK_BASIC_INFO),
                    $0,
                    &count
                )
            }
        }

        return result == KERN_SUCCESS ? Int64(info.resident_size) : 0
    }

    private func getAvailableMemory() -> Int64 {
        let totalMemory = ProcessInfo.processInfo.physicalMemory
        let usedMemory = getCurrentMemoryUsage()
        return Int64(totalMemory) - usedMemory
    }

    private func getCurrentCPUUsage() -> Double {
        var cpuInfo: processor_info_array_t!
        var numCpuInfo: mach_msg_type_number_t = 0
        var numCpus: natural_t = 0

        let result = host_processor_info(
            mach_host_self(),
            PROCESSOR_CPU_LOAD_INFO,
            &numCpus,
            &cpuInfo,
            &numCpuInfo
        )

        guard result == KERN_SUCCESS else { return 0 }

        // Simplified CPU calculation - in production would track deltas
        return 0.15 // Placeholder for actual implementation
    }

    private func checkSystemHealth() {
        let memoryUsageRatio = Double(currentMetrics.memoryUsage) / Double(ProcessInfo.processInfo.physicalMemory)

        // Check memory threshold
        if memoryUsageRatio > thresholds.maxMemoryUsage {
            createAlert(
                type: .highMemoryUsage,
                severity: .warning,
                message: "Memory usage at \(Int(memoryUsageRatio * 100))%"
            )
        }

        // Check CPU threshold
        if currentMetrics.cpuUsage > thresholds.maxCPUUsage {
            createAlert(
                type: .highCPUUsage,
                severity: .warning,
                message: "CPU usage at \(Int(currentMetrics.cpuUsage * 100))%"
            )
        }

        // Check thermal state
        if currentMetrics.thermalState == .serious || currentMetrics.thermalState == .critical {
            createAlert(
                type: .thermalThrottle,
                severity: .critical,
                message: "Device thermal state: \(thermalStateString(currentMetrics.thermalState))"
            )
        }
    }

    private func checkPerformanceThresholds(_ summary: GenerationSummary) {
        // Check tokens per second
        if summary.tokensPerSecond < thresholds.minTokensPerSecond {
            createAlert(
                type: .lowPerformance,
                severity: .info,
                message: "Low token generation speed: \(String(format: "%.1f", summary.tokensPerSecond)) tokens/sec"
            )
        }

        // Check latency
        if summary.timeToFirstToken > thresholds.maxLatency {
            createAlert(
                type: .highLatency,
                severity: .warning,
                message: "High latency: \(String(format: "%.2f", summary.timeToFirstToken))s to first token"
            )
        }
    }

    private func createAlert(type: AlertType, severity: AlertSeverity, message: String) {
        let alert = PerformanceAlert(
            id: UUID(),
            type: type,
            severity: severity,
            message: message,
            timestamp: Date()
        )

        alerts.append(alert)

        // Keep only recent alerts
        let cutoff = Date().addingTimeInterval(-300) // 5 minutes
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

    @objc private func handleMemoryWarning() {
        queue.async { [weak self] in
            self?.createAlert(
                type: .memoryWarning,
                severity: .critical,
                message: "System memory warning received"
            )
        }
    }

    @objc private func handleThermalStateChange() {
        queue.async { [weak self] in
            guard let self = self else { return }
            self.currentMetrics.thermalState = ProcessInfo.processInfo.thermalState

            if self.currentMetrics.thermalState == .serious || self.currentMetrics.thermalState == .critical {
                self.logger.warning("Thermal state changed to \(self.thermalStateString(self.currentMetrics.thermalState))")
            }
        }
    }

    private func logGenerationSummary(_ summary: GenerationSummary) {
        logger.info("""
            Generation completed:
            - Framework: \(summary.framework.rawValue)
            - Model: \(summary.modelName)
            - Total time: \(String(format: "%.2f", summary.totalTime))s
            - Time to first token: \(String(format: "%.3f", summary.timeToFirstToken))s
            - Tokens/sec: \(String(format: "%.1f", summary.tokensPerSecond))
            - Token count: \(summary.tokenCount)
            - Memory used: \(ByteCountFormatter.string(fromByteCount: summary.memoryUsed, countStyle: .memory))
            """)
    }

    private func average(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        return values.reduce(0, +) / Double(values.count)
    }

    private func average(_ values: [Int64]) -> Int64 {
        guard !values.isEmpty else { return 0 }
        return values.reduce(0, +) / Int64(values.count)
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

    private func generateCSV(from report: PerformanceReport) -> String {
        var csv = "Timestamp,Memory Usage,CPU Usage,Framework\n"

        for snapshot in report.snapshots {
            csv += "\(snapshot.timestamp.timeIntervalSince1970),"
            csv += "\(snapshot.memoryUsage),"
            csv += "\(snapshot.cpuUsage),"
            csv += "\(snapshot.activeFramework?.rawValue ?? "none")\n"
        }

        return csv
    }
}

// MARK: - Supporting Types

/// Live performance metrics
public struct LiveMetrics {
    public var memoryUsage: Int64 = 0
    public var availableMemory: Int64 = 0
    public var cpuUsage: Double = 0
    public var thermalState: ProcessInfo.ThermalState = .nominal
    public var currentTokensPerSecond: Double = 0
    public var timeToFirstToken: TimeInterval = 0
}

/// Performance snapshot at a point in time
public struct PerformanceSnapshot: Codable {
    public let timestamp: Date
    public let memoryUsage: Int64
    public let cpuUsage: Double
    public let activeFramework: LLMFramework?
}

/// Generation tracking information
internal struct GenerationTracking {
    let id: UUID
    let framework: LLMFramework
    let modelName: String
    let startTime: CFAbsoluteTime
    let startMemory: Int64
    var firstTokenTime: CFAbsoluteTime?
    var tokenCount: Int = 0
    var tokensGenerated: [String] = []
}

/// Generation performance summary
public struct GenerationSummary {
    public let id: UUID
    public let framework: LLMFramework
    public let modelName: String
    public let totalTime: TimeInterval
    public let timeToFirstToken: TimeInterval
    public let tokenCount: Int
    public let tokensPerSecond: Double
    public let memoryUsed: Int64
}

/// Performance thresholds configuration
public struct PerformanceThresholds {
    public let maxMemoryUsage: Double
    public let minTokensPerSecond: Double
    public let maxLatency: TimeInterval
    public let maxCPUUsage: Double
}

/// Performance alert
public struct PerformanceAlert: Identifiable {
    public let id: UUID
    public let type: AlertType
    public let severity: AlertSeverity
    public let message: String
    public let timestamp: Date
}

/// Alert types
public enum AlertType {
    case highMemoryUsage
    case highCPUUsage
    case thermalThrottle
    case lowPerformance
    case highLatency
    case memoryWarning
}

/// Alert severity levels
public enum AlertSeverity {
    case info
    case warning
    case critical
}

/// Performance report
public struct PerformanceReport: Codable {
    public let timeRange: TimeInterval
    public let averageMemoryUsage: Int64
    public let peakMemoryUsage: Int64
    public let averageCPUUsage: Double
    public let peakCPUUsage: Double
    public let alertCount: Int
    public let snapshots: [PerformanceSnapshot]
}

/// Export format options
public enum PerformanceExportFormat {
    case json
    case csv
}

// Platform-specific imports
#if os(iOS) || os(tvOS)
import UIKit
#endif
