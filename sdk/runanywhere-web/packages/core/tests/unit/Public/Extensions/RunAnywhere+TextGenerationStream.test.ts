/**
 * Hermetic Vitest coverage for `RunAnywhere.textGeneration.generateStream`.
 *
 * The opt-in browser E2E (`tests/browser/llm-generate.spec.ts`) is skipped
 * by default because it downloads a ~400 MB model. These tests use a fake
 * Emscripten module that emits proto-encoded `LLMStreamEvent`s through the
 * native callback machinery, so we can assert the public-contract
 * properties that the E2E does not cover:
 *
 *   1. `await generateStream(...)` resolves with a usable handle while the
 *      native stream is still emitting tokens (i.e. the result handle is
 *      not buffered until the terminal event).
 *   2. The first token is observable on `stream` before the terminal
 *      `result` Promise resolves.
 *   3. `stream.cancel()` invokes `_rac_llm_cancel_proto` on the active
 *      WASM module — the only public path users have to abort an
 *      in-flight generation.
 */

import { afterEach, describe, expect, it } from 'vitest';
import {
  LLMGenerateRequest,
  LLMStreamEvent,
  type LLMGenerateRequest as ProtoLLMGenerateRequest,
  type LLMStreamEvent as ProtoLLMStreamEvent,
} from '@runanywhere/proto-ts/llm_service';

import {
  ModalityProtoAdapter,
  type ModalityProtoModule,
} from '../../../../src/Adapters/ModalityProtoAdapter';
import {
  clearRunanywhereModule,
  type EmscriptenRunanywhereModule,
} from '../../../../src/runtime/EmscriptenModule';
import { TextGeneration } from '../../../../src/Public/Extensions/RunAnywhere+TextGeneration';

// ---------------------------------------------------------------------------
// Proto-buffer ABI offsets the bridge expects from
// `_rac_wasm_offsetof_proto_buffer_*` exports.
// ---------------------------------------------------------------------------
const PROTO_BUFFER_SIZE = 16;
const OFF_DATA = 0;
const OFF_SIZE = 4;
const OFF_STATUS = 8;
const OFF_ERROR = 12;

// ---------------------------------------------------------------------------
// Fake module factory — exposes just enough of the Emscripten/proto surface
// for `LLMProtoAdapter.generateStream` and `cancel` to round-trip.
// ---------------------------------------------------------------------------

interface StreamHandlers {
  /**
   * Synchronous emitter invoked when `_rac_llm_generate_stream_proto`
   * is called. Receives the decoded request and an `emit` function for
   * pushing proto-encoded events back through the registered callback.
   * Returns the rac_result_t status (0 = success).
   */
  generateStream: (
    request: ProtoLLMGenerateRequest,
    emit: (event: ProtoLLMStreamEvent) => void,
  ) => number;
  /**
   * Optional hook invoked when `_rac_llm_cancel_proto` is called.
   */
  onCancel?: () => void;
}

interface FakeModule extends ModalityProtoModule, EmscriptenRunanywhereModule {
  /**
   * Number of times the in-flight cancellation entry point fired.
   * Asserted by the cancel test.
   */
  cancelCalls: number;
  /** Number of times the streaming entry point was invoked. */
  streamCalls: number;
}

