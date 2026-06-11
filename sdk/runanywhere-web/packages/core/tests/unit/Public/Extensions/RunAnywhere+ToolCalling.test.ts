/**
 * Hermetic Vitest coverage for `RunAnywhere.toolCalling.generateWithTools`.
 *
 * pass3-syn-060: the session-driver rewrite (RunAnywhere+ToolCalling.ts:504)
 * delegates the generate -> parse -> validate -> execute -> follow-up loop to
 * commons via the session ABI (`_rac_tool_calling_session_*_proto`). The
 * synchronous-callback / drain-loop machinery (addFunction trampoline,
 * malloc'd uint64 handle slot, low/high uint32 reconstruction, awaited
 * Promise<ToolResult> between native calls) was previously untested.
 *
 * These tests install a fake EmscriptenRunanywhereModule whose
 * `_rac_tool_calling_session_*` exports synchronously emit serialized
 * `ToolCallingSessionEvent` bytes through the registered callback, mirroring
 * the real commons run-loop. The harness asserts:
 *
 *  1. `buildSessionCreateRequest` mirrors Swift's `makeRunLoopRequest`
 *     wire shape (pass3-syn-060 evidence).
 *  2. `decodeSessionEvent` happy path returns the decoded event; decode
 *     failures surface as a structured `decode-error` rather than null
 *     (pass3-syn-152).
 *  3. `encodeStepRequest` round-trips through proto encode/decode.
 *  4. The addFunction trampoline lifecycle (callback installed before
 *     create, removed after destroy).
 *  5. Cancellation via session handle (both AbortSignal-after-create and
 *     pass3-syn-153 already-aborted-before-create).
 *  6. Async executor rejection propagation (the failed ToolResult is fed
 *     back to commons via step_with_result).
 *  7. The decode-failure-to-stalled disambiguation (pass3-syn-152).
 */

import { afterEach, describe, expect, it, vi } from 'vitest';
import {
  ToolCall,
  ToolCallingResult,
  ToolCallingSessionCreateRequest,
  ToolCallingSessionEvent,
  ToolCallingSessionStepWithResultRequest,
  ToolChoiceMode,
  ToolDefinition,
  ToolParameterType,
  ToolResult,
  type ToolCall as ProtoToolCall,
  type ToolCallingResult as ProtoToolCallingResult,
  type ToolCallingSessionCreateRequest as ProtoToolCallingSessionCreateRequest,
  type ToolCallingSessionStepWithResultRequest as ProtoToolCallingSessionStepWithResultRequest,
  type ToolDefinition as ProtoToolDefinition,
} from '@runanywhere/proto-ts/tool_calling';

import { ProtoErrorCode, SDKException } from '../../../../src/Foundation/SDKException';
import {
  clearRunanywhereModule,
  setRunanywhereModule,
  type EmscriptenRunanywhereModule,
} from '../../../../src/runtime/EmscriptenModule';
import { ToolCalling } from '../../../../src/Public/Extensions/RunAnywhere+ToolCalling';

// ---------------------------------------------------------------------------
// Proto-buffer ABI offsets the bridge expects from
// `_rac_wasm_offsetof_proto_buffer_*` exports.
// ---------------------------------------------------------------------------
const PROTO_BUFFER_SIZE = 16;
const OFF_DATA = 0;
const OFF_SIZE = 4;
const OFF_STATUS = 8;
const OFF_ERROR = 12;

// Sequential u64 handle the fake commons publishes on session_create. Matches
// the real commons counter (tool_calling_session.cpp:104). Tests assert this
// flows back through the addFunction trampoline and the cancel path.
const FAKE_SESSION_HANDLE = 0x42n;

// ---------------------------------------------------------------------------
// Fake module — synchronous emulation of the commons session ABI.
// ---------------------------------------------------------------------------

