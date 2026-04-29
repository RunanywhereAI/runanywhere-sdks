/**
 * RunAnywhere+TextGeneration.ts
 *
 * Text generation namespace — mirrors Swift's `RunAnywhere+TextGeneration.swift`.
 * Provides `RunAnywhere.textGeneration.*` capability surface (generate / generateStream / chat).
 * Also exposes the canonical §3 verbs `generateStructuredStream` and
 * `extractStructuredOutput` as flat top-level functions for use by RunAnywhere.ts.
 */

import type { LLMGenerationOptions, LLMGenerationResult } from '@runanywhere/proto-ts/llm_options';
import type { StructuredOutputResult } from '@runanywhere/proto-ts/structured_output';
import type { LLMStreamingResult } from '../../types/index';
import { chat, generate, generateStream } from './RunAnywhere+Convenience';
import { ExtensionPoint } from '../../Infrastructure/ExtensionPoint';
import { SDKException } from '../../Foundation/SDKException';

export type { LLMGenerationOptions, LLMGenerationResult };
export type { LLMStreamingResult };
export type { StructuredOutputResult };

// ---------------------------------------------------------------------------
// Schema type accepted by the canonical structured-output verbs.
// ---------------------------------------------------------------------------

/** Minimal JSON Schema descriptor accepted by structured-output methods. */
export interface JSONSchemaDescriptor {
  jsonSchema: string;
  parse?: (text: string) => unknown;
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/** Wrap raw model text into a `StructuredOutputResult`. */
function toStructuredOutputResult(text: string, parsed: unknown): StructuredOutputResult {
  const jsonBytes = new TextEncoder().encode(JSON.stringify(parsed));
  return {
    parsedJson: jsonBytes,
    rawText: text,
    validation: {
      isValid: true,
      containsJson: true,
    },
  };
}

/** Best-effort JSON extractor — strips markdown fences and returns parsed value. */
function extractJsonFromText(text: string): unknown {
  const cleaned = text.trim()
    .replace(/^```(?:json)?\s*/i, '')
    .replace(/```\s*$/i, '');
  return JSON.parse(cleaned);
}

// ---------------------------------------------------------------------------
// §3 `generateStructuredStream` — canonical flat verb
// ---------------------------------------------------------------------------

/**
 * Streaming structured output (§3 `generateStructuredStream`).
 *
 * Delegates to the LLM provider's native `generateStructuredStream` if available;
 * otherwise adapts `generateStream` by buffering and JSON-parsing the complete
 * token stream before yielding a single `StructuredOutputResult` event.
 */
export async function* generateStructuredStream(
  prompt: string,
  schema: JSONSchemaDescriptor,
  options?: Partial<LLMGenerationOptions>,
): AsyncIterable<StructuredOutputResult> {
  const llm = ExtensionPoint.getProvider('llm') as {
    generateStructuredStream?: (
      prompt: string,
      schema: { jsonSchema: string },
      options?: Partial<LLMGenerationOptions>,
    ) => AsyncIterable<StructuredOutputResult>;
  } | undefined;

  if (typeof llm?.generateStructuredStream === 'function') {
    yield* llm.generateStructuredStream(prompt, schema, options);
    return;
  }

  // Fallback: stream the raw text, collect it, then parse once at the end.
  const fullPrompt =
    'Respond ONLY with JSON matching this JSON Schema. ' +
    'Do not include explanations or markdown.\n' +
    `Schema:\n${schema.jsonSchema}\n\nPrompt:\n${prompt}`;

  const streaming = await generateStream(fullPrompt, options);
  let accumulated = '';
  for await (const chunk of streaming.stream) {
    // The LLM stream emits string tokens directly.
    if (typeof chunk === 'string') {
      accumulated += chunk;
    } else if (chunk != null && typeof (chunk as unknown as { text?: string }).text === 'string') {
      accumulated += (chunk as unknown as { text: string }).text;
    }
  }

  const text = accumulated.trim();
  try {
    const parsed = typeof schema.parse === 'function'
      ? schema.parse(text)
      : extractJsonFromText(text);
    yield toStructuredOutputResult(text, parsed);
  } catch (err) {
    throw SDKException.generationFailed(
      `generateStructuredStream JSON parse failed: ${(err as Error).message}; raw: ${text.slice(0, 200)}`,
    );
  }
}

// ---------------------------------------------------------------------------
// §3 `extractStructuredOutput` — canonical flat verb (pure TS)
// ---------------------------------------------------------------------------

/**
 * Extract and validate structured output from already-generated text (§3).
 *
 * Pure TypeScript: attempts to locate and parse a JSON object from `text`
 * that matches the provided schema. Never calls the LLM backend.
 */
export function extractStructuredOutput(
  text: string,
  schema: JSONSchemaDescriptor,
): StructuredOutputResult {
  if (typeof schema.parse === 'function') {
    try {
      const parsed = schema.parse(text);
      return toStructuredOutputResult(text, parsed);
    } catch (parseErr) {
      const jsonBytes = new TextEncoder().encode('null');
      return {
        parsedJson: jsonBytes,
        rawText: text,
        validation: {
          isValid: false,
          containsJson: false,
          errorMessage: (parseErr as Error).message,
          rawOutput: text,
        },
      };
    }
  }

  // Try a sequence of increasingly lenient extractions:
  // 1. The entire text as JSON
  // 2. First JSON object found via brace-matching
  // 3. Markdown-fence stripped text
  const candidates: string[] = [
    text.trim(),
    text.trim().replace(/^```(?:json)?\s*/i, '').replace(/```\s*$/i, '').trim(),
  ];

  // Try to extract first {...} or [...] block
  const jsonMatch = text.match(/(\{[\s\S]*\}|\[[\s\S]*\])/);
  if (jsonMatch) {
    candidates.push(jsonMatch[1]);
  }

  for (const candidate of candidates) {
    try {
      const parsed = JSON.parse(candidate);
      return toStructuredOutputResult(text, parsed);
    } catch {
      // Try next candidate
    }
  }

  // All extractions failed — return a validation-failed result.
  const jsonBytes = new TextEncoder().encode('null');
  return {
    parsedJson: jsonBytes,
    rawText: text,
    validation: {
      isValid: false,
      containsJson: false,
      errorMessage: 'No valid JSON found in text',
      rawOutput: text,
    },
  };
}

// ---------------------------------------------------------------------------
// TextGeneration namespace object
// ---------------------------------------------------------------------------

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

  generateStructuredStream,
  extractStructuredOutput,
};
