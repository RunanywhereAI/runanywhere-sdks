import { afterEach, describe, expect, it } from 'vitest';
import {
  StructuredOutputParseRequest,
  StructuredOutputPromptResult,
  StructuredOutputRequest,
  StructuredOutputResult,
  StructuredOutputStreamEventKind,
  StructuredOutputValidation,
  StructuredOutputValidationRequest,
  StructuredOutputMode,
  type StructuredOutputParseRequest as ProtoStructuredOutputParseRequest,
  type StructuredOutputPromptResult as ProtoStructuredOutputPromptResult,
  type StructuredOutputRequest as ProtoStructuredOutputRequest,
  type StructuredOutputResult as ProtoStructuredOutputResult,
  type StructuredOutputStreamEvent as ProtoStructuredOutputStreamEvent,
  type StructuredOutputValidation as ProtoStructuredOutputValidation,
  type StructuredOutputValidationRequest as ProtoStructuredOutputValidationRequest,
} from '@runanywhere/proto-ts/structured_output';
import {
  LLMGenerateRequest,
  LLMStreamEvent,
  type LLMGenerateRequest as ProtoLLMGenerateRequest,
  type LLMStreamEvent as ProtoLLMStreamEvent,
} from '@runanywhere/proto-ts/llm_service';

import { ModalityProtoAdapter, type ModalityProtoModule } from '../../../../src/Adapters/ModalityProtoAdapter';
import { SDKException } from '../../../../src/Foundation/SDKException';
import {
  clearRunanywhereModule,
  registerWasmModule,
  type EmscriptenRunanywhereModule,
} from '../../../../src/runtime/EmscriptenModule';
import { StructuredOutput } from '../../../../src/Public/Extensions/RunAnywhere+StructuredOutput';
import { extractStructuredOutput, generateStructuredStream } from '../../../../src/Public/Extensions/RunAnywhere+TextGeneration';
import { installCurrentModelRegistryExports } from '../../helpers/CurrentModelRegistryModule.js';

const PROTO_BUFFER_SIZE = 16;
const OFF_DATA = 0;
const OFF_SIZE = 4;
const OFF_STATUS = 8;
const OFF_ERROR = 12;

type StructuredOutputHandlers = {
  parse: (request: ProtoStructuredOutputParseRequest) => ProtoStructuredOutputResult;
  prepare?: (request: ProtoStructuredOutputRequest) => ProtoStructuredOutputPromptResult;
  validate?: (request: ProtoStructuredOutputValidationRequest) => ProtoStructuredOutputValidation;
};

