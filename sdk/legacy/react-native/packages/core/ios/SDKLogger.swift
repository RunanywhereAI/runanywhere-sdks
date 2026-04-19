/**
 * SDKLogger.swift
 *
 * iOS native logging implementation for React Native SDK.
 * Provides structured logging with category-based filtering.
 *
 * Matches:
 * - iOS SDK: sdk/runanywhere-swift/Sources/RunAnywhere/Infrastructure/Logging/SDKLogger.swift
 * - TypeScript: packages/core/src/Foundation/Logging/Logger/SDKLogger.ts
 *
 * Usage:
 *   SDKLogger.shared.info("SDK initialized")
 *   SDKLogger.download.debug("Starting download: \(url)")
 *   SDKLogger.llm.error("Generation failed", metadata: ["modelId": "llama-3.2"])
 */

import Foundation
import os

// MARK: - LogLevel

/// Log severity levels matching TypeScript LogLevel enum
@objc public enum RNLogLevel: Int, Comparable {
    case debug = 0
    case info = 1
    case warning = 2
    case error = 3
    case fault = 4

    public static func < (lhs: RNLogLevel, rhs: RNLogLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    public var description: String {
        switch self {
        case .debug: return "DEBUG"
        case .info: return "INFO"
        case .warning: return "WARN"
        case .error: return "ERROR"
        case .fault: return "FAULT"
        }
    }
}

// MARK: - SDKLogger

// MARK: - Log Entry (for forwarding to TypeScript)

/// Log entry structure for forwarding to TypeScript
/// Matches TypeScript: LogEntry interface
@objc public class NativeLogEntry: NSObject {
    @objc public let level: Int
    @objc public let category: String
    @objc public let message: String
    @objc public let metadata: [String: Any]?
    @objc public let timestamp: Date

    @objc public init(level: RNLogLevel, category: String, message: String, metadata: [String: Any]?, timestamp: Date) {
        self.level = level.rawValue
        self.category = category
        self.message = message
        self.metadata = metadata
        self.timestamp = timestamp
        super.init()
    }

    /// Convert to dictionary for JSON serialization
    @objc public func toDictionary() -> [String: Any] {
        var dict: [String: Any] = [
            "level": level,
            "category": category,
            "message": message,
            "timestamp": ISO8601DateFormatter().string(from: timestamp)
        ]
        if let metadata = metadata {
            // Convert metadata to JSON-safe types
            dict["metadata"] = metadata.mapValues { value -> Any in
                if let stringValue = value as? String { return stringValue }
                if let numberValue = value as? NSNumber { return numberValue }
                return String(describing: value)
            }
        }
        return dict
    }
}

// MARK: - Log Forwarder Protocol

/// Protocol for forwarding logs to TypeScript
@objc public protocol NativeLogForwarder {
    func forwardLog(_ entry: NativeLogEntry)
}

/// Simple logger for SDK components with category-based filtering.
/// Thread-safe and easy to use. Supports forwarding to TypeScript.
@objc public final class SDKLogger: NSObject {

    // MARK: - Properties

    /// Logger category (e.g., "LLM", "Download", "Models")
    public let category: String

    /// Minimum log level (logs below this level are ignored)
    private static var minLogLevel: RNLogLevel = .debug

    /// Whether local console logging is enabled
    private static var localLoggingEnabled = true

    /// Whether to forward logs to TypeScript
    private static var forwardingEnabled = true

    /// Log forwarder for TypeScript bridge
    private static var logForwarder: NativeLogForwarder?

    /// OSLog instance for this category
    private lazy var osLog: OSLog = {
        OSLog(subsystem: "com.runanywhere.reactnative", category: category)
    }()

    // MARK: - Initialization

    /// Create a new logger with the specified category.
    /// - Parameter category: Category name for log filtering
    @objc public init(category: String = "SDK") {
        self.category = category
        super.init()
    }

    // MARK: - Configuration

    /// Set the minimum log level.
    /// - Parameter level: Minimum level to log
    @objc public static func setMinLogLevel(_ level: RNLogLevel) {
        minLogLevel = level
    }

    /// Get the current minimum log level.
    @objc public static func getMinLogLevel() -> RNLogLevel {
        return minLogLevel
    }

    /// Enable or disable local console logging.
    /// - Parameter enabled: Whether to log to console
    @objc public static func setLocalLoggingEnabled(_ enabled: Bool) {
        localLoggingEnabled = enabled
    }

    /// Enable or disable log forwarding to TypeScript.
    /// - Parameter enabled: Whether to forward logs
    @objc public static func setForwardingEnabled(_ enabled: Bool) {
        forwardingEnabled = enabled
    }

    /// Set the log forwarder for TypeScript bridge.
    /// - Parameter forwarder: Log forwarder implementation
    @objc public static func setLogForwarder(_ forwarder: NativeLogForwarder?) {
        logForwarder = forwarder
    }

    /// Check if log forwarding is configured
    @objc public static func isForwardingConfigured() -> Bool {
        return logForwarder != nil && forwardingEnabled
    }

    // MARK: - Logging Methods

    /// Log a debug message.
    /// - Parameters:
    ///   - message: Log message
    ///   - metadata: Optional metadata dictionary
    @objc public func debug(_ message: String, metadata: [String: Any]? = nil) {
        log(level: .debug, message: message, metadata: metadata)
    }

