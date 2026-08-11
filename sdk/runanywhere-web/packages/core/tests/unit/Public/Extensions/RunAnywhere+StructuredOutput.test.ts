import { afterEach, describe, expect, it } from 'vitest';
// idl/structured_output.proto (API-realignment so-p2) deleted the dedicated
// `StructuredOutputRequest` / `StructuredOutputValidationRequest` messages
// outright: `StructuredOutputParseRequest` (requestId, text, options,
// metadata) is now the sole request envelope shared by parse/validate/
// prepare-prompt. `StructuredOutputMode` and the `StructuredOutputStreamEvent`
// / `StructuredOutputStreamEventKind` proto types were deleted outright too
// -- `generateStructuredStream` now yields a Web-local discriminated union
// (see RunAnywhere+TextGeneration.ts's `StructuredOutputStreamEvent`
// re-export) instead of a proto message.
import {
  StructuredOutputParseRequest,
  StructuredOutputPromptResult,
  StructuredOutputResult,
  StructuredOutputValidation,
  type StructuredOutputParseRequest as ProtoStructuredOutputParseRequest,
  type StructuredOutputPromptResult as ProtoStructuredOutputPromptResult,
  type StructuredOutputResult as ProtoStructuredOutputResult,
  type StructuredOutputValidation as ProtoStructuredOutputValidation,
} from '@runanywhere/proto-ts/structured_output';
import {
  LLMGenerateRequest,
  LLMStreamEvent,
  LLMStreamEventKind,
  type LLMGenerateRequest as ProtoLLMGenerateRequest,
  type LLMStreamEvent as ProtoLLMStreamEvent,
} from '@runanywhere/proto-ts/llm_service';
import { FinishReason } from '@runanywhere/proto-ts/finish_reason';
import { MessageRole } from '@runanywhere/proto-ts/chat';

import { ModalityProtoAdapter, type ModalityProtoModule } from '../../../../src/Adapters/ModalityProtoAdapter';
import { SDKException } from '../../../../src/Foundation/SDKException';
import {
  clearRunanywhereModule,
  registerWasmModule,
  type EmscriptenRunanywhereModule,
} from '../../../../src/runtime/EmscriptenModule';
import {
  StructuredOutput,
  type StructuredOutputStreamEvent,
} from '../../../../src/Public/Extensions/RunAnywhere+StructuredOutput';
import { extractStructuredOutput, generateStructuredStream } from '../../../../src/Public/Extensions/RunAnywhere+TextGeneration';
import { installCurrentModelRegistryExports } from '../../helpers/CurrentModelRegistryModule.js';

const PROTO_BUFFER_SIZE = 16;
const OFF_DATA = 0;
const OFF_SIZE = 4;
const OFF_STATUS = 8;
const OFF_ERROR = 12;

