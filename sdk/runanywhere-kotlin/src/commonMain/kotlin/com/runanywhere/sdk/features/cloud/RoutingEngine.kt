/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * Orchestrates routing between on-device and cloud inference
 * based on the configured routing policy.
 *
 * Phase 5: cost tracking, telemetry, latency-based routing, failover.
 * Mirrors Swift RoutingEngine.swift exactly.
 */

package com.runanywhere.sdk.features.cloud

import com.runanywhere.sdk.foundation.SDKLogger
import com.runanywhere.sdk.public.RunAnywhere
import com.runanywhere.sdk.public.events.EventBus
import com.runanywhere.sdk.public.extensions.Cloud.CloudGenerationOptions
import com.runanywhere.sdk.public.extensions.Cloud.CloudProvider
import com.runanywhere.sdk.public.extensions.Cloud.ExecutionTarget
import com.runanywhere.sdk.public.extensions.Cloud.HandoffReason
import com.runanywhere.sdk.public.extensions.Cloud.RoutedGenerationResult
import com.runanywhere.sdk.public.extensions.Cloud.RoutedStreamingResult
import com.runanywhere.sdk.public.extensions.Cloud.RoutingDecision
import com.runanywhere.sdk.public.extensions.Cloud.RoutingMode
import com.runanywhere.sdk.public.extensions.Cloud.RoutingPolicy
import com.runanywhere.sdk.public.extensions.LLM.LLMGenerationOptions
import com.runanywhere.sdk.public.extensions.LLM.LLMGenerationResult
import com.runanywhere.sdk.public.extensions.LLM.LLMStreamingResult
import com.runanywhere.sdk.public.extensions.generate
import com.runanywhere.sdk.public.extensions.generateStreamWithMetrics
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.flow
import kotlinx.coroutines.selects.select
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock

// MARK: - Routing Engine

/**
 * Orchestrates generation routing between on-device (C++) and cloud providers.
 *
 * Implements the routing decision logic:
 * - ALWAYS_LOCAL: Call C++ directly (existing path)
 * - ALWAYS_CLOUD: Call CloudProviderManager
 * - HYBRID_AUTO: On-device first, auto-fallback to cloud if confidence is low
 * - HYBRID_MANUAL: On-device first, return handoff signal in result
 *
 * Phase 5 additions:
 * - Cost tracking via CloudCostTracker
 * - Telemetry events via EventBus
 * - Latency-based routing with timeout
 * - Provider failover chain support
 *
 * Mirrors Swift RoutingEngine actor exactly.
 */
object RoutingEngine {

    private val logger = SDKLogger("RoutingEngine")
    private val mutex = Mutex()

    /** Default routing policy for all requests */
    private var defaultPolicy = RoutingPolicy()

    /** Optional failover chain for cloud providers */
    private var failoverChain: ProviderFailoverChain? = null

    // MARK: - Configuration

    /**
     * Set the default routing policy.
     */
    suspend fun setDefaultPolicy(policy: RoutingPolicy) {
        mutex.withLock { defaultPolicy = policy }
    }

    /**
     * Get the current default routing policy.
     */
    suspend fun getDefaultPolicy(): RoutingPolicy {
        mutex.withLock { return defaultPolicy }
    }

    /**
     * Set the provider failover chain.
     */
    suspend fun setFailoverChain(chain: ProviderFailoverChain?) {
        mutex.withLock { failoverChain = chain }
    }

    /**
     * Get the current provider failover chain.
     */
    suspend fun getFailoverChain(): ProviderFailoverChain? {
        mutex.withLock { return failoverChain }
    }

    // MARK: - Generation

    /**
     * Generate text with routing awareness.
     *
     * Routes between on-device and cloud based on the provided policy.
     */
    suspend fun generate(
        prompt: String,
        options: LLMGenerationOptions? = null,
        routingPolicy: RoutingPolicy? = null,
        cloudProviderId: String? = null,
        cloudModel: String? = null,
    ): RoutedGenerationResult {
        val policy = routingPolicy ?: mutex.withLock { defaultPolicy }
        val startTime = System.currentTimeMillis()

        val result = when (policy.mode) {
            RoutingMode.ALWAYS_CLOUD -> generateCloud(
                prompt = prompt,
                options = options,
                policy = policy,
                cloudProviderId = cloudProviderId,
                cloudModel = cloudModel,
            )

            RoutingMode.ALWAYS_LOCAL -> generateLocal(
                prompt = prompt,
                options = options,
                policy = policy,
            )

            RoutingMode.HYBRID_AUTO -> generateHybridAuto(
                prompt = prompt,
                options = options,
                policy = policy,
                cloudProviderId = cloudProviderId,
                cloudModel = cloudModel,
            )

            RoutingMode.HYBRID_MANUAL -> generateLocal(
                prompt = prompt,
                options = options,
                policy = policy,
            )
        }

        // Emit telemetry
        val latencyMs = (System.currentTimeMillis() - startTime).toDouble()
        emitRoutingTelemetry(decision = result.routingDecision, latencyMs = latencyMs)

        return result
    }

