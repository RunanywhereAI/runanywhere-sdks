//
//  SDKLogger.swift
//  RunAnywhere SDK
//
//  Simplified logging system with multi-destination support.
//  Thread-safe, Sendable-compliant, and easy to configure.
//

import Foundation
import os

// MARK: - LogLevel

/// Log severity levels
public enum LogLevel: Int, Comparable, CustomStringConvertible, Codable, Sendable {
    case debug = 0
    case info = 1
    case warning = 2
    case error = 3
    case fault = 4

    public static func < (lhs: LogLevel, rhs: LogLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    public var description: String {
        switch self {
        case .debug: return "debug"
        case .info: return "info"
        case .warning: return "warning"
        case .error: return "error"
        case .fault: return "fault"
        }
    }
}

// MARK: - LogEntry

/// Represents a single log message with metadata
public struct LogEntry: Sendable {
    public let timestamp: Date
    public let level: LogLevel
    public let category: String
    public let message: String
    public let metadata: [String: String]?
    public let deviceInfo: DeviceInfo?

    public init(
        timestamp: Date = Date(),
        level: LogLevel,
        category: String,
        message: String,
        metadata: [String: Any]? = nil, // swiftlint:disable:this prefer_concrete_types avoid_any_type
        deviceInfo: DeviceInfo? = nil
    ) {
        self.timestamp = timestamp
        self.level = level
        self.category = category
        self.message = message
        self.metadata = metadata?.mapValues { String(describing: $0) }
        self.deviceInfo = deviceInfo
    }
}

// MARK: - LogDestination Protocol

/// Protocol for log output destinations (Console, Sentry, etc.)
public protocol LogDestination: AnyObject, Sendable { // swiftlint:disable:this avoid_any_object
    var identifier: String { get }
    var isAvailable: Bool { get }
    func write(_ entry: LogEntry)
    func flush()
}

// MARK: - LoggingConfiguration

/// Simple configuration for the logging system
public struct LoggingConfiguration: Sendable {
    public var enableLocalLogging: Bool
    public var minLogLevel: LogLevel
    public var includeDeviceMetadata: Bool
    public var enableSentryLogging: Bool

    public init(
        enableLocalLogging: Bool = true,
        minLogLevel: LogLevel = .info,
        includeDeviceMetadata: Bool = true,
        enableSentryLogging: Bool = false
    ) {
        self.enableLocalLogging = enableLocalLogging
        self.minLogLevel = minLogLevel
        self.includeDeviceMetadata = includeDeviceMetadata
        self.enableSentryLogging = enableSentryLogging
    }

    // MARK: - Environment Presets

    public static var development: LoggingConfiguration {
        LoggingConfiguration(
            enableLocalLogging: true,
            minLogLevel: .debug,
            includeDeviceMetadata: false,
            enableSentryLogging: true
        )
    }

    public static var staging: LoggingConfiguration {
        LoggingConfiguration(
            enableLocalLogging: true,
            minLogLevel: .info,
            includeDeviceMetadata: true,
            enableSentryLogging: false
        )
    }

    public static var production: LoggingConfiguration {
        LoggingConfiguration(
            enableLocalLogging: false,
            minLogLevel: .warning,
            includeDeviceMetadata: true,
            enableSentryLogging: false
        )
    }
}

// MARK: - Logging (Central Service)

/// Central logging service that routes logs to multiple destinations
public final class Logging: @unchecked Sendable {

    public static let shared = Logging()

    // MARK: - Thread-safe State

    private let lock = OSAllocatedUnfairLock<State>(initialState: State())

    private struct State {
        var configuration: LoggingConfiguration
        var destinations: [LogDestination] = []

        init() {
            let environment = RunAnywhere.currentEnvironment ?? .production
            self.configuration = LoggingConfiguration.forEnvironment(environment)
        }
    }

    public var configuration: LoggingConfiguration {
        get { lock.withLock { $0.configuration } }
        set { lock.withLock { $0.configuration = newValue } }
    }

