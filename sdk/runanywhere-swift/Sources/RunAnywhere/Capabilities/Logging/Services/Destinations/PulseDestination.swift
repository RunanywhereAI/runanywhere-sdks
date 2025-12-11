//
//  PulseDestination.swift
//  RunAnywhere SDK
//
//  Log destination that writes to Pulse for local debugging
//

import Foundation
import Pulse

/// Log destination that writes to Pulse for local debugging and development
public final class PulseDestination: LogDestination {

    // MARK: - LogDestination

    public let identifier: String = "com.runanywhere.logging.pulse"
    public let name: String = "Pulse"

    public var isAvailable: Bool {
        return true // Pulse is always available when imported
    }

    // MARK: - Properties

    private let pulseLogger = LoggerStore.shared

    // MARK: - Initialization

    public init() {
        // Enable automatic network logging
        URLSessionProxyDelegate.enableAutomaticRegistration()
    }

    // MARK: - LogDestination Operations

    public func write(_ entry: LogEntry) {
        var pulseMetadata: [String: LoggerStore.MetadataValue] = [:]

        // Add category
        pulseMetadata["category"] = .string(entry.category)

        // Convert metadata to Pulse format
        if let metadata = entry.metadata {
            for (key, value) in metadata {
                // Skip internal markers
                if key.hasPrefix("__") { continue }
                pulseMetadata[key] = .string(value)
            }
        }

        // Convert LogLevel to Pulse level
        let pulseLevel = convertToPulseLevel(entry.level)

        // Log to Pulse
        pulseLogger.storeMessage(
            label: entry.category,
            level: pulseLevel,
            message: entry.message,
            metadata: pulseMetadata.isEmpty ? nil : pulseMetadata
        )
    }

    public func flush() {
        // Pulse handles its own flushing
    }

    // MARK: - Private Helpers

    private func convertToPulseLevel(_ level: LogLevel) -> LoggerStore.Level {
        switch level {
        case .debug: return .debug
        case .info: return .info
        case .warning: return .warning
        case .error: return .error
        case .fault: return .critical
        }
    }
}
