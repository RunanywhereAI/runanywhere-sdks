//
//  LogLevel.swift
//  RunAnywhere SDK
//
//  Log severity levels for the SDK
//

import Foundation

/// Log severity levels
public enum LogLevel: Int, Comparable, CustomStringConvertible, Codable, Sendable {
    case debug = 0
    case info = 1
    case warning = 2
    case error = 3
    case fault = 4

    public static func < (lhs: LogLevel, rhs: LogLevel) -> Bool {
        return lhs.rawValue < rhs.rawValue
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
