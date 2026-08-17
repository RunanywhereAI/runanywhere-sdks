/**
 * StreamFailureNotParked.test.ts
 *
 * A stream failure has to reach the consumer even when the consumer is not
 * parked on `next()` at the instant it happens.
 *
 * Both hand-rolled iterators here (`OffscreenRuntimeBridge.getStreamIterator`
 * and `streamCallback` in `ProtoAdapterTypes`) reject the waiters that happen
 * to be parked. Neither used to keep the error anywhere, so a failure that
 * arrived while the consumer was between `next()` calls was reported to the
 * following `next()` as a clean end-of-stream.
 *
 * Run from `bindings/web/packages/core`:
 *
 *     npx vitest run tests/unit/runtime/StreamFailureNotParked.test.ts
 */

import { afterEach, beforeEach, describe, expect, it } from 'vitest';

import {
  OffscreenRuntimeBridge,
  setStreamWorkerInit,
} from '../../../src/runtime/OffscreenRuntimeBridge';
import { setStreamWorkerFactory } from '../../../src/runtime/StreamWorkerFactoryRegistry';
import { streamCallback, type ModalityProtoModule } from '../../../src/Adapters/ProtoAdapterTypes';
import type { ProtoCodec } from '../../../src/runtime/ProtoWasm';
import type { WorkerRequest, WorkerResponse } from '../../../src/runtime/StreamWorker';

const uint32Codec: ProtoCodec<number> = {
  encode(_message: number) {
    return { finish: (): Uint8Array => new Uint8Array(0) };
  },
  decode(input: Uint8Array): number {
    return new DataView(input.buffer, input.byteOffset, input.byteLength).getUint32(0, true);
  },
};

function encodeU32(value: number): Uint8Array {
  const out = new Uint8Array(4);
  new DataView(out.buffer).setUint32(0, value, true);
  return out;
}

/**
 * Posts one callback for the stream request and then stays quiet until the
 * test calls {@link crash}. Nothing is timer-driven, so "the consumer is
 * between `next()` calls" is a fact of the test rather than a race it hopes
 * to win.
 */
class CrashingWorker {
  onmessage: ((ev: MessageEvent<WorkerResponse>) => void) | null = null;
  onerror: ((ev: ErrorEvent) => void) | null = null;

  private requestId: string | null = null;

  constructor() {
    queueMicrotask(() => this.deliver({ type: 'ready' }));
  }

  postMessage(msg: WorkerRequest): void {
    // Everything that is not `init` or `cancel` is a stream request, and the
    // union narrows to the variants carrying `requestId`.
    if (msg.type === 'init' || msg.type === 'cancel') return;
    this.requestId = msg.requestId;
    this.deliver({
      type: 'callback',
      requestId: msg.requestId,
      payloadBytes: encodeU32(1),
    });
  }

  /** The worker dies mid-stream, the way a WASM OOM kills it. */
  crash(message: string): void {
    this.deliver({
      type: 'error',
      requestId: this.requestId ?? undefined,
      message,
    });
  }

  terminate(): void {}

  private deliver(data: WorkerResponse): void {
    this.onmessage?.({ data } as MessageEvent<WorkerResponse>);
  }
}

interface FakeModule extends ModalityProtoModule {
  /** Emit a uint32 value through the currently-installed callback. */
  emitValue: (callbackPtr: number, value: number) => void;
}

/** Same shape as the fake in `Adapters/StreamLiveDelivery.test.ts`. */
function makeFakeModule(): FakeModule {
  const heap = new Uint8Array(4 * 1024);
  const callbacks = new Map<number, (bytesPtr: number, size: number) => unknown>();
  let nextPtr = 1;
  // `streamCallback` treats bytesPtr === 0 as a null sentinel, so start at 1.
  let heapCursor = 1;

  const mod: Partial<FakeModule> = {
    HEAPU8: heap,
    addFunction(fn, _signature) {
      const id = nextPtr++;
      callbacks.set(id, fn as (bytesPtr: number, size: number) => unknown);
      return id;
    },
    removeFunction(ptr) {
      callbacks.delete(ptr);
    },
    emitValue(callbackPtr: number, value: number): void {
      const fn = callbacks.get(callbackPtr);
      if (!fn) throw new Error(`emitValue: no callback at ptr ${callbackPtr}`);
      heap.set(encodeU32(value), heapCursor);
      const ptr = heapCursor;
      heapCursor += 4;
      fn(ptr, 4);
    },
  };
  return mod as FakeModule;
}

describe('a stream failure that lands while the consumer is not parked', () => {
  let worker: CrashingWorker | null = null;

  beforeEach(() => {
    OffscreenRuntimeBridge.resetForTesting();
    setStreamWorkerFactory(null);
    setStreamWorkerInit(null);
  });

  afterEach(() => {
    worker = null;
    setStreamWorkerFactory(null);
    setStreamWorkerInit(null);
    OffscreenRuntimeBridge.resetForTesting();
  });

  it('is raised by the worker bridge rather than read as end-of-stream', async () => {
    setStreamWorkerInit({ wasmBytes: new ArrayBuffer(0), moduleFactoryId: 'fake-factory' });
    setStreamWorkerFactory(() => {
      worker = new CrashingWorker();
      return worker as unknown as Worker;
    });

    const bridge = OffscreenRuntimeBridge.tryGet('worker');
    expect(bridge).not.toBeNull();

    const stream = bridge!.getStreamIterator(
      { kind: 'stream.llm.generate', handle: 0, requestBytes: new Uint8Array() },
      uint32Codec,
    );
    const iterator = stream[Symbol.asyncIterator]();

    expect(await iterator.next()).toEqual({ value: 1, done: false });

    // No waiter is parked here, which is the state a consumer is in while it
    // renders the token it just received.
    worker!.crash('worker died');

    await expect(iterator.next()).rejects.toThrow('worker died');
  });

  it('is raised by streamCallback rather than read as end-of-stream', async () => {
    const fake = makeFakeModule();

    // The first emit wakes the parked consumer; the second is buffered, so
    // when the call throws there is no waiter left to reject.
    const iterator = streamCallback(fake, uint32Codec, 'crashing_test_stream', (callbackPtr) => {
      fake.emitValue(callbackPtr, 1);
      fake.emitValue(callbackPtr, 2);
      throw new Error('native call failed');
    })[Symbol.asyncIterator]();

    expect(await iterator.next()).toEqual({ value: 1, done: false });
    expect(await iterator.next()).toEqual({ value: 2, done: false });

    await expect(iterator.next()).rejects.toThrow('native call failed');
  });

  it('lets an explicit cancel outrank a failure the consumer never read', async () => {
    setStreamWorkerInit({ wasmBytes: new ArrayBuffer(0), moduleFactoryId: 'fake-factory' });
    setStreamWorkerFactory(() => {
      worker = new CrashingWorker();
      return worker as unknown as Worker;
    });

    const stream = OffscreenRuntimeBridge.tryGet('worker')!.getStreamIterator(
      { kind: 'stream.llm.generate', handle: 0, requestBytes: new Uint8Array() },
      uint32Codec,
    );
    const iterator = stream[Symbol.asyncIterator]();

    expect(await iterator.next()).toEqual({ value: 1, done: false });
    worker!.crash('worker died');

    // The consumer walked away instead of reading the error, so it should not
    // be handed that error afterwards.
    await iterator.return?.();
    expect(await iterator.next()).toEqual({ value: undefined, done: true });
  });
});