    /// Log an info message.
    /// - Parameters:
    ///   - message: Log message
    ///   - metadata: Optional metadata dictionary
    @objc public func info(_ message: String, metadata: [String: Any]? = nil) {
        log(level: .info, message: message, metadata: metadata)
    }

    /// Log a warning message.
    /// - Parameters:
    ///   - message: Log message
    ///   - metadata: Optional metadata dictionary
    @objc public func warning(_ message: String, metadata: [String: Any]? = nil) {
        log(level: .warning, message: message, metadata: metadata)
    }

    /// Log an error message.
    /// - Parameters:
    ///   - message: Log message
    ///   - metadata: Optional metadata dictionary
    @objc public func error(_ message: String, metadata: [String: Any]? = nil) {
        log(level: .error, message: message, metadata: metadata)
    }

    /// Log a fault/critical message.
    /// - Parameters:
    ///   - message: Log message
    ///   - metadata: Optional metadata dictionary
    @objc public func fault(_ message: String, metadata: [String: Any]? = nil) {
        log(level: .fault, message: message, metadata: metadata)
    }

    // MARK: - Error Logging

    /// Log an Error with full context.
    /// - Parameters:
    ///   - error: Error to log
    ///   - additionalInfo: Optional additional context
    @objc public func logError(_ error: Error, additionalInfo: String? = nil) {
        let nsError = error as NSError
        var message = error.localizedDescription
        if let info = additionalInfo {
            message += " | Context: \(info)"
        }

        var metadata: [String: Any] = [
            "error_domain": nsError.domain,
            "error_code": nsError.code
        ]

        if !nsError.userInfo.isEmpty {
            metadata["error_userInfo"] = nsError.userInfo.description
        }

        log(level: .error, message: message, metadata: metadata)
    }

    // MARK: - Core Logging

    /// Log a message with the specified level.
    /// - Parameters:
    ///   - level: Log level
    ///   - message: Log message
    ///   - metadata: Optional metadata dictionary
    public func log(level: RNLogLevel, message: String, metadata: [String: Any]? = nil) {
        guard level >= Self.minLogLevel else { return }

        let timestamp = Date()

        // Build formatted message
        var output = "[\(category)] \(message)"
        if let metadata = metadata, !metadata.isEmpty {
            let metaStr = metadata.map { "\($0.key)=\($0.value)" }.joined(separator: ", ")
            output += " | \(metaStr)"
        }

        // Log to OSLog (always, for system log capture)
        switch level {
        case .debug:
            os_log(.debug, log: osLog, "%{public}@", output)
        case .info:
            os_log(.info, log: osLog, "%{public}@", output)
        case .warning:
            os_log(.default, log: osLog, "[WARN] %{public}@", output)
        case .error:
            os_log(.error, log: osLog, "%{public}@", output)
        case .fault:
            os_log(.fault, log: osLog, "%{public}@", output)
        }

        // Also log to console if enabled
        if Self.localLoggingEnabled {
            let emoji: String
            switch level {
            case .debug: emoji = "[DEBUG]"
            case .info: emoji = "[INFO]"
            case .warning: emoji = "[WARN]"
            case .error: emoji = "[ERROR]"
            case .fault: emoji = "[FAULT]"
            }
            // swiftlint:disable:next no_print_statements
            NSLog("%@ %@", emoji, output)
        }

        // Forward to TypeScript if enabled
        if Self.forwardingEnabled, let forwarder = Self.logForwarder {
            let entry = NativeLogEntry(
                level: level,
                category: category,
                message: message,
                metadata: metadata,
                timestamp: timestamp
            )
            forwarder.forwardLog(entry)
        }
    }

    // MARK: - Convenience Loggers (Static)

    /// Shared logger for general SDK operations. Category: "RunAnywhere"
    @objc public static let shared = SDKLogger(category: "RunAnywhere")

    /// Logger for LLM operations. Category: "LLM"
    @objc public static let llm = SDKLogger(category: "LLM")

    /// Logger for STT (Speech-to-Text) operations. Category: "STT"
    @objc public static let stt = SDKLogger(category: "STT")

    /// Logger for TTS (Text-to-Speech) operations. Category: "TTS"
    @objc public static let tts = SDKLogger(category: "TTS")

    /// Logger for download operations. Category: "Download"
    @objc public static let download = SDKLogger(category: "Download")

    /// Logger for model operations. Category: "Models"
    @objc public static let models = SDKLogger(category: "Models")

    /// Logger for core SDK operations. Category: "Core"
    @objc public static let core = SDKLogger(category: "Core")

    /// Logger for VAD operations. Category: "VAD"
    @objc public static let vad = SDKLogger(category: "VAD")

    /// Logger for network operations. Category: "Network"
    @objc public static let network = SDKLogger(category: "Network")

    /// Logger for events. Category: "Events"
    @objc public static let events = SDKLogger(category: "Events")

    /// Logger for archive/extraction operations. Category: "Archive"
    @objc public static let archive = SDKLogger(category: "Archive")

    /// Logger for audio decoding operations. Category: "AudioDecoder"
    @objc public static let audioDecoder = SDKLogger(category: "AudioDecoder")
}
