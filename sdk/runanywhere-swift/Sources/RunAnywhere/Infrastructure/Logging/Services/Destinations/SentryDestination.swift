//
//  SentryDestination.swift
//  RunAnywhere SDK
//
//  Log destination that sends logs to Sentry for crash reporting and error tracking
//

import Foundation
import Sentry

/// Log destination that sends logs to Sentry for crash reporting and error tracking
/// Only logs at warning level and above are sent to Sentry
public final class SentryDestination: LogDestination {

    // MARK: - LogDestination

    public let identifier: String = "com.runanywhere.logging.sentry"
    public let name: String = "Sentry"

    public var isAvailable: Bool {
        SentryManager.shared.isInitialized
    }

    // MARK: - Properties

    /// Minimum log level to send to Sentry (warning and above)
    private let minSentryLevel: LogLevel = .warning

    // MARK: - Initialization

    public init() {
        // SentryDestination relies on SentryManager being initialized separately
    }

    // MARK: - LogDestination Operations

    public func write(_ entry: LogEntry) {
        // Only send warning level and above to Sentry
        guard entry.level >= minSentryLevel else { return }
        guard isAvailable else { return }

        // Add as breadcrumb for context trail
        addBreadcrumb(for: entry)

        // For error and fault levels, capture as Sentry event
        if entry.level >= .error {
            captureEvent(for: entry)
        }
    }

    public func flush() {
        guard isAvailable else { return }
        SentrySDK.flush(timeout: 2.0)
    }

    // MARK: - Private Helpers

    private func addBreadcrumb(for entry: LogEntry) {
        let breadcrumb = Breadcrumb(level: convertToSentryLevel(entry.level), category: entry.category)
        breadcrumb.message = entry.message
        breadcrumb.timestamp = entry.timestamp

        if let metadata = entry.metadata {
            breadcrumb.data = metadata
        }

        SentrySDK.addBreadcrumb(breadcrumb)
    }

    private func captureEvent(for entry: LogEntry) {
        let event = Event(level: convertToSentryLevel(entry.level))
        event.message = SentryMessage(formatted: entry.message)
        event.timestamp = entry.timestamp

        // Set tags
        event.tags = [
            "category": entry.category,
            "log_level": entry.level.description
        ]

        // Add metadata as extra context
        if let metadata = entry.metadata {
            event.extra = metadata
        }

        // Add device info if available
        if let deviceInfo = entry.deviceInfo {
            var extra = event.extra ?? [:]
            extra["device_model"] = deviceInfo.modelName
            extra["device_id"] = deviceInfo.deviceId
            extra["os_version"] = deviceInfo.osVersion
            extra["platform"] = deviceInfo.platform
            event.extra = extra
        }

        SentrySDK.capture(event: event)
    }

    private func convertToSentryLevel(_ level: LogLevel) -> SentryLevel {
        switch level {
        case .debug: return .debug
        case .info: return .info
        case .warning: return .warning
        case .error: return .error
        case .fault: return .fatal
        }
    }
}
