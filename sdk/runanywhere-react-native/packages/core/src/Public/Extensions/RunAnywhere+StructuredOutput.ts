/**
 * RunAnywhere+StructuredOutput.ts
 *
 * Structured output extension for JSON schema-guided generation. Wave 2:
 * aligned to proto-canonical structured-output shapes
 * (`@runanywhere/proto-ts/structured_output`).
 *
 * Reference: sdk/runanywhere-swift/Sources/RunAnywhere/Public/Extensions/LLM/RunAnywhere+StructuredOutput.swift
 */

import {
  isNativeModuleAvailable,
  requireNativeModule,
} from '../../native';
import { SDKLogger } from '../../Foundation/Logging/Logger/SDKLogger';
import { SDKException } from '../../Foundation/ErrorTypes/SDKException';
import {
  generate as generateText,
  generateStream,
} from './RunAnywhere+TextGeneration';
import {
  type JSONSchema,
  StructuredOutputOptions,
  StructuredOutputResult,
  StructuredOutputValidation,
  StructuredOutputParseRequest,
  StructuredOutputRequest,
  StructuredOutputPromptResult,
  StructuredOutputValidationRequest,
  JSONSchema as JSONSchemaMessage,
  JSONSchemaProperty,
  JSONSchemaType,
} from '@runanywhere/proto-ts/structured_output';
import { LLMGenerationOptions } from '@runanywhere/proto-ts/llm_options';
import {
  arrayBufferToBytes,
  bytesToArrayBuffer,
} from '../../services/ProtoBytes';

// ============================================================================
// Types re-exported for callers
// ============================================================================

// StructuredOutputResult and JSONSchema are re-exported from proto-ts (no
// local duplicates per §15 Iron Rule 2).

const logger = new SDKLogger('RunAnywhere.StructuredOutput');

type ProtoBridgeMethod = (requestBytes: ArrayBuffer) => Promise<ArrayBuffer>;

function toBridgeException(operation: string, error: unknown): SDKException {
  if (error instanceof SDKException) {
    return error;
  }
  const message = error instanceof Error ? error.message : String(error);
  if (/not available|unavailable|not implemented|missing/i.test(message)) {
    return SDKException.notImplemented(`${operation}: ${message}`);
  }
  return SDKException.unknown(
    `${operation}: ${message}`,
    error instanceof Error ? error : undefined
  );
}

function requireNativeProtoMethod(
  methodName: string,
  operation: string
): ProtoBridgeMethod {
  if (!isNativeModuleAvailable()) {
    throw SDKException.notImplemented(
      `${operation}: Native module not available`
    );
  }

  const native = requireNativeModule();
  const method = (native as unknown as Record<string, unknown>)[methodName];
  if (typeof method !== 'function') {
    throw SDKException.notImplemented(
      `${operation}: native method ${methodName} is unavailable`
    );
  }

  return method.bind(native) as ProtoBridgeMethod;
}

async function callNativeProto(
  methodName: string,
  requestBytes: ArrayBuffer,
  operation: string
): Promise<Uint8Array> {
  try {
    const method = requireNativeProtoMethod(methodName, operation);
    const responseBytes = await method(requestBytes);
    const bytes = arrayBufferToBytes(responseBytes);
    if (bytes.byteLength === 0) {
      throw SDKException.unknown(
        `${operation}: native bridge returned an empty proto result`
      );
    }
    return bytes;
  } catch (error) {
    throw toBridgeException(operation, error);
  }
}

function stringToBytes(text: string): Uint8Array {
  const buf = new ArrayBuffer(text.length);
  const view = new Uint8Array(buf);
  for (let i = 0; i < text.length; i++) view[i] = text.charCodeAt(i);
  return view;
}

/** UTF-8 encoder for serializing parsed JSON to `Uint8Array`. */
function jsonToBytes(value: unknown): Uint8Array {
  return stringToBytes(JSON.stringify(value));
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
  const jsonSchema =
    options?.jsonSchema ?? schema.rawJson ?? JSON.stringify(schema);
  const structuredOutput = StructuredOutputOptions.fromPartial({
    ...options,
    schema: options?.schema ?? schema,
    includeSchemaInPrompt: options?.includeSchemaInPrompt ?? true,
    jsonSchema,
  });
  return LLMGenerationOptions.fromPartial({
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
    structuredOutput,
    enableRealTimeTracking: false,
  });
}

