/**
 * RoutingTelemetry.ts
 *
 * Telemetry events for routing decisions and cloud usage.
 * Mirrors Swift RoutingTelemetry.swift exactly.
 */

import type { HandoffReason, RoutingMode, CloudExecutionTarget } from './CloudTypes';

// ============================================================================
// Routing Event
// ============================================================================

/**
 * Event emitted when a routing decision is made.
 */
export interface RoutingEvent {
  type: 'routing.decision';
  routingMode: RoutingMode;
  executionTarget: CloudExecutionTarget;
  confidence: number;
  cloudHandoffTriggered: boolean;
  handoffReason: HandoffReason;
  cloudProviderId?: string;
  cloudModel?: string;
  latencyMs: number;
  estimatedCostUSD?: number;
  timestamp: number;
}

// ============================================================================
// Cloud Cost Event
// ============================================================================

/**
 * Event emitted when a cloud request incurs cost.
 */
export interface CloudCostEvent {
  type: 'cloud.cost';
  providerId: string;
  inputTokens: number;
  outputTokens: number;
  costUSD: number;
  cumulativeTotalUSD: number;
  timestamp: number;
}

// ============================================================================
// Provider Failover Event
// ============================================================================

/**
 * Event emitted when a provider failover occurs.
 */
export interface ProviderFailoverEvent {
  type: 'cloud.provider_failover';
  failedProviderId: string;
  fallbackProviderId?: string;
  failureReason: string;
  timestamp: number;
}

// ============================================================================
// Latency Timeout Event
// ============================================================================

/**
 * Event emitted when a latency timeout triggers cloud fallback.
 */
export interface LatencyTimeoutEvent {
  type: 'routing.latency_timeout';
  maxLatencyMs: number;
  actualLatencyMs: number;
  timestamp: number;
}

// ============================================================================
// Union Type
// ============================================================================

/**
 * Union of all cloud telemetry event types.
 */
export type CloudTelemetryEvent =
  | RoutingEvent
  | CloudCostEvent
  | ProviderFailoverEvent
  | LatencyTimeoutEvent;
