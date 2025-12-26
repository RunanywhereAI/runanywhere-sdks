//
//  SentryDestination.swift
//  RunAnywhere SDK
//
//  Log destination that sends logs to Sentry for error tracking
//

import Foundation
import Sentry

/// Log destination that sends warning+ logs to Sentry
public final class SentryDestination: LogDestination, @unchecked Sendable {

    // MARK: - LogDestination

    public static let destinationID = "com.runanywhere.logging.sentry"

    public let identifier: String = SentryDestination.destinationID

    public var isAvailable: Bool {
        SentryManager.shared.isInitialized
    }

    /// Only send warning level and above to Sentry
    private let minSentryLevel: LogLevel = .warning

    public init() {}

    // MARK: - LogDestination Operations

    public func write(_ entry: LogEntry) {
        guard entry.level >= minSentryLevel, isAvailable else { return }

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
        event.tags = [
            "category": entry.category,
            "log_level": entry.level.description
        ]

        if let metadata = entry.metadata {
            event.extra = metadata
        }

        if let deviceInfo = entry.deviceInfo {
            var extra = event.extra ?? [:]
            extra["device_model"] = deviceInfo.deviceModel
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