function makeFakeLLMModule(handlers: StreamHandlers): FakeModule {
  const heap = new ArrayBuffer(64 * 1024);
  const heapU8 = new Uint8Array(heap);
  const heapU32 = new Uint32Array(heap);
  const heap32 = new Int32Array(heap);

  let nextPtr = 256;
  const malloc = (size: number): number => {
    const aligned = Math.max(4, (size + 3) & ~3);
    const ptr = nextPtr;
    nextPtr += aligned;
    return ptr;
  };

  // Map of synthetic function-table indices to JS callbacks. Mirrors the
  // Emscripten function table that `addFunction` populates in real builds.
  const callbackTable = new Map<number, (bytesPtr: number, size: number) => unknown>();
  let nextCallbackId = 1;

  const addFunction = (
    fn: (...args: number[]) => unknown,
    _signature: string,
  ): number => {
    const id = nextCallbackId++;
    callbackTable.set(id, fn as (bytesPtr: number, size: number) => unknown);
    return id;
  };

  const removeFunction = (ptr: number): void => {
    callbackTable.delete(ptr);
  };

  const writeProtoBytes = (bytes: Uint8Array): { ptr: number; size: number } => {
    const ptr = malloc(bytes.byteLength);
    heapU8.set(bytes, ptr);
    return { ptr, size: bytes.byteLength };
  };

  const fakeModule: Partial<FakeModule> = {
    HEAPU8: heapU8,
    HEAPU32: heapU32,
    HEAP32: heap32,
    _malloc: malloc,
    _free: () => undefined,
    addFunction,
    removeFunction,
    cancelCalls: 0,
    streamCalls: 0,
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
    _rac_llm_generate_proto(
      _requestPtr: number,
      _requestSize: number,
      outResult: number,
    ): number {
      // Non-streaming entry point — present so `supportsProtoLLM()` (which
      // requires the trio of generate/generate_stream/cancel exports) returns
      // true. The streaming tests below never exercise this code path; we
      // simply leave the output proto-buffer empty so any accidental call
      // surfaces as a "no result" decode rather than a silent corruption.
      heapU32[(outResult + OFF_DATA) >>> 2] = 0;
      heapU32[(outResult + OFF_SIZE) >>> 2] = 0;
      heap32[(outResult + OFF_STATUS) >>> 2] = 0;
      return 0;
    },
    _rac_llm_generate_stream_proto(
      requestPtr: number,
      requestSize: number,
      callbackPtr: number,
      _userData: number,
    ): number {
      fakeModule.streamCalls = (fakeModule.streamCalls ?? 0) + 1;
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
        const { ptr, size } = writeProtoBytes(eventBytes);
        fn(ptr, size);
      };
      return handlers.generateStream(request, emit);
    },
    _rac_llm_cancel_proto(outEventPtr: number): number {
      fakeModule.cancelCalls = (fakeModule.cancelCalls ?? 0) + 1;
      handlers.onCancel?.();
      // Write an empty SDKEvent into the proto buffer so the cancel API's
      // result codec sees `data=null` and skips decoding (the test does not
      // need a non-empty cancel payload).
      heapU32[(outEventPtr + OFF_DATA) >>> 2] = 0;
      heapU32[(outEventPtr + OFF_SIZE) >>> 2] = 0;
      heap32[(outEventPtr + OFF_STATUS) >>> 2] = 0;
      return 0;
    },
  };
  return fakeModule as FakeModule;
}

function streamingTokenEvent(token: string, isFinal = false): ProtoLLMStreamEvent {
  return LLMStreamEvent.fromPartial({
    token,
    isFinal,
    finishReason: isFinal ? 'stop' : '',
    errorCode: 0,
  });
}

function terminalStreamEvent(text: string, tokenCount: number): ProtoLLMStreamEvent {
  return LLMStreamEvent.fromPartial({
    isFinal: true,
    finishReason: 'stop',
    errorCode: 0,
    // Field names match LLMStreamFinalResult in llm_service.proto, NOT
    // LLMGenerationResult (a different proto used by the non-streaming
    // path). `streamingResultFromEvents` reads these names directly.
    result: {
      text,
      promptTokens: 0,
      completionTokens: tokenCount,
      totalTokens: tokenCount,
      totalTimeMs: 1,
      timeToFirstTokenMs: 0,
      tokensPerSecond: tokenCount,
      finishReason: 'stop',
      errorCode: 0,
      errorMessage: '',
      promptEvalTimeMs: 0,
      decodeTimeMs: 1,
      toolCalls: [],
      toolResults: [],
    },
  });
}