interface SessionScript {
  /**
   * Sequence of events to emit when `_rac_tool_calling_session_create_proto`
   * fires. The first call drains this list; subsequent
   * `_rac_tool_calling_session_step_with_result_proto` calls drain the
   * `onStep` per-call lists.
   */
  onCreate: ToolCallingSessionEvent[];
  /**
   * Per-step event lists. Indexed by the step counter (0 = events emitted
   * when the first step_with_result fires).
   */
  onStep?: ToolCallingSessionEvent[][];
  /**
   * Override the bytes emitted by the callback for the next create / step
   * call. Used to test the decode-failure path.
   */
  rawCallbackBytes?: Uint8Array | null;
  /** rc to return from session_create. Default 0. */
  createRc?: number;
  /** rc to return from session_step_with_result. Default 0. */
  stepRc?: number;
}

interface FakeToolCallingModule extends EmscriptenRunanywhereModule {
  capturedCreateRequest: ProtoToolCallingSessionCreateRequest | undefined;
  capturedStepRequests: ProtoToolCallingSessionStepWithResultRequest[];
  cancelHandles: Array<number | bigint>;
  destroyHandles: Array<number | bigint>;
  liveCallbacks: Map<number, (...args: number[]) => unknown>;
  activeCallbackIds: Set<number>;
  stepCallCount: number;
}

function makeFakeModule(script: SessionScript): FakeToolCallingModule {
  const heap = new ArrayBuffer(256 * 1024);
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

  const callbackTable = new Map<number, (...args: number[]) => unknown>();
  const liveCallbackIds = new Set<number>();
  let nextCallbackId = 1;

  const addFunction = (
    fn: (...args: number[]) => unknown,
    _signature: string,
  ): number => {
    const id = nextCallbackId++;
    callbackTable.set(id, fn);
    liveCallbackIds.add(id);
    return id;
  };

  const removeFunction = (ptr: number): void => {
    liveCallbackIds.delete(ptr);
    callbackTable.delete(ptr);
  };

  const writeBytes = (bytes: Uint8Array): { ptr: number; size: number } => {
    const ptr = malloc(bytes.byteLength);
    heapU8.set(bytes, ptr);
    return { ptr, size: bytes.byteLength };
  };

  const emitEvents = (
    callbackPtr: number,
    events: ToolCallingSessionEvent[],
  ): void => {
    const fn = callbackTable.get(callbackPtr);
    if (!fn) {
      throw new Error(`fake commons: unknown callback id ${callbackPtr}`);
    }
    for (const event of events) {
      const bytes = ToolCallingSessionEvent.encode(event).finish();
      const { ptr, size } = writeBytes(bytes);
      fn(ptr, size, 0);
    }
  };

  const emitRaw = (
    callbackPtr: number,
    bytes: Uint8Array,
  ): void => {
    const fn = callbackTable.get(callbackPtr);
    if (!fn) {
      throw new Error(`fake commons: unknown callback id ${callbackPtr}`);
    }
    const { ptr, size } = writeBytes(bytes);
    fn(ptr, size, 0);
  };

  const fake: Partial<FakeToolCallingModule> = {
    HEAPU8: heapU8,
    HEAPU32: heapU32,
    HEAP32: heap32,
    _malloc: malloc,
    _free: () => undefined,
    addFunction,
    removeFunction,
    UTF8ToString: () => '',
    stringToUTF8: () => undefined,
    lengthBytesUTF8: () => 0,
    capturedCreateRequest: undefined,
    capturedStepRequests: [],
    cancelHandles: [],
    destroyHandles: [],
    liveCallbacks: callbackTable,
    activeCallbackIds: liveCallbackIds,
    stepCallCount: 0,
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
    _rac_tool_calling_session_create_proto(
      requestPtr: number,
      requestSize: number,
      callbackPtr: number,
      _userData: number,
      outSessionHandlePtr: number,
    ): number {
      const requestBytes = heapU8.slice(requestPtr, requestPtr + requestSize);
      fake.capturedCreateRequest = ToolCallingSessionCreateRequest.decode(requestBytes);

      // Synchronously emit the scripted events through the registered
      // callback — exactly how commons drives the run loop.
      if (script.rawCallbackBytes) {
        emitRaw(callbackPtr, script.rawCallbackBytes);
      } else {
        emitEvents(callbackPtr, script.onCreate);
      }

      // Publish the session handle as low/high uint32 halves into the
      // malloc'd 8-byte slot.
      const handle = FAKE_SESSION_HANDLE;
      heapU32[outSessionHandlePtr >>> 2] = Number(handle & 0xffff_ffffn);
      heapU32[(outSessionHandlePtr >>> 2) + 1] = Number(handle >> 32n);
      return script.createRc ?? 0;
    },
    _rac_tool_calling_session_step_with_result_proto(
      requestPtr: number,
      requestSize: number,
    ): number {
      const requestBytes = heapU8.slice(requestPtr, requestPtr + requestSize);
      const stepRequest = ToolCallingSessionStepWithResultRequest.decode(requestBytes);
      fake.capturedStepRequests!.push(stepRequest);
      const idx = fake.stepCallCount!;
      fake.stepCallCount = idx + 1;

      // Find the callback installed at create. There's at most one for a
      // given session in this harness.
      const callbackPtr = Array.from(liveCallbackIds)[0];
      if (callbackPtr != null) {
        const next = script.onStep?.[idx] ?? [];
        emitEvents(callbackPtr, next);
      }
      return script.stepRc ?? 0;
    },
    _rac_tool_calling_session_destroy_proto(handle: number | bigint): number {
      fake.destroyHandles!.push(handle);
      return 0;
    },
    _rac_tool_calling_session_cancel_proto(handle: number | bigint): number {
      fake.cancelHandles!.push(handle);
      return 0;
    },
    // The supportsProtoToolCalling check + bridge require these to be present.
    _rac_tool_call_parse_proto: () => 0,
    _rac_tool_call_format_prompt_proto: () => 0,
    _rac_tool_call_validate_proto: () => 0,
  };
  return fake as FakeToolCallingModule;
}

