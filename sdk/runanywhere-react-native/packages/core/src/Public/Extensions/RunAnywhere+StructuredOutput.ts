/**
 * RunAnywhere+StructuredOutput.ts
 *
 * Structured output extension for JSON schema-guided generation.
 * Delegates to native StructuredOutputBridge.
 *
 * Reference: sdk/runanywhere-swift/Sources/RunAnywhere/Public/Extensions/LLM/RunAnywhere+StructuredOutput.swift
 */

import { requireNativeModule, isNativeModuleAvailable } from '@runanywhere/native';
import { SDKLogger } from '../../Foundation/Logging/Logger/SDKLogger';
import { generateStream } from './RunAnywhere+TextGeneration';
import type {
  StructuredOutputResult,
  StructuredOutputOptions,
  JSONSchema,
} from '../../types/StructuredOutputTypes';

const logger = new SDKLogger('RunAnywhere.StructuredOutput');

/**
 * Stream token for structured output streaming
 */
export interface StreamToken {
  text: string;
  timestamp: Date;
  tokenIndex: number;
}

/**
 * Structured output stream result
 */
export interface StructuredOutputStreamResult<T> {
  /** Async iterator for tokens */
  tokenStream: AsyncIterable<StreamToken>;

  /** Promise that resolves to final parsed result */
  result: Promise<T>;
}

/**
 * Generate structured output following a JSON schema
 * Matches Swift SDK: RunAnywhere.generateStructured(_:prompt:options:)
 *
 * @param prompt The prompt text
 * @param schema JSON schema defining the output structure
 * @param options Optional generation options
 * @returns Structured output result with parsed data
 */
export async function generateStructured<T = unknown>(
  prompt: string,
  schema: JSONSchema,
  options?: StructuredOutputOptions
): Promise<StructuredOutputResult<T>> {
  if (!isNativeModuleAvailable()) {
    throw new Error('Native module not available');
  }

  const native = requireNativeModule();

  try {
    logger.debug('Generating structured output...');

    const schemaJson = JSON.stringify(schema);
    const optionsJson = options ? JSON.stringify(options) : undefined;

    const resultJson = await native.generateStructured(prompt, schemaJson, optionsJson);

    // Check for error
    if (resultJson.includes('"error"')) {
      const parsed = JSON.parse(resultJson);
      if (parsed.error) {
        throw new Error(parsed.error);
      }
    }

    // Parse the JSON result
    const data = JSON.parse(resultJson) as T;

    return {
      data,
      raw: resultJson,
      success: true,
    };
  } catch (error) {
    const msg = error instanceof Error ? error.message : String(error);
    logger.error(`Structured output failed: ${msg}`);

    return {
      data: null as T,
      raw: '',
      success: false,
      error: msg,
    };
  }
}

/**
 * Generate structured output with streaming support
 * Matches Swift SDK: RunAnywhere.generateStructuredStream(_:content:options:)
 *
 * Returns both a token stream for real-time display and a promise for the final result.
 *
 * Example:
 * ```typescript
 * interface Quiz {
 *   question: string;
 *   options: string[];
 *   answer: number;
 * }
 *
 * const schema: JSONSchema = {
 *   type: 'object',
 *   properties: {
 *     question: { type: 'string' },
 *     options: { type: 'array', items: { type: 'string' } },
 *     answer: { type: 'integer' }
 *   },
 *   required: ['question', 'options', 'answer']
 * };
 *
 * const streaming = generateStructuredStream<Quiz>(prompt, schema);
 *
 * // Display tokens in real-time
 * for await (const token of streaming.tokenStream) {
 *   console.log(token.text);
 * }
 *
 * // Get parsed result
 * const quiz = await streaming.result;
 * ```
 */
export function generateStructuredStream<T = unknown>(
  prompt: string,
  schema: JSONSchema,
  options?: StructuredOutputOptions
): StructuredOutputStreamResult<T> {
  // Build system prompt for JSON generation
  const systemPrompt = buildStructuredOutputSystemPrompt(schema);
  const fullPrompt = `${systemPrompt}\n\n${prompt}`;

  let fullText = '';
  let resolveResult: ((value: T) => void) | null = null;
  let rejectResult: ((error: Error) => void) | null = null;

  // Create result promise
  const resultPromise = new Promise<T>((resolve, reject) => {
    resolveResult = resolve;
    rejectResult = reject;
  });

  // Create token stream generator
  async function* tokenGenerator(): AsyncGenerator<StreamToken> {
    try {
      const streamingResult = await generateStream(fullPrompt, {
        maxTokens: options?.maxTokens ?? 1500,
        temperature: options?.temperature ?? 0.7,
      });

      let tokenIndex = 0;
      for await (const token of streamingResult.stream) {
        fullText += token;

        yield {
          text: token,
          timestamp: new Date(),
          tokenIndex: tokenIndex++,
        };
      }

      // Parse the final result
      const parsed = parseStructuredOutput<T>(fullText);
      if (resolveResult) {
        resolveResult(parsed);
      }
    } catch (error) {
      const err = error instanceof Error ? error : new Error(String(error));
      if (rejectResult) {
        rejectResult(err);
      }
      throw err;
    }
  }

  return {
    tokenStream: tokenGenerator(),
    result: resultPromise,
  };
}

/**
 * Generate structured output with automatic type inference
 * @param prompt The prompt text
 * @param schema JSON schema defining the output structure
 * @returns The generated data matching the schema
 */
export async function generate<T = unknown>(
  prompt: string,
  schema: JSONSchema
): Promise<T> {
  const result = await generateStructured<T>(prompt, schema);

  if (!result.success) {
    throw new Error(result.error || 'Structured generation failed');
  }

  return result.data;
}

/**
 * Extract entities from text using structured output
 * @param text Source text to extract from
 * @param entitySchema Schema describing the entities to extract
 * @returns Extracted entities
 */
export async function extractEntities<T = unknown>(
  text: string,
  entitySchema: JSONSchema
): Promise<T> {
  const prompt = `Extract the following information from this text:

${text}

Return the extracted data as JSON matching the provided schema.`;

  return generate<T>(prompt, entitySchema);
}

/**
 * Classify text into categories using structured output
 * @param text Text to classify
 * @param categories List of possible categories
 * @returns Classification result
 */
export async function classify(
  text: string,
  categories: string[]
): Promise<{ category: string; confidence: number }> {
  const schema: JSONSchema = {
    type: 'object',
    properties: {
      category: {
        type: 'string',
        enum: categories,
        description: 'The category that best matches the text',
      },
      confidence: {
        type: 'number',
        minimum: 0,
        maximum: 1,
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

/**
 * Build system prompt for structured JSON output
 */
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

/**
 * Parse structured output from generated text
 */
function parseStructuredOutput<T>(text: string): T {
  // Try to extract JSON from the response
  let jsonStr = text.trim();

  // Remove markdown code blocks if present
  const codeBlockMatch = jsonStr.match(/```(?:json)?\s*([\s\S]*?)```/);
  if (codeBlockMatch && codeBlockMatch[1]) {
    jsonStr = codeBlockMatch[1].trim();
  }

  // Find JSON object boundaries
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
