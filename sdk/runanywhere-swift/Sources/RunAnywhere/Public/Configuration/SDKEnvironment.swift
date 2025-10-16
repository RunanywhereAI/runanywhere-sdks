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

/// **Layer 2: SDK Initialization Parameters** - Bootstrap configuration for SDK setup
///
/// These parameters are used to **initialize the SDK** when your app starts. They configure
/// the basic authentication and environment mode.
///
/// **This is NOT for runtime configuration.** For dynamic settings like temperature, routing policy,
/// or storage limits, use `ConfigurationData` and `RunAnywhere.updateConfiguration()` instead.
///
/// **When to Use:**
/// - Setting up API authentication (API key)
/// - Choosing environment mode (dev/staging/production)
/// - Providing backend URL
///
/// **Configuration Layers:**
/// - **Layer 1**: Build-time constants (`RunAnywhereConstants` from JSON/env)
/// - **Layer 2**: SDK initialization (this struct - `SDKInitParams`)
/// - **Layer 3**: Runtime configuration (`ConfigurationData`)
///
/// **Example:**
/// ```swift
/// // Production mode
/// try RunAnywhere.initialize(
///     apiKey: "your-api-key",
///     baseURL: "https://api.runanywhere.ai",
///     environment: .production
/// )
///
/// // Development mode (simpler)
/// try RunAnywhere.initialize(
///     apiKey: "dev",
///     environment: .development
/// )
///
/// // Using convenience method
/// let params = SDKInitParams.development()
/// try RunAnywhere.initialize(with: params)
/// ```
public struct SDKInitParams {
    /// API key for authentication
    public let apiKey: String

    /// Base URL for API requests (optional for development mode)
    public let baseURL: URL?

    /// Environment mode (development/staging/production)
    public let environment: SDKEnvironment

    /// Create initialization parameters
    /// - Parameters:
    ///   - apiKey: Your RunAnywhere API key (can be empty for development)
    ///   - baseURL: Base URL for API requests (optional for development)
    ///   - environment: Environment mode (default: production)
    public init(
        apiKey: String,
        baseURL: URL? = nil,
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

    /// Development mode initializer (no URL required)
    /// - Parameter apiKey: Optional API key for development
    /// - Returns: SDK initialization parameters configured for development mode
    public static func development(apiKey: String = "dev-mode") -> SDKInitParams {
        SDKInitParams(apiKey: apiKey, baseURL: nil, environment: .development)
    }

    /// Production mode initializer with URL from constants
    /// - Parameter apiKey: Your RunAnywhere API key
    /// - Returns: SDK initialization parameters configured for production mode
    /// - Throws: SDKError if URL from constants is invalid
    public static func production(apiKey: String) throws -> SDKInitParams {
        let urlString = RunAnywhereConstants.apiURLs.production
        guard let url = URL(string: urlString) else {
            throw SDKError.validationFailed("Invalid production URL from constants: \(urlString)")
        }
        return SDKInitParams(apiKey: apiKey, baseURL: url, environment: .production)
    }

    /// Staging mode initializer with URL from constants
    /// - Parameter apiKey: Your RunAnywhere API key
    /// - Returns: SDK initialization parameters configured for staging mode
    /// - Throws: SDKError if URL from constants is invalid
    public static func staging(apiKey: String) throws -> SDKInitParams {
        let urlString = RunAnywhereConstants.apiURLs.staging
        guard let url = URL(string: urlString) else {
            throw SDKError.validationFailed("Invalid staging URL from constants: \(urlString)")
        }
        return SDKInitParams(apiKey: apiKey, baseURL: url, environment: .staging)
    }
}
