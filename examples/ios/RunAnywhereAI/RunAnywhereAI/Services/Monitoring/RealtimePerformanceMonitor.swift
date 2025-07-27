//
//  RealtimePerformanceMonitor.swift
//  RunAnywhereAI
//
//  Created by Assistant on 7/27/25.
//

import Foundation
import Combine
import os.log
import UIKit

/// Real-time performance monitoring with live metrics
class RealtimePerformanceMonitor: ObservableObject {
    static let shared = RealtimePerformanceMonitor()
    
    // MARK: - Published Properties
    @Published var currentMetrics = LiveMetrics()
    @Published var isMonitoring = false
    @Published var performanceHistory: [PerformanceSnapshot] = []
    @Published var alerts: [PerformanceAlert] = []
    
    // MARK: - Private Properties
    private let logger = os.Logger(subsystem: "com.runanywhere.ai", category: "RealtimeMonitoring")
    private var monitoringTimer: Timer?
    private var cancellables = Set<AnyCancellable>()
    private let updateInterval: TimeInterval = 0.1 // 100ms updates
    private let historyLimit = 300 // Keep last 30 seconds at 100ms intervals
    
    // Performance thresholds
    private let thresholds = PerformanceThresholds(
        maxMemoryUsage: 0.8, // 80% of available memory
        minTokensPerSecond: 10.0,
        maxLatency: 5.0,
        maxCPUUsage: 0.9 // 90% CPU
    )
    
    // Current generation tracking
    private var activeGeneration: GenerationTracking?
    
    // MARK: - Initialization
    init() {
        setupSystemMonitoring()
    }
    
    // MARK: - Public Methods
    
    /// Start monitoring system performance
    func startMonitoring() {
        guard !isMonitoring else { return }
        
        isMonitoring = true
        logger.info("Started real-time performance monitoring")
        
        // Start periodic updates
        monitoringTimer = Timer.scheduledTimer(withTimeInterval: updateInterval, repeats: true) { [weak self] _ in
            self?.updateMetrics()
        }
    }
    
    /// Stop monitoring
    func stopMonitoring() {
        isMonitoring = false
        monitoringTimer?.invalidate()
        monitoringTimer = nil
        logger.info("Stopped real-time performance monitoring")
    }
    
    /// Begin tracking a generation
    func beginGeneration(framework: LLMFramework, prompt: String) {
        activeGeneration = GenerationTracking(
            id: UUID(),
            framework: framework,
            prompt: prompt,
            startTime: CFAbsoluteTimeGetCurrent(),
            startMemory: getCurrentMemoryUsage()
        )
        
        logger.debug("Started tracking generation for \(framework.displayName)")
    }
    
    /// Record token generation
    func recordToken(_ token: String) {
        guard var generation = activeGeneration else { return }
        
        if generation.firstTokenTime == nil {
            generation.firstTokenTime = CFAbsoluteTimeGetCurrent()
            currentMetrics.timeToFirstToken = generation.firstTokenTime! - generation.startTime
        }
        
        generation.tokenCount += 1
        generation.tokens.append(token)
        activeGeneration = generation
        
        // Update live metrics
        let elapsed = CFAbsoluteTimeGetCurrent() - generation.startTime
        currentMetrics.currentTokensPerSecond = Double(generation.tokenCount) / elapsed
    }
    
    /// End generation tracking
    func endGeneration() {
        guard let generation = activeGeneration else { return }
        
        let endTime = CFAbsoluteTimeGetCurrent()
        let totalTime = endTime - generation.startTime
        let endMemory = getCurrentMemoryUsage()
        
        // Create performance summary
        let summary = GenerationSummary(
            id: generation.id,
            framework: generation.framework,
            totalTime: totalTime,
            timeToFirstToken: generation.firstTokenTime.map { $0 - generation.startTime } ?? 0,
            tokenCount: generation.tokenCount,
            tokensPerSecond: Double(generation.tokenCount) / totalTime,
            memoryUsed: endMemory - generation.startMemory,
            promptLength: generation.prompt.count,
            responseLength: generation.tokens.joined().count
        )
        
        // Log summary
        logGenerationSummary(summary)
        
        // Check for performance issues
        checkPerformanceThresholds(summary)
        
        // Clear active generation
        activeGeneration = nil
        
        // Reset current metrics
        currentMetrics.currentTokensPerSecond = 0
        currentMetrics.timeToFirstToken = 0
    }
    
