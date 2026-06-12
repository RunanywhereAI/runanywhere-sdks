//
//  SentryDestination.swift
//  RunAnywhere SDK
//
//  Log destination that sends logs to Sentry for error tracking
//

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
    private let minSentryLevel: RALogLevel = .warning

    public init() {}

    // MARK: - LogDestination Operations

    public func write(_ entry: RALogEntry) {
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

    private func addBreadcrumb(for entry: RALogEntry) {
        let breadcrumb = Breadcrumb(level: convertToSentryLevel(entry.level), category: entry.category)
        breadcrumb.message = entry.message
        breadcrumb.timestamp = Self.timestamp(from: entry)

        if !entry.metadata.isEmpty {
            breadcrumb.data = entry.metadata
        }

        SentrySDK.addBreadcrumb(breadcrumb)
    }

    private func captureEvent(for entry: RALogEntry) {
        let event = Event(level: convertToSentryLevel(entry.level))
        event.message = SentryMessage(formatted: entry.message)
        event.timestamp = Self.timestamp(from: entry)
        event.tags = [
            "category": entry.category,
            "log_level": "\(entry.level)"
        ]

        // Device metadata is folded into `entry.metadata` SDK-side (RALogEntry
        // has no native device field): keys device_model / os_version / platform.
        if !entry.metadata.isEmpty {
            event.extra = entry.metadata
        }

        SentrySDK.capture(event: event)
    }

    /// Convert the proto's `timestampUnixMs: Int64` back to a `Date`.
    private static func timestamp(from entry: RALogEntry) -> Date {
        Date(timeIntervalSince1970: Double(entry.timestampUnixMs) / 1000)
    }

    private func convertToSentryLevel(_ level: RALogLevel) -> SentryLevel {
        switch level {
        case .trace: return .debug
        case .debug: return .debug
        case .info: return .info
        case .warning: return .warning
        case .error: return .error
        case .fatal: return .fatal
        case .UNRECOGNIZED: return .info
        }
    }
}
