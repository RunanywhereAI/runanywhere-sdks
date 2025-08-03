//
//  PerformanceAlert.swift
//  RunAnywhere SDK
//
//  Performance alert model
//

import Foundation

/// Performance alert
public struct PerformanceAlert: Identifiable {
    /// Unique identifier
    public let id: UUID

    /// Type of alert
    public let type: AlertType

    /// Severity level
    public let severity: AlertSeverity

    /// Human-readable message
    public let message: String

    /// When this alert was created
    public let timestamp: Date

    public init(
        id: UUID = UUID(),
        type: AlertType,
        severity: AlertSeverity,
        message: String,
        timestamp: Date = Date()
    ) {
        self.id = id
        self.type = type
        self.severity = severity
        self.message = message
        self.timestamp = timestamp
    }
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
