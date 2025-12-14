/**
 * TTSServiceProvider.ts
 *
 * Protocol for registering external TTS implementations
 */

import type { TTSConfiguration } from '../../Models/Configuration/TTSConfiguration';
import type { TTSService } from './TTSService';

/**
 * Protocol for registering external TTS implementations
 */
export interface TTSServiceProvider {
  /**
   * Create a TTS service for the given configuration
   */
  createTTSService(configuration: TTSConfiguration): Promise<TTSService>;

  /**
   * Check if this provider can handle the given model
   */
  canHandle(modelId: string | null | undefined): boolean;

  /**
   * Provider name for identification
   */
  readonly name: string;

  /**
   * Provider version
   */
  readonly version: string;
}

