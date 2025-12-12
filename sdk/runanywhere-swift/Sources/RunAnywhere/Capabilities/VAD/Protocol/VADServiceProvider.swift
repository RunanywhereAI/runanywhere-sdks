//
//  VADServiceProvider.swift
//  RunAnywhere SDK
//
//  Protocol for VAD service providers (plugins)
//

import Foundation

/// Protocol for VAD service providers (plugins)
/// Allows registration of different VAD implementations
public protocol VADServiceProvider {

    /// Provider priority (higher = preferred)
    var priority: Int { get }

    /// Provider name for logging
    var name: String { get }

    /// Check if this provider can handle the given configuration
    /// - Parameter configuration: The VAD configuration
    /// - Returns: Whether this provider supports the configuration
    func canHandle(configuration: VADConfiguration) -> Bool

    /// Create a VAD service instance
    /// - Parameter configuration: The configuration for the service
    /// - Returns: A configured VAD service
    func createVADService(configuration: VADConfiguration) async throws -> VADService
}

// MARK: - Default Implementation

extension VADServiceProvider {
    public var priority: Int { 0 }

    public func canHandle(configuration: VADConfiguration) -> Bool {
        // Default: can handle any configuration
        return true
    }
}
