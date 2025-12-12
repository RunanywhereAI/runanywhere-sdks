//
//  AnalyticsHelpers.swift
//  RunAnywhere SDK
//
//  Utility functions for analytics operations
//

import Foundation

// MARK: - String Utilities

extension String {
    /// Convert camelCase to snake_case for analytics backend compatibility
    /// Example: "timeToFirstToken" -> "time_to_first_token"
    func toSnakeCase() -> String {
        let pattern = "([a-z0-9])([A-Z])"
        let regex = try? NSRegularExpression(pattern: pattern, options: [])
        let range = NSRange(self.startIndex..., in: self)
        return regex?.stringByReplacingMatches(
            in: self,
            options: [],
            range: range,
            withTemplate: "$1_$2"
        ).lowercased() ?? self.lowercased()
    }
}

// MARK: - Value Extraction Helpers

/// Helper functions for extracting values from analytics event data
public enum AnalyticsValueExtractor {

    /// Extract value from Any, properly unwrapping Optionals
    /// Returns nil for nil optionals, string representation for values
    public static func extractValue(from value: Any) -> String? { // swiftlint:disable:this avoid_any_type
        // Use Mirror to check if it's an Optional
        let mirror = Mirror(reflecting: value)
        if mirror.displayStyle == .optional {
            // It's an Optional - check if it has a value
            if let child = mirror.children.first {
                // Recursively extract the wrapped value
                return extractValue(from: child.value)
            } else {
                // Optional is nil
                return nil
            }
        }

        // Not an Optional, convert directly
        return convertToString(value)
    }

    /// Convert a value to its string representation
    private static func convertToString(_ value: Any) -> String? { // swiftlint:disable:this avoid_any_type
        if let stringValue = value as? String {
            return stringValue
        } else if let intValue = value as? Int {
            return String(intValue)
        } else if let doubleValue = value as? Double {
            return String(format: "%.3f", doubleValue)
        } else if let floatValue = value as? Float {
            return String(format: "%.3f", floatValue)
        } else if let boolValue = value as? Bool {
            return String(boolValue)
        } else if let int64Value = value as? Int64 {
            return String(int64Value)
        } else {
            // Fallback - avoid "Optional(...)" strings
            let description = String(describing: value)
            if description == "nil" || description.hasPrefix("Optional(") {
                return nil
            }
            return description
        }
    }

    /// Extract all properties from an object using Mirror reflection
    /// - Parameter object: The object to extract properties from
    /// - Returns: Dictionary of property names to string values
    public static func extractProperties(from object: Any) -> [String: String] { // swiftlint:disable:this avoid_any_type
        var properties: [String: String] = [:]

        let mirror = Mirror(reflecting: object)
        for child in mirror.children {
            if let label = child.label {
                if let value = extractValue(from: child.value) {
                    // Convert camelCase to snake_case for backend
                    let snakeKey = label.toSnakeCase()
                    properties[snakeKey] = value
                }
            }
        }

        return properties
    }
}

// MARK: - Date Utilities

extension Date {
    /// Format date for analytics timestamp
    var analyticsTimestamp: String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: self)
    }

    /// Parse analytics timestamp string
    static func fromAnalyticsTimestamp(_ string: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: string)
    }
}

// MARK: - Analytics ID Generation

/// Generates unique identifiers for analytics events and sessions
public enum AnalyticsIDGenerator {

    /// Generate a unique event ID
    public static func generateEventId() -> String {
        return UUID().uuidString
    }

    /// Generate a unique session ID
    public static func generateSessionId() -> String {
        return UUID().uuidString
    }

    /// Generate a unique generation ID
    public static func generateGenerationId() -> String {
        return "gen_\(UUID().uuidString)"
    }

    /// Generate a unique transcription ID
    public static func generateTranscriptionId() -> String {
        return "trans_\(UUID().uuidString)"
    }

    /// Generate a unique synthesis ID
    public static func generateSynthesisId() -> String {
        return "synth_\(UUID().uuidString)"
    }
}