function toolCallEvent(name: string, args: Record<string, unknown>): ToolCallingSessionEvent {
  return ToolCallingSessionEvent.fromPartial({
    seq: 1,
    toolCall: ToolCall.fromPartial({
      id: `call-${name}`,
      callId: `call-${name}`,
      name,
      argumentsJson: JSON.stringify(args),
    }),
  });
}

function finalResultEvent(text: string): ToolCallingSessionEvent {
  return ToolCallingSessionEvent.fromPartial({
    seq: 2,
    finalResult: ToolCallingResult.fromPartial({
      text,
      toolCalls: [],
      toolResults: [],
      isComplete: true,
      iterationsUsed: 1,
      errorCode: 0,
      rawText: text,
    }),
  });
}

function errorEvent(): ToolCallingSessionEvent {
  // 16-byte placeholder — the drain loop only checks length>0 to detect the
  // commons error_bytes arm of the oneof.
  return ToolCallingSessionEvent.fromPartial({
    seq: 3,
    errorBytes: new Uint8Array([1, 2, 3, 4, 5, 6, 7, 8]),
  });
}

function sampleToolDefinition(name = 'get_weather'): ProtoToolDefinition {
  return ToolDefinition.fromPartial({
    name,
    description: 'Get the weather for a location',
    parameters: [
      {
        name: 'location',
        type: ToolParameterType.TOOL_PARAMETER_TYPE_STRING,
        description: 'City name',
        required: true,
        enumValues: [],
      },
    ],
    examples: [],
  });
}

// ---------------------------------------------------------------------------
// Pure helper tests (buildSessionCreateRequest, decodeSessionEvent,
// encodeStepRequest) — exercised via the public surface.
// ---------------------------------------------------------------------------

