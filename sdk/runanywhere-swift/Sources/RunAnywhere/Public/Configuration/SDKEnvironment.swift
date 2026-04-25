//
//  SDKEnvironment.swift
//  RunAnywhere SDK
//
//  SDK Environment mode — determines how data is handled.
//
//  GAP 01 Phase 2: `SDKEnvironment` is a typealias for the proto3-generated
//  `RASDKEnvironment` (idl/model_types.proto). The hand-written enum was
//  removed; all C-bridge helpers, validation, and UX behaviour are
//  preserved as extensions.
//

import CRACommons
import Foundation
import SwiftProtobuf

// MARK: - Typealias

/// SDK Environment mode — determines how data is handled.
public typealias SDKEnvironment = RASDKEnvironment

// MARK: - Codable (wire format = lowercase)

extension RASDKEnvironment: Codable {
    public init(from decoder: Swift.Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        switch raw.lowercased() {
        case "development": self = .development
        case "staging":     self = .staging
        case "production":  self = .production
        default:            self = .unspecified
        }
    }

    public func encode(to encoder: Swift.Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(self.wireString)
    }
}

// MARK: - Extensions (preserved from the hand-written enum)

public extension RASDKEnvironment {
    /// Lowercase wire string ("development" / "staging" / "production").
    var wireString: String {
        switch self {
        case .development: return "development"
        case .staging:     return "staging"
        case .production:  return "production"
        default:           return "unspecified"
        }
    }

    /// Parse a wire-format string back into a case.
    static func fromWireString(_ s: String) -> RASDKEnvironment? {
        switch s.lowercased() {
        case "development": return .development
        case "staging":     return .staging
        case "production":  return .production
        default:            return nil
        }
    }

    /// All three deployable environments, excluding `.unspecified` /
    /// `UNRECOGNIZED`. Preserves the `CaseIterable.allCases` semantics of
    /// the pre-IDL hand-written enum.
    static var deployableCases: [RASDKEnvironment] {
        [.development, .staging, .production]
    }

    // MARK: - C++ Bridge

    /// Convert to C++ environment type for cross-platform consistency.
    var cEnvironment: rac_environment_t {
        switch self {
        case .development: return RAC_ENV_DEVELOPMENT
        case .staging:     return RAC_ENV_STAGING
        case .production:  return RAC_ENV_PRODUCTION
        default:           return RAC_ENV_DEVELOPMENT
        }
    }

    /// Human-readable description.
    var description: String {
        switch self {
        case .development: return "Development Environment"
        case .staging:     return "Staging Environment"
        case .production:  return "Production Environment"
        default:           return "Unspecified Environment"
        }
    }

    /// Check if this is a production environment (uses C++).
    var isProduction: Bool { rac_env_is_production(cEnvironment) }

    /// Check if this is a testing environment (uses C++).
    var isTesting: Bool { rac_env_is_testing(cEnvironment) }

    /// Check if this environment requires a valid backend URL (uses C++).
    var requiresBackendURL: Bool { rac_env_requires_backend_url(cEnvironment) }

    // MARK: - Build Configuration Validation

    /// Check if the current build configuration is compatible with this
    /// environment. Production is only allowed in Release builds.
    var isCompatibleWithCurrentBuild: Bool {
        switch self {
        case .development, .staging:
            return true
        case .production:
            #if DEBUG
            return false
            #else
            return true
            #endif
        default:
            return false
        }
    }

    /// Returns true if we're running in a DEBUG build.
    static var isDebugBuild: Bool {
        #if DEBUG
        return true
        #else
        return false
        #endif
    }

    // MARK: - Environment-Specific Settings

    /// Determine logging verbosity based on environment.
    var defaultLogLevel: LogLevel {
        switch self {
        case .development: return .debug
        case .staging:     return .info
        case .production:  return .warning
        default:           return .info
        }
    }

    /// Should send telemetry data (production only) — uses C++.
    var shouldSendTelemetry: Bool { rac_env_should_send_telemetry(cEnvironment) }

    /// Should use mock data sources (development only).
    var useMockData: Bool { self == .development }

    /// Should sync with backend (non-development) — uses C++.
    var shouldSyncWithBackend: Bool { rac_env_should_sync_with_backend(cEnvironment) }

    /// Requires API authentication (non-development) — uses C++.
    var requiresAuthentication: Bool { rac_env_requires_auth(cEnvironment) }
}

/// SDK initialization parameters.
public struct SDKInitParams {
    /// API key for authentication.
    public let apiKey: String

    /// Base URL for API requests. Required for staging/production; optional
    /// for development (uses placeholder if not provided).
    public let baseURL: URL

    /// Environment mode (development/staging/production).
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

    /// Create initialization parameters for staging or production.
    public init(
        apiKey: String,
        baseURL: URL,
        environment: SDKEnvironment = .production
    ) throws {
        self.apiKey = apiKey
        self.baseURL = baseURL
        self.environment = environment

        try Self.validate(apiKey: apiKey, baseURL: baseURL, environment: environment)
    }

    /// Convenience initializer with string URL for staging or production.
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

    /// Convenience initializer for development mode (no URL required).
    public init(forDevelopmentWithAPIKey apiKey: String = "") {
        self.apiKey = apiKey
        self.baseURL = Self.developmentPlaceholderURL
        self.environment = .development
    }

    // MARK: - Validation (Uses C++ for cross-platform consistency)

    private static func validate(
        apiKey: String,
        baseURL: URL,
        environment: SDKEnvironment
    ) throws {
        let logger = SDKLogger(category: "SDKInitParams")

        let cEnv = environment.cEnvironment

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

        let urlResult = baseURL.absoluteString.withCString { ptr in
            rac_validate_base_url(ptr, cEnv)
        }
        if urlResult != RAC_VALIDATION_OK {
            let message = String(cString: rac_validation_error_message(urlResult))
            throw SDKError.general(.validationFailed, message)
        }

        if environment == .staging, baseURL.scheme?.lowercased() == "http" {
            logger.warning("Using HTTP for staging environment. Consider using HTTPS for security.")
        }

        if environment == .staging, let host = baseURL.host?.lowercased() {
            if host.contains("localhost") || host.contains("127.0.0.1") ||
               host.contains("example.com") || host.contains(".local") {
                logger.warning("Staging environment using local/example URL: \(host)")
            }
        }

        logger.info("URL validated for \(environment.description): \(baseURL.absoluteString)")
    }
}
