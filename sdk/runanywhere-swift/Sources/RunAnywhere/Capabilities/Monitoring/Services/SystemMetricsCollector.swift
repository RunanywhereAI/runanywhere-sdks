//
//  SystemMetricsCollector.swift
//  RunAnywhere SDK
//
//  Collects and updates performance metrics
//

import Foundation

/// Collects and updates performance metrics
internal class SystemMetricsCollector {
    private let logger = SDKLogger(category: "MetricsCollector")
    private let systemMetrics = SystemMetrics()
    private let queue = DispatchQueue(label: "com.runanywhere.sdk.metricscollector")

    private var currentMetrics = LiveMetrics()

    /// Update all metrics
    func updateMetrics(activeGeneration: PerformanceGenerationTracking?) -> LiveMetrics {
        queue.sync {
            // Update system metrics
            currentMetrics.memoryUsage = systemMetrics.getCurrentMemoryUsage()
            currentMetrics.availableMemory = systemMetrics.getAvailableMemory()
            currentMetrics.cpuUsage = systemMetrics.getCurrentCPUUsage()
            currentMetrics.thermalState = systemMetrics.getThermalState()

            // Generation metrics are updated separately via recordToken

            return currentMetrics
        }
    }

    /// Update generation-specific metrics
    func updateGenerationMetrics(
        timeToFirstToken: TimeInterval?,
        tokensPerSecond: Double
    ) {
        queue.async { [weak self] in
            guard let self = self else { return }

            if let ttft = timeToFirstToken {
                self.currentMetrics.timeToFirstToken = ttft
            }
            self.currentMetrics.currentTokensPerSecond = tokensPerSecond
        }
    }

    /// Reset generation metrics
    func resetGenerationMetrics() {
        queue.async { [weak self] in
            self?.currentMetrics.currentTokensPerSecond = 0
            self?.currentMetrics.timeToFirstToken = 0
        }
    }

    /// Get current metrics
    func getCurrentMetrics() -> LiveMetrics {
        queue.sync {
            return currentMetrics
        }
    }

    /// Create a performance snapshot
    func createSnapshot(activeFramework: LLMFramework?) -> PerformanceSnapshot {
        let metrics = getCurrentMetrics()

        return PerformanceSnapshot(
            timestamp: Date(),
            memoryUsage: metrics.memoryUsage,
            cpuUsage: metrics.cpuUsage,
            activeFramework: activeFramework
        )
    }
}
