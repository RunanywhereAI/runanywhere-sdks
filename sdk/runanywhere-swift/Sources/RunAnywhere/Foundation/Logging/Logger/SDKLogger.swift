//
//  SDKLogger.swift
//  RunAnywhere SDK
//
//  Centralized logging utility for SDK components with sensitive data protection
//

import Foundation

/// Centralized logging utility with sensitive data protection
public struct SDKLogger {
    private let category: String

    public init(category: String = "SDK") {
        self.category = category
    }

    // MARK: - Standard Logging Methods

    /// Log a debug message
    public func debug(_ message: String, metadata: [String: Any]? = nil) {  // swiftlint:disable:this prefer_concrete_types avoid_any_type
        LoggingManager.shared.log(level: .debug, category: category, message: message, metadata: metadata)
    }

    /// Log an info message
    public func info(_ message: String, metadata: [String: Any]? = nil) {  // swiftlint:disable:this prefer_concrete_types avoid_any_type
        LoggingManager.shared.log(level: .info, category: category, message: message, metadata: metadata)
    }

    /// Log a warning message
    public func warning(_ message: String, metadata: [String: Any]? = nil) {  // swiftlint:disable:this prefer_concrete_types avoid_any_type
        LoggingManager.shared.log(level: .warning, category: category, message: message, metadata: metadata)
    }

    /// Log an error message
    public func error(_ message: String, metadata: [String: Any]? = nil) {  // swiftlint:disable:this prefer_concrete_types avoid_any_type
        LoggingManager.shared.log(level: .error, category: category, message: message, metadata: metadata)
    }

    /// Log a fault message
    public func fault(_ message: String, metadata: [String: Any]? = nil) {  // swiftlint:disable:this prefer_concrete_types avoid_any_type
        LoggingManager.shared.log(level: .fault, category: category, message: message, metadata: metadata)
    }

    /// Log a message with a specific level
    public func log(level: LogLevel, _ message: String, metadata: [String: Any]? = nil) {  // swiftlint:disable:this prefer_concrete_types avoid_any_type
        LoggingManager.shared.log(level: level, category: category, message: message, metadata: metadata)
    }

    // MARK: - Sensitive Data Logging

    /// Log a debug message with sensitive data protection
    func debugSensitive(_ message: String, category: SensitiveDataCategory, metadata: [String: Any]? = nil) {  // swiftlint:disable:this prefer_concrete_types avoid_any_type
        logSensitive(level: .debug, message: message, category: category, metadata: metadata)
    }

    /// Log an info message with sensitive data protection
    func infoSensitive(_ message: String, category: SensitiveDataCategory, metadata: [String: Any]? = nil) {  // swiftlint:disable:this prefer_concrete_types avoid_any_type
        logSensitive(level: .info, message: message, category: category, metadata: metadata)
    }

    /// Log a warning message with sensitive data protection
    func warningSensitive(_ message: String, category: SensitiveDataCategory, metadata: [String: Any]? = nil) {  // swiftlint:disable:this prefer_concrete_types avoid_any_type
        logSensitive(level: .warning, message: message, category: category, metadata: metadata)
    }

    /// Log an error message with sensitive data protection
    func errorSensitive(_ message: String, category: SensitiveDataCategory, metadata: [String: Any]? = nil) {  // swiftlint:disable:this prefer_concrete_types avoid_any_type
        logSensitive(level: .error, message: message, category: category, metadata: metadata)
    }

    /// Log sensitive data with appropriate protection
    private func logSensitive(level: LogLevel, message: String, category sensitiveCategory: SensitiveDataCategory, metadata: [String: Any]? = nil) {  // swiftlint:disable:this prefer_concrete_types avoid_any_type
        var enrichedMetadata = metadata ?? [:]
        enrichedMetadata[LogMetadataKeys.sensitiveDataCategory] = sensitiveCategory
        enrichedMetadata[LogMetadataKeys.sensitiveDataPolicy] = sensitiveCategory.defaultPolicy

        // Sanitize message based on policy
        let sanitizedMessage = sanitizeMessage(message, category: sensitiveCategory)

        LoggingManager.shared.log(
            level: level,
            category: self.category,
            message: sanitizedMessage,
            metadata: enrichedMetadata
        )
    }

    // MARK: - Performance Logging

    /// Log performance metrics
    func performance(_ metric: String, value: Double, metadata: [String: Any]? = nil) {  // swiftlint:disable:this prefer_concrete_types avoid_any_type
        var enrichedMetadata = metadata ?? [:]
        enrichedMetadata["metric"] = metric
        enrichedMetadata["value"] = value
        enrichedMetadata["type"] = "performance"

        LoggingManager.shared.log(
            level: .info,
            category: "\(category).Performance",
            message: "\(metric): \(value)",
            metadata: enrichedMetadata
        )
    }

    private func sanitizeMessage(_ message: String, category: SensitiveDataCategory) -> String {
        let policy = category.defaultPolicy

        switch policy {
        case .none:
            return message
        case .sensitive:
            // In production, replace with placeholder
            #if DEBUG
            return message
            #else
            return "\(category.sanitizedPlaceholder) - Length: \(message.count)"
            #endif
        case .critical:
            return category.sanitizedPlaceholder
        case .redacted:
            return "[REDACTED]"
        }
    }
}
