import Foundation

/// SDK Environment mode - determines how data is handled
public enum SDKEnvironment: String, CaseIterable, Sendable {
    /// Development/testing mode - may use local data, verbose logging
    case development

    /// Staging mode - testing with real services
    case staging

    /// Production mode - live environment
    case production

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

    /// Check if this environment requires a valid backend URL
    public var requiresBackendURL: Bool {
        self != .development
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

    /// Should send telemetry data (production only)
    public var shouldSendTelemetry: Bool {
        self == .production
    }

    /// Should use mock data sources (development only)
    public var useMockData: Bool {
        self == .development
    }

    /// Should sync with backend (non-development)
    public var shouldSyncWithBackend: Bool {
        self != .development
    }

    /// Requires API authentication (non-development)
    public var requiresAuthentication: Bool {
        self != .development
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
    /// - Throws: RunAnywhereError if validation fails
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
    /// - Throws: RunAnywhereError if URL is invalid or validation fails
    public init(
        apiKey: String,
        baseURL: String,
        environment: SDKEnvironment = .production
    ) throws {
        guard let url = URL(string: baseURL) else {
            throw RunAnywhereError.validationFailed("Invalid base URL format: \(baseURL)")
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

    // MARK: - Validation

    /// Validate initialization parameters based on environment
    /// - Parameters:
    ///   - apiKey: The API key to validate
    ///   - baseURL: The base URL to validate
    ///   - environment: The target environment
    /// - Throws: RunAnywhereError if validation fails
    private static func validate(
        apiKey: String,
        baseURL: URL,
        environment: SDKEnvironment
    ) throws {
        let logger = SDKLogger(category: "SDKInitParams")

        // 1. Check build configuration compatibility for production
        // NOTE: Temporarily disabled for testing production mode in DEBUG builds
        // if environment == .production {
        //     #if DEBUG
        //     throw RunAnywhereError.environmentMismatch(
        //         "Production environment cannot be used in DEBUG builds. " +
        //         "Use .development or .staging for testing, or build in Release mode for production."
        //     )
        //     #endif
        // }

        // 2. Validate API key for staging and production
        if environment.requiresAuthentication {
            guard !apiKey.isEmpty else {
                throw RunAnywhereError.invalidAPIKey("API key is required for \(environment.description)")
            }

            // Basic API key format validation (at least 10 characters)
            guard apiKey.count >= 10 else {
                throw RunAnywhereError.invalidAPIKey("API key appears to be invalid (too short)")
            }
        }

        // 3. Validate URL for staging and production
        if environment.requiresBackendURL {
            // Check for valid scheme (must be HTTPS for production, HTTPS or HTTP for staging)
            guard let scheme = baseURL.scheme?.lowercased() else {
                throw RunAnywhereError.validationFailed("Base URL must have a valid scheme (https)")
            }

            if environment == .production {
                guard scheme == "https" else {
                    throw RunAnywhereError.validationFailed(
                        "Production environment requires HTTPS. Got: \(scheme)"
                    )
                }
            } else if environment == .staging {
                guard scheme == "https" || scheme == "http" else {
                    throw RunAnywhereError.validationFailed(
                        "Staging environment requires HTTP or HTTPS. Got: \(scheme)"
                    )
                }

                // Warn if using HTTP in staging
                if scheme == "http" {
                    logger.warning("⚠️ Using HTTP for staging environment. Consider using HTTPS for security.")
                }
            }

            // Check for valid host
            guard let host = baseURL.host, !host.isEmpty else {
                throw RunAnywhereError.validationFailed("Base URL must have a valid host")
            }

            // Warn about localhost/example URLs
            let lowercaseHost = host.lowercased()
            if lowercaseHost.contains("localhost") ||
               lowercaseHost.contains("127.0.0.1") ||
               lowercaseHost.contains("example.com") ||
               lowercaseHost.contains(".local") {
                if environment == .production {
                    throw RunAnywhereError.validationFailed(
                        "Production environment cannot use localhost or example URLs: \(host)"
                    )
                } else {
                    logger.warning("⚠️ Staging environment using local/example URL: \(host)")
                }
            }

            logger.info("✅ URL validated for \(environment.description): \(baseURL.absoluteString)")
        }
    }
}
