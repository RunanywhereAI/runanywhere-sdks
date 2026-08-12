//
//  CppBridge+HTTP.swift
//  RunAnywhere SDK
//
//  HTTP bridge extension - thin wrapper over HTTPClientAdapter.
//  All actual network logic is in Adapters/HTTPClientAdapter.swift
//

import Foundation

// MARK: - HTTP Bridge

extension CppBridge {

    /// HTTP bridge that delegates to `HTTPClientAdapter`.
    public enum HTTP {

        /// Shared HTTP service instance
        public static var shared: HTTPClientAdapter {
            HTTPClientAdapter.shared
        }

        /// Configure HTTP with base URL and API key
        public static func configure(baseURL: URL, apiKey: String) async {
            await HTTPClientAdapter.shared.configure(baseURL: baseURL, apiKey: apiKey)
        }

        /// Configure HTTP with base URL string and API key
        public static func configure(baseURL: String, apiKey: String) async {
            await HTTPClientAdapter.shared.configure(baseURL: baseURL, apiKey: apiKey)
        }

        /// Check if HTTP is configured
        public static var isConfigured: Bool {
            get async {
                await HTTPClientAdapter.shared.isConfigured
            }
        }

        /// Check if HTTP has a non-placeholder endpoint and token.
        public static var hasUsableConfiguration: Bool {
            get async {
                await HTTPClientAdapter.shared.hasUsableConfiguration
            }
        }
    }
}
