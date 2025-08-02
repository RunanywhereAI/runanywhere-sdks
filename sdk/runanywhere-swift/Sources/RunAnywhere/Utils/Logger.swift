//
//  Logger.swift
//  RunAnywhere SDK
//
//  Unified logging utility with local and remote logging support
//

import Foundation
import os.log

/// Logging configuration
public struct LoggingConfiguration {
    /// Enable local logging (console/os_log)
    public var enableLocalLogging: Bool = true

    /// Enable remote logging (telemetry)
    public var enableRemoteLogging: Bool = false

    /// Remote logging endpoint
    public var remoteEndpoint: URL?

    /// Log level filter
    public var minLogLevel: LogLevel = .info

    /// Include device metadata in remote logs
    public var includeDeviceMetadata: Bool = true

    /// Maximum log entries to batch before sending
    public var batchSize: Int = 100

    /// Maximum time to wait before sending logs (seconds)
    public var batchInterval: TimeInterval = 60

    public init() {}
}

/// Log levels
public enum LogLevel: Int, Comparable {
    case debug = 0
    case info = 1
    case warning = 2
    case error = 3
    case fault = 4

    public static func < (lhs: LogLevel, rhs: LogLevel) -> Bool {
        return lhs.rawValue < rhs.rawValue
    }
}

/// Centralized logging manager
public class LoggingManager {
    public static let shared = LoggingManager()

    /// Current logging configuration
    public var configuration = LoggingConfiguration()

    /// Log entries pending remote submission
    private var pendingLogs: [LogEntry] = []
    private let pendingLogsQueue = DispatchQueue(label: "com.runanywhere.sdk.logging", qos: .utility)
    private var batchTimer: Timer?

    private init() {
        startBatchTimer()
    }

    /// Update logging configuration
    public func configure(_ config: LoggingConfiguration) {
        self.configuration = config
        if config.enableRemoteLogging {
            startBatchTimer()
        } else {
            stopBatchTimer()
        }
    }

    /// Internal logging method
    internal func log(level: LogLevel, category: String, message: String, metadata: [String: Any]? = nil) {
        // Check if we should log this level
        guard level >= configuration.minLogLevel else { return }

        // Create log entry
        let entry = LogEntry(
            timestamp: Date(),
            level: level,
            category: category,
            message: message,
            metadata: metadata,
            deviceInfo: configuration.includeDeviceMetadata ? DeviceInfo.current : nil
        )

        // Local logging
        if configuration.enableLocalLogging {
            logLocally(entry)
        }

        // Remote logging
        if configuration.enableRemoteLogging {
            queueForRemote(entry)
        }
    }

    private func logLocally(_ entry: LogEntry) {
        let formattedMessage = "[\(entry.category)] \(entry.message)"

        if #available(iOS 14.0, *) {
            let logger = os.Logger(subsystem: "com.runanywhere.sdk", category: entry.category)
            switch entry.level {
            case .debug:
                logger.debug("\(formattedMessage)")
            case .info:
                logger.info("\(formattedMessage)")
            case .warning:
                logger.warning("\(formattedMessage)")
            case .error:
                logger.error("\(formattedMessage)")
            case .fault:
                logger.fault("\(formattedMessage)")
            }
        } else {
            let levelString = entry.level.description.uppercased()
            print("[RunAnywhereSDK] [\(entry.category)] \(levelString): \(entry.message)")
        }
    }

    private func queueForRemote(_ entry: LogEntry) {
        pendingLogsQueue.async { [weak self] in
            guard let self = self else { return }
            self.pendingLogs.append(entry)

            if self.pendingLogs.count >= self.configuration.batchSize {
                self.sendLogs()
            }
        }
    }

    private func sendLogs() {
        pendingLogsQueue.async { [weak self] in
            guard let self = self,
                  !self.pendingLogs.isEmpty,
                  let endpoint = self.configuration.remoteEndpoint else { return }

            let logsToSend = self.pendingLogs
            self.pendingLogs.removeAll()

            // Create batch payload
            let batch = LogBatch(
                logs: logsToSend,
                sessionId: UUID().uuidString, // TODO: Add session tracking to SDK
                sdkVersion: "1.0.0"
            )

            // Send logs (simplified - in production would use proper networking)
            Task {
                do {
                    var request = URLRequest(url: endpoint)
                    request.httpMethod = "POST"
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    request.httpBody = try JSONEncoder().encode(batch)

                    let (_, response) = try await URLSession.shared.data(for: request)

                    if let httpResponse = response as? HTTPURLResponse,
                       httpResponse.statusCode != 200 {
                        // Re-queue logs on failure
                        self.pendingLogsQueue.async {
                            self.pendingLogs.insert(contentsOf: logsToSend, at: 0)
                        }
                    }
                } catch {
                    // Re-queue logs on error
                    self.pendingLogsQueue.async {
                        self.pendingLogs.insert(contentsOf: logsToSend, at: 0)
                    }
                }
            }
        }
    }

    private func startBatchTimer() {
        stopBatchTimer()
        batchTimer = Timer.scheduledTimer(withTimeInterval: configuration.batchInterval, repeats: true) { [weak self] _ in
            self?.sendLogs()
        }
    }

    private func stopBatchTimer() {
        batchTimer?.invalidate()
        batchTimer = nil
    }
}

/// Simple logging utility that handles iOS version compatibility
internal struct SDKLogger {
    private let category: String

    init(category: String) {
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
}

// MARK: - Supporting Types

/// Log entry structure
internal struct LogEntry: Encodable {
    let timestamp: Date
    let level: LogLevel
    let category: String
    let message: String
    let metadata: [String: String]?
    let deviceInfo: DeviceInfo?

    init(timestamp: Date, level: LogLevel, category: String, message: String, metadata: [String: Any]?, deviceInfo: DeviceInfo?) {
        self.timestamp = timestamp
        self.level = level
        self.category = category
        self.message = message
        self.metadata = metadata?.mapValues { String(describing: $0) }
        self.deviceInfo = deviceInfo
    }

    enum CodingKeys: String, CodingKey {
        case timestamp, level, category, message, metadata, deviceInfo
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(timestamp, forKey: .timestamp)
        try container.encode(level.description, forKey: .level)
        try container.encode(category, forKey: .category)
        try container.encode(message, forKey: .message)
        if let metadata = metadata {
            try container.encode(metadata, forKey: .metadata)
        }
        // Skip deviceInfo encoding for now to avoid circular dependency
    }
}

/// Log batch for remote submission
internal struct LogBatch: Encodable {
    let logs: [LogEntry]
    let sessionId: String
    let sdkVersion: String
}

extension LogLevel: CustomStringConvertible {
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

extension LogLevel: Codable {}
