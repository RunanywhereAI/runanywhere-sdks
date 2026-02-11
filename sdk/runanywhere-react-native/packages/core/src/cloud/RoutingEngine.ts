/**
 * RoutingEngine.ts
 *
 * Orchestrates routing between on-device and cloud inference
 * based on the configured routing policy.
 *
 * Phase 5 features:
 * - Cost tracking via `CloudCostTracker`
 * - Telemetry events via `EventBus`
 * - Latency-based routing (TTFT timeout)
 * - Provider failover chain
 *
 * Reference: sdk/runanywhere-swift/Sources/RunAnywhere/Features/Cloud/RoutingEngine.swift
 */

import { generate, generateStream } from '../Public/Extensions/RunAnywhere+TextGeneration';
import { EventBus } from '../Public/Events/EventBus';
import { CloudCostTracker } from './CloudCostTracker';
import type { CloudCostSummary } from './CloudCostTracker';
import { CloudProviderManager } from './CloudProviderManager';
import { ProviderFailoverChain } from './ProviderFailoverChain';
import { CloudProviderError } from './OpenAICompatibleProvider';
import {
  type CloudGenerationOptions,
  CloudExecutionTarget,
  type CloudRoutingPolicy,
  DEFAULT_ROUTING_POLICY,
  HandoffReason,
  type RoutedGenerationResult,
  type RoutedStreamingResult,
  type RoutingDecision,
  RoutingMode,
} from './CloudTypes';
import type {
  RoutingEvent,
  CloudCostEvent,
  LatencyTimeoutEvent,
} from './RoutingTelemetry';
import type { LLMGenerationResult, LLMStreamingResult } from '../types/LLMTypes';
import type { GenerationOptions } from '../types/models';

// ============================================================================
// Routing Engine
// ============================================================================

/**
 * Orchestrates generation routing between on-device (C++) and cloud providers.
 *
 * Implements the routing decision logic:
 * - ALWAYS_LOCAL: Call C++ directly (existing path)
 * - ALWAYS_CLOUD: Call CloudProviderManager
 * - HYBRID_AUTO: On-device first, auto-fallback to cloud if confidence is low
 * - HYBRID_MANUAL: On-device first, return handoff signal in result
 *
 * Phase 5 features:
 * - Cost tracking via `CloudCostTracker`
 * - Telemetry events via `EventBus`
 * - Latency-based routing (TTFT timeout via Promise.race)
 * - Provider failover chain
 */
export class RoutingEngine {
  /** Shared singleton instance */
  static readonly shared = new RoutingEngine();

  /** Default routing policy for all requests */
  private defaultPolicy: CloudRoutingPolicy = { ...DEFAULT_ROUTING_POLICY };

  /** Optional failover chain for cloud providers */
  private failoverChain: ProviderFailoverChain | null = null;

  // ============================================================================
  // Configuration
  // ============================================================================

  /** Set the default routing policy */
  setDefaultPolicy(policy: CloudRoutingPolicy): void {
    this.defaultPolicy = { ...policy };
  }

  /** Get the current default routing policy */
  getDefaultPolicy(): CloudRoutingPolicy {
    return { ...this.defaultPolicy };
  }

  /** Set the provider failover chain */
  setFailoverChain(chain: ProviderFailoverChain | null): void {
    this.failoverChain = chain;
  }

  /** Get the current failover chain */
  getFailoverChain(): ProviderFailoverChain | null {
    return this.failoverChain;
  }

  // ============================================================================
  // Cost Summary
  // ============================================================================

  /** Get the current cloud cost summary */
  cloudCostSummary(): CloudCostSummary {
    return CloudCostTracker.shared.summary;
  }

  /** Reset all tracked cloud costs */
  resetCloudCosts(): void {
    CloudCostTracker.shared.reset();
  }

  // ============================================================================
  // Generation
  // ============================================================================