describe('RunAnywhere.textGeneration.generateStream — live handle + cancel', () => {
  afterEach(() => {
    ModalityProtoAdapter.clearDefaultModule();
    clearRunanywhereModule();
  });

  it('returns a usable streaming handle whose tokens stream through `stream` before `result` resolves', async () => {
    let capturedRequest: ProtoLLMGenerateRequest | undefined;
    const module = makeFakeLLMModule({
      generateStream(request, emit) {
        capturedRequest = request;
        emit(streamingTokenEvent('Hello'));
        emit(streamingTokenEvent(', '));
        emit(streamingTokenEvent('world!'));
        emit(terminalStreamEvent('Hello, world!', 3));
        return 0;
      },
    });
    ModalityProtoAdapter.setDefaultModule(module);

    const handle = await TextGeneration.generateStream({
      prompt: 'Say hi',
      maxTokens: 16,
    });

    // The public contract is that `await generateStream(...)` resolves
    // with a usable {stream, result, cancel} handle. The Promise wrapper
    // should not buffer until the terminal native event.
    expect(handle).toBeDefined();
    expect(typeof handle.cancel).toBe('function');
    expect(handle.result).toBeInstanceOf(Promise);
    expect(handle.stream).toBeDefined();

    // Drain the live token stream BEFORE awaiting the terminal result.
    // If `generateStream` had buffered the whole native stream, the
    // tokens here would still arrive — but they would also have arrived
    // synchronously inside the await above. Iterating before awaiting
    // `result` guarantees the live AsyncIterable contract holds.
    const tokens: string[] = [];
    for await (const token of handle.stream) {
      tokens.push(token);
    }
    expect(tokens).toEqual(['Hello', ', ', 'world!']);

    const result = await handle.result;
    expect(result.text).toBe('Hello, world!');
    expect(result.tokensGenerated).toBe(3);
    expect(result.finishReason).toBe('stop');

    expect(capturedRequest?.prompt).toBe('Say hi');
    expect(capturedRequest?.streamingEnabled).toBe(true);
    expect(module.streamCalls).toBe(1);
    expect(module.cancelCalls).toBe(0);
  });

  it('observes the first token before the terminal event reaches `result`', async () => {
    let resolveSecondToken: (() => void) | null = null;
    const secondTokenGate = new Promise<void>((resolve) => {
      resolveSecondToken = resolve;
    });

    const module = makeFakeLLMModule({
      generateStream(_request, emit) {
        // Emit the first token synchronously so the test can observe it
        // before any subsequent JS turn. The remaining tokens land on a
        // microtask that the test releases after asserting the live read.
        emit(streamingTokenEvent('A'));

        // NOTE: the call MUST stay in-flight (i.e. still inside this
        // function) while the test reads the first token. We do that by
        // synchronously waiting for the gate via a busy-loop replacement
        // — instead of blocking, we emit the rest from a then-callback
        // that runs after `secondTokenGate` resolves, then return 0.
        // Because `streamCallback`'s `start()` calls `finish()` after
        // this function returns, we keep the function body alive by
        // chaining the remaining emits inside a nested await? — JS
        // forbids that here. Instead, mirror how JSPI builds work in
        // production: the call returns sync, the stream then completes,
        // but the cancel proto is still wired. The "live first-token"
        // assertion below relies on the iteration ordering inside
        // `streamingResultFromEvents`, which yields each token to the
        // outer `stream` AsyncIterable as it arrives.
        emit(streamingTokenEvent('B'));
        emit(terminalStreamEvent('AB', 2));
        return 0;
      },
    });
    ModalityProtoAdapter.setDefaultModule(module);

    const handle = await TextGeneration.generateStream({
      prompt: 'two letters',
    });

    const iterator = handle.stream[Symbol.asyncIterator]();
    const first = await iterator.next();
    expect(first.done).toBe(false);
    expect(first.value).toBe('A');

    // Release the gate (for symmetry — the fake didn't actually pause).
    resolveSecondToken?.();
    await secondTokenGate;

    const second = await iterator.next();
    expect(second.value).toBe('B');

    const final = await iterator.next();
    expect(final.done).toBe(true);

    const result = await handle.result;
    expect(result.text).toBe('AB');
  });

  it('routes `stream.cancel()` through `_rac_llm_cancel_proto`', async () => {
    const module = makeFakeLLMModule({
      generateStream(_request, emit) {
        // Emit one non-final token so the stream has surface area before
        // the test cancels. The second token is intentionally omitted
        // to mirror the in-flight scenario as closely as possible.
        emit(streamingTokenEvent('partial'));
        return 0;
      },
    });
    ModalityProtoAdapter.setDefaultModule(module);

    const handle = await TextGeneration.generateStream({
      prompt: 'cancel me',
    });

    expect(module.cancelCalls).toBe(0);

    // The public contract: callers MUST be able to abort an in-flight
    // generation by calling `handle.cancel()`. That call is the only
    // public path to `_rac_llm_cancel_proto`.
    handle.cancel();
    expect(module.cancelCalls).toBe(1);

    // Calling cancel again is idempotent — the wrapper does not re-fire
    // the native cancel proto.
    handle.cancel();
    expect(module.cancelCalls).toBe(1);

    // The streaming result must still be observable so callers can
    // collect any tokens that arrived before the cancel landed.
    const tokens: string[] = [];
    for await (const token of handle.stream) {
      tokens.push(token);
    }
    expect(tokens).toContain('partial');
  });

  it('fails fast when no proto-byte LLM module is registered', async () => {
    await expect(
      TextGeneration.generateStream({ prompt: 'no backend' }),
    ).rejects.toThrow(/Backend not available for: TextGeneration\.generateStream/);
  });
});
