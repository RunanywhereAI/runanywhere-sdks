/**
 * RoutingDecision.ts
 *
 * Routing decision for a request
 *
 * Reference: sdk/runanywhere-swift/Sources/RunAnywhere/Capabilities/Routing/Models/RoutingDecision.swift
 */

import { ExecutionTarget } from './ExecutionTarget';
import type { LLMFramework } from '../../../Core/Models/Framework/LLMFramework';
import type { RoutingReason } from './RoutingReason';

/**
 * Routing decision for a request
 */
export type RoutingDecision =
  | {
      type: 'onDevice';
      framework: LLMFramework | null;
      reason: RoutingReason;
    }
  | {
      type: 'cloud';
      provider: string | null;
      reason: RoutingReason;
    }
  | {
      type: 'hybrid';
      devicePortion: number;
      framework: LLMFramework | null;
      reason: RoutingReason;
    };

/**
 * Get execution target from routing decision
 */
export function getExecutionTarget(decision: RoutingDecision): ExecutionTarget {
  switch (decision.type) {
    case 'onDevice':
      return ExecutionTarget.OnDevice;
    case 'cloud':
      return ExecutionTarget.Cloud;
    case 'hybrid':
      return ExecutionTarget.Hybrid;
  }
}

/**
 * Get selected framework from routing decision
 */
export function getSelectedFramework(
  decision: RoutingDecision
): LLMFramework | null {
  switch (decision.type) {
    case 'onDevice':
      return decision.framework;
    case 'hybrid':
      return decision.framework;
    case 'cloud':
      return null;
  }
}