describe('ToolCalling.buildSessionCreateRequest (via generateWithTools)', () => {
  afterEach(() => {
    clearRunanywhereModule();
    ToolCalling.clearTools();
  });

  it('serializes the session-create request with all session-level fields populated', async () => {
    const module = makeFakeModule({ onCreate: [finalResultEvent('hi')] });
    setRunanywhereModule(module);

    const tool = sampleToolDefinition();
    await ToolCalling.generateWithTools('What is the weather?', {
      tools: [tool],
      temperature: 0.42,
      maxTokens: 256,
      systemPrompt: 'You are helpful.',
      maxIterations: 5,
      keepToolsAvailable: true,
      formatHint: 'openai',
      toolChoice: ToolChoiceMode.TOOL_CHOICE_MODE_AUTO,
      forcedToolName: 'get_weather',
    });

    expect(module.capturedCreateRequest).toBeDefined();
    expect(module.capturedCreateRequest!.prompt).toBe('What is the weather?');
    expect(module.capturedCreateRequest!.maxTokens).toBe(256);
    expect(module.capturedCreateRequest!.temperature).toBeCloseTo(0.42, 5);
    expect(module.capturedCreateRequest!.systemPrompt).toBe('You are helpful.');
    expect(module.capturedCreateRequest!.tools).toHaveLength(1);
    expect(module.capturedCreateRequest!.tools[0]!.name).toBe('get_weather');
    expect(module.capturedCreateRequest!.formatHint).toBe('openai');
    expect(module.capturedCreateRequest!.maxIterations).toBe(5);
    expect(module.capturedCreateRequest!.keepToolsAvailable).toBe(true);
    // Swift makeRunLoopRequest parity (RunAnywhere+ToolCalling.swift:528-536):
    // validate_calls stays UNSET unless the caller specifies it, so commons
    // applies its documented default (true).
    expect(module.capturedCreateRequest!.validateCalls).toBeUndefined();
    expect(module.capturedCreateRequest!.toolChoice).toBe(
      ToolChoiceMode.TOOL_CHOICE_MODE_AUTO,
    );
    expect(module.capturedCreateRequest!.forcedToolName).toBe('get_weather');
  });

  it('falls back to maxToolCalls when maxIterations is unset', async () => {
    const module = makeFakeModule({ onCreate: [finalResultEvent('done')] });
    setRunanywhereModule(module);

    await ToolCalling.generateWithTools('Q', {
      tools: [sampleToolDefinition()],
      maxToolCalls: 7,
    });

    expect(module.capturedCreateRequest!.maxIterations).toBe(7);
  });
});