function makeStructuredOutputModule(
  handlerOrHandlers:
    | ((request: ProtoStructuredOutputParseRequest) => ProtoStructuredOutputResult)
    | StructuredOutputHandlers,
  llmStreamHandler?: (
    request: ProtoLLMGenerateRequest,
    emit: (event: ProtoLLMStreamEvent) => void,
  ) => number,
): ModalityProtoModule & EmscriptenRunanywhereModule {
  const handlers = typeof handlerOrHandlers === 'function'
    ? { parse: handlerOrHandlers }
    : handlerOrHandlers;
  const heap = new ArrayBuffer(64 * 1024);
  const heapU8 = new Uint8Array(heap);
  const heapU32 = new Uint32Array(heap);
  const heap32 = new Int32Array(heap);
  let nextPtr = 256;

  const malloc = (size: number): number => {
    const alignedSize = Math.max(4, (size + 3) & ~3);
    const ptr = nextPtr;
    nextPtr += alignedSize;
    return ptr;
  };

  const writeResult = (
    outResult: number,
    resultBytes: Uint8Array,
  ): void => {
    const resultPtr = malloc(resultBytes.byteLength);
    heapU8.set(resultBytes, resultPtr);
    heapU32[(outResult + OFF_DATA) >>> 2] = resultPtr;
    heapU32[(outResult + OFF_SIZE) >>> 2] = resultBytes.byteLength;
    heap32[(outResult + OFF_STATUS) >>> 2] = 0;
  };

  const writeEmptyResult = (outResult: number): void => {
    heapU32[(outResult + OFF_DATA) >>> 2] = 0;
    heapU32[(outResult + OFF_SIZE) >>> 2] = 0;
    heap32[(outResult + OFF_STATUS) >>> 2] = 0;
  };

  // Map of synthetic function-table indices to JS callbacks. Mirrors the
  // Emscripten function table that `addFunction` populates in real builds
  // (same harness pattern as RunAnywhere+TextGenerationStream.test.ts).
  const callbackTable = new Map<number, (bytesPtr: number, size: number) => unknown>();
  let nextCallbackId = 1;

  const module: Partial<ModalityProtoModule & EmscriptenRunanywhereModule> = {
    HEAPU8: heapU8,
    HEAPU32: heapU32,
    HEAP32: heap32,
    _malloc: malloc,
    _free: () => undefined,
    addFunction(fn: (...args: number[]) => unknown, _signature: string): number {
      const id = nextCallbackId;
      nextCallbackId += 1;
      callbackTable.set(id, fn as (bytesPtr: number, size: number) => unknown);
      return id;
    },
    removeFunction(ptr: number): void {
      callbackTable.delete(ptr);
    },
    _rac_proto_buffer_init(bufferPtr: number): void {
      heapU32[(bufferPtr + OFF_DATA) >>> 2] = 0;
      heapU32[(bufferPtr + OFF_SIZE) >>> 2] = 0;
      heap32[(bufferPtr + OFF_STATUS) >>> 2] = 0;
      heapU32[(bufferPtr + OFF_ERROR) >>> 2] = 0;
    },
    _rac_proto_buffer_free: () => undefined,
    _rac_wasm_sizeof_proto_buffer: () => PROTO_BUFFER_SIZE,
    _rac_wasm_offsetof_proto_buffer_data: () => OFF_DATA,
    _rac_wasm_offsetof_proto_buffer_size: () => OFF_SIZE,
    _rac_wasm_offsetof_proto_buffer_status: () => OFF_STATUS,
    _rac_wasm_offsetof_proto_buffer_error_message: () => OFF_ERROR,
    _rac_structured_output_parse_proto(
      requestPtr: number,
      requestSize: number,
      outResult: number,
    ): number {
      const requestBytes = heapU8.slice(requestPtr, requestPtr + requestSize);
      const request = StructuredOutputParseRequest.decode(requestBytes);
      const resultBytes = StructuredOutputResult.encode(handlers.parse(request)).finish();
      writeResult(outResult, resultBytes);
      return 0;
    },
  };
  if (handlers.prepare) {
    module._rac_structured_output_prepare_prompt_proto = (
      requestPtr: number,
      requestSize: number,
      outResult: number,
    ): number => {
      const requestBytes = heapU8.slice(requestPtr, requestPtr + requestSize);
      const request = StructuredOutputRequest.decode(requestBytes);
      const resultBytes = StructuredOutputPromptResult.encode(handlers.prepare!(request)).finish();
      writeResult(outResult, resultBytes);
      return 0;
    };
  }
  if (handlers.validate) {
    module._rac_structured_output_validate_proto = (
      requestPtr: number,
      requestSize: number,
      outResult: number,
    ): number => {
      const requestBytes = heapU8.slice(requestPtr, requestPtr + requestSize);
      const request = StructuredOutputValidationRequest.decode(requestBytes);
      const resultBytes = StructuredOutputValidation.encode(handlers.validate!(request)).finish();
      writeResult(outResult, resultBytes);
      return 0;
    };
  }
  if (llmStreamHandler) {
    module._rac_llm_generate_proto = (
      _requestPtr: number,
      _requestSize: number,
      outResult: number,
    ): number => {
      // Present so `supportsProtoLLM()` (which requires the
      // generate/generate_stream/cancel trio) returns true; the streaming
      // structured-output path never exercises it.
      writeEmptyResult(outResult);
      return 0;
    };
    module._rac_llm_generate_stream_proto = (
      requestPtr: number,
      requestSize: number,
      callbackPtr: number,
      _userData: number,
    ): number => {
      const fn = callbackTable.get(callbackPtr);
      if (!fn) {
        throw new Error(
          `_rac_llm_generate_stream_proto: unknown callback id ${callbackPtr}`,
        );
      }
      const requestBytes = heapU8.slice(requestPtr, requestPtr + requestSize);
      const request = LLMGenerateRequest.decode(requestBytes);
      const emit = (event: ProtoLLMStreamEvent): void => {
        const eventBytes = LLMStreamEvent.encode(event).finish();
        const ptr = malloc(eventBytes.byteLength);
        heapU8.set(eventBytes, ptr);
        fn(ptr, eventBytes.byteLength);
      };
      return llmStreamHandler(request, emit);
    };
    module._rac_llm_cancel_proto = (outEventPtr: number): number => {
      writeEmptyResult(outEventPtr);
      return 0;
    };
  }
  return installCurrentModelRegistryExports(module) as
    ModalityProtoModule & EmscriptenRunanywhereModule;
}

function streamingTokenEvent(token: string, isFinal = false): ProtoLLMStreamEvent {
  return LLMStreamEvent.fromPartial({
    token,
    isFinal,
    finishReason: isFinal ? 'stop' : '',
    errorCode: 0,
  });
}

