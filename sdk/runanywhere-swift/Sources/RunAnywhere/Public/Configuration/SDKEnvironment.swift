import Foundation

/// SDK Environment mode - determines how data is handled
public enum SDKEnvironment: String, CaseIterable, Sendable {
    /// Development/testing mode - may use local data, verbose logging
    case development = "development"

    /// Staging mode - testing with real services
    case staging = "staging"

    /// Production mode - live environment
    case production = "production"

    /// Human-readable description
    public var description: String {
        switch self {
        case .development:
            return "Development Environment"
        case .staging:
            return "Staging Environment"
        case .production:
            return "Production Environment"
        }
    }

    /// Check if this is a production environment
    public var isProduction: Bool {
        self == .production
    }

    /// Check if this is a testing environment
    public var isTesting: Bool {
        self == .development || self == .staging
    }

    /// Determine logging verbosity based on environment
    public var defaultLogLevel: LogLevel {
        switch self {
        case .development:
            return .debug
        case .staging:
            return .info
        case .production:
            return .warning
        }
    }

    /// Should send telemetry data
    public var shouldSendTelemetry: Bool {
        // Only send telemetry in production
        self == .production
    }
}

/// SDK initialization parameters
public struct SDKInitParams {
    /// API key for authentication
    public let apiKey: String

    /// Base URL for API requests
    public let baseURL: URL

    /// Environment mode (development/staging/production)
    public let environment: SDKEnvironment

    /// Create initialization parameters
    /// - Parameters:
    ///   - apiKey: Your RunAnywhere API key
    ///   - baseURL: Base URL for API requests
    ///   - environment: Environment mode (default: production)
    public init(
        apiKey: String,
        baseURL: URL,
        environment: SDKEnvironment = .production
    ) {
        self.apiKey = apiKey
        self.baseURL = baseURL
        self.environment = environment
    }

    /// Convenience initializer with string URL
    /// - Parameters:
    ///   - apiKey: Your RunAnywhere API key
    ///   - baseURL: Base URL string for API requests
    ///   - environment: Environment mode (default: production)
    /// - Throws: SDKError if URL is invalid
    public init(
        apiKey: String,
        baseURL: String,
        environment: SDKEnvironment = .production
    ) throws {
        guard let url = URL(string: baseURL) else {
            throw SDKError.validationFailed("Invalid base URL: \(baseURL)")
        }
        self.init(apiKey: apiKey, baseURL: url, environment: environment)
    }
}