// `StructuredOutputParseRequest` is the sole request envelope shared by
// parse/prepare-prompt/validate now (the dedicated `StructuredOutputRequest`
// / `StructuredOutputValidationRequest` messages were deleted outright).
type StructuredOutputHandlers = {
  parse: (request: ProtoStructuredOutputParseRequest) => ProtoStructuredOutputResult;
  prepare?: (request: ProtoStructuredOutputParseRequest) => ProtoStructuredOutputPromptResult;
  validate?: (request: ProtoStructuredOutputParseRequest) => ProtoStructuredOutputValidation;
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
      // fromPartial fills commons-owned defaults (repairAttempted/repairAttempts,
      // etc.) so fixture stubs that omit new int32 fields do not throw
      // "invalid int32: undefined" on encode.
      const resultBytes = StructuredOutputResult.encode(
        StructuredOutputResult.fromPartial(handlers.parse(request)),
      ).finish();
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
      const request = StructuredOutputParseRequest.decode(requestBytes);
      const resultBytes = StructuredOutputPromptResult.encode(
        StructuredOutputPromptResult.fromPartial(handlers.prepare!(request)),
      ).finish();
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
      const request = StructuredOutputParseRequest.decode(requestBytes);
      const resultBytes = StructuredOutputValidation.encode(
        StructuredOutputValidation.fromPartial(handlers.validate!(request)),
      ).finish();
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

// `LLMStreamEvent.isFinal` (boolean) was replaced by the `eventKind` enum,
// and `finishReason`/`errorCode` moved onto the FinishReason enum + optional
// `error: SDKError` field.
function streamingTokenEvent(token: string, isFinal = false): ProtoLLMStreamEvent {
  return LLMStreamEvent.fromPartial({
    token,
    eventKind: isFinal
      ? LLMStreamEventKind.LLM_STREAM_EVENT_KIND_COMPLETED
      : LLMStreamEventKind.LLM_STREAM_EVENT_KIND_TOKEN,
    finishReason: isFinal ? FinishReason.FINISH_REASON_STOP : FinishReason.FINISH_REASON_UNSPECIFIED,
  });
}

describe('extractStructuredOutput', () => {
  afterEach(() => {
    ModalityProtoAdapter.clearDefaultModule();
    clearRunanywhereModule();
  });

  it('routes StructuredOutput.Parse through generated proto bytes', () => {
    let captured: ProtoStructuredOutputParseRequest | undefined;
    // `StructuredOutputResult.parsedJson`→`.json` (a plain string, not
    // bytes); `.errorCode` was deleted outright (optional `error: SDKError`
    // replaced it). `StructuredOutputOptions.jsonSchema`→`.schema` (a oneof
    // arm alongside `.grammar`/`.regex`), and `.mode` was deleted outright
    // -- the oneof arm itself is the sole constraint-kind signal now.
    const module = makeStructuredOutputModule((request) => {
      captured = request;
      return {
        json: '{"city":"San Francisco"}',
        rawText: request.text,
        validation: {
          isValid: true,
          containsJson: true,
          rawOutput: request.text,
          extractedJson: '{"city":"San Francisco"}',
          validationErrors: [],
          validationTimeMs: 0,
        },
      };
    });
    ModalityProtoAdapter.registerModuleCapabilities(['llm', 'structured-output'], module);

    const result = extractStructuredOutput(
      'prefix {"city":"San Francisco"} suffix',
      { jsonSchema: '{"type":"object","required":["city"]}' },
    );

    expect(captured?.text).toBe('prefix {"city":"San Francisco"} suffix');
    expect(captured?.options?.schema).toBe('{"type":"object","required":["city"]}');
    expect(result.json).toBe('{"city":"San Francisco"}');
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

  it('routes prompt preparation through generated StructuredOutputParseRequest bytes', () => {
    // `StructuredOutputRequest` was deleted outright -- prompt preparation
    // now shares `StructuredOutputParseRequest` (text/options/metadata) with
    // parse/validate. `StructuredOutputOptions.mode`/`.repairJson`/
    // `.maxRetries` were all deleted outright too; `jsonSchema`→`.schema`.
    let captured: ProtoStructuredOutputParseRequest | undefined;
    const module = makeStructuredOutputModule({
      parse: () => StructuredOutputResult.fromPartial({}),
      prepare(request) {
        captured = request;
        return StructuredOutputPromptResult.fromPartial({
          preparedPrompt: `PREPARED:${request.text}`,
          systemPrompt: 'Output JSON.',
          jsonSchema: request.options?.schema,
        });
      },
    });
    registerWasmModule(['llm', 'structured-output'], module);

    const result = StructuredOutput.preparePrompt({
      requestId: 'req_1',
      text: 'weather in SF',
      options: {
        includeSchemaInPrompt: true,
        schema: '{"type":"object","required":["city"]}',
      },
      metadata: { source: 'test' },
    });

    expect(captured?.requestId).toBe('req_1');
    expect(captured?.text).toBe('weather in SF');
    expect(captured?.options?.schema).toBe('{"type":"object","required":["city"]}');
    expect(captured?.metadata.source).toBe('test');
    expect(result.preparedPrompt).toBe('PREPARED:weather in SF');
    expect(result.systemPrompt).toBe('Output JSON.');
  });

  it('routes structured validation through generated StructuredOutputParseRequest bytes', () => {
    // `StructuredOutputValidationRequest` was deleted outright -- validation
    // shares `StructuredOutputParseRequest` too.
    let captured: ProtoStructuredOutputParseRequest | undefined;
    const module = makeStructuredOutputModule({
      parse: () => StructuredOutputResult.fromPartial({}),
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
    expect(captured?.options?.schema).toBe('{"type":"object","required":["city"]}');
    expect(captured?.options?.includeSchemaInPrompt).toBe(true);
    expect(result.isValid).toBe(true);
    expect(result.extractedJson).toBe('{"city":"San Francisco"}');
  });

  it('does not fall back when prompt preparation or validation proto exports are absent', () => {
    const module = makeStructuredOutputModule({
      parse: () => StructuredOutputResult.fromPartial({}),
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
    // `StructuredOutputResult.parsedJson`→`.json`; `.errorCode` was deleted
    // outright.
    const module = makeStructuredOutputModule(
      (request) => {
        capturedParse = request;
        return {
          json: '{"city":"San Francisco"}',
          rawText: request.text,
          validation: {
            isValid: true,
            containsJson: true,
            rawOutput: request.text,
            extractedJson: '{"city":"San Francisco"}',
            validationErrors: [],
            validationTimeMs: 0,
          },
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

    // `StructuredOutputStreamEvent`/`StructuredOutputStreamEventKind` proto
    // types were deleted outright -- `generateStructuredStream` now yields
    // the Web-local `StructuredOutputStreamEvent` union
    // (`{kind:'token',token}` | `{kind:'completed',result}`), imported from
    // RunAnywhere+StructuredOutput.ts (re-exported from
    // RunAnywhere+TextGeneration.ts).
    const events: StructuredOutputStreamEvent[] = [];
    for await (const event of generateStructuredStream(
      'weather in SF',
      { jsonSchema: '{"type":"object","required":["city"]}' },
      { maxOutputTokens: 64 },
    )) {
      events.push(event);
    }

    // The LLM request goes through the real streaming path with the schema
    // mapped from the structured-output options (Swift
    // RALLMTypes+CppBridge.swift:66-74 parity) and the Swift defaults
    // (RALLMTypes+CppBridge.swift:13-21) filling the unset knobs.
    // `LLMGenerateRequest.prompt` was deleted outright -- the prompt rides
    // the last entry of `messages: ChatMessage[]` now.
    expect(capturedGenerate?.messages.at(-1)?.content).toBe('weather in SF');
    expect(capturedGenerate?.messages.at(-1)?.role).toBe(MessageRole.MESSAGE_ROLE_USER);
    expect(capturedGenerate?.options?.structuredOutput?.includeSchemaInPrompt).toBe(true);
    expect(capturedGenerate?.options?.structuredOutput?.schema).toBe('{"type":"object","required":["city"]}');
    expect(capturedGenerate?.options?.maxOutputTokens).toBe(64);
    expect(capturedGenerate?.options?.temperature).toBeCloseTo(0.7);
    expect(capturedGenerate?.options?.topP).toBeCloseTo(1.0);
    // repeat_penalty defaults to 1.1 (idl/llm_options.proto), matching
    // llama.cpp/Ollama convention -- not the old repetition_penalty field's
    // 1.0 default.
    expect(capturedGenerate?.options?.repeatPenalty).toBeCloseTo(1.1);

    // Three token events stream through before the terminal completed event.
    expect(events).toHaveLength(4);
    expect(events.map((event) => event.kind)).toEqual([
      'token',
      'token',
      'token',
      'completed',
    ]);
    expect(
      events.slice(0, 3).map((event) => (event.kind === 'token' ? event.token : undefined)),
    ).toEqual([
      'prefix ',
      '{"city":"San Francisco"}',
      ' suffix',
    ]);

    // The accumulated transcript is parsed through StructuredOutput.Parse
    // proto bytes and carried on the terminal event's `result`.
    expect(capturedParse?.text).toBe('prefix {"city":"San Francisco"} suffix');
    expect(capturedParse?.options?.schema).toBe('{"type":"object","required":["city"]}');
    const terminal = events[3]!;
    expect(terminal.kind).toBe('completed');
    if (terminal.kind !== 'completed') throw new Error('expected a completed event');
    expect(terminal.result.json).toBe('{"city":"San Francisco"}');
    expect(terminal.result.validation?.isValid).toBe(true);
  });
});
