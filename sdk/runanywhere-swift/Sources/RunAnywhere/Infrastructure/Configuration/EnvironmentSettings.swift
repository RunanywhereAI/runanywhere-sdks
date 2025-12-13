//
//  EnvironmentSettings.swift
//  RunAnywhere SDK
//
//  Internal helper for environment-specific settings.
//  Separates business logic from the public SDKEnvironment enum.
//

import Foundation

/// Internal helper that provides environment-specific settings and behavior
internal struct EnvironmentSettings {

    // MARK: - Logging Configuration

    /// Determine logging verbosity based on environment
    /// - Parameter environment: The SDK environment
    /// - Returns: Appropriate log level for the environment
    static func defaultLogLevel(for environment: SDKEnvironment) -> LogLevel {
        switch environment {
        case .development:
            return .debug
        case .staging:
            return .info
        case .production:
            return .warning
        }
    }

    // MARK: - Telemetry Configuration

    /// Determine whether telemetry should be sent
    /// - Parameter environment: The SDK environment
    /// - Returns: True if telemetry should be sent in this environment
    static func shouldSendTelemetry(for environment: SDKEnvironment) -> Bool {
        // Only send telemetry in production
        environment == .production
    }

    // MARK: - Data Source Configuration

    /// Determine whether mock data should be used
    /// - Parameter environment: The SDK environment
    /// - Returns: True if mock data sources should be used
    static func useMockData(for environment: SDKEnvironment) -> Bool {
        environment == .development
    }

    // MARK: - Backend Synchronization

    /// Determine whether backend synchronization should occur
    /// - Parameter environment: The SDK environment
    /// - Returns: True if backend sync should be enabled
    static func shouldSyncWithBackend(for environment: SDKEnvironment) -> Bool {
        environment != .development
    }

    // MARK: - Authentication Configuration

    /// Determine whether API authentication is required
    /// - Parameter environment: The SDK environment
    /// - Returns: True if authentication is required
    static func requiresAuthentication(for environment: SDKEnvironment) -> Bool {
        environment != .development
    }
}