    public var destinations: [LogDestination] {
        lock.withLock { $0.destinations }
    }

    // MARK: - Initialization

    private init() {
        let config = lock.withLock { $0.configuration }
        if config.enableSentryLogging {
            setupSentryLogging()
        }
    }

    // MARK: - Configuration

    public func configure(_ config: LoggingConfiguration) {
        let oldConfig = lock.withLock { state -> LoggingConfiguration in
            let old = state.configuration
            state.configuration = config
            return old
        }

        // Handle Sentry state changes
        if config.enableSentryLogging && !oldConfig.enableSentryLogging {
            setupSentryLogging()
        } else if !config.enableSentryLogging && oldConfig.enableSentryLogging {
            removeSentryDestination()
        }
    }

    public func setLocalLoggingEnabled(_ enabled: Bool) {
        lock.withLock { $0.configuration.enableLocalLogging = enabled }
    }

    public func setMinLogLevel(_ level: LogLevel) {
        lock.withLock { $0.configuration.minLogLevel = level }
    }

    public func setIncludeDeviceMetadata(_ include: Bool) {
        lock.withLock { $0.configuration.includeDeviceMetadata = include }
    }

    public func setSentryLoggingEnabled(_ enabled: Bool) {
        var config = configuration
        config.enableSentryLogging = enabled
        configure(config)
    }

    // MARK: - Core Logging

    public func log(
        level: LogLevel,
        category: String,
        message: String,
        metadata: [String: Any]? = nil // swiftlint:disable:this prefer_concrete_types avoid_any_type
    ) {
        let (config, currentDestinations) = lock.withLock { ($0.configuration, $0.destinations) }

        guard level >= config.minLogLevel else { return }
        guard config.enableLocalLogging || config.enableSentryLogging else { return }

        let entry = LogEntry(
            level: level,
            category: category,
            message: message,
            metadata: sanitizeMetadata(metadata),
            deviceInfo: config.includeDeviceMetadata ? DeviceInfo.current : nil
        )

        // Write to console if local logging enabled
        if config.enableLocalLogging {
            printToConsole(entry)
        }

        // Write to all registered destinations
        for destination in currentDestinations where destination.isAvailable {
            destination.write(entry)
        }
    }

    // MARK: - Destination Management

    public func addDestination(_ destination: LogDestination) {
        lock.withLock { state in
            guard !state.destinations.contains(where: { $0.identifier == destination.identifier }) else { return }
            state.destinations.append(destination)
        }
    }

    public func removeDestination(_ destination: LogDestination) {
        lock.withLock { state in
            state.destinations.removeAll { $0.identifier == destination.identifier }
        }
    }

    public func flush() {
        let currentDestinations = destinations
        for destination in currentDestinations {
            destination.flush()
        }
    }

    // MARK: - Private Helpers

    private func setupSentryLogging() {
        let environment = RunAnywhere.currentEnvironment ?? .development
        SentryManager.shared.initialize(environment: environment)
        addDestination(SentryDestination())
    }

    private func removeSentryDestination() {
        lock.withLock { state in
            state.destinations.removeAll { $0.identifier == SentryDestination.destinationID }
        }
    }

    private func printToConsole(_ entry: LogEntry) {
        let emoji: String
        switch entry.level {
        case .debug: emoji = "🔍"
        case .info: emoji = "ℹ️"
        case .warning: emoji = "⚠️"
        case .error: emoji = "❌"
        case .fault: emoji = "💥"
        }

        var output = "\(emoji) [\(entry.category)] \(entry.message)"
        if let metadata = entry.metadata, !metadata.isEmpty {
            let metaStr = metadata.map { "\($0.key)=\($0.value)" }.joined(separator: ", ")
            output += " | \(metaStr)"
        }

        #if DEBUG
        print(output)
        #endif
    }

    // MARK: - Metadata Sanitization

    private static let sensitivePatterns = ["key", "secret", "password", "token", "auth", "credential"]

