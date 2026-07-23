//
//  CppBridge+Environment.swift
//  RunAnywhere SDK
//
//  Environment and configuration bridge extensions for C++ interop.
//

import CRACommons
import Foundation

// MARK: - Environment Bridge

extension CppBridge {

    /// Environment configuration bridge
    /// Wraps C++ rac_environment.h functions
    public enum Environment {

        /// Convert Swift environment to C++ type
        public static func toC(_ env: SDKEnvironment) -> rac_environment_t {
            switch env {
            case .development:   return RAC_ENV_DEVELOPMENT
            case .production:    return RAC_ENV_PRODUCTION
            default:             return RAC_ENV_DEVELOPMENT
            }
        }

        /// Convert C++ environment to Swift type
        public static func fromC(_ env: rac_environment_t) -> SDKEnvironment {
            switch env {
            case RAC_ENV_DEVELOPMENT: return .development
            case RAC_ENV_PRODUCTION: return .production
            default: return .development
            }
        }

        /// Check if environment requires authentication
        public static func requiresAuth(_ env: SDKEnvironment) -> Bool {
            return rac_env_requires_auth(toC(env))
        }

        /// Check if environment requires backend URL
        public static func requiresBackendURL(_ env: SDKEnvironment) -> Bool {
            return rac_env_requires_backend_url(toC(env))
        }

        /// Validate API key for environment
        public static func validateAPIKey(_ key: String, for env: SDKEnvironment) -> rac_validation_result_t {
            return key.withCString { rac_validate_api_key($0, toC(env)) }
        }

        /// Validate base URL for environment
        public static func validateBaseURL(_ url: String, for env: SDKEnvironment) -> rac_validation_result_t {
            return url.withCString { rac_validate_base_url($0, toC(env)) }
        }

        /// Get validation error message
        public static func validationErrorMessage(_ result: rac_validation_result_t) -> String {
            return String(cString: rac_validation_error_message(result))
        }
    }
}

// MARK: - Development Config Bridge

extension CppBridge {

    /// Development configuration bridge
    /// Wraps the canonical commons usability checks from rac_dev_config.h so
    /// every SDK agrees on the placeholder/URL rules. The backend is reached
    /// only through the effective base URL — no credentials are baked in.
    public enum DevConfig {

        /// Whether a baked-in credential is usable: non-empty and not a
        /// scaffolding placeholder. Delegates to the canonical commons rule
        /// (`rac_dev_config_is_usable_credential`) so every SDK agrees instead
        /// of each re-implementing the placeholder regex.
        static func isUsableCredential(_ value: String?) -> Bool {
            guard let value else { return false }
            return value.withCString { rac_dev_config_is_usable_credential($0) }
        }

        /// Whether a string is a usable absolute http(s) URL. Delegates to the
        /// canonical commons rule (`rac_dev_config_is_usable_http_url`).
        static func isUsableHTTPURL(_ value: String?) -> Bool {
            guard let value else { return false }
            return value.withCString { rac_dev_config_is_usable_http_url($0) }
        }
    }
}

// MARK: - Endpoints Bridge

extension CppBridge {

    /// API endpoint paths bridge
    /// Wraps C++ rac_endpoints.h macros and functions
    public enum Endpoints {

        // Static endpoint strings (from C macros)
        public static let authenticate = RAC_ENDPOINT_AUTHENTICATE
        public static let refresh = RAC_ENDPOINT_REFRESH
        public static let health = RAC_ENDPOINT_HEALTH

        /// Get device registration endpoint for environment
        public static func deviceRegistration(for env: SDKEnvironment) -> String {
            return String(cString: rac_endpoint_device_registration(Environment.toC(env)))
        }

        /// Get model assignments endpoint
        public static func modelAssignments() -> String {
            return String(cString: rac_endpoint_model_assignments())
        }
    }
}
