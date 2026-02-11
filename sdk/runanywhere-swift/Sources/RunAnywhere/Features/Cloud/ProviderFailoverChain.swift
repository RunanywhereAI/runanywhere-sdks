//
//  ProviderFailoverChain.swift
//  RunAnywhere SDK
//
//  Provider failover chain with priority ordering and circuit breaker.
//

import Foundation

// MARK: - Provider Failover Chain

/// Manages a priority-ordered chain of cloud providers with automatic failover.
///
/// If the primary provider fails, the chain tries the next provider.
/// Includes a simple circuit breaker to avoid repeatedly calling unhealthy providers.
///
/// ```swift
/// let chain = ProviderFailoverChain()
/// chain.addProvider(openaiProvider, priority: 100)
/// chain.addProvider(groqProvider, priority: 50)  // lower priority = fallback
/// ```
public actor ProviderFailoverChain {

    // MARK: - Types

    struct ProviderEntry {
        let provider: any CloudProvider
        let priority: Int
        var consecutiveFailures: Int = 0
        var lastFailureTime: Date?
        var isCircuitOpen: Bool = false
    }

    // MARK: - Configuration

    /// Number of consecutive failures before circuit opens
    private let circuitBreakerThreshold: Int

    /// How long to wait before trying an open circuit again (seconds)
    private let circuitBreakerCooldownSeconds: TimeInterval

    // MARK: - State

    private var entries: [ProviderEntry] = []

    // MARK: - Init

    public init(
        circuitBreakerThreshold: Int = 3,
        circuitBreakerCooldownSeconds: TimeInterval = 60
    ) {
        self.circuitBreakerThreshold = circuitBreakerThreshold
        self.circuitBreakerCooldownSeconds = circuitBreakerCooldownSeconds
    }

    // MARK: - Configuration

    /// Add a provider with a priority (higher = preferred)
    public func addProvider(_ provider: any CloudProvider, priority: Int) {
        entries.append(ProviderEntry(provider: provider, priority: priority))
        entries.sort { $0.priority > $1.priority }
    }

    /// Remove a provider by ID
    public func removeProvider(providerId: String) {
        entries.removeAll { $0.provider.providerId == providerId }
    }

    // MARK: - Execution

    /// Try generation across the provider chain with failover
    func generate(
        prompt: String,
        options: CloudGenerationOptions
    ) async throws -> CloudGenerationResult {
        var lastError: Error?

        for i in entries.indices {
            let entry = entries[i]

            // Skip providers with open circuits (unless cooldown elapsed)
            if entry.isCircuitOpen {
                if let lastFailure = entry.lastFailureTime,
                   Date().timeIntervalSince(lastFailure) < circuitBreakerCooldownSeconds {
                    continue
                }
                // Cooldown elapsed, try half-open
                entries[i].isCircuitOpen = false
            }

            do {
                let result = try await entry.provider.generate(prompt: prompt, options: options)

                // Success: reset failure count
                entries[i].consecutiveFailures = 0
                entries[i].isCircuitOpen = false

                return result
            } catch {
                lastError = error

                // Record failure
                entries[i].consecutiveFailures += 1
                entries[i].lastFailureTime = Date()

                // Open circuit if threshold reached
                if entries[i].consecutiveFailures >= circuitBreakerThreshold {
                    entries[i].isCircuitOpen = true
                }
            }
        }

        throw lastError ?? CloudProviderError.noProviderRegistered
    }

    /// Try streaming generation across the provider chain
    func generateStream(
        prompt: String,
        options: CloudGenerationOptions
    ) async throws -> AsyncThrowingStream<String, Error> {
        for i in entries.indices {
            let entry = entries[i]

            if entry.isCircuitOpen {
                if let lastFailure = entry.lastFailureTime,
                   Date().timeIntervalSince(lastFailure) < circuitBreakerCooldownSeconds {
                    continue
                }
                entries[i].isCircuitOpen = false
            }

            // For streaming, we return the first available provider's stream
            // Failover during streaming is more complex and deferred to future
            if await entry.provider.isAvailable() {
                entries[i].consecutiveFailures = 0
                return entry.provider.generateStream(prompt: prompt, options: options)
            }
        }

        throw CloudProviderError.noProviderRegistered
    }

    /// Get health status of all providers
    public var healthStatus: [ProviderHealthStatus] {
        entries.map { entry in
            ProviderHealthStatus(
                providerId: entry.provider.providerId,
                displayName: entry.provider.displayName,
                priority: entry.priority,
                consecutiveFailures: entry.consecutiveFailures,
                isCircuitOpen: entry.isCircuitOpen,
                lastFailureTime: entry.lastFailureTime
            )
        }
    }
}

// MARK: - Provider Health Status

/// Health status of a provider in the failover chain
public struct ProviderHealthStatus: Sendable {
    public let providerId: String
    public let displayName: String
    public let priority: Int
    public let consecutiveFailures: Int
    public let isCircuitOpen: Bool
    public let lastFailureTime: Date?
}
