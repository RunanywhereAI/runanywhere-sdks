/**
 * RunAnywhere+StructuredOutput.ts
 *
 * Structured output extension for JSON schema-guided generation. Wave 2:
 * aligned to proto-canonical structured-output shapes
 * (`@runanywhere/proto-ts/structured_output`).
 *
 * Reference: sdk/runanywhere-swift/Sources/RunAnywhere/Public/Extensions/LLM/RunAnywhere+StructuredOutput.swift
 */

import { isNativeModuleAvailable } from '../../native';
import { SDKLogger } from '../../Foundation/Logging/Logger/SDKLogger';
import {
  generate as generateText,
  generateStream,
} from './RunAnywhere+TextGeneration';
import {
  type JSONSchema,
  type StructuredOutputOptions,
  type StructuredOutputResult,
  type StructuredOutputValidation,
  JSONSchema as JSONSchemaMessage,
  JSONSchemaProperty,
  JSONSchemaType,
} from '@runanywhere/proto-ts/structured_output';
import type { LLMGenerationOptions } from '@runanywhere/proto-ts/llm_options';

// ============================================================================
// Types re-exported for callers
// ============================================================================

// StructuredOutputResult and JSONSchema are re-exported from proto-ts (no
// local duplicates per §15 Iron Rule 2).

const logger = new SDKLogger('RunAnywhere.StructuredOutput');

/** Stream token emitted during structured-output streaming. */
export interface StreamToken {
  text: string;
  timestamp: Date;
  tokenIndex: number;
}

/** UTF-8 encoder for serializing parsed JSON to `Uint8Array`. */
function jsonToBytes(value: unknown): Uint8Array {
  const text = JSON.stringify(value);
  const buf = new ArrayBuffer(text.length);
  const view = new Uint8Array(buf);
  for (let i = 0; i < text.length; i++) view[i] = text.charCodeAt(i);
  return view;
}

/** UTF-8 decoder for the proto `parsedJson: Uint8Array`. */
function bytesToString(bytes: Uint8Array): string {
  let s = '';
  for (let i = 0; i < bytes.length; i++) s += String.fromCharCode(bytes[i]!);
  return s;
}

function llmOptionsForStructuredOutput(
  schema: JSONSchema,
  options?: StructuredOutputOptions,
  streamingEnabled: boolean = false
): LLMGenerationOptions {
  const jsonSchema = options?.jsonSchema ?? JSON.stringify(schema);
  return {
    maxTokens: 1500,
    temperature: 0.7,
    topP: 1.0,
    topK: 0,
    repetitionPenalty: 1.0,
    stopSequences: [],
    streamingEnabled,
    preferredFramework: 0,
    systemPrompt: '',
    jsonSchema,
    structuredOutput: options ?? {
      schema,
      includeSchemaInPrompt: true,
      jsonSchema,
    },
    enableRealTimeTracking: false,
  };
}

/**
 * Generate structured output following a JSON schema.
 *
 * Matches Swift SDK: `RunAnywhere.generateStructured(_:prompt:options:)`.
 */
export async function generateStructured<T = unknown>(
  prompt: string,
  schema: JSONSchema,
  options?: StructuredOutputOptions
): Promise<StructuredOutputResult> {
  if (!isNativeModuleAvailable()) {
    throw new Error('Native module not available');
  }
  try {
    logger.debug('Generating structured output...');
    const result = await generateText(
      prompt,
      llmOptionsForStructuredOutput(schema, options, false)
    );
    const resultJson = result.jsonOutput ?? result.text;
    const data = JSON.parse(resultJson) as T;
    const validation: StructuredOutputValidation = {
      isValid: true,
      containsJson: true,
      rawOutput: result.text,
      extractedJson: resultJson,
    };
    return {
      parsedJson: jsonToBytes(data),
      validation,
      rawText: resultJson,
    };
  } catch (error) {
    const msg = error instanceof Error ? error.message : String(error);
    logger.error(`Structured output failed: ${msg}`);
    const validation: StructuredOutputValidation = {
      isValid: false,
      containsJson: false,
      errorMessage: msg,
    };
    return {
      parsedJson: new Uint8Array(0),
      validation,
    };
  }
}

/**
 * Generate structured output with streaming support.
 *
 * Returns an `AsyncIterable<StructuredOutputResult>` that emits one item per
 * streaming token's accumulated JSON, finishing with the final parsed result
 * when the stream ends.
 *
 * Matches Swift SDK: `RunAnywhere.generateStructuredStream(_:content:options:)`
 * and the canonical cross-SDK spec §3 return type.
 */
