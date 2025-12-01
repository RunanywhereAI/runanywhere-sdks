/**
 * TTSService.ts
 *
 * Protocol for TTS service implementations
 */

import type { TTSConfiguration } from '../../Models/Configuration/TTSConfiguration';
import type { TTSResult } from '../../Models/TTS/TTSResult';

/**
 * Protocol for TTS service implementations
 */
export interface TTSService {
  /**
   * Initialize the TTS service with model path
   */
  initialize(modelPath?: string | null): Promise<void>;

  /**
   * Synthesize text to speech
   */
  synthesize(text: string, configuration?: TTSConfiguration): Promise<TTSResult>;

  /**
   * Get available voices
   */
  getAvailableVoices?(): Promise<string[]>;

  /**
   * Check if service is ready
   */
  readonly isReady: boolean;

  /**
   * Current model identifier
   */
  readonly currentModel: string | null;

  /**
   * Clean up and release resources
   */
  cleanup(): Promise<void>;
}

