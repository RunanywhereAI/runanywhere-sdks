//
//  PerformanceMonitor.swift
//  RunAnywhere SDK
//
//  Protocol for real-time performance monitoring
//

import Foundation

/// Protocol for real-time performance monitoring capabilities
public protocol PerformanceMonitor {
    /// Current live metrics
    var currentMetrics: LiveMetrics { get }

    /// Whether monitoring is active
    var isMonitoring: Bool { get }

    /// Performance history snapshots
    var performanceHistory: [PerformanceSnapshot] { get }

    /// Active performance alerts
    var alerts: [PerformanceAlert] { get }

    /// Start monitoring system performance
    func startMonitoring()

    /// Stop monitoring
    func stopMonitoring()

    /// Begin tracking a generation
    func beginGeneration(framework: LLMFramework, modelInfo: ModelInfo)

    /// Record token generation
    func recordToken(_ token: String)

    /// End generation tracking
    func endGeneration() -> GenerationSummary?

    /// Get performance report for a time range
    func generateReport(timeRange: TimeInterval) -> PerformanceReport

    /// Add callback for performance alerts
    func addAlertCallback(_ callback: @escaping (PerformanceAlert) -> Void)

    /// Export performance data
    func exportPerformanceData(format: PerformanceExportFormat) throws -> Data
}
