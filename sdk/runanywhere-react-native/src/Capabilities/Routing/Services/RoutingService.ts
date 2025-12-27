/**
 * RoutingService.ts
 *
 * Service for making routing decisions
 *
 * Reference: sdk/runanywhere-swift/Sources/RunAnywhere/Capabilities/Routing/Services/RoutingService.swift
 */

import type { RoutingDecision } from '../Models/RoutingDecision';
import type { RoutingReason } from '../Models/RoutingReason';
import { ExecutionTarget } from '../Models/ExecutionTarget';
import { LLMFramework } from '../../../Core/Models/Framework/LLMFramework';
import type { GenerationOptions } from '../../TextGeneration/Models/GenerationOptions';
import { CostCalculator } from './CostCalculator';
import { ResourceChecker } from './ResourceChecker';

/**
 * Service for making routing decisions
 */
export class RoutingService {
  private costCalculator: CostCalculator;
  private resourceChecker: ResourceChecker;

  constructor(costCalculator: CostCalculator, resourceChecker: ResourceChecker) {
    this.costCalculator = costCalculator;
    this.resourceChecker = resourceChecker;
  }

  /**
   * Determine the optimal routing for a generation request
   * FORCE LOCAL ONLY - Always route to on-device execution
   */
  public async determineRouting(
    prompt: string,
    context: any | null,
    options: GenerationOptions
  ): Promise<RoutingDecision> {
    // FORCE ON-DEVICE ONLY - ignore all other logic
    return {
      type: 'onDevice',
      framework: this.selectBestFramework(options),
      reason: { type: 'privacySensitive' }, // Use privacy as the reason for forcing local
    };
  }

  /**
   * Select best framework
   */
  private selectBestFramework(options: GenerationOptions): LLMFramework | null {
    // Prefer user's framework choice if available
    if (options.preferredFramework) {
      return options.preferredFramework;
    }

    // Default to CoreML on Apple platforms
    return LLMFramework.CoreML;
  }

  /**
   * Check if service is healthy
   */
  public isHealthy(): boolean {
    return true;
  }
}

// CostCalculator and ResourceChecker are exported from separate files