describe('extractStructuredOutput', () => {
  afterEach(() => {
    ModalityProtoAdapter.clearDefaultModule();
    clearRunanywhereModule();
  });

  it('routes StructuredOutput.Parse through generated proto bytes', () => {
    let captured: ProtoStructuredOutputParseRequest | undefined;
    const module = makeStructuredOutputModule((request) => {
      captured = request;
      return {
        parsedJson: new TextEncoder().encode('{"city":"San Francisco"}'),
        rawText: request.text,
        validation: {
          isValid: true,
          containsJson: true,
          rawOutput: request.text,
          extractedJson: '{"city":"San Francisco"}',
          validationErrors: [],
          validationTimeMs: 0,
        },
        errorCode: 0,
      };
    });
    ModalityProtoAdapter.registerModuleCapabilities(['llm', 'structured-output'], module);

    const result = extractStructuredOutput(
      'prefix {"city":"San Francisco"} suffix',
      { jsonSchema: '{"type":"object","required":["city"]}' },
    );

    expect(captured?.text).toBe('prefix {"city":"San Francisco"} suffix');
    expect(captured?.options?.jsonSchema).toBe('{"type":"object","required":["city"]}');
    expect(captured?.options?.mode).toBe(
      StructuredOutputMode.STRUCTURED_OUTPUT_MODE_JSON_SCHEMA,
    );
    expect(new TextDecoder().decode(result.parsedJson)).toBe('{"city":"San Francisco"}');
    expect(result.validation?.isValid).toBe(true);
  });

  it('does not fall back to a TypeScript parser when the proto export is absent', () => {
    expect(() => extractStructuredOutput('{"city":"San Francisco"}', { jsonSchema: '{}' }))
      .toThrow(/Backend not available for: extractStructuredOutput/);
  });
});

describe('StructuredOutput facade prepare/validate', () => {
  afterEach(() => {
    ModalityProtoAdapter.clearDefaultModule();
    clearRunanywhereModule();
  });

  it('routes prompt preparation through generated StructuredOutputRequest bytes', () => {
    let captured: ProtoStructuredOutputRequest | undefined;
    const module = makeStructuredOutputModule({
      parse: () => StructuredOutputResult.fromPartial({ errorCode: 0 }),
      prepare(request) {
        captured = request;
        return StructuredOutputPromptResult.fromPartial({
          preparedPrompt: `PREPARED:${request.prompt}`,
          systemPrompt: 'Output JSON.',
          jsonSchema: request.options?.jsonSchema,
          errorCode: 0,
        });
      },
    });
    registerWasmModule(['llm', 'structured-output'], module);

    const result = StructuredOutput.preparePrompt({
      requestId: 'req_1',
      prompt: 'weather in SF',
      options: {
        includeSchemaInPrompt: true,
        jsonSchema: '{"type":"object","required":["city"]}',
        mode: StructuredOutputMode.STRUCTURED_OUTPUT_MODE_JSON_SCHEMA,
        repairJson: false,
        maxRetries: 0,
      },
      metadata: { source: 'test' },
    });

    expect(captured?.requestId).toBe('req_1');
    expect(captured?.prompt).toBe('weather in SF');
    expect(captured?.options?.jsonSchema).toBe('{"type":"object","required":["city"]}');
    expect(captured?.metadata.source).toBe('test');
    expect(result.preparedPrompt).toBe('PREPARED:weather in SF');
    expect(result.systemPrompt).toBe('Output JSON.');
  });

  it('routes structured validation through generated StructuredOutputValidationRequest bytes', () => {
    let captured: ProtoStructuredOutputValidationRequest | undefined;
    const module = makeStructuredOutputModule({
      parse: () => StructuredOutputResult.fromPartial({ errorCode: 0 }),
      validate(request) {
        captured = request;
        return StructuredOutputValidation.fromPartial({
          isValid: true,
          containsJson: true,
          rawOutput: request.text,
          extractedJson: '{"city":"San Francisco"}',
          validationErrors: [],
          validationTimeMs: 3,
        });
      },
    });
    registerWasmModule(['llm', 'structured-output'], module);

    const result = StructuredOutput.validate(
      'prefix {"city":"San Francisco"} suffix',
      { jsonSchema: '{"type":"object","required":["city"]}' },
    );

    expect(captured?.text).toBe('prefix {"city":"San Francisco"} suffix');
    expect(captured?.options?.jsonSchema).toBe('{"type":"object","required":["city"]}');
    expect(captured?.options?.includeSchemaInPrompt).toBe(true);
    expect(captured?.options?.mode).toBe(
      StructuredOutputMode.STRUCTURED_OUTPUT_MODE_JSON_SCHEMA,
    );
    expect(result.isValid).toBe(true);
    expect(result.extractedJson).toBe('{"city":"San Francisco"}');
  });

  it('does not fall back when prompt preparation or validation proto exports are absent', () => {
    const module = makeStructuredOutputModule({
      parse: () => StructuredOutputResult.fromPartial({ errorCode: 0 }),
    });
    registerWasmModule(['llm', 'structured-output'], module);

    expect(() => StructuredOutput.preparePrompt(
      'weather in SF',
      { jsonSchema: '{"type":"object"}' },
    )).toThrow(SDKException);
    expect(() => StructuredOutput.preparePrompt(
      'weather in SF',
      { jsonSchema: '{"type":"object"}' },
    )).toThrow(/Backend not available for: structuredOutput\.preparePrompt/);

    expect(() => StructuredOutput.validate(
      '{"city":"San Francisco"}',
      { jsonSchema: '{"type":"object"}' },
    )).toThrow(SDKException);
    expect(() => StructuredOutput.validate(
      '{"city":"San Francisco"}',
      { jsonSchema: '{"type":"object"}' },
    )).toThrow(/Backend not available for: structuredOutput\.validate/);
  });
});