  /**
   * Generate text with routing awareness.
   * Routes between on-device and cloud based on the provided policy.
   */
  async generate(params: {
    prompt: string;
    options?: GenerationOptions;
    routingPolicy?: CloudRoutingPolicy;
    cloudProviderId?: string;
    cloudModel?: string;
  }): Promise<RoutedGenerationResult> {
    const policy = params.routingPolicy ?? this.defaultPolicy;
    const startTime = Date.now();

    let result: RoutedGenerationResult;

    switch (policy.mode) {
      case RoutingMode.AlwaysCloud:
        result = await this.generateCloud(
          params.prompt,
          params.options,
          policy,
          params.cloudProviderId,
          params.cloudModel,
        );
        break;

      case RoutingMode.AlwaysLocal:
        result = await this.generateLocal(params.prompt, params.options, policy);
        break;

      case RoutingMode.HybridAuto:
        result = await this.generateHybridAuto(
          params.prompt,
          params.options,
          policy,
          params.cloudProviderId,
          params.cloudModel,
        );
        break;

      case RoutingMode.HybridManual:
        result = await this.generateLocal(params.prompt, params.options, policy);
        break;
    }

    // Emit telemetry
    const latencyMs = Date.now() - startTime;
    this.emitRoutingTelemetry(result.routingDecision, latencyMs);

    return result;
  }

  /**
   * Generate text with streaming and routing awareness.
   */
  async generateStream(params: {
    prompt: string;
    options?: GenerationOptions;
    routingPolicy?: CloudRoutingPolicy;
    cloudProviderId?: string;
    cloudModel?: string;
  }): Promise<RoutedStreamingResult> {
    const policy = params.routingPolicy ?? this.defaultPolicy;

    switch (policy.mode) {
      case RoutingMode.AlwaysCloud:
        return this.generateStreamCloud(
          params.prompt,
          params.options,
          policy,
          params.cloudProviderId,
          params.cloudModel,
        );

      case RoutingMode.AlwaysLocal: {
        const streamResult = await generateStream(params.prompt, params.options);
        const decision = createDecision({
          executionTarget: CloudExecutionTarget.OnDevice,
          policy,
        });
        return { streamingResult: streamResult, routingDecision: decision };
      }

      case RoutingMode.HybridAuto:
        return this.generateStreamHybridAuto(
          params.prompt,
          params.options,
          policy,
          params.cloudProviderId,
          params.cloudModel,
        );

      case RoutingMode.HybridManual: {
        const streamResult = await generateStream(params.prompt, params.options);
        const decision = createDecision({
          executionTarget: CloudExecutionTarget.OnDevice,
          policy,
        });
        return { streamingResult: streamResult, routingDecision: decision };
      }
    }
  }

  // ============================================================================
  // Private: Local Generation
  // ============================================================================

  private async generateLocal(
    prompt: string,
    options: GenerationOptions | undefined,
    policy: CloudRoutingPolicy,
  ): Promise<RoutedGenerationResult> {
    // Build options with confidence threshold
    const effectiveOptions = optionsWithConfidence(options, policy.confidenceThreshold);

    const result = await generate(prompt, effectiveOptions);

    const decision = createDecision({
      executionTarget: CloudExecutionTarget.OnDevice,
      policy,
      onDeviceConfidence: result.confidence ?? 1.0,
      cloudHandoffTriggered: result.cloudHandoff ?? false,
      handoffReason: mapHandoffReason(result.handoffReason),
    });

    // Map GenerationResult to LLMGenerationResult
    const llmResult = generationResultToLLMResult(result);

    return { generationResult: llmResult, routingDecision: decision };
  }

  // ============================================================================
  // Private: Cloud Generation
  // ============================================================================

