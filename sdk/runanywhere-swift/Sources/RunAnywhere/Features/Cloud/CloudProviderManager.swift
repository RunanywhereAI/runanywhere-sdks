//
//  CloudProviderManager.swift
//  RunAnywhere SDK
//
//  Manages cloud provider registration and selection.
//

import Foundation

// MARK: - Cloud Provider Manager

/// Central manager for cloud AI providers.
///
/// Handles provider registration, selection, and lifecycle.
/// Thread-safe via actor isolation.
public actor CloudProviderManager {

    /// Shared singleton instance
    public static let shared = CloudProviderManager()

    // MARK: - State

    private var providers: [String: any CloudProvider] = [:]
    private var defaultProviderId: String?

    // MARK: - Registration

    /// Register a cloud provider
    public func register(_ provider: any CloudProvider) {
        providers[provider.providerId] = provider

        // First registered provider becomes the default
        if defaultProviderId == nil {
            defaultProviderId = provider.providerId
        }
    }

    /// Unregister a cloud provider
    public func unregister(providerId: String) {
        providers.removeValue(forKey: providerId)

        if defaultProviderId == providerId {
            defaultProviderId = providers.keys.first
        }
    }

    /// Set the default provider
    public func setDefault(providerId: String) throws {
        guard providers[providerId] != nil else {
            throw CloudProviderError.providerNotFound(id: providerId)
        }
        defaultProviderId = providerId
    }

    // MARK: - Provider Access

    /// Get the default cloud provider
    public func getDefault() throws -> any CloudProvider {
        guard let id = defaultProviderId, let provider = providers[id] else {
            throw CloudProviderError.noProviderRegistered
        }
        return provider
    }

    /// Get a specific cloud provider by ID
    public func get(providerId: String) throws -> any CloudProvider {
        guard let provider = providers[providerId] else {
            throw CloudProviderError.providerNotFound(id: providerId)
        }
        return provider
    }

    /// Get all registered provider IDs
    public var registeredProviderIds: [String] {
        Array(providers.keys)
    }

    /// Check if any providers are registered
    public var hasProviders: Bool {
        !providers.isEmpty
    }

    /// Remove all registered providers
    public func removeAll() {
        providers.removeAll()
        defaultProviderId = nil
    }
}
