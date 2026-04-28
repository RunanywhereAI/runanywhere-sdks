/**
 * RunAnywhere+TextGeneration.ts
 *
 * Text generation namespace — mirrors Swift's `RunAnywhere+TextGeneration.swift`.
 * Provides `RunAnywhere.textGeneration.*` capability surface (generate / generateStream / chat).
 */

import type { LLMGenerationOptions, LLMGenerationResult } from '@runanywhere/proto-ts/llm_options';
import type { LLMStreamingResult } from '../../types/index';
import { chat, generate, generateStream } from './RunAnywhere+Convenience';

export type { LLMGenerationOptions, LLMGenerationResult };
export type { LLMStreamingResult };

export const TextGeneration = {
  async generate(options: Partial<LLMGenerationOptions>): Promise<LLMGenerationResult> {
    const prompt = (options as { prompt?: string }).prompt ?? '';
    return generate(prompt, options);
  },

  async generateStream(options: Partial<LLMGenerationOptions>): Promise<LLMStreamingResult> {
    const prompt = (options as { prompt?: string }).prompt ?? '';
    return generateStream(prompt, options);
  },

  async chat(prompt: string, options?: Partial<LLMGenerationOptions>): Promise<string> {
    return chat(prompt, options);
  },
};