  private async generateCloud(
    prompt: string,
    options: GenerationOptions | undefined,
    policy: CloudRoutingPolicy,
    cloudProviderId?: string,
    cloudModel?: string,
  ): Promise<RoutedGenerationResult> {
    const cloudOpts: CloudGenerationOptions = {
      model: cloudModel ?? 'gpt-4o-mini',
      maxTokens: options?.maxTokens ?? 1024,
      temperature: options?.temperature ?? 0.7,
      systemPrompt: options?.systemPrompt,
    };

    // Enforce cost cap before making the request
    if (policy.costCapUSD > 0) {
      const summary = CloudCostTracker.shared.summary;
      if (summary.totalCostUSD >= policy.costCapUSD) {
        throw CloudProviderError.budgetExceeded(
          summary.totalCostUSD,
          policy.costCapUSD,
        );
      }
    }

    let cloudResult;

    // Try failover chain first if available, else direct provider
    if (this.failoverChain) {
      cloudResult = await this.failoverChain.generate(prompt, cloudOpts);
    } else {
      const manager = CloudProviderManager.shared;
      const provider = cloudProviderId
        ? manager.get(cloudProviderId)
        : manager.getDefault();
      cloudResult = await provider.generate(prompt, cloudOpts);
    }

    // Track cost
    if (cloudResult.estimatedCostUSD != null) {
      CloudCostTracker.shared.recordRequest(
        cloudResult.providerId,
        cloudResult.inputTokens,
        cloudResult.outputTokens,
        cloudResult.estimatedCostUSD,
      );

      // Emit cost event
      const cumulative = CloudCostTracker.shared.summary.totalCostUSD;
      const costEvent: CloudCostEvent = {
        type: 'cloud.cost',
        providerId: cloudResult.providerId,
        inputTokens: cloudResult.inputTokens,
        outputTokens: cloudResult.outputTokens,
        costUSD: cloudResult.estimatedCostUSD,
        cumulativeTotalUSD: cumulative,
        timestamp: Date.now(),
      };
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      EventBus.publish('Performance', costEvent as any);
    }

    const decision = createDecision({
      executionTarget: CloudExecutionTarget.Cloud,
      policy,
      cloudProviderId: cloudResult.providerId,
      cloudModel: cloudOpts.model,
    });

    const llmResult: LLMGenerationResult = {
      text: cloudResult.text,
      inputTokens: cloudResult.inputTokens,
      tokensUsed: cloudResult.outputTokens,
      modelUsed: cloudOpts.model,
      latencyMs: cloudResult.latencyMs,
      framework: 'cloud',
      tokensPerSecond:
        cloudResult.latencyMs > 0
          ? cloudResult.outputTokens / (cloudResult.latencyMs / 1000)
          : 0,
      thinkingTokens: 0,
      responseTokens: cloudResult.outputTokens,
    };

    return { generationResult: llmResult, routingDecision: decision };
  }

  // ============================================================================
  // Private: Hybrid Auto Generation
  // ============================================================================

  private async generateHybridAuto(
    prompt: string,
    options: GenerationOptions | undefined,
    policy: CloudRoutingPolicy,
    cloudProviderId?: string,
    cloudModel?: string,
  ): Promise<RoutedGenerationResult> {
    // Latency-based routing: race local generation against timeout
    if (policy.maxLocalLatencyMs > 0) {
      const localResult = await this.generateLocalWithTimeout(
        prompt,
        options,
        policy,
        policy.maxLocalLatencyMs,
      );

      if (localResult != null) {
        // Local completed within timeout
        if (!localResult.routingDecision.cloudHandoffTriggered) {
          return localResult;
        }
        // Local completed but recommends handoff - fall through to cloud
      } else {
        // Timeout exceeded - emit event and fall back to cloud
        const timeoutEvent: LatencyTimeoutEvent = {
          type: 'routing.latency_timeout',
          maxLatencyMs: policy.maxLocalLatencyMs,
          actualLatencyMs: policy.maxLocalLatencyMs,
          timestamp: Date.now(),
        };
        // eslint-disable-next-line @typescript-eslint/no-explicit-any
        EventBus.publish('Performance', timeoutEvent as any);
      }
    } else {
      // No timeout: try on-device first with confidence tracking
      const localResult = await this.generateLocal(prompt, options, policy);

      // If on-device was confident enough, return it
      if (!localResult.routingDecision.cloudHandoffTriggered) {
        return localResult;
      }
    }

    // Fall back to cloud
    const cloudResult = await this.generateCloud(
      prompt,
      options,
      policy,
      cloudProviderId,
      cloudModel,
    );

    // Mark as hybrid fallback
    const decision = createDecision({
      executionTarget: CloudExecutionTarget.HybridFallback,
      policy,
      onDeviceConfidence: 0.0,
      cloudHandoffTriggered: true,
      handoffReason:
        policy.maxLocalLatencyMs > 0
          ? HandoffReason.FirstTokenLowConfidence
          : HandoffReason.RollingWindowDegradation,
      cloudProviderId: cloudResult.routingDecision.cloudProviderId,
      cloudModel: cloudResult.routingDecision.cloudModel,
    });

    return {
      generationResult: cloudResult.generationResult,
      routingDecision: decision,
    };
  }

  // ============================================================================
  // Private: Local Generation with Timeout
  // ============================================================================

  /**
   * Run local generation with a timeout using Promise.race.
   * Returns null if timeout is exceeded.
   */
  private async generateLocalWithTimeout(
    prompt: string,
    options: GenerationOptions | undefined,
    policy: CloudRoutingPolicy,
    timeoutMs: number,
  ): Promise<RoutedGenerationResult | null> {
    const localPromise = this.generateLocal(prompt, options, policy);

    const timeoutPromise = new Promise<null>((resolve) => {
      setTimeout(() => resolve(null), timeoutMs);
    });

    return Promise.race([localPromise, timeoutPromise]);
  }

