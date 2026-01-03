import CRACommons
import Foundation

/// SDK Environment mode - determines how data is handled
public enum SDKEnvironment: String, CaseIterable, Sendable {
    /// Development/testing mode - may use local data, verbose logging
    case development

    /// Staging mode - testing with real services
    case staging

    /// Production mode - live environment
    case production

    // MARK: - C++ Bridge

    /// Convert to C++ environment type for cross-platform consistency
    var cEnvironment: rac_environment_t {
        switch self {
        case .development: return RAC_ENV_DEVELOPMENT
        case .staging: return RAC_ENV_STAGING
        case .production: return RAC_ENV_PRODUCTION
        }
    }

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

    /// Check if this is a production environment (uses C++)
    public var isProduction: Bool {
        rac_env_is_production(cEnvironment)
    }

    /// Check if this is a testing environment (uses C++)
    public var isTesting: Bool {
        rac_env_is_testing(cEnvironment)
    }

    /// Check if this environment requires a valid backend URL (uses C++)
    public var requiresBackendURL: Bool {
        rac_env_requires_backend_url(cEnvironment)
    }

    // MARK: - Build Configuration Validation

    /// Check if the current build configuration is compatible with this environment
    /// Production environment is only allowed in Release builds
    public var isCompatibleWithCurrentBuild: Bool {
        switch self {
        case .development, .staging:
            return true
        case .production:
            #if DEBUG
            return false
            #else
            return true
            #endif
        }
    }

    /// Returns true if we're running in a DEBUG build
    public static var isDebugBuild: Bool {
        #if DEBUG
        return true
        #else
        return false
        #endif
    }

    // MARK: - Environment-Specific Settings

    /// Determine logging verbosity based on environment
    public var defaultLogLevel: LogLevel {
        switch self {
        case .development: return .debug
        case .staging: return .info
        case .production: return .warning
        }
    }

    /// Should send telemetry data (production only) - uses C++
    public var shouldSendTelemetry: Bool {
        rac_env_should_send_telemetry(cEnvironment)
    }

    /// Should use mock data sources (development only)
    public var useMockData: Bool {
        self == .development // Keep simple - no C++ equivalent
    }

    /// Should sync with backend (non-development) - uses C++
    public var shouldSyncWithBackend: Bool {
        rac_env_should_sync_with_backend(cEnvironment)
    }

    /// Requires API authentication (non-development) - uses C++
    public var requiresAuthentication: Bool {
        rac_env_requires_auth(cEnvironment)
    }
}

/// SDK initialization parameters
public struct SDKInitParams {
    /// API key for authentication
    public let apiKey: String

    /// Base URL for API requests
    /// - Required for staging and production environments
    /// - Optional for development (uses placeholder if not provided)
    public let baseURL: URL

    /// Environment mode (development/staging/production)
    public let environment: SDKEnvironment

    // MARK: - Default Development URL

    /// Placeholder URL used for development when no URL is provided.
    /// Development mode uses local analytics, so this is just a placeholder.
    private static let developmentPlaceholderURL: URL = {
        guard let url = URL(string: "https://dev.runanywhere.local") else {
            fatalError("Invalid hardcoded development URL")
        }
        return url
    }()

    // MARK: - Initializers

    /// Create initialization parameters for staging or production
    /// - Parameters:
    ///   - apiKey: Your RunAnywhere API key (required)
    ///   - baseURL: Base URL for API requests (required, must be valid HTTPS URL)
    ///   - environment: Environment mode (default: production)
    /// - Throws: SDKError if validation fails
    public init(
        apiKey: String,
        baseURL: URL,
        environment: SDKEnvironment = .production
    ) throws {
        self.apiKey = apiKey
        self.baseURL = baseURL
        self.environment = environment

        // Validate based on environment
        try Self.validate(apiKey: apiKey, baseURL: baseURL, environment: environment)
    }

    /// Convenience initializer with string URL for staging or production
    /// - Parameters:
    ///   - apiKey: Your RunAnywhere API key
    ///   - baseURL: Base URL string for API requests
    ///   - environment: Environment mode (default: production)
    /// - Throws: SDKError if URL is invalid or validation fails
    public init(
        apiKey: String,
        baseURL: String,
        environment: SDKEnvironment = .production
    ) throws {
        guard let url = URL(string: baseURL) else {
            throw SDKError.general(.validationFailed, "Invalid base URL format: \(baseURL)")
        }
        try self.init(apiKey: apiKey, baseURL: url, environment: environment)
    }

    /// Convenience initializer for development mode (no URL required)
    /// - Parameter apiKey: Optional API key (not required for development)
    /// - Note: Development mode uses Supabase internally for dev analytics
    public init(forDevelopmentWithAPIKey apiKey: String = "") {
        self.apiKey = apiKey
        self.baseURL = Self.developmentPlaceholderURL
        self.environment = .development
    }

    // MARK: - Validation (Uses C++ for cross-platform consistency)

    /// Validate initialization parameters based on environment
    /// Uses C++ validation logic for cross-platform consistency.
    /// - Parameters:
    ///   - apiKey: The API key to validate
    ///   - baseURL: The base URL to validate
    ///   - environment: The target environment
    /// - Throws: SDKError if validation fails
    private static func validate(
        apiKey: String,
        baseURL: URL,
        environment: SDKEnvironment
    ) throws {
        let logger = SDKLogger(category: "SDKInitParams")

        // 1. Swift-only: Check DEBUG build for production (compile-time check)
        if environment == .production {
            #if DEBUG
            throw SDKError.general(.environmentMismatch,
                "Production environment cannot be used in DEBUG builds. " +
                "Use .development or .staging for testing, or build in Release mode.")
            #endif
        }

        // 2. Call C++ validation for API key and URL
        let cEnv = environment.cEnvironment

        // Validate API key via C++
        let apiKeyResult = apiKey.withCString { ptr in
            rac_validate_api_key(ptr, cEnv)
        }
        if apiKeyResult != RAC_VALIDATION_OK {
            let message = String(cString: rac_validation_error_message(apiKeyResult))
            switch apiKeyResult {
            case RAC_VALIDATION_API_KEY_REQUIRED:
                throw SDKError.general(.invalidAPIKey, "\(message) for \(environment.description)")
            case RAC_VALIDATION_API_KEY_TOO_SHORT:
                throw SDKError.general(.invalidAPIKey, message)
            default:
                throw SDKError.general(.validationFailed, message)
            }
        }

        // Validate URL via C++
        let urlResult = baseURL.absoluteString.withCString { ptr in
            rac_validate_base_url(ptr, cEnv)
        }
        if urlResult != RAC_VALIDATION_OK {
            let message = String(cString: rac_validation_error_message(urlResult))
            throw SDKError.general(.validationFailed, message)
        }

        // Log warnings for staging HTTP (C++ validates but doesn't warn)
        if environment == .staging, baseURL.scheme?.lowercased() == "http" {
            logger.warning("Using HTTP for staging environment. Consider using HTTPS for security.")
        }

        // Log warnings for staging localhost (C++ validates but doesn't warn)
        if environment == .staging, let host = baseURL.host?.lowercased() {
            if host.contains("localhost") || host.contains("127.0.0.1") ||
               host.contains("example.com") || host.contains(".local") {
                logger.warning("Staging environment using local/example URL: \(host)")
            }
        }

        logger.info("URL validated for \(environment.description): \(baseURL.absoluteString)")
    }
}
