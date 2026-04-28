/**
 * RunAnywhere+StructuredOutput.ts
 *
 * Structured output extension for JSON schema-guided generation. Wave 2:
 * aligned to proto-canonical structured-output shapes
 * (`@runanywhere/proto-ts/structured_output`).
 *
 * Reference: sdk/runanywhere-swift/Sources/RunAnywhere/Public/Extensions/LLM/RunAnywhere+StructuredOutput.swift
 */

import { requireNativeModule, isNativeModuleAvailable } from '../../native';
import { SDKLogger } from '../../Foundation/Logging/Logger/SDKLogger';
import { generateStream } from './RunAnywhere+TextGeneration';
import {
  type JSONSchema,
  type StructuredOutputOptions,
  type StructuredOutputResult,
  type StructuredOutputValidation,
  JSONSchemaType,
} from '@runanywhere/proto-ts/structured_output';

const logger = new SDKLogger('RunAnywhere.StructuredOutput');

/** Stream token emitted during structured-output streaming. */
export interface StreamToken {
  text: string;
  timestamp: Date;
  tokenIndex: number;
}

/** Streaming structured-output handle. */
export interface StructuredOutputStreamResult<T> {
  tokenStream: AsyncIterable<StreamToken>;
  result: Promise<T>;
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
  const native = requireNativeModule();
  try {
    logger.debug('Generating structured output...');
    const schemaJson = JSON.stringify(schema);
    const optionsJson = options ? JSON.stringify(options) : undefined;
    const resultJson = await native.generateStructured(
      prompt,
      schemaJson,
      optionsJson
    );

    if (resultJson.includes('"error"')) {
      const parsed = JSON.parse(resultJson);
      if (parsed.error) {
        const validation: StructuredOutputValidation = {
          isValid: false,
          containsJson: false,
          errorMessage: parsed.error,
          rawOutput: resultJson,
        };
        return {
          parsedJson: new Uint8Array(0),
          validation,
          rawText: resultJson,
        };
      }
    }

    const data = JSON.parse(resultJson) as T;
    const validation: StructuredOutputValidation = {
      isValid: true,
      containsJson: true,
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
 * Matches Swift SDK: `RunAnywhere.generateStructuredStream(_:content:options:)`.
 */
export function generateStructuredStream<T = unknown>(
  prompt: string,
  schema: JSONSchema,
  options?: StructuredOutputOptions
): StructuredOutputStreamResult<T> {
  const systemPrompt = buildStructuredOutputSystemPrompt(schema);
  const fullPrompt = `${systemPrompt}\n\n${prompt}`;

  let fullText = '';
  let resolveResult: ((value: T) => void) | null = null;
  let rejectResult: ((error: Error) => void) | null = null;

  const resultPromise = new Promise<T>((resolve, reject) => {
    resolveResult = resolve;
    rejectResult = reject;
  });

  async function* tokenGenerator(): AsyncGenerator<StreamToken> {
    try {
      let tokenIndex = 0;
      for await (const token of generateStream(fullPrompt, {
        maxTokens: 1500,
        temperature: 0.7,
        topP: 1.0,
        topK: 0,
        repetitionPenalty: 1.0,
        stopSequences: [],
        streamingEnabled: true,
        preferredFramework: 0,
      })) {
        fullText += token.text;
        yield {
          text: token.text,
          timestamp: new Date(),
          tokenIndex: tokenIndex++,
        };
      }
      const parsed = parseStructuredOutput<T>(fullText);
      if (resolveResult) resolveResult(parsed);
    } catch (error) {
      const err = error instanceof Error ? error : new Error(String(error));
      if (rejectResult) rejectResult(err);
      throw err;
    }
  }

  return {
    tokenStream: tokenGenerator(),
    result: resultPromise,
  };
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
    type: JSONSchemaType.JSON_SCHEMA_TYPE_OBJECT,
    properties: {
      category: {
        type: JSONSchemaType.JSON_SCHEMA_TYPE_STRING,
        enumValues: categories,
        description: 'The category that best matches the text',
      },
      confidence: {
        type: JSONSchemaType.JSON_SCHEMA_TYPE_NUMBER,
        enumValues: [],
        description: 'Confidence score between 0 and 1',
      },
    },
    required: ['category', 'confidence'],
  };
  const prompt = `Classify the following text into one of these categories: ${categories.join(', ')}

Text: ${text}

Respond with the category and your confidence level.`;
  return generate<{ category: string; confidence: number }>(prompt, schema);
}

// ============================================================================
// Private Helpers
// ============================================================================

function buildStructuredOutputSystemPrompt(schema: JSONSchema): string {
  return `You are a JSON generator that outputs ONLY valid JSON without any additional text.
Start your response with { and end with }. Do not include any text before or after the JSON.
Do not include markdown code blocks or any formatting.

Expected JSON schema:
${JSON.stringify(schema, null, 2)}

Important:
- Output ONLY the JSON object, nothing else
- Ensure all required fields are present
- Use the exact field names from the schema
- Match the expected types (string, number, array, etc.)`;
}

function parseStructuredOutput<T>(text: string): T {
  let jsonStr = text.trim();
  const codeBlockMatch = jsonStr.match(/```(?:json)?\s*([\s\S]*?)```/);
  if (codeBlockMatch && codeBlockMatch[1]) {
    jsonStr = codeBlockMatch[1].trim();
  }
  const startIdx = jsonStr.indexOf('{');
  const endIdx = jsonStr.lastIndexOf('}');
  if (startIdx === -1 || endIdx === -1 || startIdx >= endIdx) {
    throw new Error('No valid JSON object found in the response');
  }
  jsonStr = jsonStr.substring(startIdx, endIdx + 1);
  try {
    return JSON.parse(jsonStr) as T;
  } catch (error) {
    throw new Error(`Failed to parse JSON: ${error}`);
  }
}
