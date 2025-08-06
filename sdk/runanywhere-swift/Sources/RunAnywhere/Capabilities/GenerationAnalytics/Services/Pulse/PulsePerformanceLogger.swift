//
//  PulsePerformanceLogger.swift
//  RunAnywhere SDK
//
//  Pulse-based performance logging for generation analytics
//

import Foundation
import Pulse

/// Pulse-based performance logger for generation analytics
internal final class PulsePerformanceLogger {

    // MARK: - Singleton

    static let shared = PulsePerformanceLogger()

    // MARK: - Properties

    private let logger: LoggerStore

    // MARK: - Initialization

    private init() {
        self.logger = LoggerStore.shared
    }

    // MARK: - Generation Performance Logging

    /// Log generation performance metrics
    func logGenerationPerformance(_ performance: GenerationPerformance) {
        let metadata: [String: LoggerStore.MetadataValue] = [
            "modelId": .string(performance.modelId),
            "executionTarget": .string(performance.executionTarget.rawValue),
            "metrics": .stringConvertible([
                "timeToFirstToken": String(performance.timeToFirstToken),
                "tokensPerSecond": String(performance.tokensPerSecond),
                "totalDuration": String(performance.totalDuration),
                "memoryUsed": String(performance.memoryUsed),
                "cpuUsage": String(performance.cpuUsage),
                "gpuUsage": String(performance.gpuUsage ?? 0)
            ]),
            "cost": .stringConvertible([
                "totalCost": String(performance.totalCost),
                "savedCost": String(performance.savedCost)
            ]),
            "type": .string("performance_metrics")
        ]

        logger.storeMessage(
            label: "Performance",
            level: .info,
            message: "Generation performance metrics recorded",
            metadata: metadata
        )
    }

    /// Log system metrics
    func logSystemMetrics(_ metrics: SystemMetrics) {
        let metadata: [String: LoggerStore.MetadataValue] = [
            "memory": .stringConvertible([
                "used": String(metrics.memoryUsed),
                "available": String(metrics.memoryAvailable),
                "pressure": metrics.memoryPressure.rawValue
            ]),
            "cpu": .double(metrics.cpuUsage),
            "thermal": .string(metrics.thermalState.rawValue),
            "battery": .double(metrics.batteryLevel),
            "type": .string("system_metrics")
        ]

        logger.storeMessage(
            label: "System",
            level: .debug,
            message: "System metrics captured",
            metadata: metadata
        )
    }

    /// Log generation session performance
    func logSessionPerformance(_ session: GenerationSession) {
        let metadata: [String: LoggerStore.MetadataValue] = [
            "sessionId": .string(session.id),
            "generationCount": .int(session.generations.count),
            "totalTokens": .int(session.totalTokensUsed),
            "totalCost": .double(session.totalCost),
            "savedCost": .double(session.totalSavedCost),
            "duration": .double(session.duration),
            "modelBreakdown": .stringConvertible(
                Dictionary(grouping: session.generations, by: { $0.modelId })
                    .mapValues { $0.count }
            ),
            "type": .string("session_performance")
        ]

        logger.storeMessage(
            label: "Performance",
            level: .info,
            message: "Session performance summary",
            metadata: metadata
        )
    }

    /// Log live generation metrics
    func logLiveMetrics(_ metrics: LiveGenerationMetrics) {
        let metadata: [String: LoggerStore.MetadataValue] = [
            "generationId": .string(metrics.generationId),
            "tokensGenerated": .int(metrics.tokensGenerated),
            "timeElapsed": .double(metrics.timeElapsed),
            "tokensPerSecond": .double(metrics.tokensPerSecond),
            "memoryUsage": .int(Int(metrics.memoryUsage)),
            "state": .string(metrics.state.rawValue),
            "type": .string("live_metrics")
        ]

        logger.storeMessage(
            label: "Performance",
            level: .trace,
            message: "Live generation metrics",
            metadata: metadata
        )
    }

    /// Log performance alert
    func logPerformanceAlert(
        type: String,
        message: String,
        threshold: Double,
        currentValue: Double,
        recommendation: String? = nil
    ) {
        var metadata: [String: LoggerStore.MetadataValue] = [
            "alertType": .string(type),
            "threshold": .double(threshold),
            "currentValue": .double(currentValue),
            "exceedance": .double(currentValue - threshold),
            "type": .string("performance_alert")
        ]

        if let recommendation = recommendation {
            metadata["recommendation"] = .string(recommendation)
        }

        logger.storeMessage(
            label: "Performance",
            level: .warning,
            message: "Performance alert: \(message)",
            metadata: metadata
        )
    }

    /// Log benchmark results
    func logBenchmarkResults(
        benchmarkId: String,
        modelId: String,
        results: [String: Any]
    ) {
        var metadata: [String: LoggerStore.MetadataValue] = [
            "benchmarkId": .string(benchmarkId),
            "modelId": .string(modelId),
            "type": .string("benchmark_results")
        ]

        // Convert results to metadata values
        for (key, value) in results {
            if let stringValue = value as? String {
                metadata[key] = .string(stringValue)
            } else if let intValue = value as? Int {
                metadata[key] = .int(intValue)
            } else if let doubleValue = value as? Double {
                metadata[key] = .double(doubleValue)
            } else if let dictValue = value as? [String: String] {
                metadata[key] = .stringConvertible(dictValue)
            } else {
                metadata[key] = .string(String(describing: value))
            }
        }

        logger.storeMessage(
            label: "Benchmark",
            level: .info,
            message: "Benchmark completed for model \(modelId)",
            metadata: metadata
        )
    }

    /// Log A/B test results
    func logABTestResults(
        testId: String,
        variantA: String,
        variantB: String,
        winner: String?,
        metrics: [String: Double]
    ) {
        var metadata: [String: LoggerStore.MetadataValue] = [
            "testId": .string(testId),
            "variantA": .string(variantA),
            "variantB": .string(variantB),
            "type": .string("ab_test_results")
        ]

        if let winner = winner {
            metadata["winner"] = .string(winner)
        }

        // Add metrics
        var metricsDict: [String: String] = [:]
        for (key, value) in metrics {
            metricsDict[key] = String(format: "%.2f", value)
        }
        metadata["metrics"] = .stringConvertible(metricsDict)

        logger.storeMessage(
            label: "ABTesting",
            level: .info,
            message: "A/B test completed: \(testId)",
            metadata: metadata
        )
    }
}
