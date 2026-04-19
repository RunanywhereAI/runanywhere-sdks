//
//  CppBridge+HTTP.swift
//  RunAnywhere SDK
//
//  HTTP bridge extension - thin wrapper over HTTPService.
//  All actual network logic is in Data/Network/Services/HTTPService.swift
//

import CRACommons
import Foundation

// MARK: - HTTP Bridge

extension CppBridge {

    /// HTTP bridge - thin wrapper over HTTPService
    /// This provides C++ bridge compatibility while delegating to HTTPService
    public enum HTTP {

        /// Shared HTTP service instance
        public static var shared: HTTPService {
            HTTPService.shared
        }

        /// Configure HTTP with base URL and API key
        public static func configure(baseURL: URL, apiKey: String) async {
            await HTTPService.shared.configure(baseURL: baseURL, apiKey: apiKey)
        }

        /// Configure HTTP with base URL string and API key
        public static func configure(baseURL: String, apiKey: String) async {
            await HTTPService.shared.configure(baseURL: baseURL, apiKey: apiKey)
        }

        /// Check if HTTP is configured
        public static var isConfigured: Bool {
            get async {
                await HTTPService.shared.isConfigured
            }
        }
    }
}