    /**
     * Generate text with streaming and routing awareness.
     */
    suspend fun generateStream(
        prompt: String,
        options: LLMGenerationOptions? = null,
        routingPolicy: RoutingPolicy? = null,
        cloudProviderId: String? = null,
        cloudModel: String? = null,
    ): RoutedStreamingResult {
        val policy = routingPolicy ?: mutex.withLock { defaultPolicy }

        return when (policy.mode) {
            RoutingMode.ALWAYS_CLOUD -> generateStreamCloud(
                prompt = prompt,
                options = options,
                policy = policy,
                cloudProviderId = cloudProviderId,
                cloudModel = cloudModel,
            )

            RoutingMode.ALWAYS_LOCAL -> {
                val streamResult = RunAnywhere.generateStreamWithMetrics(prompt, options)
                val decision = RoutingDecision(executionTarget = ExecutionTarget.ON_DEVICE, policy = policy)
                RoutedStreamingResult(streamingResult = streamResult, routingDecision = decision)
            }

            RoutingMode.HYBRID_AUTO -> generateStreamHybridAuto(
                prompt = prompt,
                options = options,
                policy = policy,
                cloudProviderId = cloudProviderId,
                cloudModel = cloudModel,
            )

            RoutingMode.HYBRID_MANUAL -> {
                val streamResult = RunAnywhere.generateStreamWithMetrics(prompt, options)
                val decision = RoutingDecision(executionTarget = ExecutionTarget.ON_DEVICE, policy = policy)
                RoutedStreamingResult(streamingResult = streamResult, routingDecision = decision)
            }
        }
    }

    // MARK: - Private: Local Generation

    private suspend fun generateLocal(
        prompt: String,
        options: LLMGenerationOptions?,
        policy: RoutingPolicy,
    ): RoutedGenerationResult {
        // Build options with confidence threshold
        val effectiveOptions = optionsWithConfidence(options, threshold = policy.confidenceThreshold)

        val result = RunAnywhere.generate(prompt, effectiveOptions)

        val decision = RoutingDecision(
            executionTarget = ExecutionTarget.ON_DEVICE,
            policy = policy,
            onDeviceConfidence = result.confidence ?: 1.0f,
            cloudHandoffTriggered = result.cloudHandoff ?: false,
            handoffReason = result.handoffReason ?: HandoffReason.NONE,
        )

        return RoutedGenerationResult(generationResult = result, routingDecision = decision)
    }

    // MARK: - Private: Cloud Generation

    private suspend fun generateCloud(
        prompt: String,
        options: LLMGenerationOptions?,
        policy: RoutingPolicy,
        cloudProviderId: String?,
        cloudModel: String?,
    ): RoutedGenerationResult {
        val cloudOpts = CloudGenerationOptions(
            model = cloudModel ?: "gpt-4o-mini",
            maxTokens = options?.maxTokens ?: 1024,
            temperature = options?.temperature ?: 0.7f,
            systemPrompt = options?.systemPrompt,
        )

        // Enforce cost cap
        if (policy.costCapUSD > 0) {
            val summary = CloudCostTracker.summary()
            if (summary.totalCostUSD >= policy.costCapUSD.toDouble()) {
                throw CloudProviderError.BudgetExceeded(
                    currentUSD = summary.totalCostUSD,
                    capUSD = policy.costCapUSD.toDouble(),
                )
            }
        }

        val cloudResult: com.runanywhere.sdk.public.extensions.Cloud.CloudGenerationResult

        // Try failover chain first if available
        val chain = mutex.withLock { failoverChain }
        if (chain != null) {
            cloudResult = chain.generate(prompt = prompt, options = cloudOpts)
        } else {
            val provider: CloudProvider = if (cloudProviderId != null) {
                CloudProviderManager.get(cloudProviderId)
            } else {
                CloudProviderManager.getDefault()
            }
            cloudResult = provider.generate(prompt = prompt, options = cloudOpts)
        }

        // Track cost
        val cost = cloudResult.estimatedCostUSD
        if (cost != null) {
            CloudCostTracker.recordRequest(
                providerId = cloudResult.providerId,
                inputTokens = cloudResult.inputTokens,
                outputTokens = cloudResult.outputTokens,
                costUSD = cost,
            )
            val cumulative = CloudCostTracker.summary().totalCostUSD
            EventBus.publish(
                CloudCostEvent(
                    providerId = cloudResult.providerId,
                    inputTokens = cloudResult.inputTokens,
                    outputTokens = cloudResult.outputTokens,
                    costUSD = cost,
                    cumulativeTotalUSD = cumulative,
                ),
            )
        }

        val decision = RoutingDecision(
            executionTarget = ExecutionTarget.CLOUD,
            policy = policy,
            cloudProviderId = cloudResult.providerId,
            cloudModel = cloudOpts.model,
        )

        val llmResult = LLMGenerationResult(
            text = cloudResult.text,
            inputTokens = cloudResult.inputTokens,
            tokensUsed = cloudResult.outputTokens,
            modelUsed = cloudOpts.model,
            latencyMs = cloudResult.latencyMs,
            framework = "cloud",
            tokensPerSecond = if (cloudResult.latencyMs > 0) {
                cloudResult.outputTokens.toDouble() / (cloudResult.latencyMs / 1000.0)
            } else {
                0.0
            },
        )

        return RoutedGenerationResult(generationResult = llmResult, routingDecision = decision)
    }