describe('ToolCalling decode/encode (via generateWithTools wire round-trip)', () => {
  afterEach(() => {
    clearRunanywhereModule();
    ToolCalling.clearTools();
  });

  it('happy-path decode: serialized ToolCallingSessionEvent reaches the drain loop', async () => {
    const module = makeFakeModule({ onCreate: [finalResultEvent('decoded ok')] });
    setRunanywhereModule(module);

    const result = await ToolCalling.generateWithTools('hi', {
      tools: [sampleToolDefinition()],
    });

    expect(result.text).toBe('decoded ok');
    expect(result.isComplete).toBe(true);
  });

  it('decode failure: surfaces structured "event decode failed" instead of "session stalled" (pass3-syn-152)', async () => {
    // Emit garbage that won't decode as ToolCallingSessionEvent. With the
    // pre-fix code, the callback returned null and the drain loop threw
    // "Tool-calling session stalled" with no breadcrumb pointing at the
    // real cause (proto decode break).
    const garbage = new Uint8Array([0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff]);
    const module = makeFakeModule({
      onCreate: [],
      rawCallbackBytes: garbage,
    });
    setRunanywhereModule(module);

    let captured: unknown;
    try {
      await ToolCalling.generateWithTools('hi', {
        tools: [sampleToolDefinition()],
      });
    } catch (err) {
      captured = err;
    }

    expect(captured).toBeInstanceOf(SDKException);
    const sdkErr = captured as SDKException;
    // `.code` is the positive proto ErrorCode (Swift parity); the signed
    // rac_result_t lives on `.cAbiCode`.
    expect(sdkErr.code).toBe(ProtoErrorCode.ERROR_CODE_BACKEND_ERROR);
    expect(sdkErr.cAbiCode).toBe(-ProtoErrorCode.ERROR_CODE_BACKEND_ERROR);
    expect(sdkErr.message).toMatch(/decode failed/i);
    expect(sdkErr.proto.nestedMessage ?? '').toMatch(/ToolCallingSessionEvent/i);
  });

  it('encodes step_with_result with the tool-call id, result JSON, and (on failure) the error message', async () => {
    const module = makeFakeModule({
      onCreate: [toolCallEvent('echo', { value: 'x' })],
      onStep: [[finalResultEvent('after-step')]],
    });
    setRunanywhereModule(module);

    ToolCalling.registerTool(
      ToolDefinition.fromPartial({ name: 'echo', description: '', parameters: [] }),
      async (call) => {
        return ToolResult.fromPartial({
          name: call.name,
          toolCallId: call.callId,
          callId: call.callId,
          resultJson: '{"echoed":"x"}',
          success: true,
        });
      },
    );

    const result = await ToolCalling.generateWithTools('use echo', {
      tools: [ToolDefinition.fromPartial({ name: 'echo' })],
    });

    expect(result.text).toBe('after-step');
    expect(module.capturedStepRequests).toHaveLength(1);
    expect(module.capturedStepRequests[0]!.toolCallId).toBe('call-echo');
    expect(module.capturedStepRequests[0]!.resultJson).toBe('{"echoed":"x"}');
    expect(module.capturedStepRequests[0]!.error).toBeUndefined();
    // sessionHandle is the low 32 bits of FAKE_SESSION_HANDLE (0x42).
    expect(module.capturedStepRequests[0]!.sessionHandle).toBe(
      Number(FAKE_SESSION_HANDLE),
    );
  });

  it('propagates executor rejection as a failed ToolResult in the step request', async () => {
    const module = makeFakeModule({
      onCreate: [toolCallEvent('bad', {})],
      onStep: [[finalResultEvent('after-fail')]],
    });
    setRunanywhereModule(module);

    ToolCalling.registerTool(
      ToolDefinition.fromPartial({ name: 'bad' }),
      async () => {
        throw new Error('tool blew up');
      },
    );

    const result = await ToolCalling.generateWithTools('try bad', {
      tools: [ToolDefinition.fromPartial({ name: 'bad' })],
    });

    expect(result.text).toBe('after-fail');
    expect(module.capturedStepRequests).toHaveLength(1);
    // Failed executor -> the callback path on ToolCalling.executeTool
    // returns a ToolResult with success=false + an error message; the
    // generator pipes that into step_with_result's `error` field.
    expect(module.capturedStepRequests[0]!.error).toBe('tool blew up');
  });
});

// ---------------------------------------------------------------------------
// addFunction trampoline lifecycle.
// ---------------------------------------------------------------------------

