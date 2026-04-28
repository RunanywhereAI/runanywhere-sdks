/**
 * RunAnywhere+StructuredOutput.ts
 *
 * Structured output namespace — mirrors Swift's `RunAnywhere+StructuredOutput.swift`.
 * Provides schema-driven JSON generation via `RunAnywhere.structuredOutput.*`.
 */

import type { LLMGenerationOptions } from '@runanywhere/proto-ts/llm_options';
import type {
  StructuredOutputOptions,
  StructuredOutputResult,
} from '@runanywhere/proto-ts/structured_output';
import { generateStructured } from './RunAnywhere+Convenience';

export type { StructuredOutputOptions, StructuredOutputResult };

export const StructuredOutput = {
  async generate<T = unknown>(
    prompt: string,
    schema: { jsonSchema: string; parse?: (text: string) => T },
    options?: Partial<LLMGenerationOptions>,
  ): Promise<T> {
    return generateStructured<T>(prompt, schema, options);
  },
};
