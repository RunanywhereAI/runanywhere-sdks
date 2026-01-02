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
            case .development: return RAC_ENV_DEVELOPMENT
            case .staging: return RAC_ENV_STAGING
            case .production: return RAC_ENV_PRODUCTION
            }
        }

        /// Convert C++ environment to Swift type
        public static func fromC(_ env: rac_environment_t) -> SDKEnvironment {
            switch env {
            case RAC_ENV_DEVELOPMENT: return .development
            case RAC_ENV_STAGING: return .staging
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
    /// Wraps C++ rac_dev_config.h functions
    /// Used for development mode with Supabase backend
    public enum DevConfig {

        /// Check if development config is available
        public static var isAvailable: Bool {
            rac_dev_config_is_available()
        }

        /// Get Supabase URL for development mode
        public static var supabaseURL: String? {
            guard isAvailable else { return nil }
            guard let ptr = rac_dev_config_get_supabase_url() else { return nil }
            return String(cString: ptr)
        }

        /// Get Supabase API key for development mode
        public static var supabaseKey: String? {
            guard isAvailable else { return nil }
            guard let ptr = rac_dev_config_get_supabase_key() else { return nil }
            return String(cString: ptr)
        }

        /// Get build token for development mode
        public static var buildToken: String? {
            guard rac_dev_config_has_build_token() else { return nil }
            guard let ptr = rac_dev_config_get_build_token() else { return nil }
            return String(cString: ptr)
        }

        /// Get Sentry DSN for crash reporting (optional)
        public static var sentryDSN: String? {
            guard let ptr = rac_dev_config_get_sentry_dsn() else { return nil }
            return String(cString: ptr)
        }

        /// Configure CppBridge.HTTP for development mode using C++ config
        /// - Returns: true if configured successfully, false if config not available
        @discardableResult
        public static func configureHTTP() async -> Bool {
            guard let urlString = supabaseURL,
                  let url = URL(string: urlString),
                  let apiKey = supabaseKey else {
                return false
            }
            await CppBridge.HTTP.shared.configure(baseURL: url, apiKey: apiKey)
            return true
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

        /// Get telemetry endpoint for environment
        public static func telemetry(for env: SDKEnvironment) -> String {
            return String(cString: rac_endpoint_telemetry(Environment.toC(env)))
        }

        /// Get model assignments endpoint
        public static func modelAssignments(deviceType: String, platform: String) -> String {
            var buffer = [CChar](repeating: 0, count: 512)
            deviceType.withCString { dt in
                platform.withCString { plat in
                    _ = rac_endpoint_model_assignments(dt, plat, &buffer, buffer.count)
                }
            }
            return String(cString: buffer)
        }

        /// Get model download endpoint
        public static func modelDownload(modelId: String) -> String {
            var buffer = [CChar](repeating: 0, count: 512)
            modelId.withCString { mid in
                _ = rac_endpoint_model_download(mid, &buffer, buffer.count)
            }
            return String(cString: buffer)
        }
    }
}