describe('ToolCalling.generateWithTools — addFunction trampoline lifecycle', () => {
  afterEach(() => {
    clearRunanywhereModule();
    ToolCalling.clearTools();
  });

  it('installs exactly one callback during create and removes it on cleanup', async () => {
    const module = makeFakeModule({ onCreate: [finalResultEvent('ok')] });
    setRunanywhereModule(module);

    const addSpy = vi.spyOn(module, 'addFunction');
    const removeSpy = vi.spyOn(module, 'removeFunction');

    await ToolCalling.generateWithTools('hi', {
      tools: [sampleToolDefinition()],
    });

    expect(addSpy).toHaveBeenCalledTimes(1);
    expect(removeSpy).toHaveBeenCalledTimes(1);
    // After cleanup, the callback table should be empty.
    expect(module.activeCallbackIds.size).toBe(0);
    // session_destroy ran during cleanup.
    expect(module.destroyHandles).toHaveLength(1);
    expect(module.destroyHandles[0]).toBe(Number(FAKE_SESSION_HANDLE));
  });

  it('removes the callback even when the executor closure rejects through the step path', async () => {
    const module = makeFakeModule({
      onCreate: [toolCallEvent('explodes', {})],
      // After the tool result is fed back, commons fires an error_bytes
      // terminal event. The drain loop throws — and cleanup still must run.
      onStep: [[errorEvent()]],
    });
    setRunanywhereModule(module);

    ToolCalling.registerTool(
      ToolDefinition.fromPartial({ name: 'explodes' }),
      async () => ToolResult.fromPartial({
        name: 'explodes',
        toolCallId: 'call-explodes',
        callId: 'call-explodes',
        success: false,
        error: 'no',
        resultJson: '',
      }),
    );

    await expect(
      ToolCalling.generateWithTools('use explodes', {
        tools: [ToolDefinition.fromPartial({ name: 'explodes' })],
      }),
    ).rejects.toBeInstanceOf(SDKException);

    expect(module.activeCallbackIds.size).toBe(0);
    expect(module.destroyHandles).toHaveLength(1);
  });
});

// ---------------------------------------------------------------------------
// Cancellation tests (pass2-syn-007 + pass3-syn-153).
// ---------------------------------------------------------------------------

describe('ToolCalling.generateWithTools — cancellation', () => {
  afterEach(() => {
    clearRunanywhereModule();
    ToolCalling.clearTools();
  });

  it('pass3-syn-153: throws synchronously without touching session_create when signal is already aborted', async () => {
    const module = makeFakeModule({ onCreate: [finalResultEvent('should-not-run')] });
    setRunanywhereModule(module);
    const createSpy = vi.spyOn(module, '_rac_tool_calling_session_create_proto');

    const controller = new AbortController();
    controller.abort();

    let captured: unknown;
    try {
      await ToolCalling.generateWithTools(
        'hi',
        { tools: [sampleToolDefinition()] },
        { signal: controller.signal },
      );
    } catch (err) {
      captured = err;
    }

    expect(captured).toBeInstanceOf(SDKException);
    expect((captured as SDKException).code).toBe(ProtoErrorCode.ERROR_CODE_GENERATION_CANCELLED);
    expect((captured as SDKException).cAbiCode).toBe(-ProtoErrorCode.ERROR_CODE_GENERATION_CANCELLED);
    expect((captured as SDKException).proto.nestedMessage ?? '').toMatch(/already aborted/i);
    // The eager-abort gate MUST be reached before we touch commons / addFunction.
    expect(createSpy).not.toHaveBeenCalled();
    expect(module.cancelHandles).toHaveLength(0);
    expect(module.destroyHandles).toHaveLength(0);
  });

  it('forwards a mid-stream AbortSignal abort to _rac_tool_calling_session_cancel_proto with the published handle', async () => {
    // Script: first event is a tool_call so the drain loop pauses to await
    // the executor. The executor aborts the controller before returning,
    // which fires the abort listener (registered AFTER create). The
    // subsequent step_with_result fires the final_result event so the loop
    // terminates cleanly.
    const module = makeFakeModule({
      onCreate: [toolCallEvent('noop', {})],
      onStep: [[finalResultEvent('done')]],
    });
    setRunanywhereModule(module);

    const controller = new AbortController();
    ToolCalling.registerTool(
      ToolDefinition.fromPartial({ name: 'noop' }),
      async (call) => {
        // Abort while the executor is awaiting — the addEventListener
        // path on the AbortSignal should now fire onAbort, which routes
        // to _rac_tool_calling_session_cancel_proto.
        controller.abort();
        return ToolResult.fromPartial({
          name: call.name,
          toolCallId: call.callId,
          callId: call.callId,
          success: true,
          resultJson: '{}',
        });
      },
    );

    await ToolCalling.generateWithTools(
      'use noop',
      { tools: [ToolDefinition.fromPartial({ name: 'noop' })] },
      { signal: controller.signal },
    );

    expect(module.cancelHandles.length).toBeGreaterThanOrEqual(1);
    // Cancel arg must match the published session handle (low 32 bits of
    // FAKE_SESSION_HANDLE in this harness).
    expect(module.cancelHandles[0]).toBe(Number(FAKE_SESSION_HANDLE));
    // Cleanup destroys the session exactly once.
    expect(module.destroyHandles).toHaveLength(1);
  });
});

