/**
 * RoutingReason.ts
 *
 * Reason for routing decision
 *
 * Reference: sdk/runanywhere-swift/Sources/RunAnywhere/Capabilities/Routing/Models/RoutingReason.swift
 */

import { ExecutionTarget } from './ExecutionTarget';
import { LLMFramework } from '../../../Core/Models/Framework/LLMFramework';

/**
 * Routing policy
 */
export enum RoutingPolicy {
  PrivacyFirst = 'privacyFirst',
  CostOptimized = 'costOptimized',
  PerformanceOptimized = 'performanceOptimized',
  Balanced = 'balanced',
}

/**
 * Reason for routing decision
 */
export type RoutingReason =
  | { type: 'privacySensitive' }
  | { type: 'insufficientResources'; resource: string }
  | { type: 'lowComplexity' }
  | { type: 'highComplexity' }
  | { type: 'policyDriven'; policy: RoutingPolicy }
  | { type: 'userPreference'; target: ExecutionTarget }
  | { type: 'frameworkUnavailable'; framework: LLMFramework }
  | { type: 'costOptimization'; savedAmount: number }
  | { type: 'latencyOptimization'; expectedMs: number }
  | { type: 'modelNotAvailable' };

/**
 * Get human-readable description of routing reason
 */
export function getRoutingReasonDescription(reason: RoutingReason): string {
  switch (reason.type) {
    case 'privacySensitive':
      return 'Privacy-sensitive content detected';
    case 'insufficientResources':
      return `Insufficient ${reason.resource}`;
    case 'lowComplexity':
      return 'Low complexity task suitable for device';
    case 'highComplexity':
      return 'High complexity task requiring cloud';
    case 'policyDriven':
      return `Policy-driven decision: ${reason.policy}`;
    case 'userPreference':
      return `User preference: ${reason.target}`;
    case 'frameworkUnavailable':
      return `${reason.framework} not available`;
    case 'costOptimization':
      return `Cost optimization: saving $${reason.savedAmount.toFixed(2)}`;
    case 'latencyOptimization':
      return `Latency optimization: ${Math.floor(reason.expectedMs)}ms expected`;
    case 'modelNotAvailable':
      return 'Model not available on device';
  }
}

