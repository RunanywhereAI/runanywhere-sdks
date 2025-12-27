/**
 * SpeakerDiarizationServiceProvider.ts
 *
 * Protocol for registering external Speaker Diarization implementations
 */

import type { SpeakerDiarizationConfiguration } from '../../Models/Configuration/SpeakerDiarizationConfiguration';
import type { SpeakerDiarizationService } from './SpeakerDiarizationService';

/**
 * Protocol for registering external Speaker Diarization implementations
 */
export interface SpeakerDiarizationServiceProvider {
  /**
   * Create a Speaker Diarization service for the given configuration
   */
  createSpeakerDiarizationService(
    configuration: SpeakerDiarizationConfiguration
  ): Promise<SpeakerDiarizationService>;

  /**
   * Check if this provider can handle the given model
   */
  canHandle(modelId: string | null | undefined): boolean;

  /**
   * Provider name for identification
   */
  readonly name: string;
}
