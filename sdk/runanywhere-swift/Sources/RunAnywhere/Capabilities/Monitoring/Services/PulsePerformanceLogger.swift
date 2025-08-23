//
//  PulsePerformanceLogger.swift
//  RunAnywhere SDK
//
//  Pulse logging for performance data
//

import Foundation
import Pulse

/// Structured performance logging via Pulse
public class PulsePerformanceLogger {

    // MARK: - Singleton

    public static let shared = PulsePerformanceLogger()

    // MARK: - Properties

    private let logger = SDKLogger(category: "PulsePerformance")

    // MARK: - Initialization

    private init() {}

    // MARK: - Logging Methods

    /// Log generation performance metrics
    public func logGenerationPerformance(_ performance: GenerationPerformance) {
        logger.info("Generation Performance: TTFT=\(performance.timeToFirstToken)s Total=\(performance.totalGenerationTime)s TPS=\(performance.tokensPerSecond)",
                   metadata: [
                       "timeToFirstToken": "\(performance.timeToFirstToken)",
                       "totalGenerationTime": "\(performance.totalGenerationTime)",
                       "inputTokens": "\(performance.inputTokens)",
                       "outputTokens": "\(performance.outputTokens)",
                       "tokensPerSecond": "\(performance.tokensPerSecond)",
                       "modelId": performance.modelId,
                       "executionTarget": "\(performance.executionTarget)",
                       "routingFramework": performance.routingFramework,
                       "routingReason": performance.routingReason,
                       "timestamp": "\(performance.timestamp.timeIntervalSince1970)"
                   ])
    }

    /// Log performance alert
    public func logPerformanceAlert(_ alert: PerformanceAlert) {
        logger.warning("Performance Alert: \(alert.message)",
                      metadata: [
                          "id": alert.id.uuidString,
                          "type": "\(alert.type)",
                          "severity": "\(alert.severity)",
                          "message": alert.message,
                          "timestamp": "\(alert.timestamp.timeIntervalSince1970)"
                      ])
    }
}