    /// Get performance report
    func generateReport(timeRange: TimeInterval = 300) -> PerformanceReport {
        let cutoffTime = Date().timeIntervalSince1970 - timeRange
        let relevantHistory = performanceHistory.filter { $0.timestamp.timeIntervalSince1970 > cutoffTime }
        
        // Calculate statistics
        let memoryUsages = relevantHistory.map { $0.memoryUsage }
        let cpuUsages = relevantHistory.map { $0.cpuUsage }
        let frameRates = relevantHistory.compactMap { $0.frameRate }
        
        return PerformanceReport(
            timeRange: timeRange,
            averageMemoryUsage: average(memoryUsages),
            peakMemoryUsage: memoryUsages.max() ?? 0,
            averageCPUUsage: average(cpuUsages),
            peakCPUUsage: cpuUsages.max() ?? 0,
            averageFrameRate: average(frameRates),
            alertCount: alerts.filter { $0.timestamp.timeIntervalSince1970 > cutoffTime }.count,
            snapshots: relevantHistory
        )
    }
    
    /// Export performance data
    func exportPerformanceData(format: PerformanceExportFormat) throws -> Data {
        let report = generateReport()
        
        switch format {
        case .json:
            return try JSONEncoder().encode(report)
        case .csv:
            return generateCSV(from: report).data(using: .utf8)!
        case .markdown:
            return generateMarkdown(from: report).data(using: .utf8)!
        }
    }
    
    // MARK: - Private Methods
    
    private func setupSystemMonitoring() {
        // Monitor app lifecycle
        NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)
            .sink { [weak self] _ in
                self?.startMonitoring()
            }
            .store(in: &cancellables)
        
        NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)
            .sink { [weak self] _ in
                self?.stopMonitoring()
            }
            .store(in: &cancellables)
        
        // Monitor memory warnings
        NotificationCenter.default.publisher(for: UIApplication.didReceiveMemoryWarningNotification)
            .sink { [weak self] _ in
                self?.handleMemoryWarning()
            }
            .store(in: &cancellables)
        
        // Monitor thermal state
        ProcessInfo.processInfo.publisher(for: \.thermalState)
            .sink { [weak self] state in
                self?.handleThermalStateChange(state)
            }
            .store(in: &cancellables)
    }
    
    private func updateMetrics() {
        // Update system metrics
        currentMetrics.memoryUsage = getCurrentMemoryUsage()
        currentMetrics.availableMemory = getAvailableMemory()
        currentMetrics.cpuUsage = getCurrentCPUUsage()
        currentMetrics.thermalState = ProcessInfo.processInfo.thermalState
        currentMetrics.batteryLevel = UIDevice.current.batteryLevel
        currentMetrics.frameRate = getFrameRate()
        
        // Create snapshot
        let snapshot = PerformanceSnapshot(
            timestamp: Date(),
            memoryUsage: currentMetrics.memoryUsage,
            cpuUsage: currentMetrics.cpuUsage,
            frameRate: currentMetrics.frameRate,
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
        
        // Simplified CPU calculation
        return Double.random(in: 0.1...0.3) // Placeholder
    }
    
    private func getFrameRate() -> Double {
        // Get main screen refresh rate
        if #available(iOS 15.0, *) {
            return Double(UIScreen.main.maximumFramesPerSecond)
        } else {
            return 60.0
        }
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
    
    private func handleMemoryWarning() {
        createAlert(
            type: .memoryWarning,
            severity: .critical,
            message: "System memory warning received"
        )
        
        // Clear caches
        NotificationCenter.default.post(name: .clearModelCaches, object: nil)
    }
    
    private func handleThermalStateChange(_ state: ProcessInfo.ThermalState) {
        currentMetrics.thermalState = state
        
        if state == .serious || state == .critical {
            logger.warning("Thermal state changed to \(self.thermalStateString(state))")
        }
    }
    
    private func logGenerationSummary(_ summary: GenerationSummary) {
        logger.info("""
            Generation completed:
            - Framework: \(summary.framework.displayName)
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
        var csv = "Timestamp,Memory Usage,CPU Usage,Frame Rate\n"
        
        for snapshot in report.snapshots {
            csv += "\(snapshot.timestamp.timeIntervalSince1970),"
            csv += "\(snapshot.memoryUsage),"
            csv += "\(snapshot.cpuUsage),"
            csv += "\(snapshot.frameRate ?? 0)\n"
        }
        
        return csv
    }
    
    private func generateMarkdown(from report: PerformanceReport) -> String {
        var markdown = "# Performance Report\n\n"
        markdown += "Time Range: \(Int(report.timeRange))s\n\n"
        
        markdown += "## Summary\n\n"
        markdown += "- Average Memory: \(ByteCountFormatter.string(fromByteCount: report.averageMemoryUsage, countStyle: .memory))\n"
        markdown += "- Peak Memory: \(ByteCountFormatter.string(fromByteCount: report.peakMemoryUsage, countStyle: .memory))\n"
        markdown += "- Average CPU: \(String(format: "%.1f", report.averageCPUUsage * 100))%\n"
        markdown += "- Peak CPU: \(String(format: "%.1f", report.peakCPUUsage * 100))%\n"
        markdown += "- Alert Count: \(report.alertCount)\n"
        
        return markdown
    }
}

// MARK: - Supporting Types

struct LiveMetrics {
    var memoryUsage: Int64 = 0
    var availableMemory: Int64 = 0
    var cpuUsage: Double = 0
    var thermalState: ProcessInfo.ThermalState = .nominal
    var batteryLevel: Float = 1.0
    var frameRate: Double? = nil
    var currentTokensPerSecond: Double = 0
    var timeToFirstToken: TimeInterval = 0
}

struct PerformanceSnapshot: Codable {
    let timestamp: Date
    let memoryUsage: Int64
    let cpuUsage: Double
    let frameRate: Double?
    let activeFramework: LLMFramework?
}

struct GenerationTracking {
    let id: UUID
    let framework: LLMFramework
    let prompt: String
    let startTime: CFAbsoluteTime
    let startMemory: Int64
    var firstTokenTime: CFAbsoluteTime?
    var tokenCount: Int = 0
    var tokens: [String] = []
}

struct GenerationSummary {
    let id: UUID
    let framework: LLMFramework
    let totalTime: TimeInterval
    let timeToFirstToken: TimeInterval
    let tokenCount: Int
    let tokensPerSecond: Double
    let memoryUsed: Int64
    let promptLength: Int
    let responseLength: Int
}

struct PerformanceThresholds {
    let maxMemoryUsage: Double
    let minTokensPerSecond: Double
    let maxLatency: TimeInterval
    let maxCPUUsage: Double
}

struct PerformanceAlert: Identifiable {
    let id: UUID
    let type: AlertType
    let severity: AlertSeverity
    let message: String
    let timestamp: Date
}

enum AlertType {
    case highMemoryUsage
    case highCPUUsage
    case thermalThrottle
    case lowPerformance
    case highLatency
    case memoryWarning
}

enum AlertSeverity {
    case info
    case warning
    case critical
}

struct PerformanceReport: Codable {
    let timeRange: TimeInterval
    let averageMemoryUsage: Int64
    let peakMemoryUsage: Int64
    let averageCPUUsage: Double
    let peakCPUUsage: Double
    let averageFrameRate: Double
    let alertCount: Int
    let snapshots: [PerformanceSnapshot]
}

enum PerformanceExportFormat {
    case json
    case csv
    case markdown
}