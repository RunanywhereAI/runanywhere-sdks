//
//  AnalyticsEventData.swift
//  RunAnywhere SDK
//
//  Shared analytics event data models and base protocol
//

import Foundation

/// Base protocol for all structured event data
public protocol AnalyticsEventData: Codable, Sendable {}

// MARK: - Voice/Pipeline Event Data Models (Shared)

/// Pipeline creation event data
public struct PipelineCreationData: AnalyticsEventData {
    public let stageCount: Int
    public let stages: [String]

    public init(stageCount: Int, stages: [String]) {
        self.stageCount = stageCount
        self.stages = stages
    }
}

/// Pipeline started event data
public struct PipelineStartedData: AnalyticsEventData {
    public let stageCount: Int
    public let stages: [String]
    public let startTimestamp: TimeInterval

    public init(stageCount: Int, stages: [String], startTimestamp: TimeInterval) {
        self.stageCount = stageCount
        self.stages = stages
        self.startTimestamp = startTimestamp
    }
}

/// Pipeline completion event data
public struct PipelineCompletionData: AnalyticsEventData {
    public let stageCount: Int
    public let stages: [String]
    public let totalTimeMs: Double

    public init(stageCount: Int, stages: [String], totalTimeMs: Double) {
        self.stageCount = stageCount
        self.stages = stages
        self.totalTimeMs = totalTimeMs
    }
}

/// Stage execution event data
public struct StageExecutionData: AnalyticsEventData {
    public let stageName: String
    public let durationMs: Double

    public init(stageName: String, durationMs: Double) {
        self.stageName = stageName
        self.durationMs = durationMs
    }
}

/// Voice transcription event data (for voice pipeline)
public struct VoiceTranscriptionData: AnalyticsEventData {
    public let durationMs: Double
    public let wordCount: Int
    public let audioLengthMs: Double
    public let realTimeFactor: Double

    public init(durationMs: Double, wordCount: Int, audioLengthMs: Double, realTimeFactor: Double) {
        self.durationMs = durationMs
        self.wordCount = wordCount
        self.audioLengthMs = audioLengthMs
        self.realTimeFactor = realTimeFactor
    }
}

// MARK: - Monitoring Event Data Models (Shared)

/// Resource usage event data
public struct ResourceUsageData: AnalyticsEventData {
    public let memoryUsageMB: Double
    public let cpuUsagePercent: Double
    public let diskUsageMB: Double?
    public let batteryLevel: Float?

    public init(memoryUsageMB: Double, cpuUsagePercent: Double, diskUsageMB: Double? = nil, batteryLevel: Float? = nil) {
        self.memoryUsageMB = memoryUsageMB
        self.cpuUsagePercent = cpuUsagePercent
        self.diskUsageMB = diskUsageMB
        self.batteryLevel = batteryLevel
    }
}

/// Performance metrics event data
public struct PerformanceMetricsData: AnalyticsEventData {
    public let operationName: String
    public let durationMs: Double
    public let success: Bool
    public let errorCode: String?

    public init(operationName: String, durationMs: Double, success: Bool, errorCode: String? = nil) {
        self.operationName = operationName
        self.durationMs = durationMs
        self.success = success
        self.errorCode = errorCode
    }
}

/// CPU threshold event data
public struct CPUThresholdData: AnalyticsEventData {
    public let cpuUsage: Double
    public let threshold: Double
    public let timestamp: TimeInterval

    public init(cpuUsage: Double, threshold: Double) {
        self.cpuUsage = cpuUsage
        self.threshold = threshold
        self.timestamp = Date().timeIntervalSince1970
    }
}

/// Disk space warning event data
public struct DiskSpaceWarningData: AnalyticsEventData {
    public let availableSpaceMB: Int
    public let requiredSpaceMB: Int
    public let timestamp: TimeInterval

    public init(availableSpaceMB: Int, requiredSpaceMB: Int) {
        self.availableSpaceMB = availableSpaceMB
        self.requiredSpaceMB = requiredSpaceMB
        self.timestamp = Date().timeIntervalSince1970
    }
}

/// Network latency event data
public struct NetworkLatencyData: AnalyticsEventData {
    public let endpoint: String
    public let latencyMs: Double
    public let timestamp: TimeInterval

    public init(endpoint: String, latencyMs: Double) {
        self.endpoint = endpoint
        self.latencyMs = latencyMs
        self.timestamp = Date().timeIntervalSince1970
    }
}

/// Memory warning event data
public struct MemoryWarningData: AnalyticsEventData {
    public let warningLevel: String
    public let availableMemoryMB: Int
    public let timestamp: TimeInterval

    public init(warningLevel: String, availableMemoryMB: Int) {
        self.warningLevel = warningLevel
        self.availableMemoryMB = availableMemoryMB
        self.timestamp = Date().timeIntervalSince1970
    }
}

// MARK: - Session Event Data Models (Shared)

/// Session started event data
public struct SessionStartedData: AnalyticsEventData {
    public let modelId: String
    public let sessionType: String
    public let timestamp: TimeInterval

    public init(modelId: String, sessionType: String) {
        self.modelId = modelId
        self.sessionType = sessionType
        self.timestamp = Date().timeIntervalSince1970
    }
}

/// Session ended event data
public struct SessionEndedData: AnalyticsEventData {
    public let sessionId: String
    public let duration: TimeInterval
    public let timestamp: TimeInterval

    public init(sessionId: String, duration: TimeInterval) {
        self.sessionId = sessionId
        self.duration = duration
        self.timestamp = Date().timeIntervalSince1970
    }
}

// MARK: - Generic Error Data (Shared)

/// Generic error event data (for legacy analytics)
public struct LegacyErrorEventData: AnalyticsEventData {
    public let error: String
    public let context: String
    public let errorCode: String?
    public let timestamp: TimeInterval

    public init(error: String, context: AnalyticsContext, errorCode: String? = nil) {
        self.error = error
        self.context = context.rawValue
        self.errorCode = errorCode
        self.timestamp = Date().timeIntervalSince1970
    }
}