  // ============================================================================
  // Private: Cloud Streaming
  // ============================================================================

  private async generateStreamCloud(
    prompt: string,
    options: GenerationOptions | undefined,
    policy: CloudRoutingPolicy,
    cloudProviderId?: string,
    cloudModel?: string,
  ): Promise<RoutedStreamingResult> {
    // Enforce cost cap
    if (policy.costCapUSD > 0) {
      const summary = CloudCostTracker.shared.summary;
      if (summary.totalCostUSD >= policy.costCapUSD) {
        throw CloudProviderError.budgetExceeded(
          summary.totalCostUSD,
          policy.costCapUSD,
        );
      }
    }

    const cloudOpts: CloudGenerationOptions = {
      model: cloudModel ?? 'gpt-4o-mini',
      maxTokens: options?.maxTokens ?? 1024,
      temperature: options?.temperature ?? 0.7,
      systemPrompt: options?.systemPrompt,
    };

    let cloudStream: AsyncGenerator<string>;

    // Try failover chain first
    if (this.failoverChain) {
      cloudStream = this.failoverChain.generateStream(prompt, cloudOpts);
    } else {
      const manager = CloudProviderManager.shared;
      const provider = cloudProviderId
        ? manager.get(cloudProviderId)
        : manager.getDefault();
      cloudStream = provider.generateStream(prompt, cloudOpts);
    }

    const modelId = cloudOpts.model;
    const provId = cloudProviderId ?? 'default';

    // Collect tokens and build LLMStreamingResult
    let fullText = '';
    let tokenCount = 0;
    const startTime = Date.now();
    let firstTokenTime: number | null = null;

    // Token queue for async iteration
    const tokenQueue: string[] = [];
    let tokenResolver: ((value: IteratorResult<string>) => void) | null = null;
    let streamDone = false;
    let streamError: Error | null = null;
    let resolveResult: ((result: LLMGenerationResult) => void) | null = null;
    let rejectResult: ((error: Error) => void) | null = null;

    const resultPromise = new Promise<LLMGenerationResult>((resolve, reject) => {
      resolveResult = resolve;
      rejectResult = reject;
    });

    // Start consuming cloud stream in background
    void (async () => {
      try {
        for await (const token of cloudStream) {
          if (firstTokenTime === null) {
            firstTokenTime = Date.now();
          }
          fullText += token;
          tokenCount++;

          if (tokenResolver) {
            tokenResolver({ value: token, done: false });
            tokenResolver = null;
          } else {
            tokenQueue.push(token);
          }
        }

        streamDone = true;
        const latencyMs = Date.now() - startTime;

        const finalResult: LLMGenerationResult = {
          text: fullText,
          inputTokens: Math.ceil(fullText.length / 4),
          tokensUsed: tokenCount,
          modelUsed: modelId,
          latencyMs,
          framework: 'cloud',
          tokensPerSecond: latencyMs > 0 ? (tokenCount / latencyMs) * 1000 : 0,
          timeToFirstTokenMs: firstTokenTime ? firstTokenTime - startTime : undefined,
          thinkingTokens: 0,
          responseTokens: tokenCount,
        };

        resolveResult?.(finalResult);

        if (tokenResolver) {
          tokenResolver({ value: undefined as unknown as string, done: true });
          tokenResolver = null;
        }
      } catch (err) {
        streamDone = true;
        streamError = err instanceof Error ? err : new Error(String(err));
        rejectResult?.(streamError);
        if (tokenResolver) {
          tokenResolver({ value: undefined as unknown as string, done: true });
          tokenResolver = null;
        }
      }
    })();

    // Create async iterable for tokens
    async function* tokenGenerator(): AsyncGenerator<string> {
      while (!streamDone || tokenQueue.length > 0) {
        if (tokenQueue.length > 0) {
          yield tokenQueue.shift()!;
        } else if (!streamDone) {
          const iterResult = await new Promise<IteratorResult<string>>((resolve) => {
            tokenResolver = resolve;
          });
          if (iterResult.done) break;
          yield iterResult.value;
        }
      }
      if (streamError) {
        throw streamError;
      }
    }

    const streamingResult: LLMStreamingResult = {
      stream: tokenGenerator(),
      result: resultPromise,
      cancel: () => {
        /* Cloud streams cannot be cancelled mid-flight */
      },
    };

    const decision = createDecision({
      executionTarget: CloudExecutionTarget.Cloud,
      policy,
      cloudProviderId: provId,
      cloudModel: modelId,
    });

    return { streamingResult, routingDecision: decision };
  }

