import { describe, expect, it } from 'vitest';

import {
  registerStreamModuleFactory,
  runStreamWorker,
  type StreamWorkerModule,
  type StreamWorkerScope,
  type WorkerRequest,
  type WorkerResponse,
} from '../../../src/runtime/StreamWorker';

interface AsyncifyWorkerModule extends StreamWorkerModule {
  ccallObservations: Array<{ functionName: string; async: boolean }>;
  directCalls: number;
  freeCalls: number[];
  requestPtr: number;
  resolveNative(returnCode: number): void;
}

function makeAsyncifyWorkerModule(): AsyncifyWorkerModule {
  const heap = new Uint8Array(4096);
  const callbacks = new Map<number, (...args: number[]) => number | void>();
  let nextPtr = 64;
  let nextCallback = 1;
  let resolveNative: ((returnCode: number) => void) | undefined;
  const nativeGate = new Promise<number>((resolve) => {
    resolveNative = resolve;
  });

  const module: AsyncifyWorkerModule = {
    HEAPU8: heap,
    ccallObservations: [],
    directCalls: 0,
    freeCalls: [],
    requestPtr: 0,
    _malloc(size) {
      const ptr = nextPtr;
      nextPtr += Math.max(4, (size + 3) & ~3);
      return ptr;
    },
    _free(ptr) {
      module.freeCalls.push(ptr);
    },
    addFunction(fn) {
      const ptr = nextCallback;
      nextCallback += 1;
      callbacks.set(ptr, fn);
      return ptr;
    },
    removeFunction(ptr) {
      callbacks.delete(ptr);
    },
    ccall(functionName, _returnType, _argumentTypes, args, options) {
      module.ccallObservations.push({ functionName, async: options?.async === true });
      const requestPtr = Number(args[0]);
      const callbackPtr = Number(args[2]);
      if (!Number.isFinite(requestPtr) || !Number.isFinite(callbackPtr)) {
        throw new TypeError('worker ccall received non-numeric pointers');
      }
      module.requestPtr = requestPtr;
      const callback = callbacks.get(callbackPtr);
      if (!callback) throw new Error(`worker callback ${callbackPtr} is not registered`);
      const eventPtr = module._malloc(4);
      heap.set([1, 2, 3, 4], eventPtr);
      callback(eventPtr, 4, 0);
      return nativeGate;
    },
    _rac_llm_generate_stream_proto() {
      module.directCalls += 1;
      return -1;
    },
    _rac_vlm_stream_proto() {
      module.directCalls += 1;
      return -1;
    },
    resolveNative(returnCode) {
      if (!resolveNative) throw new Error('native gate already resolved');
      const resolve = resolveNative;
      resolveNative = undefined;
      resolve(returnCode);
    },
  };
  return module;
}

async function flushMicrotasks(): Promise<void> {
  await Promise.resolve();
  await Promise.resolve();
  await Promise.resolve();
}

async function exerciseAsyncWorkerCall(kind: 'llm' | 'vlm'): Promise<void> {
  const module = makeAsyncifyWorkerModule();
  const responses: WorkerResponse[] = [];
  const scope: StreamWorkerScope = {
    onmessage: null,
    postMessage(message) {
      responses.push(message);
    },
  };
  const factoryId = `asyncify-${kind}-${Math.random().toString(36).slice(2)}`;
  registerStreamModuleFactory(factoryId, async () => module);
  runStreamWorker(scope);

  const dispatch = (request: WorkerRequest): void => {
    scope.onmessage?.({ data: request } as MessageEvent<WorkerRequest>);
  };
  dispatch({ type: 'init', wasmBytes: new ArrayBuffer(0), moduleFactoryId: factoryId });
  await flushMicrotasks();
  expect(responses).toContainEqual({ type: 'ready' });

  const requestId = `${kind}-request`;
  dispatch(kind === 'llm'
    ? {
      type: 'stream.llm.generate',
      requestId,
      handle: 0,
      requestBytes: Uint8Array.of(9, 8, 7),
    }
    : {
      type: 'stream.vlm.generate',
      requestId,
      requestBytes: Uint8Array.of(9, 8, 7),
    });
  await flushMicrotasks();

  const functionName = kind === 'llm'
    ? 'rac_llm_generate_stream_proto'
    : 'rac_vlm_stream_proto';
  expect(module.ccallObservations).toContainEqual({ functionName, async: true });
  expect(module.directCalls).toBe(0);
  expect(responses.some((response) => (
    response.type === 'callback' && response.requestId === requestId
  ))).toBe(true);
  expect(module.requestPtr).toBeGreaterThan(0);
  expect(module.freeCalls).not.toContain(module.requestPtr);

  module.resolveNative(0);
  await flushMicrotasks();
  expect(module.freeCalls).toContain(module.requestPtr);
  expect(responses).toContainEqual({ type: 'done', requestId, returnCode: 0 });
}

describe('StreamWorker Asyncify dispatch', () => {
  it('uses async ccall and retains LLM request bytes until settlement', async () => {
    await exerciseAsyncWorkerCall('llm');
  });

  it('uses async ccall and retains VLM request bytes until settlement', async () => {
    await exerciseAsyncWorkerCall('vlm');
  });
});
