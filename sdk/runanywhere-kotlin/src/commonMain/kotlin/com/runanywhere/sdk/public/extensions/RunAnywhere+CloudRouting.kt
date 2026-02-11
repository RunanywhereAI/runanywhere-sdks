/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * Public API for cloud routing and hybrid inference.
 * Mirrors Swift RunAnywhere+CloudRouting.swift exactly.
 */

package com.runanywhere.sdk.public.extensions

import com.runanywhere.sdk.features.cloud.CloudCostSummary
import com.runanywhere.sdk.features.cloud.CloudCostTracker
import com.runanywhere.sdk.features.cloud.CloudProviderManager
import com.runanywhere.sdk.features.cloud.ProviderFailoverChain
import com.runanywhere.sdk.features.cloud.ProviderHealthStatus
import com.runanywhere.sdk.features.cloud.RoutingEngine
import com.runanywhere.sdk.public.RunAnywhere
import com.runanywhere.sdk.public.extensions.Cloud.CloudProvider
import com.runanywhere.sdk.public.extensions.Cloud.RoutedGenerationResult
import com.runanywhere.sdk.public.extensions.Cloud.RoutedStreamingResult
import com.runanywhere.sdk.public.extensions.Cloud.RoutingPolicy
import com.runanywhere.sdk.public.extensions.LLM.LLMGenerationOptions

// MARK: - Cloud Provider Registration

/**
 * Register a cloud provider for hybrid routing.
 *
 * ```kotlin
 * val provider = OpenAICompatibleProvider(
 *     apiKey = "sk-...",
 *     model = "gpt-4o-mini"
 * )
 * RunAnywhere.registerCloudProvider(provider)
 * ```
 */
suspend fun RunAnywhere.registerCloudProvider(provider: CloudProvider) {
    CloudProviderManager.register(provider)
}

/**
 * Unregister a cloud provider.
 */
suspend fun RunAnywhere.unregisterCloudProvider(providerId: String) {
    CloudProviderManager.unregister(providerId)
}

/**
 * Set the default cloud provider.
 *
 * @throws CloudProviderError.ProviderNotFound if the provider is not registered
 */
suspend fun RunAnywhere.setDefaultCloudProvider(providerId: String) {
    CloudProviderManager.setDefault(providerId)
}

/**
 * Set the default routing policy for all generation requests.
 */
suspend fun RunAnywhere.setDefaultRoutingPolicy(policy: RoutingPolicy) {
    RoutingEngine.setDefaultPolicy(policy)
}

// MARK: - Routing-Aware Generation

/**
 * Generate text with routing policy.
 *
 * Routes between on-device and cloud based on the policy.
 *
 * ```kotlin
 * // Hybrid auto: on-device first, auto-fallback to cloud
 * val result = RunAnywhere.generateWithRouting(
 *     "Explain quantum computing",
 *     routingPolicy = RoutingPolicy.hybridAuto(confidenceThreshold = 0.7f),
 *     cloudModel = "gpt-4o-mini"
 * )
 * println(result.generationResult.text)
 * println(result.routingDecision.executionTarget) // ON_DEVICE or CLOUD
 * ```
 */
suspend fun RunAnywhere.generateWithRouting(
    prompt: String,
    options: LLMGenerationOptions? = null,
    routingPolicy: RoutingPolicy? = null,
    cloudProviderId: String? = null,
    cloudModel: String? = null,
): RoutedGenerationResult {
    return RoutingEngine.generate(
        prompt = prompt,
        options = options,
        routingPolicy = routingPolicy,
        cloudProviderId = cloudProviderId,
        cloudModel = cloudModel,
    )
}

/**
 * Stream text with routing policy.
 *
 * ```kotlin
 * val result = RunAnywhere.generateStreamWithRouting(
 *     "Write a poem",
 *     routingPolicy = RoutingPolicy.hybridAuto()
 * )
 * result.streamingResult.stream.collect { token ->
 *     print(token)
 * }
 * ```
 */
suspend fun RunAnywhere.generateStreamWithRouting(
    prompt: String,
    options: LLMGenerationOptions? = null,
    routingPolicy: RoutingPolicy? = null,
    cloudProviderId: String? = null,
    cloudModel: String? = null,
): RoutedStreamingResult {
    return RoutingEngine.generateStream(
        prompt = prompt,
        options = options,
        routingPolicy = routingPolicy,
        cloudProviderId = cloudProviderId,
        cloudModel = cloudModel,
    )
}

// MARK: - Provider Failover Chain

/**
 * Set or clear the provider failover chain for automatic failover between cloud providers.
 *
 * ```kotlin
 * val chain = ProviderFailoverChain()
 * chain.addProvider(openaiProvider, priority = 10)
 * chain.addProvider(groqProvider, priority = 5)
 * RunAnywhere.setProviderFailoverChain(chain)
 * ```
 */
suspend fun RunAnywhere.setProviderFailoverChain(chain: ProviderFailoverChain?) {
    RoutingEngine.setFailoverChain(chain)
}

/**
 * Get the health status of all providers in the failover chain.
 *
 * @return List of provider health statuses, or null if no failover chain is configured.
 */
suspend fun RunAnywhere.failoverChainHealthStatus(): List<ProviderHealthStatus>? {
    val chain = RoutingEngine.getFailoverChain() ?: return null
    return chain.healthStatus()
}

// MARK: - Cost Tracking

/**
 * Get a summary of cumulative cloud API costs.
 *
 * ```kotlin
 * val costs = RunAnywhere.cloudCostSummary()
 * println("Total cost: $${costs.totalCostUSD}")
 * println("Requests: ${costs.totalRequests}")
 * ```
 */
suspend fun RunAnywhere.cloudCostSummary(): CloudCostSummary {
    return CloudCostTracker.summary()
}

/**
 * Reset all tracked cloud costs to zero.
 */
suspend fun RunAnywhere.resetCloudCosts() {
    CloudCostTracker.reset()
}