    // MARK: - Private: Hybrid Auto Generation

    private suspend fun generateHybridAuto(
        prompt: String,
        options: LLMGenerationOptions?,
        policy: RoutingPolicy,
        cloudProviderId: String?,
        cloudModel: String?,
    ): RoutedGenerationResult {
        // Latency-based routing: race local generation against timeout
        if (policy.maxLocalLatencyMs > 0) {
            val localResult = generateLocalWithTimeout(prompt, options, policy, policy.maxLocalLatencyMs)

            if (localResult != null) {
                if (!localResult.routingDecision.cloudHandoffTriggered) {
                    return localResult
                }
            } else {
                // Timeout exceeded
                EventBus.publish(
                    LatencyTimeoutEvent(
                        maxLatencyMs = policy.maxLocalLatencyMs,
                        actualLatencyMs = policy.maxLocalLatencyMs.toDouble(),
                    ),
                )
            }
        } else {
            // No latency limit: try on-device first with confidence tracking
            val localResult = generateLocal(prompt = prompt, options = options, policy = policy)

            // If on-device was confident enough, return it
            if (!localResult.routingDecision.cloudHandoffTriggered) {
                return localResult
            }
        }

        // Fall back to cloud
        val cloudResult = generateCloud(
            prompt = prompt,
            options = options,
            policy = policy,
            cloudProviderId = cloudProviderId,
            cloudModel = cloudModel,
        )

        // Mark as hybrid fallback
        val decision = RoutingDecision(
            executionTarget = ExecutionTarget.HYBRID_FALLBACK,
            policy = policy,
            onDeviceConfidence = 0.0f,
            cloudHandoffTriggered = true,
            handoffReason = if (policy.maxLocalLatencyMs > 0) {
                HandoffReason.FIRST_TOKEN_LOW_CONFIDENCE
            } else {
                HandoffReason.ROLLING_WINDOW_DEGRADATION
            },
            cloudProviderId = cloudResult.routingDecision.cloudProviderId,
            cloudModel = cloudResult.routingDecision.cloudModel,
        )

        return RoutedGenerationResult(
            generationResult = cloudResult.generationResult,
            routingDecision = decision,
        )
    }

    // MARK: - Local Generation with Timeout

    private suspend fun generateLocalWithTimeout(
        prompt: String,
        options: LLMGenerationOptions?,
        policy: RoutingPolicy,
        timeoutMs: Long,
    ): RoutedGenerationResult? = coroutineScope {
        val effectiveOptions = optionsWithConfidence(options, threshold = policy.confidenceThreshold)

        val localJob = async {
            val result = RunAnywhere.generate(prompt, effectiveOptions)
            val decision = RoutingDecision(
                executionTarget = ExecutionTarget.ON_DEVICE,
                policy = policy,
                onDeviceConfidence = result.confidence ?: 1.0f,
                cloudHandoffTriggered = result.cloudHandoff ?: false,
                handoffReason = result.handoffReason ?: HandoffReason.NONE,
            )
            RoutedGenerationResult(generationResult = result, routingDecision = decision)
        }

        val timeoutJob = async {
            delay(timeoutMs)
            null
        }

        select<RoutedGenerationResult?> {
            localJob.onAwait { it }
            timeoutJob.onAwait {
                localJob.cancel()
                null
            }
        }
    }

