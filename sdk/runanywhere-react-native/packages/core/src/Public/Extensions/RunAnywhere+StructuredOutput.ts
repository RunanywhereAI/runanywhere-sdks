/**
 * RunAnywhere+StructuredOutput.ts
 *
 * Structured output generation extension for RunAnywhere SDK.
 * Matches iOS: RunAnywhere+StructuredOutput.swift
 */

import type { GenerationOptions } from '../../types';
import { StructuredOutputHandler } from '../../Capabilities/StructuredOutput/Services/StructuredOutputHandler';
import type { GeneratableType } from '../../Capabilities/StructuredOutput/Services/StructuredOutputHandler';
import * as TextGeneration from './RunAnywhere+TextGeneration';

// ============================================================================
// Structured Output Extension
// ============================================================================

/**
 * Generate structured output that conforms to a type schema
 *
 * Matches iOS: `RunAnywhere.generateStructured(_:prompt:options:)`
 */
export async function generateStructured<T>(
  schema: GeneratableType,
  prompt: string,
  options?: GenerationOptions
): Promise<T> {
  const handler = new StructuredOutputHandler();

  const systemPrompt = handler.getSystemPrompt(schema);
  const userPrompt = handler.buildUserPrompt(schema, prompt);

  const effectiveOptions: GenerationOptions = {
    ...options,
    maxTokens: options?.maxTokens ?? 1500,
    temperature: options?.temperature ?? 0.7,
    systemPrompt: systemPrompt,
  };

  const result = await TextGeneration.generate(userPrompt, effectiveOptions);
  return handler.parseStructuredOutput<T>(result.text, schema);
}

/**
 * Extract JSON from potentially mixed text
 * @internal
 */
export function extractJSON(text: string): string {
  const trimmed = text.trim();

  const startIndex = trimmed.indexOf('{');
  if (startIndex !== -1) {
    const endIndex = findMatchingBrace(trimmed, startIndex);
    if (endIndex !== null) {
      return trimmed.substring(startIndex, endIndex + 1);
    }
  }

  const arrayStartIndex = trimmed.indexOf('[');
  if (arrayStartIndex !== -1) {
    const arrayEndIndex = findMatchingBracket(trimmed, arrayStartIndex);
    if (arrayEndIndex !== null) {
      return trimmed.substring(arrayStartIndex, arrayEndIndex + 1);
    }
  }

  if (trimmed.startsWith('{') || trimmed.startsWith('[')) {
    return trimmed;
  }

  throw new Error('No valid JSON found in the response');
}

function findMatchingBrace(text: string, startIndex: number): number | null {
  let depth = 0;
  let inString = false;
  let escaped = false;

  for (let i = startIndex; i < text.length; i++) {
    const char = text[i];

    if (escaped) {
      escaped = false;
      continue;
    }

    if (char === '\\') {
      escaped = true;
      continue;
    }

    if (char === '"') {
      inString = !inString;
      continue;
    }

    if (inString) continue;

    if (char === '{') {
      depth++;
    } else if (char === '}') {
      depth--;
      if (depth === 0) {
        return i;
      }
    }
  }

  return null;
}

function findMatchingBracket(text: string, startIndex: number): number | null {
  let depth = 0;
  let inString = false;
  let escaped = false;

  for (let i = startIndex; i < text.length; i++) {
    const char = text[i];

    if (escaped) {
      escaped = false;
      continue;
    }

    if (char === '\\') {
      escaped = true;
      continue;
    }

    if (char === '"') {
      inString = !inString;
      continue;
    }

    if (inString) continue;

    if (char === '[') {
      depth++;
    } else if (char === ']') {
      depth--;
      if (depth === 0) {
        return i;
      }
    }
  }

  return null;
}
