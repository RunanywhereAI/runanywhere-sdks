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
                "totalGenerationTime": String(performance.totalGenerationTime),
                "inputTokens": String(performance.inputTokens),
                "outputTokens": String(performance.outputTokens),
                "tokensPerSecond": String(performance.tokensPerSecond)
            ]),
            "routing": .stringConvertible([
                "framework": performance.routingFramework ?? "none",
                "reason": performance.routingReason
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
    func logSystemMetrics(_ metrics: LiveMetrics) {
        let metadata: [String: LoggerStore.MetadataValue] = [
            "memory": .stringConvertible([
                "used": String(metrics.memoryUsage),
                "available": String(metrics.availableMemory)
            ]),
            "cpu": .string(String(metrics.cpuUsage)),
            "thermal": .string(String(describing: metrics.thermalState)),
            "currentTokensPerSecond": .string(String(metrics.currentTokensPerSecond)),
            "timeToFirstToken": .string(String(metrics.timeToFirstToken)),
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
            "sessionId": .string(session.id.uuidString),
            "modelId": .string(session.modelId),
            "sessionType": .string(String(describing: session.sessionType)),
            "generationCount": .string(String(session.generationCount)),
            "totalInputTokens": .string(String(session.totalInputTokens)),
            "totalOutputTokens": .string(String(session.totalOutputTokens)),
            "averageTimeToFirstToken": .string(String(session.averageTimeToFirstToken)),
            "averageTokensPerSecond": .string(String(session.averageTokensPerSecond)),
            "totalDuration": .string(String(session.totalDuration)),
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
            "generationId": .string(metrics.generationId.uuidString),
            "sessionId": .string(metrics.sessionId.uuidString),
            "tokensGenerated": .string(String(metrics.tokensGenerated)),
            "elapsedTime": .string(String(metrics.elapsedTime)),
            "currentTokensPerSecond": .string(String(metrics.currentTokensPerSecond)),
            "hasFirstToken": .string(String(metrics.hasFirstToken)),
            "timeToFirstToken": .string(metrics.timeToFirstToken.map { String($0) } ?? "nil"),
            "type": .string("live_metrics")
        ]

        logger.storeMessage(
            label: "Performance",
            level: .trace,
            message: "Live generation metrics",
            metadata: metadata
        )
    }

    /// Log performance alert with minimal information
    func logPerformanceAlert(_ alert: PerformanceAlert) {
        let metadata: [String: LoggerStore.MetadataValue] = [
            "alertId": .string(alert.id.uuidString),
            "alertType": .string(alert.type.rawValue),
            "severity": .string(String(describing: alert.severity)),
            "timestamp": .string(ISO8601DateFormatter().string(from: alert.timestamp)),
            "type": .string("performance_alert")
        ]

        logger.storeMessage(
            label: "Performance",
            level: .warning,
            message: alert.message,
            metadata: metadata
        )
    }

    /// Log performance alert with detailed metrics
    func logPerformanceAlert(
        type: String,
        message: String,
        threshold: Double,
        currentValue: Double,
        recommendation: String? = nil
    ) {
        var metadata: [String: LoggerStore.MetadataValue] = [
            "alertType": .string(type),
            "threshold": .string(String(threshold)),
            "currentValue": .string(String(currentValue)),
            "exceedance": .string(String(currentValue - threshold)),
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
                metadata[key] = .string(String(intValue))
            } else if let doubleValue = value as? Double {
                metadata[key] = .string(String(doubleValue))
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
