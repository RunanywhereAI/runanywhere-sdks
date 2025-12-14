/**
 * SpeakerDiarizationService.ts
 *
 * Protocol for Speaker Diarization service implementations
 */

import type { SpeakerDiarizationResult } from '../../Models/SpeakerDiarization/SpeakerDiarizationResult';

/**
 * Protocol for Speaker Diarization service implementations
 */
export interface SpeakerDiarizationService {
  /**
   * Initialize the service
   */
  initialize(modelPath?: string | null): Promise<void>;

  /**
   * Process audio for speaker diarization
   */
  processAudio(audioData: string | ArrayBuffer, sampleRate?: number): Promise<SpeakerDiarizationResult>;

  /**
   * Check if service is ready
   */
  readonly isReady: boolean;

  /**
   * Clean up and release resources
   */
  cleanup(): Promise<void>;
}

