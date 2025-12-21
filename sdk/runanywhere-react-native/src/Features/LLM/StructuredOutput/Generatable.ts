/**
 * Generatable.ts
 *
 * Protocol for types that can be generated as structured output from LLMs
 *
 * Reference: sdk/runanywhere-swift/Sources/RunAnywhere/Features/LLM/StructuredOutput/Generatable.swift
 */

import type { GenerationHints } from './GenerationHints';

/**
 * Protocol for types that can be generated as structured output from LLMs
 * Matches iOS Generatable protocol
 */
export interface Generatable {
  /**
   * The JSON schema for this type
   */
  readonly jsonSchema: string;

  /**
   * Type-specific generation hints
   * Returns undefined for default behavior
   */
  readonly generationHints?: GenerationHints;
}

/**
 * Structured output configuration
 * Matches iOS StructuredOutputConfig
 */
export interface StructuredOutputConfig {
  /**
   * The type to generate
   */
  readonly type: Generatable;

  /**
   * Whether to include schema in prompt
   */
  readonly includeSchemaInPrompt: boolean;
}

/**
 * Creates a structured output configuration
 */
export function createStructuredOutputConfig(
  type: Generatable,
  includeSchemaInPrompt: boolean = true
): StructuredOutputConfig {
  return {
    type,
    includeSchemaInPrompt,
  };
}

/**
 * Helper to create a Generatable type from a JSON schema
 */
export function createGeneratable(
  jsonSchema: string,
  generationHints?: GenerationHints
): Generatable {
  return {
    jsonSchema,
    generationHints,
  };
}
