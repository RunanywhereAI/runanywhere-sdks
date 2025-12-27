/**
 * LLMService.ts
 *
 * Protocol for LLM service implementations
 */

import type { GenerationResult } from '../../../Capabilities/TextGeneration/Models/GenerationResult';
import type { GenerationOptions } from '../../../Capabilities/TextGeneration/Models/GenerationOptions';

/**
 * Protocol for LLM service implementations
 */
export interface LLMService {
  /**
   * Initialize the LLM service with model path
   */
  initialize(modelPath?: string | null): Promise<void>;

  /**
   * Generate text from prompt
   */
  generate(prompt: string, options?: GenerationOptions): Promise<GenerationResult>;

  /**
   * Stream generate text from prompt
   */
  generateStream?(
    prompt: string,
    options?: GenerationOptions,
    onToken?: (token: string) => void
  ): Promise<GenerationResult>;

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
