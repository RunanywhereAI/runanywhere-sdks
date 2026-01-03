/**
 * RunAnywhere+StructuredOutput.ts
 *
 * Structured output extension.
 * Delegates to native commons.
 *
 * Reference: sdk/runanywhere-swift/Sources/RunAnywhere/Public/Extensions/LLM/RunAnywhere+StructuredOutput.swift
 */

import { requireNativeModule, isNativeModuleAvailable } from '@runanywhere/native';
import { SDKLogger } from '../../Foundation/Logging/Logger/SDKLogger';

const logger = new SDKLogger('RunAnywhere.StructuredOutput');

/**
 * Structured output result
 */
export interface StructuredOutputResult<T = unknown> {
  data: T;
  raw: string;
}

/**
 * Generate structured output (JSON mode)
 */
export async function generateStructured<T = unknown>(
  prompt: string,
  _schema?: Record<string, unknown>
): Promise<StructuredOutputResult<T>> {
  if (!isNativeModuleAvailable()) {
    throw new Error('Native module not available');
  }

  const native = requireNativeModule();

  try {
    // Use JSON mode
    const result = await native.generate(prompt, JSON.stringify({ jsonMode: true }));
    const parsed = JSON.parse(result);
    return {
      data: parsed as T,
      raw: result,
    };
  } catch (error) {
    const msg = error instanceof Error ? error.message : String(error);
    logger.error(`Structured output failed: ${msg}`);
    throw error;
  }
}
