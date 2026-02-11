//
//  RoutingEngine.swift
//  RunAnywhere SDK
//
//  Orchestrates routing between on-device and cloud inference
//  based on the configured routing policy.
//

import CRACommons
import Foundation

// MARK: - Routing Engine

/// Orchestrates generation routing between on-device (C++) and cloud providers.
///
/// Implements the routing decision logic:
/// - ALWAYS_LOCAL: Call C++ directly (existing path)
/// - ALWAYS_CLOUD: Call CloudProviderManager
/// - HYBRID_AUTO: On-device first, auto-fallback to cloud if confidence is low
/// - HYBRID_MANUAL: On-device first, return handoff signal in result
///
/// Phase 5 features:
/// - Cost tracking via `CloudCostTracker`
/// - Telemetry events via `EventBus`
/// - Latency-based routing (TTFT timeout)
/// - Provider failover chain
actor RoutingEngine {

    static let shared = RoutingEngine()

    /// Default routing policy for all requests
    private var defaultPolicy = RoutingPolicy()

    /// Optional failover chain for cloud providers
    private var failoverChain: ProviderFailoverChain?

    // MARK: - Configuration

    /// Set the default routing policy
    func setDefaultPolicy(_ policy: RoutingPolicy) {
        self.defaultPolicy = policy
    }

    /// Get the current default routing policy
    func getDefaultPolicy() -> RoutingPolicy {
        defaultPolicy
    }

    /// Set the provider failover chain
    func setFailoverChain(_ chain: ProviderFailoverChain?) {
        self.failoverChain = chain
    }

    /// Get the current failover chain
    func getFailoverChain() -> ProviderFailoverChain? {
        failoverChain
    }

    // MARK: - Generation

    /// Generate text with routing awareness
    ///
    /// Routes between on-device and cloud based on the provided policy.
    func generate(
        prompt: String,
        options: LLMGenerationOptions?,
        routingPolicy: RoutingPolicy?,
        cloudProviderId: String? = nil,
        cloudModel: String? = nil
    ) async throws -> RoutedGenerationResult {
        let policy = routingPolicy ?? defaultPolicy
        let startTime = Date()

        let result: RoutedGenerationResult

        switch policy.mode {
        case .alwaysCloud:
            result = try await generateCloud(
                prompt: prompt,
                options: options,
                policy: policy,
                cloudProviderId: cloudProviderId,
                cloudModel: cloudModel
            )

        case .alwaysLocal:
            result = try await generateLocal(prompt: prompt, options: options, policy: policy)

        case .hybridAuto:
            result = try await generateHybridAuto(
                prompt: prompt,
                options: options,
                policy: policy,
                cloudProviderId: cloudProviderId,
                cloudModel: cloudModel
            )

        case .hybridManual:
            result = try await generateLocal(prompt: prompt, options: options, policy: policy)
        }

        // Emit telemetry
        let latencyMs = Date().timeIntervalSince(startTime) * 1000
        emitRoutingTelemetry(decision: result.routingDecision, latencyMs: latencyMs)

        return result
    }

    /// Generate text with streaming and routing awareness
    func generateStream(
        prompt: String,
        options: LLMGenerationOptions?,
        routingPolicy: RoutingPolicy?,
        cloudProviderId: String? = nil,
        cloudModel: String? = nil
    ) async throws -> RoutedStreamingResult {
        let policy = routingPolicy ?? defaultPolicy

        switch policy.mode {
        case .alwaysCloud:
            return try await generateStreamCloud(
                prompt: prompt,
                options: options,
                policy: policy,
                cloudProviderId: cloudProviderId,
                cloudModel: cloudModel
            )

        case .alwaysLocal:
            let streamResult = try await RunAnywhere.generateStream(prompt, options: options)
            let decision = RoutingDecision(executionTarget: .onDevice, policy: policy)
            return RoutedStreamingResult(streamingResult: streamResult, routingDecision: decision)

        case .hybridAuto:
            return try await generateStreamHybridAuto(
                prompt: prompt,
                options: options,
                policy: policy,
                cloudProviderId: cloudProviderId,
                cloudModel: cloudModel
            )

        case .hybridManual:
            let streamResult = try await RunAnywhere.generateStream(prompt, options: options)
            let decision = RoutingDecision(executionTarget: .onDevice, policy: policy)
            return RoutedStreamingResult(streamingResult: streamResult, routingDecision: decision)
        }
    }

    // MARK: - Private: Local Generation

    private func generateLocal(
        prompt: String,
        options: LLMGenerationOptions?,
        policy: RoutingPolicy
    ) async throws -> RoutedGenerationResult {
        // Build options with confidence threshold
        let effectiveOptions = optionsWithConfidence(options, threshold: policy.confidenceThreshold)

        let result = try await RunAnywhere.generate(prompt, options: effectiveOptions)

        let decision = RoutingDecision(
            executionTarget: .onDevice,
            policy: policy,
            onDeviceConfidence: result.confidence ?? 1.0,
            cloudHandoffTriggered: result.cloudHandoff ?? false,
            handoffReason: result.handoffReason ?? .none
        )

        return RoutedGenerationResult(generationResult: result, routingDecision: decision)
    }

    // MARK: - Private: Cloud Generation

    private func generateCloud(
        prompt: String,
        options: LLMGenerationOptions?,
        policy: RoutingPolicy,
        cloudProviderId: String?,
        cloudModel: String?
    ) async throws -> RoutedGenerationResult {
        let cloudOpts = CloudGenerationOptions(
            model: cloudModel ?? "gpt-4o-mini",
            maxTokens: options?.maxTokens ?? 1024,
            temperature: options?.temperature ?? 0.7,
            systemPrompt: options?.systemPrompt
        )

        // Enforce cost cap before making the request
        if policy.costCapUSD > 0 {
            let summary = await CloudCostTracker.shared.summary
            if summary.totalCostUSD >= Double(policy.costCapUSD) {
                throw CloudProviderError.budgetExceeded(
                    currentUSD: summary.totalCostUSD,
                    capUSD: Double(policy.costCapUSD)
                )
            }
        }

        let cloudResult: CloudGenerationResult

        // Try failover chain first if available, else direct provider
        if let chain = failoverChain {
            cloudResult = try await chain.generate(prompt: prompt, options: cloudOpts)
        } else {
            let provider: any CloudProvider
            if let id = cloudProviderId {
                provider = try await CloudProviderManager.shared.get(providerId: id)
            } else {
                provider = try await CloudProviderManager.shared.getDefault()
            }
            cloudResult = try await provider.generate(prompt: prompt, options: cloudOpts)
        }

        // Track cost
        if let cost = cloudResult.estimatedCostUSD {
            await CloudCostTracker.shared.recordRequest(
                providerId: cloudResult.providerId,
                inputTokens: cloudResult.inputTokens,
                outputTokens: cloudResult.outputTokens,
                costUSD: cost
            )
            // Emit cost event
            let cumulative = await CloudCostTracker.shared.summary.totalCostUSD
            EventBus.shared.publish(CloudCostEvent(
                providerId: cloudResult.providerId,
                inputTokens: cloudResult.inputTokens,
                outputTokens: cloudResult.outputTokens,
                costUSD: cost,
                cumulativeTotalUSD: cumulative
            ))
        }

        let decision = RoutingDecision(
            executionTarget: .cloud,
            policy: policy,
            cloudProviderId: cloudResult.providerId,
            cloudModel: cloudOpts.model
        )

        let llmResult = LLMGenerationResult(
            text: cloudResult.text,
            inputTokens: cloudResult.inputTokens,
            tokensUsed: cloudResult.outputTokens,
            modelUsed: cloudOpts.model,
            latencyMs: cloudResult.latencyMs,
            framework: "cloud",
            tokensPerSecond: cloudResult.latencyMs > 0
                ? Double(cloudResult.outputTokens) / (cloudResult.latencyMs / 1000.0) : 0
        )

        return RoutedGenerationResult(generationResult: llmResult, routingDecision: decision)
    }

    // MARK: - Private: Hybrid Auto Generation

    private func generateHybridAuto(
        prompt: String,
        options: LLMGenerationOptions?,
        policy: RoutingPolicy,
        cloudProviderId: String?,
        cloudModel: String?
    ) async throws -> RoutedGenerationResult {
        // Latency-based routing: race local generation against timeout
        if policy.maxLocalLatencyMs > 0 {
            let localResult = try await generateLocalWithTimeout(
                prompt: prompt,
                options: options,
                policy: policy,
                timeoutMs: policy.maxLocalLatencyMs
            )

            if let result = localResult {
                // Local completed within timeout
                if !result.routingDecision.cloudHandoffTriggered {
                    return result
                }
                // Local completed but recommends handoff - fall through to cloud
            } else {
                // Timeout exceeded - emit event and fall back to cloud
                EventBus.shared.publish(LatencyTimeoutEvent(
                    maxLatencyMs: policy.maxLocalLatencyMs,
                    actualLatencyMs: Double(policy.maxLocalLatencyMs)
                ))
            }
        } else {
            // No timeout: try on-device first with confidence tracking
            let localResult = try await generateLocal(prompt: prompt, options: options, policy: policy)

            // If on-device was confident enough, return it
            if !localResult.routingDecision.cloudHandoffTriggered {
                return localResult
            }
        }

        // Fall back to cloud
        let cloudResult = try await generateCloud(
            prompt: prompt,
            options: options,
            policy: policy,
            cloudProviderId: cloudProviderId,
            cloudModel: cloudModel
        )

        // Mark as hybrid fallback
        let decision = RoutingDecision(
            executionTarget: .hybridFallback,
            policy: policy,
            onDeviceConfidence: 0.0,
            cloudHandoffTriggered: true,
            handoffReason: policy.maxLocalLatencyMs > 0 ? .firstTokenLowConfidence : .rollingWindowDegradation,
            cloudProviderId: cloudResult.routingDecision.cloudProviderId,
            cloudModel: cloudResult.routingDecision.cloudModel
        )

        return RoutedGenerationResult(
            generationResult: cloudResult.generationResult,
            routingDecision: decision
        )
    }

    // MARK: - Private: Local Generation with Timeout

    /// Run local generation with a timeout. Returns nil if timeout is exceeded.
    private func generateLocalWithTimeout(
        prompt: String,
        options: LLMGenerationOptions?,
        policy: RoutingPolicy,
        timeoutMs: UInt32
    ) async throws -> RoutedGenerationResult? {
        let effectiveOptions = optionsWithConfidence(options, threshold: policy.confidenceThreshold)

        return try await withThrowingTaskGroup(of: RoutedGenerationResult?.self) { group in
            // Task 1: Local generation
            group.addTask {
                let result = try await RunAnywhere.generate(prompt, options: effectiveOptions)
                let decision = RoutingDecision(
                    executionTarget: .onDevice,
                    policy: policy,
                    onDeviceConfidence: result.confidence ?? 1.0,
                    cloudHandoffTriggered: result.cloudHandoff ?? false,
                    handoffReason: result.handoffReason ?? .none
                )
                return RoutedGenerationResult(generationResult: result, routingDecision: decision)
            }

            // Task 2: Timeout
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(timeoutMs) * 1_000_000)
                return nil // Timeout reached
            }

            // Return whichever finishes first
            let first = try await group.next()!
            group.cancelAll()
            return first
        }
    }

    // MARK: - Private: Cloud Streaming

    private func generateStreamCloud(
        prompt: String,
        options: LLMGenerationOptions?,
        policy: RoutingPolicy,
        cloudProviderId: String?,
        cloudModel: String?
    ) async throws -> RoutedStreamingResult {
        // Enforce cost cap
        if policy.costCapUSD > 0 {
            let summary = await CloudCostTracker.shared.summary
            if summary.totalCostUSD >= Double(policy.costCapUSD) {
                throw CloudProviderError.budgetExceeded(
                    currentUSD: summary.totalCostUSD,
                    capUSD: Double(policy.costCapUSD)
                )
            }
        }

        let cloudOpts = CloudGenerationOptions(
            model: cloudModel ?? "gpt-4o-mini",
            maxTokens: options?.maxTokens ?? 1024,
            temperature: options?.temperature ?? 0.7,
            systemPrompt: options?.systemPrompt
        )

        let cloudStream: AsyncThrowingStream<String, Error>

        // Try failover chain first
        if let chain = failoverChain {
            cloudStream = try await chain.generateStream(prompt: prompt, options: cloudOpts)
        } else {
            let provider: any CloudProvider
            if let id = cloudProviderId {
                provider = try await CloudProviderManager.shared.get(providerId: id)
            } else {
                provider = try await CloudProviderManager.shared.getDefault()
            }
            cloudStream = provider.generateStream(prompt: prompt, options: cloudOpts)
        }

        let modelId = cloudOpts.model
        let provId = cloudProviderId ?? "default"

        // Wrap cloud stream into LLMStreamingResult
        let tokenStream = AsyncThrowingStream<String, Error> { continuation in
            Task {
                do {
                    for try await token in cloudStream {
                        continuation.yield(token)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }

        let resultTask = Task<LLMGenerationResult, Error> {
            return LLMGenerationResult(
                text: "",
                tokensUsed: 0,
                modelUsed: modelId,
                latencyMs: 0,
                framework: "cloud"
            )
        }

        let streamResult = LLMStreamingResult(stream: tokenStream, result: resultTask)
        let decision = RoutingDecision(
            executionTarget: .cloud,
            policy: policy,
            cloudProviderId: provId,
            cloudModel: modelId
        )

        return RoutedStreamingResult(streamingResult: streamResult, routingDecision: decision)
    }

    // MARK: - Private: Hybrid Auto Streaming

    private func generateStreamHybridAuto(
        prompt: String,
        options: LLMGenerationOptions?,
        policy: RoutingPolicy,
        cloudProviderId: String?,
        cloudModel: String?
    ) async throws -> RoutedStreamingResult {
        // For streaming hybrid, start with on-device and monitor confidence
        // If handoff is needed, the C++ layer will stop generation and signal
        let streamResult = try await RunAnywhere.generateStream(prompt, options: options)
        let decision = RoutingDecision(executionTarget: .onDevice, policy: policy)
        return RoutedStreamingResult(streamingResult: streamResult, routingDecision: decision)
    }

    // MARK: - Telemetry

    private nonisolated func emitRoutingTelemetry(
        decision: RoutingDecision,
        latencyMs: Double,
        estimatedCostUSD: Double? = nil
    ) {
        EventBus.shared.publish(RoutingEvent(
            routingMode: decision.policy.mode,
            executionTarget: decision.executionTarget,
            confidence: decision.onDeviceConfidence,
            cloudHandoffTriggered: decision.cloudHandoffTriggered,
            handoffReason: decision.handoffReason,
            cloudProviderId: decision.cloudProviderId,
            cloudModel: decision.cloudModel,
            latencyMs: latencyMs,
            estimatedCostUSD: estimatedCostUSD
        ))
    }

    // MARK: - Helpers

    private func optionsWithConfidence(
        _ options: LLMGenerationOptions?,
        threshold: Float
    ) -> LLMGenerationOptions {
        let opts = options ?? LLMGenerationOptions()
        // Return options with confidence threshold set
        // The threshold is passed to C++ via rac_llm_options_t.confidence_threshold
        return LLMGenerationOptions(
            maxTokens: opts.maxTokens,
            temperature: opts.temperature,
            topP: opts.topP,
            stopSequences: opts.stopSequences,
            streamingEnabled: opts.streamingEnabled,
            preferredFramework: opts.preferredFramework,
            structuredOutput: opts.structuredOutput,
            systemPrompt: opts.systemPrompt,
            confidenceThreshold: threshold
        )
    }
}

// MARK: - Routed Results

/// Generation result enriched with routing metadata
public struct RoutedGenerationResult: Sendable {
    /// The generation result
    public let generationResult: LLMGenerationResult

    /// How the request was routed
    public let routingDecision: RoutingDecision
}

/// Streaming result enriched with routing metadata
public struct RoutedStreamingResult: Sendable {
    /// The streaming result
    public let streamingResult: LLMStreamingResult

    /// How the request was routed
    public let routingDecision: RoutingDecision
}
