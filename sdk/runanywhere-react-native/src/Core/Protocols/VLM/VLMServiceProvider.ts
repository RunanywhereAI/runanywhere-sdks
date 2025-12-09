/**
 * VLMServiceProvider.ts
 *
 * Protocol for registering external VLM implementations
 */

import type { VLMConfiguration } from '../../Models/Configuration/VLMConfiguration';
import type { VLMService } from './VLMService';

/**
 * Protocol for registering external VLM implementations
 */
export interface VLMServiceProvider {
  /**
   * Create a VLM service for the given configuration
   */
  createVLMService(configuration: VLMConfiguration): Promise<VLMService>;

  /**
   * Check if this provider can handle the given model
   */
  canHandle(modelId: string | null | undefined): boolean;

  /**
   * Provider name for identification
   */
  readonly name: string;
}