// ---------------------------------------------------------------------------
// Executor rejection propagation through the public ToolCalling.executeTool
// surface (independent of the generateWithTools session driver).
// ---------------------------------------------------------------------------

describe('ToolCalling.executeTool — executor promise rejection', () => {
  afterEach(() => {
    ToolCalling.clearTools();
  });

  it('captures executor rejection as a failed ToolResult', async () => {
    ToolCalling.registerTool(
      ToolDefinition.fromPartial({ name: 'will_fail' }),
      async () => {
        throw new Error('boom');
      },
    );

    const result = await ToolCalling.executeTool(
      ToolCall.fromPartial({
        id: 'tc-1',
        callId: 'tc-1',
        name: 'will_fail',
        argumentsJson: '{}',
      }),
    );

    expect(result.success).toBe(false);
    expect(result.error).toBe('boom');
    expect(result.toolCallId).toBe('tc-1');
    expect(result.name).toBe('will_fail');
  });

  it('returns an Unknown-tool failure when the registry has no match', async () => {
    const result = await ToolCalling.executeTool(
      ToolCall.fromPartial({
        id: 'tc-2',
        callId: 'tc-2',
        name: 'not_registered',
        argumentsJson: '{}',
      }),
    );

    expect(result.success).toBe(false);
    expect(result.error).toMatch(/Unknown tool: not_registered/);
  });

  it('returns a successful ToolResult with metadata defaults when the executor resolves', async () => {
    ToolCalling.registerTool(
      ToolDefinition.fromPartial({ name: 'echo' }),
      async (call) => ToolResult.fromPartial({
        name: call.name,
        // Intentionally omit toolCallId / callId / startedAtMs / completedAtMs
        // to assert toolResultWithDefaults fills them in.
        resultJson: '{"echoed":true}',
        success: true,
      }),
    );

    const result = await ToolCalling.executeTool(
      ToolCall.fromPartial({
        id: 'tc-3',
        callId: 'tc-3',
        name: 'echo',
        argumentsJson: '{}',
      }),
    );

    expect(result.success).toBe(true);
    // toolResultWithDefaults backfills toolCallId from the originating call.
    expect(result.toolCallId).toBe('tc-3');
    expect(result.name).toBe('echo');
    expect(result.resultJson).toBe('{"echoed":true}');
    expect(result.completedAtMs).toBeGreaterThan(0);
    expect(result.startedAtMs).toBeGreaterThan(0);
  });
});

// ---------------------------------------------------------------------------
// Smoke: the public surface compiles against the type-level expected
// signatures the harness uses elsewhere. Avoids "imports work but the types
// drifted" silent breaks.
// ---------------------------------------------------------------------------

describe('ToolCalling public types', () => {
  it('ToolCall / ToolDefinition / ToolCallingResult are usable without explicit casts', () => {
    const tool: ProtoToolDefinition = sampleToolDefinition();
    const call: ProtoToolCall = ToolCall.fromPartial({
      id: 'x',
      name: tool.name,
      argumentsJson: '{}',
    });
    const result: ProtoToolCallingResult = ToolCallingResult.fromPartial({
      text: 'ok',
      toolCalls: [call],
      isComplete: true,
    });
    expect(result.text).toBe('ok');
  });
});