function structuredOutputOptionsForSchema(
  schema: JSONSchema,
  options?: StructuredOutputOptions
): StructuredOutputOptions {
  return StructuredOutputOptions.fromPartial({
    ...options,
    schema: options?.schema ?? schema,
    includeSchemaInPrompt: options?.includeSchemaInPrompt ?? true,
    jsonSchema:
      options?.jsonSchema ?? schema.rawJson ?? JSON.stringify(schema),
  });
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
  logger.debug('Generating structured output...');
  const promptResult = await prepareStructuredOutputPrompt(
    prompt,
    schema,
    options
  );
  const generationPrompt = promptResult.preparedPrompt || prompt;
  const result = await generateText(
    generationPrompt,
    llmOptionsForStructuredOutput(schema, options, false)
  );
  const resultJson = result.jsonOutput ?? result.text;
  const validation = await validateStructuredOutput(resultJson, schema, options);
  return StructuredOutputResult.fromPartial({
    parsedJson: stringToBytes(validation.extractedJson ?? resultJson),
    validation,
    rawText: result.text,
  });
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
      const promptResult = await prepareStructuredOutputPrompt(
        prompt,
        schema,
        options
      );
      const generationPrompt = promptResult.preparedPrompt || prompt;
      for await (const event of generateStream(
        generationPrompt,
        llmOptionsForStructuredOutput(schema, options, true)
      )) {
        if (event.token) {
          fullText += event.token;
          const partialValidation: StructuredOutputValidation =
            StructuredOutputValidation.fromPartial({
              isValid: false,
              containsJson: fullText.includes('{'),
              rawOutput: fullText,
            });
          yield StructuredOutputResult.fromPartial({
            parsedJson: jsonToBytes({}),
            validation: partialValidation,
            rawText: fullText,
          });
        }
        if (event.isFinal) break;
      }

      const finalValidation = await validateStructuredOutput(
        fullText,
        schema,
        options
      );
      yield StructuredOutputResult.fromPartial({
        parsedJson: stringToBytes(finalValidation.extractedJson ?? ''),
        validation: finalValidation,
        rawText: fullText,
      });
    } catch (error) {
      if (error instanceof SDKException) {
        throw error;
      }
      const msg = error instanceof Error ? error.message : String(error);
      logger.error(`Structured stream failed: ${msg}`);
      const errorValidation: StructuredOutputValidation =
        StructuredOutputValidation.fromPartial({
          isValid: false,
          containsJson: false,
          errorMessage: msg,
        });
      yield StructuredOutputResult.fromPartial({
        parsedJson: new Uint8Array(0),
        validation: errorValidation,
      });
    }
  }

  return resultGenerator();
}

/**
 * Extract structured data from an existing text string without invoking the LLM.
 *
 * Matches Swift SDK: `RunAnywhere.extractStructuredOutput(_:schema:)` and
 * canonical cross-SDK spec §3.
 */
export async function extractStructuredOutput(
  text: string,
  schema: JSONSchema
): Promise<StructuredOutputResult> {
  const request = StructuredOutputParseRequest.fromPartial({
    text,
    options: StructuredOutputOptions.fromPartial({
      schema,
      includeSchemaInPrompt: true,
      jsonSchema: schema.rawJson || undefined,
    }),
  });
  const responseBytes = await callNativeProto(
    'structuredOutputParseProto',
    bytesToArrayBuffer(StructuredOutputParseRequest.encode(request).finish()),
    'structuredOutputParse'
  );
  return StructuredOutputResult.decode(responseBytes);
}

/**
 * Prepare a structured-output prompt using commons generated-proto semantics.
 */
export async function prepareStructuredOutputPrompt(
  prompt: string,
  schema: JSONSchema,
  options?: StructuredOutputOptions
): Promise<StructuredOutputPromptResult> {
  const request = StructuredOutputRequest.fromPartial({
    prompt,
    options: structuredOutputOptionsForSchema(schema, options),
  });
  const responseBytes = await callNativeProto(
    'structuredOutputPreparePromptProto',
    bytesToArrayBuffer(StructuredOutputRequest.encode(request).finish()),
    'structuredOutputPreparePrompt'
  );
  const result = StructuredOutputPromptResult.decode(responseBytes);
  if (result.errorMessage) {
    throw SDKException.unknown(result.errorMessage);
  }
  return result;
}

/**
 * Validate structured output text using commons generated-proto semantics.
 */
export async function validateStructuredOutput(
  text: string,
  schema: JSONSchema,
  options?: StructuredOutputOptions
): Promise<StructuredOutputValidation> {
  const request = StructuredOutputValidationRequest.fromPartial({
    text,
    options: structuredOutputOptionsForSchema(schema, options),
  });
  const responseBytes = await callNativeProto(
    'structuredOutputValidateProto',
    bytesToArrayBuffer(
      StructuredOutputValidationRequest.encode(request).finish()
    ),
    'structuredOutputValidate'
  );
  return StructuredOutputValidation.decode(responseBytes);
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
    throw SDKException.generationFailed(
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
