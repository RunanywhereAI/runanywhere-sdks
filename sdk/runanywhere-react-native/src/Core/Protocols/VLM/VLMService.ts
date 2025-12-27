/**
 * VLMService.ts
 *
 * Protocol for VLM service implementations
 */

import type { VLMResult } from '../../Models/VLM/VLMResult';

/**
 * Protocol for VLM service implementations
 */
export interface VLMService {
  /**
   * Initialize the service
   */
  initialize(modelPath?: string | null): Promise<void>;

  /**
   * Process image and text for vision-language understanding
   */
  process(
    imageData: string | ArrayBuffer,
    textPrompt: string,
    options?: {
      maxTokens?: number;
      temperature?: number;
    }
  ): Promise<VLMResult>;

  /**
   * Get current model identifier
   */
  readonly currentModel: string | null;

  /**
   * Check if service is ready
   */
  readonly isReady: boolean;

  /**
   * Clean up and release resources
   */
  cleanup(): Promise<void>;
}
