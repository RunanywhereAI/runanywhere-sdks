/**
 * RunAnywhere+StructuredOutput.ts
 *
 * Structured output extension for JSON schema-guided generation. All shapes
 * come from `@runanywhere/proto-ts/structured_output`; commons owns the
 * generation/parse/prepare-prompt run loop through proto-byte methods.
 *
 * Mirrors `sdk/runanywhere-swift/Sources/RunAnywhere/Public/Extensions/LLM/RunAnywhere+StructuredOutput.swift`.
 */

import {
  isNativeModuleAvailable,
  requireNativeModule,
} from '../../../native';
import { SDKLogger } from '../../../Foundation/Logging/Logger/SDKLogger';
import { SDKException } from '../../../Foundation/Errors/SDKException';
import type {
  LLMGenerationOptions,
  LLMGenerationResult,
} from '@runanywhere/proto-ts/llm_options';
import {
  LLMGenerationOptions as LLMGenerationOptionsMessage,
} from '@runanywhere/proto-ts/llm_options';
import {
  type JSONSchema,
  StructuredOutputOptions,
  StructuredOutputResult,
  StructuredOutputParseRequest,
  StructuredOutputRequest,
  StructuredOutputPromptResult,
  StructuredOutputStreamEvent,
  StructuredOutputStreamEventKind,
} from '@runanywhere/proto-ts/structured_output';
import {
  arrayBufferToBytes,
  bytesToArrayBuffer,
} from '../../../services/ProtoBytes';
import { generate as generateText } from './RunAnywhere+TextGeneration';

// ============================================================================
// Types re-exported for callers
// ============================================================================

// StructuredOutputResult and JSONSchema come from `@runanywhere/proto-ts`;
// no RN-local duplicates.

const logger = new SDKLogger('RunAnywhere.StructuredOutput');
let requestCounter = 0;

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

function nextStructuredOutputRequestId(): string {
  requestCounter += 1;
  return `rn-structured-${Date.now()}-${requestCounter}`;
}

function encodeStructuredOutputRequest(
  prompt: string,
  schema: JSONSchema,
  options?: StructuredOutputOptions
): ArrayBuffer {
  return bytesToArrayBuffer(
    StructuredOutputRequest.encode(
      StructuredOutputRequest.fromPartial({
        requestId: nextStructuredOutputRequestId(),
        prompt,
        options: structuredOutputOptionsForSchema(schema, options),
        metadata: {},
      })
    ).finish()
  );
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
  const responseBytes = await callNativeProto(
    'structuredOutputGenerateProto',
    encodeStructuredOutputRequest(prompt, schema, options),
    'structuredOutputGenerate'
  );
  return StructuredOutputResult.decode(responseBytes);
}

/**
 * Generate raw text with structured-output options attached to the LLM request.
 *
 * Matches Swift SDK: `RunAnywhere.generateWithStructuredOutput(...)`.
 */
export async function generateWithStructuredOutput(
  prompt: string,
  structuredOutput: StructuredOutputOptions,
  options?: LLMGenerationOptions
): Promise<LLMGenerationResult> {
  let generationOptions: LLMGenerationOptions = LLMGenerationOptionsMessage.fromPartial({
    ...options,
    structuredOutput,
    jsonSchema: options?.jsonSchema ?? structuredOutput.jsonSchema ?? '',
  });

  if (structuredOutput.includeSchemaInPrompt) {
    const prepared = await prepareStructuredOutputPrompt(prompt, structuredOutput);
    if (prepared.errorMessage) {
      throw SDKException.generationFailedWith(prepared.errorMessage);
    }
    if (prepared.systemPrompt) {
      generationOptions = LLMGenerationOptionsMessage.fromPartial({
        ...generationOptions,
        systemPrompt: prepared.systemPrompt,
      });
    }
    if (prepared.jsonSchema && !generationOptions.jsonSchema) {
      generationOptions = LLMGenerationOptionsMessage.fromPartial({
        ...generationOptions,
        jsonSchema: prepared.jsonSchema,
      });
    }
  }

  return generateText(prompt, generationOptions);
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
  const requestBytes = encodeStructuredOutputRequest(prompt, schema, options);

  async function* resultGenerator(): AsyncGenerator<StructuredOutputResult> {
    if (!isNativeModuleAvailable()) {
      throw SDKException.nativeModuleUnavailable();
    }
    const native = requireNativeModule();
    const method = (native as unknown as Record<string, unknown>)
      .structuredOutputGenerateStreamProto;
    if (typeof method !== 'function') {
      throw SDKException.notImplemented(
        'structuredOutputGenerateStream: native method unavailable'
      );
    }

    const queue: StructuredOutputResult[] = [];
    let done = false;
    let streamError: Error | null = null;
    let resolver: ((value: IteratorResult<StructuredOutputResult>) => void) | null = null;

    const finish = (): void => {
      done = true;
      if (resolver) {
        resolver({ value: undefined as unknown as StructuredOutputResult, done: true });
        resolver = null;
      }
    };

    const push = (result: StructuredOutputResult): void => {
      if (resolver) {
        resolver({ value: result, done: false });
        resolver = null;
      } else {
        queue.push(result);
      }
    };

    (method as (
      requestBytes: ArrayBuffer,
      onEventBytes: (eventBytes: ArrayBuffer) => void
    ) => Promise<void>).call(native, requestBytes, (eventBytes: ArrayBuffer) => {
      try {
        const event = StructuredOutputStreamEvent.decode(arrayBufferToBytes(eventBytes));
        if (event.errorMessage) {
          streamError = SDKException.generationFailedWith(event.errorMessage);
        }
        if (event.result) {
          push(event.result);
        } else if (
          event.kind ===
          StructuredOutputStreamEventKind.STRUCTURED_OUTPUT_STREAM_EVENT_KIND_PARTIAL_JSON
        ) {
          push(
            StructuredOutputResult.fromPartial({
              parsedJson: stringToBytes(event.partialJson ?? ''),
              validation: event.validation,
              rawText: event.partialJson ?? '',
            })
          );
        }
        if (
          event.kind ===
            StructuredOutputStreamEventKind.STRUCTURED_OUTPUT_STREAM_EVENT_KIND_COMPLETED ||
          event.kind ===
            StructuredOutputStreamEventKind.STRUCTURED_OUTPUT_STREAM_EVENT_KIND_ERROR
        ) {
          finish();
        }
      } catch (error) {
        streamError = error instanceof Error ? error : new Error(String(error));
        finish();
      }
    })
      .catch((error: Error) => {
        streamError = error;
      })
      .finally(finish);

    while (!done || queue.length > 0) {
      if (queue.length > 0) {
        yield queue.shift()!;
      } else if (!done) {
        const next = await new Promise<IteratorResult<StructuredOutputResult>>((resolve) => {
          resolver = resolve;
        });
        if (next.done) break;
        yield next.value;
      }
    }
    if (streamError) throw streamError;
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

async function prepareStructuredOutputPrompt(
  prompt: string,
  options: StructuredOutputOptions
): Promise<StructuredOutputPromptResult> {
  const request = StructuredOutputRequest.fromPartial({
    prompt,
    options,
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
