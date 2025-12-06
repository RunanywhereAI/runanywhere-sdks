/**
 * WakeWordServiceProvider.ts
 *
 * Protocol for registering external Wake Word Detection implementations
 */

import type { WakeWordConfiguration } from '../../Models/Configuration/WakeWordConfiguration';
import type { WakeWordService } from './WakeWordService';

/**
 * Protocol for registering external Wake Word Detection implementations
 */
export interface WakeWordServiceProvider {
  /**
   * Create a Wake Word service for the given configuration
   */
  createWakeWordService(configuration: WakeWordConfiguration): Promise<WakeWordService>;

  /**
   * Check if this provider can handle the given model
   */
  canHandle(modelId: string | null | undefined): boolean;

  /**
   * Provider name for identification
   */
  readonly name: string;
}

