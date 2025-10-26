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

    /// Should use mock data sources
    public var useMockData: Bool {
        self == .development
    }

    /// Should sync with backend
    public var shouldSyncWithBackend: Bool {
        self != .development
    }

    /// Requires API authentication
    public var requiresAuthentication: Bool {
        self != .development
    }
}

/// Supabase configuration for development device analytics
/// Internal - automatically configured based on environment
internal struct SupabaseConfig: Sendable {
    /// Supabase project URL
    let projectURL: URL

    /// Supabase anon/public API key (safe to expose in client apps)
    let anonKey: String

    /// Get Supabase configuration for the given environment
    /// - Parameter environment: The SDK environment
    /// - Returns: Supabase configuration if applicable for this environment
    static func configuration(for environment: SDKEnvironment) -> SupabaseConfig? {
        switch environment {
        case .development:
            // Development mode: Use RunAnywhere's public Supabase for dev analytics
            // Note: Anon key is safe to include in client code - data access is controlled by RLS policies
            return SupabaseConfig(
                projectURL: URL(string: "https://fhtgjtxuoikwwouxqzrn.supabase.co")!,
                anonKey: "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImZodGdqdHh1b2lrd3dvdXhxenJuIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjExOTkwNzIsImV4cCI6MjA3Njc3NTA3Mn0.aIssX-t8CIqt8zoctNhMS8fm3wtH-DzsQiy9FunqD9E"
            )
        case .staging, .production:
            // Production/Staging: No Supabase, use traditional backend
            return nil
        }
    }
}

/// SDK initialization parameters
public struct SDKInitParams {
    /// API key for authentication
    public let apiKey: String

    /// Base URL for API requests (required for cross-platform consistency)
    /// Note: In development mode, this is accepted but Supabase is used internally for dev analytics
    public let baseURL: URL

    /// Environment mode (development/staging/production)
    public let environment: SDKEnvironment

    /// Internal Supabase configuration (auto-configured based on environment)
    internal var supabaseConfig: SupabaseConfig? {
        return SupabaseConfig.configuration(for: environment)
    }

    /// Create initialization parameters
    /// - Parameters:
    ///   - apiKey: Your RunAnywhere API key (can be empty for development)
    ///   - baseURL: Base URL for API requests (required, even in development mode)
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