describe('generateStructuredStream', () => {
  afterEach(() => {
    ModalityProtoAdapter.clearDefaultModule();
    clearRunanywhereModule();
  });

  it('streams token events then parses the accumulated text into a terminal COMPLETED event', async () => {
    let capturedGenerate: ProtoLLMGenerateRequest | undefined;
    let capturedParse: ProtoStructuredOutputParseRequest | undefined;
    const module = makeStructuredOutputModule(
      (request) => {
        capturedParse = request;
        return {
          parsedJson: new TextEncoder().encode('{"city":"San Francisco"}'),
          rawText: request.text,
          validation: {
            isValid: true,
            containsJson: true,
            rawOutput: request.text,
            extractedJson: '{"city":"San Francisco"}',
            validationErrors: [],
            validationTimeMs: 0,
          },
          errorCode: 0,
        };
      },
      (request, emit) => {
        capturedGenerate = request;
        emit(streamingTokenEvent('prefix '));
        emit(streamingTokenEvent('{"city":"San Francisco"}'));
        emit(streamingTokenEvent(' suffix'));
        emit(streamingTokenEvent('', true));
        return 0;
      },
    );
    ModalityProtoAdapter.registerModuleCapabilities(['llm', 'structured-output'], module);

    const events: ProtoStructuredOutputStreamEvent[] = [];
    for await (const event of generateStructuredStream(
      'weather in SF',
      { jsonSchema: '{"type":"object","required":["city"]}' },
      { maxTokens: 64 },
    )) {
      events.push(event);
    }

    // The LLM request goes through the real streaming path with the schema
    // mapped from the structured-output options (Swift
    // RALLMTypes+CppBridge.swift:66-74 parity) and the Swift defaults
    // (RALLMTypes+CppBridge.swift:13-21) filling the unset knobs.
    expect(capturedGenerate?.prompt).toBe('weather in SF');
    expect(capturedGenerate?.options?.streamingEnabled).toBe(true);
    expect(capturedGenerate?.options?.jsonSchema).toBe('{"type":"object","required":["city"]}');
    expect(capturedGenerate?.options?.responseFormat).toBe('json_schema');
    expect(capturedGenerate?.options?.maxTokens).toBe(64);
    expect(capturedGenerate?.options?.temperature).toBeCloseTo(0.8);
    expect(capturedGenerate?.options?.topP).toBeCloseTo(1.0);
    expect(capturedGenerate?.options?.repetitionPenalty).toBeCloseTo(1.0);

    // Three TOKEN events stream through before the terminal COMPLETED event;
    // `seq` is monotonically increasing across the whole stream.
    expect(events).toHaveLength(4);
    expect(events.map((event) => event.kind)).toEqual([
      StructuredOutputStreamEventKind.STRUCTURED_OUTPUT_STREAM_EVENT_KIND_TOKEN,
      StructuredOutputStreamEventKind.STRUCTURED_OUTPUT_STREAM_EVENT_KIND_TOKEN,
      StructuredOutputStreamEventKind.STRUCTURED_OUTPUT_STREAM_EVENT_KIND_TOKEN,
      StructuredOutputStreamEventKind.STRUCTURED_OUTPUT_STREAM_EVENT_KIND_COMPLETED,
    ]);
    expect(events.slice(0, 3).map((event) => event.token)).toEqual([
      'prefix ',
      '{"city":"San Francisco"}',
      ' suffix',
    ]);
    expect(events.map((event) => event.seq)).toEqual([1, 2, 3, 4]);

    // The accumulated transcript is parsed through StructuredOutput.Parse
    // proto bytes and carried on the terminal event's `result`.
    expect(capturedParse?.text).toBe('prefix {"city":"San Francisco"} suffix');
    expect(capturedParse?.options?.jsonSchema).toBe('{"type":"object","required":["city"]}');
    const terminal = events[3]!;
    expect(terminal.result).toBeDefined();
    expect(new TextDecoder().decode(terminal.result!.parsedJson)).toBe('{"city":"San Francisco"}');
    expect(terminal.result!.validation?.isValid).toBe(true);
  });
});
