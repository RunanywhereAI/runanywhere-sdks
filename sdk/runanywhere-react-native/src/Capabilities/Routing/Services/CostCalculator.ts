/**
 * CostCalculator.ts
 *
 * Cost calculator for routing decisions
 */

import type { GenerationOptions } from '../../TextGeneration/Models/GenerationOptions';

/**
 * Cost calculator for routing decisions
 */
export class CostCalculator {
  /**
   * Calculate on-device cost
   */
  public async calculateOnDeviceCost(
    _tokenCount: number,
    _options: GenerationOptions
  ): Promise<number> {
    // On-device is essentially free (just battery/processing)
    return 0.0;
  }

  /**
   * Calculate cloud cost
   */
  public async calculateCloudCost(
    tokenCount: number,
    _options: GenerationOptions
  ): Promise<number> {
    // Simple cost model: $0.001 per token
    return tokenCount * 0.001;
  }
}
