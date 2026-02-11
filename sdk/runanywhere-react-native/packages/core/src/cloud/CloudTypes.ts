/**
 * CloudTypes.ts
 *
 * Types for cloud provider infrastructure and routing.
 *
 * Reference: sdk/runanywhere-swift/Sources/RunAnywhere/Public/Extensions/Cloud/CloudTypes.swift
 */

import type { LLMGenerationResult, LLMStreamingResult } from '../types/LLMTypes';

// ============================================================================
// Routing Mode
// ============================================================================

/**
 * Routing mode for inference requests
 */
export enum RoutingMode {
  /** Never use cloud - all inference on-device only */
  AlwaysLocal = 'always_local',

  /** Always use cloud - skip on-device inference */
  AlwaysCloud = 'always_cloud',

  /** On-device first, auto-fallback to cloud on low confidence */
  HybridAuto = 'hybrid_auto',

  /** On-device first, return handoff signal for app to decide */
  HybridManual = 'hybrid_manual',
}

// ============================================================================
// Execution Target
// ============================================================================

/**
 * Where inference was actually executed
 */
export enum CloudExecutionTarget {
  OnDevice = 'on_device',
  Cloud = 'cloud',
  HybridFallback = 'hybrid_fallback',
}

// ============================================================================
// Handoff Reason
// ============================================================================

/**
 * Reason why the on-device engine recommended cloud handoff
 */
export enum HandoffReason {
  /** No handoff needed */
  None = 0,

  /** First token had low confidence */
  FirstTokenLowConfidence = 1,

  /** Rolling window showed degrading confidence */
  RollingWindowDegradation = 2,
}

// ============================================================================
// Routing Policy
// ============================================================================

/**
 * Policy controlling how requests are routed between on-device and cloud
 */
export interface CloudRoutingPolicy {
  /** Routing mode */
  mode: RoutingMode;

  /** Confidence threshold for cloud handoff (0.0 - 1.0). Only relevant for hybrid modes. */
  confidenceThreshold: number;

  /** Max on-device time-to-first-token before cloud fallback (ms). 0 = no limit. */
  maxLocalLatencyMs: number;

  /** Max cloud cost per request in USD. 0.0 = no cap. */
  costCapUSD: number;

  /** Whether to prefer streaming for cloud calls */
  preferStreaming: boolean;
}

// ============================================================================
// Routing Decision
// ============================================================================

/**
 * Metadata about how a generation request was routed
 */
export interface RoutingDecision {
  /** Where inference was executed */
  executionTarget: CloudExecutionTarget;

  /** The routing policy that was applied */
  policy: CloudRoutingPolicy;

  /** On-device confidence score (0.0 - 1.0) */
  onDeviceConfidence: number;

  /** Whether cloud handoff was triggered */
  cloudHandoffTriggered: boolean;

  /** Reason for cloud handoff */
  handoffReason: HandoffReason;

  /** Cloud provider ID used (undefined if on-device only) */
  cloudProviderId?: string;

  /** Cloud model used (undefined if on-device only) */
  cloudModel?: string;
}

// ============================================================================
// Cloud Generation Options
// ============================================================================

/**
 * Options specific to cloud-based generation
 */
export interface CloudGenerationOptions {
  /** Cloud model identifier (e.g., "gpt-4o-mini") */
  model: string;

  /** Maximum tokens to generate */
  maxTokens?: number;

  /** Temperature for sampling */
  temperature?: number;

  /** System prompt */
  systemPrompt?: string;

  /** Messages in chat format (role, content pairs) */
  messages?: Array<{ role: string; content: string }>;
}

// ============================================================================
// Cloud Generation Result
// ============================================================================

/**
 * Result from cloud-based generation
 */
export interface CloudGenerationResult {
  /** Generated text */
  text: string;

  /** Tokens used (input) */
  inputTokens: number;

  /** Tokens used (output) */
  outputTokens: number;

  /** Total latency in milliseconds */
  latencyMs: number;

  /** Provider that handled the request */
  providerId: string;

  /** Model used */
  model: string;

  /** Estimated cost in USD (undefined if unknown) */
  estimatedCostUSD?: number;
}

// ============================================================================
// Routed Results
// ============================================================================

/**
 * Generation result enriched with routing metadata
 */
export interface RoutedGenerationResult {
  /** The generation result */
  generationResult: LLMGenerationResult;

  /** How the request was routed */
  routingDecision: RoutingDecision;
}

/**
 * Streaming result enriched with routing metadata
 */
export interface RoutedStreamingResult {
  /** The streaming result */
  streamingResult: LLMStreamingResult;

  /** How the request was routed */
  routingDecision: RoutingDecision;
}

// ============================================================================
// Default Policies
// ============================================================================

/** Default routing policy: hybrid manual with 0.7 confidence threshold */
export const DEFAULT_ROUTING_POLICY: CloudRoutingPolicy = {
  mode: RoutingMode.HybridManual,
  confidenceThreshold: 0.7,
  maxLocalLatencyMs: 0,
  costCapUSD: 0,
  preferStreaming: true,
};

/** Always run on-device, never use cloud */
export const LOCAL_ONLY_POLICY: CloudRoutingPolicy = {
  mode: RoutingMode.AlwaysLocal,
  confidenceThreshold: 0,
  maxLocalLatencyMs: 0,
  costCapUSD: 0,
  preferStreaming: false,
};

/** Always use cloud provider */
export const CLOUD_ONLY_POLICY: CloudRoutingPolicy = {
  mode: RoutingMode.AlwaysCloud,
  confidenceThreshold: 0,
  maxLocalLatencyMs: 0,
  costCapUSD: 0,
  preferStreaming: true,
};

/**
 * Create a hybrid auto routing policy with custom confidence threshold
 */
export function hybridAutoPolicy(confidenceThreshold = 0.7): CloudRoutingPolicy {
  return {
    mode: RoutingMode.HybridAuto,
    confidenceThreshold,
    maxLocalLatencyMs: 0,
    costCapUSD: 0,
    preferStreaming: true,
  };
}

/**
 * Create a hybrid manual routing policy with custom confidence threshold
 */
export function hybridManualPolicy(confidenceThreshold = 0.7): CloudRoutingPolicy {
  return {
    mode: RoutingMode.HybridManual,
    confidenceThreshold,
    maxLocalLatencyMs: 0,
    costCapUSD: 0,
    preferStreaming: true,
  };
}