    // MARK: - Private: Cloud Streaming

    private suspend fun generateStreamCloud(
        prompt: String,
        options: LLMGenerationOptions?,
        policy: RoutingPolicy,
        cloudProviderId: String?,
        cloudModel: String?,
    ): RoutedStreamingResult {
        // Enforce cost cap
        if (policy.costCapUSD > 0) {
            val summary = CloudCostTracker.summary()
            if (summary.totalCostUSD >= policy.costCapUSD.toDouble()) {
                throw CloudProviderError.BudgetExceeded(
                    currentUSD = summary.totalCostUSD,
                    capUSD = policy.costCapUSD.toDouble(),
                )
            }
        }

        val cloudOpts = CloudGenerationOptions(
            model = cloudModel ?: "gpt-4o-mini",
            maxTokens = options?.maxTokens ?: 1024,
            temperature = options?.temperature ?: 0.7f,
            systemPrompt = options?.systemPrompt,
        )

        val cloudStream: kotlinx.coroutines.flow.Flow<String>

        val chain = mutex.withLock { failoverChain }
        if (chain != null) {
            cloudStream = chain.generateStream(prompt = prompt, options = cloudOpts)
        } else {
            val provider: CloudProvider = if (cloudProviderId != null) {
                CloudProviderManager.get(cloudProviderId)
            } else {
                CloudProviderManager.getDefault()
            }
            cloudStream = provider.generateStream(prompt = prompt, options = cloudOpts)
        }

        val modelId = cloudOpts.model
        val provId = cloudProviderId ?: "default"

        // Collect tokens and build both stream + result
        val resultDeferred = CompletableDeferred<LLMGenerationResult>()

        val tokenFlow = flow {
            val fullText = StringBuilder()
            try {
                cloudStream.collect { token ->
                    fullText.append(token)
                    emit(token)
                }
                // Complete with final result
                resultDeferred.complete(
                    LLMGenerationResult(
                        text = fullText.toString(),
                        tokensUsed = maxOf(1, fullText.length / 4),
                        modelUsed = modelId,
                        latencyMs = 0.0,
                        framework = "cloud",
                    ),
                )
            } catch (e: Exception) {
                resultDeferred.completeExceptionally(e)
                throw e
            }
        }

        val streamResult = LLMStreamingResult(stream = tokenFlow, result = resultDeferred)
        val decision = RoutingDecision(
            executionTarget = ExecutionTarget.CLOUD,
            policy = policy,
            cloudProviderId = provId,
            cloudModel = modelId,
        )

        return RoutedStreamingResult(streamingResult = streamResult, routingDecision = decision)
    }

    // MARK: - Private: Hybrid Auto Streaming

    private suspend fun generateStreamHybridAuto(
        prompt: String,
        options: LLMGenerationOptions?,
        policy: RoutingPolicy,
        cloudProviderId: String?,
        cloudModel: String?,
    ): RoutedStreamingResult {
        // For streaming hybrid, start with on-device and monitor confidence
        // If handoff is needed, the C++ layer will stop generation and signal
        val streamResult = RunAnywhere.generateStreamWithMetrics(prompt, options)
        val decision = RoutingDecision(executionTarget = ExecutionTarget.ON_DEVICE, policy = policy)
        return RoutedStreamingResult(streamingResult = streamResult, routingDecision = decision)
    }

    // MARK: - Telemetry

    private fun emitRoutingTelemetry(
        decision: RoutingDecision,
        latencyMs: Double,
        estimatedCostUSD: Double? = null,
    ) {
        EventBus.publish(
            RoutingEvent(
                routingMode = decision.policy.mode,
                executionTarget = decision.executionTarget,
                confidence = decision.onDeviceConfidence,
                cloudHandoffTriggered = decision.cloudHandoffTriggered,
                handoffReason = decision.handoffReason,
                cloudProviderId = decision.cloudProviderId,
                cloudModel = decision.cloudModel,
                latencyMs = latencyMs,
                estimatedCostUSD = estimatedCostUSD,
            ),
        )
    }

    // MARK: - Helpers

    private fun optionsWithConfidence(
        options: LLMGenerationOptions?,
        threshold: Float,
    ): LLMGenerationOptions {
        val opts = options ?: LLMGenerationOptions()
        // Return options with confidence threshold set
        // The threshold is passed to C++ via rac_llm_options_t.confidence_threshold
        return opts.copy(confidenceThreshold = threshold)
    }
}
