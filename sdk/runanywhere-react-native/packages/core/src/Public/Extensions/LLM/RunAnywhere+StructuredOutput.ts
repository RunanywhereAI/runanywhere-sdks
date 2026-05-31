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
  JSONSchema as JSONSchemaCodec,
  StructuredOutputOptions,
  StructuredOutputResult,
  StructuredOutputParseRequest,
  StructuredOutputRequest,
  StructuredOutputPromptResult,
  StructuredOutputStreamEvent,
  StructuredOutputStreamEventKind,
} from '@runanywhere/proto-ts/structured_output';
import { arrayBufferToBytes } from '../../../services/ProtoBytes';
import { encodeProtoMessage } from '../../../services/ProtoWire';
import { generate as generateText } from './RunAnywhere+TextGeneration';

// Re-export the wire types consumers need to discriminate the stream.
export { StructuredOutputStreamEvent, StructuredOutputStreamEventKind };

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

/**
 * Canonical JSON Schema text consumed by the commons structured-output C ABI.
 *
 * Delegates to `rac_structured_output_schema_to_json_proto` so every
 * SDK shares the same byte-exact, key-sorted, compact serializer. Returns
 * `"{}"` on any serialization or bridge failure, mirroring Swift
 * `RAJSONSchema.jsonSchemaString`.
 */
async function jsonSchemaStringForSchema(schema: JSONSchema): Promise<string> {
  try {
    const schemaBytes = encodeProtoMessage(schema, JSONSchemaCodec);
    const responseBytes = await callNativeProto(
      'structuredOutputSchemaToJsonProto',
      schemaBytes,
      'structuredOutputSchemaToJson'
    );
    if (responseBytes.byteLength === 0) {
      return '{}';
    }
    const TextDecoderCtor = globalThis.TextDecoder;
    if (typeof TextDecoderCtor === 'function') {
      return new TextDecoderCtor('utf-8').decode(responseBytes);
    }
    let result = '';
    for (let i = 0; i < responseBytes.byteLength; i++) {
      result += String.fromCharCode(responseBytes[i]!);
    }
    return result || '{}';
  } catch {
    return '{}';
  }
}

async function structuredOutputOptionsForSchema(
  schema: JSONSchema,
  options?: StructuredOutputOptions
): Promise<StructuredOutputOptions> {
  const jsonSchema =
    options?.jsonSchema ?? (await jsonSchemaStringForSchema(schema));
  return StructuredOutputOptions.fromPartial({
    ...options,
    schema: options?.schema ?? schema,
    includeSchemaInPrompt: options?.includeSchemaInPrompt ?? true,
    jsonSchema,
  });
}

function nextStructuredOutputRequestId(): string {
  requestCounter += 1;
  return `rn-structured-${Date.now()}-${requestCounter}`;
}

async function encodeStructuredOutputRequest(
  prompt: string,
  schema: JSONSchema,
  options?: StructuredOutputOptions
): Promise<ArrayBuffer> {
  const request = StructuredOutputRequest.fromPartial({
    requestId: nextStructuredOutputRequestId(),
    prompt,
    options: await structuredOutputOptionsForSchema(schema, options),
    metadata: {},
  });
  return encodeProtoMessage(request, StructuredOutputRequest);
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
    await encodeStructuredOutputRequest(prompt, schema, options),
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
 * Returns an `AsyncIterable<StructuredOutputStreamEvent>` that yields one
 * proto event per native callback (TOKEN per generated token, optional
 * PARTIAL_JSON / VALIDATION events, terminated by COMPLETED with the final
 * `result` or ERROR with `errorMessage`). Consumers discriminate on the
 * `kind` field, mirroring Swift's `AsyncThrowingStream<RAStructuredOutputStreamEvent, Error>`
 * and Kotlin's `Flow<StructuredOutputStreamEvent>`.
 *
 * Matches Swift SDK: `RunAnywhere.generateStructuredStream(_:content:options:)`
 * (sdk/runanywhere-swift/.../RunAnywhere+StructuredOutput.swift:58) and the
 * canonical cross-SDK spec §3.
 */
export function generateStructuredStream(
  prompt: string,
  schema: JSONSchema,
  options?: StructuredOutputOptions
): AsyncIterable<StructuredOutputStreamEvent> {
  async function* resultGenerator(): AsyncGenerator<StructuredOutputStreamEvent> {
    const requestBytes = await encodeStructuredOutputRequest(prompt, schema, options);
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

    const queue: StructuredOutputStreamEvent[] = [];
    let done = false;
    let streamError: Error | null = null;
    let resolver: ((value: IteratorResult<StructuredOutputStreamEvent>) => void) | null = null;

    const finish = (): void => {
      done = true;
      if (resolver) {
        resolver({ value: undefined as unknown as StructuredOutputStreamEvent, done: true });
        resolver = null;
      }
    };

    const push = (event: StructuredOutputStreamEvent): void => {
      if (resolver) {
        resolver({ value: event, done: false });
        resolver = null;
      } else {
        queue.push(event);
      }
    };

    (method as (
      requestBytes: ArrayBuffer,
      onEventBytes: (eventBytes: ArrayBuffer) => void
    ) => Promise<void>).call(native, requestBytes, (eventBytes: ArrayBuffer) => {
      try {
        const event = StructuredOutputStreamEvent.decode(arrayBufferToBytes(eventBytes));
        push(event);
        if (
          event.kind ===
            StructuredOutputStreamEventKind.STRUCTURED_OUTPUT_STREAM_EVENT_KIND_COMPLETED ||
          event.kind ===
            StructuredOutputStreamEventKind.STRUCTURED_OUTPUT_STREAM_EVENT_KIND_ERROR
        ) {
          if (
            event.kind ===
              StructuredOutputStreamEventKind.STRUCTURED_OUTPUT_STREAM_EVENT_KIND_ERROR &&
            event.errorMessage
          ) {
            streamError = SDKException.generationFailedWith(event.errorMessage);
          }
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
        const next = await new Promise<IteratorResult<StructuredOutputStreamEvent>>((resolve) => {
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
      jsonSchema: await jsonSchemaStringForSchema(schema),
    }),
  });
  const responseBytes = await callNativeProto(
    'structuredOutputParseProto',
    encodeProtoMessage(request, StructuredOutputParseRequest),
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
    encodeProtoMessage(request, StructuredOutputRequest),
    'structuredOutputPreparePrompt'
  );
  const result = StructuredOutputPromptResult.decode(responseBytes);
  if (result.errorMessage) {
    throw SDKException.unknown(result.errorMessage);
  }
  return result;
}