  // ============================================================================
  // Private: Hybrid Auto Streaming
  // ============================================================================

  private async generateStreamHybridAuto(
    prompt: string,
    options: GenerationOptions | undefined,
    policy: CloudRoutingPolicy,
    _cloudProviderId?: string,
    _cloudModel?: string,
  ): Promise<RoutedStreamingResult> {
    // For streaming hybrid, start with on-device and monitor confidence.
    // If handoff is needed, the C++ layer will stop generation and signal.
    const streamResult = await generateStream(prompt, options);
    const decision = createDecision({
      executionTarget: CloudExecutionTarget.OnDevice,
      policy,
    });
    return { streamingResult: streamResult, routingDecision: decision };
  }

  // ============================================================================
  // Private: Telemetry
  // ============================================================================

  private emitRoutingTelemetry(
    decision: RoutingDecision,
    latencyMs: number,
    estimatedCostUSD?: number,
  ): void {
    const event: RoutingEvent = {
      type: 'routing.decision',
      routingMode: decision.policy.mode,
      executionTarget: decision.executionTarget,
      confidence: decision.onDeviceConfidence,
      cloudHandoffTriggered: decision.cloudHandoffTriggered,
      handoffReason: decision.handoffReason,
      cloudProviderId: decision.cloudProviderId,
      cloudModel: decision.cloudModel,
      latencyMs,
      estimatedCostUSD,
      timestamp: Date.now(),
    };
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    EventBus.publish('Performance', event as any);
  }
}

// ============================================================================
// Helpers
// ============================================================================

/** Build options with confidence threshold for on-device generation */
function optionsWithConfidence(
  options: GenerationOptions | undefined,
  threshold: number,
): GenerationOptions {
  return {
    ...options,
    confidenceThreshold: threshold,
  };
}

/** Create a RoutingDecision with sensible defaults */
function createDecision(params: {
  executionTarget: CloudExecutionTarget;
  policy: CloudRoutingPolicy;
  onDeviceConfidence?: number;
  cloudHandoffTriggered?: boolean;
  handoffReason?: HandoffReason;
  cloudProviderId?: string;
  cloudModel?: string;
}): RoutingDecision {
  return {
    executionTarget: params.executionTarget,
    policy: params.policy,
    onDeviceConfidence: params.onDeviceConfidence ?? 1.0,
    cloudHandoffTriggered: params.cloudHandoffTriggered ?? false,
    handoffReason: params.handoffReason ?? HandoffReason.None,
    cloudProviderId: params.cloudProviderId,
    cloudModel: params.cloudModel,
  };
}

/** Map raw handoff reason number to HandoffReason enum */
function mapHandoffReason(reason?: number): HandoffReason {
  switch (reason) {
    case 1:
      return HandoffReason.FirstTokenLowConfidence;
    case 2:
      return HandoffReason.RollingWindowDegradation;
    default:
      return HandoffReason.None;
  }
}

/** Convert GenerationResult to LLMGenerationResult for routed results */
function generationResultToLLMResult(result: {
  text: string;
  thinkingContent?: string;
  tokensUsed: number;
  modelUsed: string;
  latencyMs: number;
  framework?: string;
  performanceMetrics?: { tokensPerSecond?: number; timeToFirstTokenMs?: number };
  thinkingTokens?: number;
  responseTokens: number;
  confidence?: number;
  cloudHandoff?: boolean;
  handoffReason?: number;
}): LLMGenerationResult {
  return {
    text: result.text,
    thinkingContent: result.thinkingContent,
    inputTokens: 0,
    tokensUsed: result.tokensUsed,
    modelUsed: result.modelUsed,
    latencyMs: result.latencyMs,
    framework: result.framework ?? 'unknown',
    tokensPerSecond: result.performanceMetrics?.tokensPerSecond ?? 0,
    timeToFirstTokenMs: result.performanceMetrics?.timeToFirstTokenMs,
    thinkingTokens: result.thinkingTokens ?? 0,
    responseTokens: result.responseTokens,
    confidence: result.confidence,
    cloudHandoff: result.cloudHandoff,
    handoffReason: result.handoffReason,
  };
}