    private func sanitizeMetadata(_ metadata: [String: Any]?) -> [String: Any]? { // swiftlint:disable:this prefer_concrete_types avoid_any_type
        guard let metadata = metadata else { return nil }

        var sanitized: [String: Any] = [:] // swiftlint:disable:this prefer_concrete_types avoid_any_type
        for (key, value) in metadata {
            let lowercased = key.lowercased()
            if Self.sensitivePatterns.contains(where: { lowercased.contains($0) }) {
                sanitized[key] = "[REDACTED]"
            } else if let nested = value as? [String: Any] { // swiftlint:disable:this avoid_any_type
                sanitized[key] = sanitizeMetadata(nested) ?? [:]
            } else {
                sanitized[key] = value
            }
        }
        return sanitized
    }
}

// MARK: - Environment Helper

extension LoggingConfiguration {
    static func forEnvironment(_ environment: SDKEnvironment) -> LoggingConfiguration {
        switch environment {
        case .development: return .development
        case .staging: return .staging
        case .production: return .production
        }
    }
}

extension Logging {
    /// Apply configuration based on SDK environment
    public func applyEnvironmentConfiguration(_ environment: SDKEnvironment) {
        let config = LoggingConfiguration.forEnvironment(environment)
        configure(config)
    }
}

// MARK: - SDKLogger (Convenience Wrapper)

/// Simple logger for SDK components with category-based filtering
public struct SDKLogger: Sendable {
    public let category: String

    public init(category: String = "SDK") {
        self.category = category
    }

    // MARK: - Logging Methods

    @inlinable
    public func debug(_ message: @autoclosure () -> String, metadata: [String: Any]? = nil) { // swiftlint:disable:this prefer_concrete_types avoid_any_type
        #if DEBUG
        Logging.shared.log(level: .debug, category: category, message: message(), metadata: metadata)
        #endif
    }

    public func info(_ message: String, metadata: [String: Any]? = nil) { // swiftlint:disable:this prefer_concrete_types avoid_any_type
        Logging.shared.log(level: .info, category: category, message: message, metadata: metadata)
    }

    public func warning(_ message: String, metadata: [String: Any]? = nil) { // swiftlint:disable:this prefer_concrete_types avoid_any_type
        Logging.shared.log(level: .warning, category: category, message: message, metadata: metadata)
    }

    public func error(_ message: String, metadata: [String: Any]? = nil) { // swiftlint:disable:this prefer_concrete_types avoid_any_type
        Logging.shared.log(level: .error, category: category, message: message, metadata: metadata)
    }

    public func fault(_ message: String, metadata: [String: Any]? = nil) { // swiftlint:disable:this prefer_concrete_types avoid_any_type
        Logging.shared.log(level: .fault, category: category, message: message, metadata: metadata)
    }

    // MARK: - Error Logging with Context

    public func logError(
        _ error: Error,
        additionalInfo: String? = nil,
        file: String = #file,
        line: Int = #line,
        function: String = #function
    ) {
        let fileName = (file as NSString).lastPathComponent
        let errorDesc = (error as? SDKError)?.errorDescription ?? error.localizedDescription

        var message = "\(errorDesc) at \(fileName):\(line) in \(function)"
        if let info = additionalInfo {
            message += " | Context: \(info)"
        }

        var metadata: [String: Any] = [ // swiftlint:disable:this prefer_concrete_types avoid_any_type
            "source_file": fileName,
            "source_line": line,
            "source_function": function
        ]

        if let sdkError = error as? SDKError {
            metadata["error_code"] = sdkError.code.rawValue
            metadata["error_category"] = sdkError.category.rawValue
        }

        Logging.shared.log(level: .error, category: category, message: message, metadata: metadata)
    }
}

// MARK: - Convenience Loggers

extension SDKLogger {
    public static let shared = SDKLogger(category: "RunAnywhere")
    public static let llm = SDKLogger(category: "LLM")
    public static let stt = SDKLogger(category: "STT")
    public static let tts = SDKLogger(category: "TTS")
    public static let download = SDKLogger(category: "Download")
    public static let models = SDKLogger(category: "Models")
}
