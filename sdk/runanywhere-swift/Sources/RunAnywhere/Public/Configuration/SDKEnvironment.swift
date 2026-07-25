//
//  SDKEnvironment.swift
//  RunAnywhere SDK
//
//  SDK Environment mode — determines how data is handled.
//
//  `SDKEnvironment` is a typealias for the proto3-generated
//  `RASDKEnvironment` (idl/model_types.proto). The hand-written enum was
//  removed; all C-bridge helpers, validation, and UX behaviour are
//  preserved as extensions.
//

import CRACommons
import Foundation

// MARK: - Typealias

/// SDK Environment mode — determines how data is handled.
public typealias SDKEnvironment = RASDKEnvironment

// MARK: - Codable (wire format = lowercase)
//
// `wireString` and `from(wireString:)` are codegen-generated in
// Generated/RAConvenience.swift from the `rac_wire_string` annotations in
// idl/model_types.proto. The Codable conformance below delegates to those
// generated accessors so encoding and decoding share one canonical mapping.

extension RASDKEnvironment: Codable {
    public init(from decoder: Swift.Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = RASDKEnvironment.from(wireString: raw) ?? .unspecified
    }

    public func encode(to encoder: Swift.Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(self.wireString)
    }
}

// MARK: - Extensions (preserved from the hand-written enum)

public extension RASDKEnvironment {
    /// Deployable product environments (development + production).
    static var deployableCases: [RASDKEnvironment] {
        [.development, .production]
    }

    // MARK: - C++ Bridge

    /// Convert to C++ environment type for cross-platform consistency.
    var cEnvironment: rac_environment_t {
        switch self {
        case .development: return RAC_ENV_DEVELOPMENT
        case .production:  return RAC_ENV_PRODUCTION
        default:           return RAC_ENV_DEVELOPMENT
        }
    }

    /// Human-readable description.
    var description: String {
        switch self {
        case .development: return "Development Environment"
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
        case .development:
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
    var defaultLogLevel: RALogLevel {
        switch self {
        case .development: return .debug
        case .production:  return .warning
        default:           return .info
        }
    }

    /// Should send telemetry data (production only) — uses C++.
    var shouldSendTelemetry: Bool { rac_env_should_send_telemetry(cEnvironment) }

    /// Should sync with backend (non-development) — uses C++.
    var shouldSyncWithBackend: Bool { rac_env_should_sync_with_backend(cEnvironment) }

    /// Requires API authentication (non-development) — uses C++.
    var requiresAuthentication: Bool { rac_env_requires_auth(cEnvironment) }
}

/// SDK initialization parameters.
public struct SDKInitParams: Sendable {
    /// API key for authentication.
    public let apiKey: String

    /// Base URL for API requests. Required for production; optional
    /// for development (uses placeholder if not provided).
    public let baseURL: URL

    /// Environment mode (development/production).
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

    /// Create initialization parameters for production.
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

    /// Convenience initializer with string URL for production.
    public init(
        apiKey: String,
        baseURL: String,
        environment: SDKEnvironment = .production
    ) throws {
        guard let url = URL(string: baseURL) else {
            throw SDKException(code: .validationFailed, message: "Invalid base URL format: \(baseURL)", category: .internal)
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
                throw SDKException(code: .invalidApiKey, message: "\(message) for \(environment.description)", category: .internal)
            case RAC_VALIDATION_API_KEY_TOO_SHORT:
                throw SDKException(code: .invalidApiKey, message: message, category: .internal)
            default:
                throw SDKException(code: .validationFailed, message: message, category: .internal)
            }
        }

        let urlResult = baseURL.absoluteString.withCString { ptr in
            rac_validate_base_url(ptr, cEnv)
        }
        if urlResult != RAC_VALIDATION_OK {
            let message = String(cString: rac_validation_error_message(urlResult))
            throw SDKException(code: .validationFailed, message: message, category: .internal)
        }

        logger.info("URL validated for \(environment.description): \(baseURL.absoluteString)")
    }
}
