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
import { SDKException } from '../../Foundation/SDKException';
import { generateStructuredStream } from './RunAnywhere+TextGeneration';

export type { StructuredOutputOptions, StructuredOutputResult };

export const StructuredOutput = {
  async generate<T = unknown>(
    prompt: string,
    schema: { jsonSchema: string; parse?: (text: string) => T },
    options?: Partial<LLMGenerationOptions>,
  ): Promise<T> {
    let result: StructuredOutputResult | undefined;
    for await (const event of generateStructuredStream(prompt, schema, options)) {
      result = event;
    }
    if (!result) {
      throw SDKException.generationFailed('Structured output did not return a result');
    }
    if (result.validation && !result.validation.isValid) {
      throw SDKException.generationFailed(
        result.validation.errorMessage ?? 'Structured output validation failed',
      );
    }
    const jsonText = new TextDecoder().decode(result.parsedJson);
    if (typeof schema.parse === 'function') {
      return schema.parse(jsonText);
    }
    try {
      return JSON.parse(jsonText) as T;
    } catch (error) {
      throw SDKException.generationFailed(
        `Structured output deserialization failed: ${(error as Error).message}`,
      );
    }
  },
};
