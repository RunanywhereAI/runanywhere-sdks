//
//  SDKLogger.swift
//  RunAnywhere SDK
//
//  Simple logging utility for SDK components
//

import Foundation

/// Simple logging utility that handles iOS version compatibility
internal struct SDKLogger {
    private let category: String

    init(category: String = "SDK") {
        self.category = category
    }

    /// Log a debug message
    func debug(_ message: String, metadata: [String: Any]? = nil) {
        LoggingManager.shared.log(level: .debug, category: category, message: message, metadata: metadata)
    }

    /// Log an info message
    func info(_ message: String, metadata: [String: Any]? = nil) {
        LoggingManager.shared.log(level: .info, category: category, message: message, metadata: metadata)
    }

    /// Log a warning message
    func warning(_ message: String, metadata: [String: Any]? = nil) {
        LoggingManager.shared.log(level: .warning, category: category, message: message, metadata: metadata)
    }

    /// Log an error message
    func error(_ message: String, metadata: [String: Any]? = nil) {
        LoggingManager.shared.log(level: .error, category: category, message: message, metadata: metadata)
    }

    /// Log a fault message
    func fault(_ message: String, metadata: [String: Any]? = nil) {
        LoggingManager.shared.log(level: .fault, category: category, message: message, metadata: metadata)
    }

    /// Log a message with a specific level
    func log(level: LogLevel, _ message: String, metadata: [String: Any]? = nil) {
        LoggingManager.shared.log(level: level, category: category, message: message, metadata: metadata)
    }
}
