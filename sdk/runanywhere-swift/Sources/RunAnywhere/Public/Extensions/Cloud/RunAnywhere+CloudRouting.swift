//
//  RunAnywhere+CloudRouting.swift
//  RunAnywhere SDK
//
//  Public API for cloud routing and hybrid inference.
//

import Foundation

// MARK: - Cloud Provider Registration

public extension RunAnywhere {

    /// Register a cloud provider for hybrid routing
    ///
    /// ```swift
    /// let provider = OpenAICompatibleProvider(
    ///     apiKey: "sk-...",
    ///     model: "gpt-4o-mini"
    /// )
    /// RunAnywhere.registerCloudProvider(provider)
    /// ```
    static func registerCloudProvider(_ provider: any CloudProvider) async {
        await CloudProviderManager.shared.register(provider)
    }

    /// Unregister a cloud provider
    static func unregisterCloudProvider(providerId: String) async {
        await CloudProviderManager.shared.unregister(providerId: providerId)
    }

    /// Set the default cloud provider
    static func setDefaultCloudProvider(providerId: String) async throws {
        try await CloudProviderManager.shared.setDefault(providerId: providerId)
    }

    /// Set the default routing policy for all generation requests
    static func setDefaultRoutingPolicy(_ policy: RoutingPolicy) async {
        await RoutingEngine.shared.setDefaultPolicy(policy)
    }
}

// MARK: - Provider Failover Chain

public extension RunAnywhere {

    /// Configure a provider failover chain for automatic provider failover.
    ///
    /// When set, cloud requests will try providers in priority order,
    /// with circuit breaker protection for unhealthy providers.
    ///
    /// ```swift
    /// let chain = ProviderFailoverChain(circuitBreakerThreshold: 3)
    /// await chain.addProvider(openaiProvider, priority: 100)
    /// await chain.addProvider(groqProvider, priority: 50)
    /// await RunAnywhere.setProviderFailoverChain(chain)
    /// ```
    static func setProviderFailoverChain(_ chain: ProviderFailoverChain?) async {
        await RoutingEngine.shared.setFailoverChain(chain)
    }

    /// Get the current failover chain health status
    static func failoverChainHealthStatus() async -> [ProviderHealthStatus]? {
        guard let chain = await RoutingEngine.shared.getFailoverChain() else { return nil }
        return await chain.healthStatus
    }
}

// MARK: - Cost Tracking

public extension RunAnywhere {

    /// Access the cloud cost tracker for monitoring API spend.
    ///
    /// ```swift
    /// let costs = await RunAnywhere.cloudCostTracker.summary
    /// print("Total cloud cost: $\(costs.totalCostUSD)")
    /// ```
    static var cloudCostTracker: CloudCostTracker {
        CloudCostTracker.shared
    }

    /// Get a snapshot of current cloud costs
    static func cloudCostSummary() async -> CloudCostSummary {
        await CloudCostTracker.shared.summary
    }

    /// Reset cloud cost tracking
    static func resetCloudCosts() async {
        await CloudCostTracker.shared.reset()
    }
}

// MARK: - Routing-Aware Generation

public extension RunAnywhere {

    /// Generate text with routing policy
    ///
    /// Routes between on-device and cloud based on the policy.
    ///
    /// ```swift
    /// // Hybrid auto: on-device first, auto-fallback to cloud
    /// let result = try await RunAnywhere.generateWithRouting(
    ///     "Explain quantum computing",
    ///     routingPolicy: .hybridAuto(confidenceThreshold: 0.7),
    ///     cloudModel: "gpt-4o-mini"
    /// )
    /// print(result.generationResult.text)
    /// print(result.routingDecision.executionTarget) // .onDevice or .cloud
    /// ```
    static func generateWithRouting(
        _ prompt: String,
        options: LLMGenerationOptions? = nil,
        routingPolicy: RoutingPolicy? = nil,
        cloudProviderId: String? = nil,
        cloudModel: String? = nil
    ) async throws -> RoutedGenerationResult {
        try await RoutingEngine.shared.generate(
            prompt: prompt,
            options: options,
            routingPolicy: routingPolicy,
            cloudProviderId: cloudProviderId,
            cloudModel: cloudModel
        )
    }

    /// Stream text with routing policy
    ///
    /// ```swift
    /// let result = try await RunAnywhere.generateStreamWithRouting(
    ///     "Write a poem",
    ///     routingPolicy: .hybridAuto()
    /// )
    /// for try await token in result.streamingResult.stream {
    ///     print(token, terminator: "")
    /// }
    /// ```
    static func generateStreamWithRouting(
        _ prompt: String,
        options: LLMGenerationOptions? = nil,
        routingPolicy: RoutingPolicy? = nil,
        cloudProviderId: String? = nil,
        cloudModel: String? = nil
    ) async throws -> RoutedStreamingResult {
        try await RoutingEngine.shared.generateStream(
            prompt: prompt,
            options: options,
            routingPolicy: routingPolicy,
            cloudProviderId: cloudProviderId,
            cloudModel: cloudModel
        )
    }
}
