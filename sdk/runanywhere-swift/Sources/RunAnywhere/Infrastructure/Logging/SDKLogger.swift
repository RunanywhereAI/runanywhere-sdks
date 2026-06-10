//
//  SDKLogger.swift
//  RunAnywhere SDK
//
//  Simplified logging system with multi-destination support.
//  Thread-safe, Sendable-compliant, and easy to configure.
//

import CRACommons
import Foundation
import os

// MARK: - RALogLevel ordering

/// `RALogLevel` (generated proto) is the canonical severity enum:
/// `trace(0) < debug(1) < info(2) < warning(3) < error(4) < fatal(5)`.
/// SwiftProtobuf's generated enum is not `Comparable`, so we add ordered
/// comparisons here for severity gating (`level >= minLogLevel`).
extension RALogLevel: @retroactive Comparable {
    public static func < (lhs: RALogLevel, rhs: RALogLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

// MARK: - LogDestination Protocol

/// Protocol for log output destinations (Console, Sentry, etc.)
public protocol LogDestination: AnyObject, Sendable { // swiftlint:disable:this avoid_any_object
    var identifier: String { get }
    var isAvailable: Bool { get }
    func write(_ entry: RALogEntry)
    func flush()
}

// MARK: - RALoggingConfiguration Presets

/// Environment presets for the generated `RALoggingConfiguration` proto.
/// The struct itself is generated under `Sources/RunAnywhere/Generated/`;
/// these factories supply the dev/staging/prod defaults.
extension RALoggingConfiguration {
    public static var development: RALoggingConfiguration {
        var config = RALoggingConfiguration()
        config.enableLocalLogging = true
        config.minLogLevel = .debug
        config.includeDeviceMetadata = false
        config.enableSentryLogging = true
        return config
    }

    public static var staging: RALoggingConfiguration {
        var config = RALoggingConfiguration()
        config.enableLocalLogging = true
        config.minLogLevel = .info
        config.includeDeviceMetadata = true
        config.enableSentryLogging = false
        return config
    }

    public static var production: RALoggingConfiguration {
        var config = RALoggingConfiguration()
        config.enableLocalLogging = false
        config.minLogLevel = .warning
        config.includeDeviceMetadata = true
        config.enableSentryLogging = false
        return config
    }
}

// MARK: - Logging (Central Service)

/// Central logging service that routes logs to multiple destinations
public final class Logging: @unchecked Sendable {

    public static let shared = Logging()

    // MARK: - Thread-safe State

    private let lock = OSAllocatedUnfairLock<State>(initialState: State())

    private struct State {
        var configuration: RALoggingConfiguration
        var destinations: [LogDestination] = []

        init() {
            let environment = RunAnywhere.currentEnvironment ?? .production
            self.configuration = RALoggingConfiguration.forEnvironment(environment)
        }
    }

    public var configuration: RALoggingConfiguration {
        get { lock.withLock { $0.configuration } }
        set { lock.withLock { $0.configuration = newValue } }
    }

    public var destinations: [LogDestination] {
        lock.withLock { $0.destinations }
    }

    // MARK: - Initialization

    private init() {
        let config = lock.withLock { $0.configuration }
        syncOSLogDestination(for: config)
        if config.enableSentryLogging {
            setupSentryLogging()
        }
    }

    // MARK: - Configuration

    public func configure(_ config: RALoggingConfiguration) {
        let oldConfig = lock.withLock { state -> RALoggingConfiguration in
            let old = state.configuration
            state.configuration = config
            return old
        }

        syncOSLogDestination(for: config)

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

    public func setMinLogLevel(_ level: RALogLevel) {
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
        level: RALogLevel,
        category: String,
        message: String,
        metadata: [String: Any]? = nil // swiftlint:disable:this prefer_concrete_types avoid_any_type
    ) {
        let (config, currentDestinations) = lock.withLock { ($0.configuration, $0.destinations) }

        guard level >= config.minLogLevel else { return }

        // `RALogEntry` (generated proto) has no native `deviceInfo` or `Date`
        // field, so fold the platform-only bits SDK-side: device metadata goes
        // into the `metadata` map, and the `Date` timestamp is converted to the
        // proto's `timestampUnixMs: Int64`.
        var stringMetadata = (sanitizeMetadata(metadata) ?? [:]).mapValues { String(describing: $0) }
        if config.includeDeviceMetadata {
            let deviceInfo = DeviceInfoFactory.current
            stringMetadata["device_model"] = deviceInfo.deviceModel
            stringMetadata["os_version"] = deviceInfo.osVersion
            stringMetadata["platform"] = deviceInfo.platform
        }

        var entry = RALogEntry()
        entry.timestampUnixMs = Int64(Date().timeIntervalSince1970 * 1000)
        entry.level = level
        entry.category = category
        entry.message = message
        entry.metadata = stringMetadata

        // Console print is optional; unified logging (OSLog) is always on for
        // simulator/device log capture used by E2E catalog grep markers.
        if config.enableLocalLogging {
            printToConsole(entry)
        }

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

    private func syncOSLogDestination(for _: RALoggingConfiguration) {
        let hasOSLog = lock.withLock { state in
            state.destinations.contains { $0.identifier == OSLogDestination.destinationID }
        }
        if !hasOSLog {
            addDestination(OSLogDestination())
        }
    }

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

    private func printToConsole(_ entry: RALogEntry) {
        let emoji: String
        switch entry.level {
        case .trace: emoji = "🔬"
        case .debug: emoji = "🔍"
        case .info: emoji = "ℹ️"
        case .warning: emoji = "⚠️"
        case .error: emoji = "❌"
        case .fatal: emoji = "💥"
        case .UNRECOGNIZED: emoji = "❓"
        }

        var output = "\(emoji) [\(entry.category)] \(entry.message)"
        if !entry.metadata.isEmpty {
            let metaStr = entry.metadata.map { "\($0.key)=\($0.value)" }.joined(separator: ", ")
            output += " | \(metaStr)"
        }

        // Always print when local logging is enabled (controlled by configuration)
        // The enableLocalLogging flag already controls whether this method is called
        // swiftlint:disable:next no_print_statements
        print(output)
    }

    // MARK: - Metadata Sanitization

    /// Determines if a metadata key should be redacted by delegating to the
    /// canonical C++ policy (`rac_log_metadata_should_redact`). Keeps Swift
    /// and C++ logs in sync without duplicating the substring list.
    private func shouldRedact(_ key: String) -> Bool {
        var out: rac_bool_t = 0
        let rc = key.withCString { rac_log_metadata_should_redact($0, &out) }
        return rc == RAC_SUCCESS && out != 0
    }

    private func sanitizeMetadata(_ metadata: [String: Any]?) -> [String: Any]? { // swiftlint:disable:this prefer_concrete_types avoid_any_type
        guard let metadata = metadata else { return nil }

        var sanitized: [String: Any] = [:] // swiftlint:disable:this prefer_concrete_types avoid_any_type
        for (key, value) in metadata {
            if shouldRedact(key) {
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

extension RALoggingConfiguration {
    static func forEnvironment(_ environment: SDKEnvironment) -> RALoggingConfiguration {
        switch environment {
        case .development:  return .development
        case .staging:      return .staging
        case .production:   return .production
        default:            return .development
        }
    }
}

extension Logging {
    /// Apply configuration based on SDK environment
    public func applyEnvironmentConfiguration(_ environment: SDKEnvironment) {
        let config = RALoggingConfiguration.forEnvironment(environment)
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
        Logging.shared.log(level: .fatal, category: category, message: message, metadata: metadata)
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
        let errorDesc = (error as? SDKException)?.errorDescription ?? error.localizedDescription

        var message = "\(errorDesc) at \(fileName):\(line) in \(function)"
        if let info = additionalInfo {
            message += " | Context: \(info)"
        }

        var metadata: [String: Any] = [ // swiftlint:disable:this prefer_concrete_types avoid_any_type
            "source_file": fileName,
            "source_line": line,
            "source_function": function
        ]

        if let sdkError = error as? SDKException {
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
    public static let voiceAgent = SDKLogger(category: "VoiceAgent")
}
