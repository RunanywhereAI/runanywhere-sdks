//
//  DevelopmentNetworkConfig.swift
//  RunAnywhere SDK
//
//  Network configuration for development mode
//  Combines Supabase config + build token in one place
//

import Foundation

/// Development mode network configuration
/// Used when SDK is initialized with `.development` environment
///
/// This consolidates all 3 values needed for development mode:
/// 1. Supabase project URL (base URL for API calls)
/// 2. Supabase anon key (API key / authorization)
/// 3. Build token (validates SDK installation)
///
/// Security Model:
/// - DevelopmentConfig.swift is in .gitignore (not committed to main branch)
/// - Real values are ONLY in release tags (for SPM distribution)
/// - Token is used ONLY when SDK is in .development mode
/// - Backend validates token via POST /api/v1/devices/register/dev
public struct DevelopmentNetworkConfig: Sendable {

    // MARK: - Properties

    /// Base URL for development API calls (Supabase project URL)
    public let baseURL: URL

    /// API key for development (Supabase anon key)
    public let apiKey: String

    /// Build token for SDK validation
    public let buildToken: String

    // MARK: - Singleton

    /// Shared development configuration
    /// Returns nil if configuration is invalid (shouldn't happen in valid builds)
    public static let shared: DevelopmentNetworkConfig? = {
        guard let url = URL(string: DevelopmentConfig.supabaseURL) else {
            assertionFailure("Invalid Supabase URL in DevelopmentConfig")
            return nil
        }
        return DevelopmentNetworkConfig(
            baseURL: url,
            apiKey: DevelopmentConfig.supabaseAnonKey,
            buildToken: DevelopmentConfig.buildToken
        )
    }()

    // MARK: - Initialization

    private init(baseURL: URL, apiKey: String, buildToken: String) {
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.buildToken = buildToken
    }

    // MARK: - Factory Methods

    /// Create an APIClient configured for development mode
    /// Uses Supabase project URL and anon key from DevelopmentConfig
    public func createAPIClient() -> APIClient {
        return APIClient(baseURL: baseURL, apiKey: apiKey)
    }

    /// Check if development configuration is available
    public static var isAvailable: Bool {
        shared != nil
    }
}

// MARK: - Convenience Extensions

extension DevelopmentNetworkConfig {
    /// Get the build token directly (convenience for request bodies)
    public static var token: String {
        shared?.buildToken ?? "invalid_config"
    }
}
