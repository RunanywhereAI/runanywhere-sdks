//
//  SDKLogger.swift
//  RunAnywhere SDK
//
//  Centralized logging utility for SDK components
//

import Foundation

/// Centralized logging utility for SDK components
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
}
