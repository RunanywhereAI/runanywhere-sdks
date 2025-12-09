/**
 * WakeWordService.ts
 *
 * Protocol for Wake Word Detection service implementations
 */

/**
 * Protocol for Wake Word Detection service implementations
 */
export interface WakeWordService {
  /**
   * Initialize the service
   */
  initialize(modelPath?: string | null): Promise<void>;

  /**
   * Process audio for wake word detection
   */
  processAudio(
    audioData: string | ArrayBuffer,
    sampleRate?: number,
    onWakeWord?: (word: string, confidence: number) => void
  ): Promise<{ detected: boolean; word?: string; confidence?: number }>;

  /**
   * Check if service is ready
   */
  readonly isReady: boolean;

  /**
   * Clean up and release resources
   */
  cleanup(): Promise<void>;
}