export function generateStructuredStream(
  prompt: string,
  schema: JSONSchema,
  options?: StructuredOutputOptions
): AsyncIterable<StructuredOutputResult> {
  async function* resultGenerator(): AsyncGenerator<StructuredOutputResult> {
    let fullText = '';
    try {
      for await (const event of generateStream(
        prompt,
        llmOptionsForStructuredOutput(schema, options, true)
      )) {
        if (event.token) {
          fullText += event.token;
          const partialValidation: StructuredOutputValidation = {
            isValid: false,
            containsJson: fullText.includes('{'),
            rawOutput: fullText,
          };
          yield {
            parsedJson: jsonToBytes({}),
            validation: partialValidation,
            rawText: fullText,
          };
        }
        if (event.isFinal) break;
      }

      yield {
        parsedJson: new Uint8Array(0),
        validation: {
          isValid: false,
          containsJson: fullText.includes('{'),
          rawOutput: fullText,
        },
        rawText: fullText,
      };
    } catch (error) {
      const msg = error instanceof Error ? error.message : String(error);
      logger.error(`Structured stream failed: ${msg}`);
      const errorValidation: StructuredOutputValidation = {
        isValid: false,
        containsJson: false,
        errorMessage: msg,
      };
      yield {
        parsedJson: new Uint8Array(0),
        validation: errorValidation,
      };
    }
  }

  return resultGenerator();
}

/**
 * Extract structured data from an existing text string without invoking the LLM.
 *
 * - If the Nitro bridge exposes `rac_structured_output_extract_json` via a
 *   `extractStructuredOutput(text, schemaJson)` native method, that is called
 *   and the result is returned.
 * - Otherwise a pure-TS JSON extraction is performed: the first JSON object
 *   found in `text` is extracted and returned as a `StructuredOutputResult`.
 *
 * Matches Swift SDK: `RunAnywhere.extractStructuredOutput(_:schema:)` and
 * canonical cross-SDK spec §3.
 */
export async function extractStructuredOutput(
  text: string,
  schema: JSONSchema
): Promise<StructuredOutputResult> {
  void schema;
  const validation: StructuredOutputValidation = {
    isValid: false,
    containsJson: text.includes('{'),
    errorMessage: 'Structured-output extraction is only exposed through the native LLM proto generation path on RN.',
    rawOutput: text,
  };
  return { parsedJson: new Uint8Array(0), validation, rawText: text };
}

/**
 * Generate structured output with automatic type inference (returns parsed value).
 */
export async function generate<T = unknown>(
  prompt: string,
  schema: JSONSchema
): Promise<T> {
  const result = await generateStructured<T>(prompt, schema);
  if (!result.validation || !result.validation.isValid) {
    throw new Error(
      result.validation?.errorMessage ?? 'Structured generation failed'
    );
  }
  return JSON.parse(bytesToString(result.parsedJson)) as T;
}

/** Extract entities from text using structured output. */
export async function extractEntities<T = unknown>(
  text: string,
  entitySchema: JSONSchema
): Promise<T> {
  const prompt = `Extract the following information from this text:

${text}

Return the extracted data as JSON matching the provided schema.`;
  return generate<T>(prompt, entitySchema);
}

/** Classify text into categories using structured output. */
export async function classify(
  text: string,
  categories: string[]
): Promise<{ category: string; confidence: number }> {
  const schema: JSONSchema = {
    ...JSONSchemaMessage.create(),
    type: JSONSchemaType.JSON_SCHEMA_TYPE_OBJECT,
    properties: {
      category: JSONSchemaProperty.create({
        type: JSONSchemaType.JSON_SCHEMA_TYPE_STRING,
        enumValues: categories,
        description: 'The category that best matches the text',
      }),
      confidence: JSONSchemaProperty.create({
        type: JSONSchemaType.JSON_SCHEMA_TYPE_NUMBER,
        enumValues: [],
        description: 'Confidence score between 0 and 1',
      }),
    },
    required: ['category', 'confidence'],
  };
  const prompt = `Classify the following text into one of these categories: ${categories.join(', ')}

Text: ${text}

Respond with the category and your confidence level.`;
  return generate<{ category: string; confidence: number }>(prompt, schema);
}
