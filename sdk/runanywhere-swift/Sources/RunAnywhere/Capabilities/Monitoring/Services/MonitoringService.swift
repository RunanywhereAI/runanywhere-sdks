//
//  MonitoringService.swift
//  RunAnywhere SDK
//
//  Main performance monitoring service
//

import Foundation
import Pulse

/// Real-time performance monitoring service
public class MonitoringService: PerformanceMonitor {

    // MARK: - Singleton

    public static let shared = MonitoringService()

    // MARK: - Properties

    public private(set) var currentMetrics = LiveMetrics()
    public private(set) var isMonitoring = false
    public private(set) var performanceHistory: [PerformanceSnapshot] = []
    public private(set) var alerts: [PerformanceAlert] = []

    // MARK: - Private Properties

    private let logger = SDKLogger(category: "MonitoringService")
    private let metricsCollector = SystemMetricsCollector()
    private let generationTracker = PerformanceGenerationTracker()
    private let historyManager = HistoryManager()
    private let alertManager = AlertManager()
    private let reportGenerator = ReportGenerator()
    private let pulsePerformanceLogger = PulsePerformanceLogger.shared

    private var monitoringTimer: Timer?
    private let updateInterval: TimeInterval = 0.1 // 100ms updates
    private let queue = DispatchQueue(label: "com.runanywhere.sdk.monitoringservice", qos: .utility)

    // MARK: - Initialization

    public init() {
        setupSystemMonitoring()
        setupPulseIntegration()
    }

    deinit {
        stopMonitoring()
    }

    // MARK: - PerformanceMonitor Protocol

    public func startMonitoring() {
        queue.async { [weak self] in
            guard let self = self, !self.isMonitoring else { return }

            self.isMonitoring = true
            self.logger.info("Started real-time performance monitoring")

            // Start periodic updates on main queue for timer
            DispatchQueue.main.async {
                self.monitoringTimer = Timer.scheduledTimer(
                    withTimeInterval: self.updateInterval,
                    repeats: true
                ) { _ in
                    self.queue.async {
                        self.updateMetrics()
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
            self.logger.info("Stopped real-time performance monitoring")
        }
    }

    public func beginGeneration(framework: LLMFramework, modelInfo: ModelInfo) {
        queue.async { [weak self] in
            guard let self = self else { return }

            let currentMemory = self.metricsCollector.getCurrentMetrics().memoryUsage
            _ = self.generationTracker.beginGeneration(
                framework: framework,
                modelInfo: modelInfo,
                currentMemory: currentMemory
            )
        }
    }

    public func recordToken(_ token: String) {
        queue.async { [weak self] in
            guard let self = self else { return }

            let currentTime = CFAbsoluteTimeGetCurrent()
            let (firstTokenTime, tokensPerSecond) = self.generationTracker.recordToken(
                token,
                currentTime: currentTime
            )

            // Update live metrics
            if let ttft = firstTokenTime, let generation = self.generationTracker.currentGeneration {
                let timeToFirstToken = ttft - generation.startTime
                self.metricsCollector.updateGenerationMetrics(
                    timeToFirstToken: timeToFirstToken,
                    tokensPerSecond: tokensPerSecond
                )
            }
        }
    }

    public func endGeneration() -> GenerationSummary? {
        var summary: GenerationSummary?

        queue.sync { [weak self] in
            guard let self = self else { return }

            let currentMemory = self.metricsCollector.getCurrentMetrics().memoryUsage
            summary = self.generationTracker.endGeneration(currentMemory: currentMemory)

            if let summary = summary {
                // Log summary
                self.logGenerationSummary(summary)

                // Check for performance issues
                self.alertManager.checkGenerationPerformance(summary)

                // Reset generation metrics
                self.metricsCollector.resetGenerationMetrics()
            }
        }

        return summary
    }

    public func generateReport(timeRange: TimeInterval = 300) -> PerformanceReport {
        queue.sync {
            let snapshots = historyManager.getSnapshots(withinTimeRange: timeRange)
            let recentAlerts = alertManager.getRecentAlerts(withinTimeRange: timeRange)

            return reportGenerator.generateReport(
                timeRange: timeRange,
                snapshots: snapshots,
                alerts: recentAlerts
            )
        }
    }

    public func addAlertCallback(_ callback: @escaping (PerformanceAlert) -> Void) {
        alertManager.addAlertCallback(callback)
    }

    public func exportPerformanceData(format: PerformanceExportFormat) throws -> Data {
        let report = generateReport()

        switch format {
        case .json:
            return try reportGenerator.exportAsJSON(report)
        case .csv:
            return reportGenerator.exportAsCSV(report)
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

    private func setupPulseIntegration() {
        // Set up alert manager callback to log alerts to Pulse
        alertManager.addAlertCallback { [weak self] alert in
            self?.pulsePerformanceLogger.logPerformanceAlert(alert)
        }
    }

    private func updateMetrics() {
        // Get current generation info if any
        let activeGeneration = generationTracker.currentGeneration

        // Update metrics
        currentMetrics = metricsCollector.updateMetrics(activeGeneration: activeGeneration)

        // Create snapshot
        let snapshot = metricsCollector.createSnapshot(
            activeFramework: activeGeneration?.framework
        )

        // Update history
        historyManager.addSnapshot(snapshot)
        performanceHistory = historyManager.getAllSnapshots()

        // Check for issues
        alertManager.checkSystemHealth(metrics: currentMetrics)
        alerts = alertManager.getAllAlerts()
    }

    @objc private func handleMemoryWarning() {
        alertManager.createMemoryWarning()
    }

    @objc private func handleThermalStateChange() {
        queue.async { [weak self] in
            guard let self = self else { return }

            let thermalState = ProcessInfo.processInfo.thermalState
            if thermalState == .serious || thermalState == .critical {
                self.logger.warning("Thermal state changed to \(thermalState)")
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

        // Log to Pulse with structured data
        let performance = GenerationPerformance(
            timeToFirstToken: summary.timeToFirstToken,
            totalGenerationTime: summary.totalTime,
            inputTokens: 0, // Not available in summary
            outputTokens: summary.tokenCount,
            tokensPerSecond: summary.tokensPerSecond,
            modelId: summary.modelName,
            executionTarget: .onDevice,
            routingFramework: summary.framework.rawValue,
            routingReason: "On-device execution"
        )
        pulsePerformanceLogger.logGenerationPerformance(performance)
    }
}

// Platform-specific imports
#if os(iOS) || os(tvOS)
import UIKit
#endif
