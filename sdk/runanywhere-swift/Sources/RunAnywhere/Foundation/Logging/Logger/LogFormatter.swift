//
//  LogFormatter.swift
//  RunAnywhere SDK
//
//  Formats log messages for output
//

import Foundation

/// Formats log messages for different output targets
internal struct LogFormatter {

    /// Format a log entry for console output
    static func formatForConsole(_ entry: LogEntry) -> String {
        let levelString = entry.level.description.uppercased()
        let timestamp = DateFormatter.iso8601.string(from: entry.timestamp)
        return "[\(timestamp)] [RunAnywhereSDK] [\(entry.category)] \(levelString): \(entry.message)"
    }

    /// Format a log entry for os_log output
    static func formatForOSLog(_ entry: LogEntry) -> String {
        return "[\(entry.category)] \(entry.message)"
    }

    /// Format metadata for inclusion in log message
    static func formatMetadata(_ metadata: [String: Any]?) -> String? {
        guard let metadata = metadata, !metadata.isEmpty else { return nil }

        let formatted = metadata
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: ", ")

        return " [\(formatted)]"
    }
}

// MARK: - Date Formatter Extension

private extension DateFormatter {
    static let iso8601: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSZ"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter
    }()
}
