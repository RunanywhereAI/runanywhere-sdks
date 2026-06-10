/**
 * StreamWorker.test.ts
 *
 * T6.1 — `OffscreenRuntimeBridge` Worker-path coverage.
 *
 * The bridge's central guarantee is that consumer-visible callbacks
 * arrive incrementally — not in one batched flush at the end. We assert
 * this by spawning a fake Worker that posts back five `callback`
 * messages over time, then a `done`. The test captures whether `done`
 * has been posted by the fake at the moment the consumer observes the
 * first callback; the answer MUST be `false`.
 *
 * Cancellation is the dual: after the consumer breaks out of the
 * async-for loop the bridge must (a) post a `cancel` to the worker and
 * (b) silently drop any further `callback` messages so the consumer
 * never sees them.
 *
 * Test-environment caveat (DECISION-7 deviation): the project's
 * lockfile is in a state that prevents installing happy-dom from the
 * agent sandbox (EACCES on the npm cache). Adding the per-file Vitest
 * environment pragma for happy-dom would crash with
 * `Cannot find package 'happy-dom'`. We instead keep Vitest's default
 * `node` env and inject the Worker dependency via the
 * `StreamWorkerFactoryRegistry` — the test never touches a real
 * `Worker` constructor, so the env choice is moot for what we assert.
 * Documented inline so the next person doesn't re-litigate it.
 *
 * Run from `sdk/runanywhere-web/packages/core`:
 *
 *     npx vitest run tests/unit/runtime/StreamWorker.test.ts
 */

import { afterEach, beforeEach, describe, expect, it } from 'vitest';

import {
  OffscreenRuntimeBridge,
  setStreamWorkerInit,
} from '../../../src/runtime/OffscreenRuntimeBridge';
import {
  setStreamWorkerFactory,
} from '../../../src/runtime/StreamWorkerFactoryRegistry';
import {
  streamCallback,
  type ModalityProtoModule,
} from '../../../src/Adapters/ProtoAdapterTypes';
import type { ProtoCodec } from '../../../src/runtime/ProtoWasm';
import type {
  WorkerRequest,
  WorkerResponse,
} from '../../../src/runtime/StreamWorker';

// ---------------------------------------------------------------------------
// Codec — 4-byte LE uint32 (matches `StreamLiveDelivery.test.ts`)
// ---------------------------------------------------------------------------

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

// ---------------------------------------------------------------------------
// Fake Worker — schedules `totalCallbacks` callbacks then a `done`.
// ---------------------------------------------------------------------------

interface FakeWorkerOptions {
  totalCallbacks: number;
  /** Spacing between scheduled `callback` messages (ms). */
  intervalMs?: number;
  /**
   * When true, the fake follows the real init→ready handshake protocol
   * — it does NOT post `ready` until it observes an `init` message.
   * When false (default for legacy tests), the fake posts `ready`
   * immediately from the constructor. See pass2-syn-030.
   */
  honorInit?: boolean;
  /**
   * When set, the fake responds to `init` with the supplied response
   * after `initDelayMs` rather than posting `ready`. Use this to drive
   * the failed-init error case.
   */
  initFailure?: { message: string; afterMs?: number };
  /**
   * When true, the fake observes `init` but never posts back — used to
   * verify the bridge's handshake timeout fires.
   */
  hangOnInit?: boolean;
}

interface FakeWorkerObservations {
  donePosted: boolean;
  cancelRequestIds: string[];
  /** Number of `callback` messages the fake DELIVERED to the consumer
   *  (i.e. ones that survived the cancel check on the fake side). */
  deliveredCallbacks: number;
  /** True once the fake observed an `init` message from the bridge. */
  initObserved: boolean;
  /** Number of stream requests posted to the fake. */
  streamRequestsObserved: number;
}

class FakeStreamWorker {
  onmessage: ((ev: MessageEvent<WorkerResponse>) => void) | null = null;
  onerror: ((ev: ErrorEvent) => void) | null = null;

  readonly observations: FakeWorkerObservations = {
    donePosted: false,
    cancelRequestIds: [],
    deliveredCallbacks: 0,
    initObserved: false,
    streamRequestsObserved: 0,
  };

  private terminated = false;
  private readonly cancelled = new Set<string>();
  private readonly timers: ReturnType<typeof setTimeout>[] = [];

  constructor(private readonly options: FakeWorkerOptions) {
    // Legacy behaviour: post `ready` from the constructor unless the
    // test explicitly opts into the real init→ready handshake.
    if (!options.honorInit && !options.hangOnInit && !options.initFailure) {
      queueMicrotask(() => this.deliver({ type: 'ready' }));
    }
  }

  postMessage(msg: WorkerRequest): void {
    if (this.terminated) return;
    switch (msg.type) {
      case 'init':
        this.observations.initObserved = true;
        if (this.options.hangOnInit) {
          // Intentional black hole — exercises the bridge handshake
          // timeout path (pass2-syn-092).
          return;
        }
        if (this.options.initFailure) {
          const after = this.options.initFailure.afterMs ?? 0;
          const message = this.options.initFailure.message;
          this.timers.push(setTimeout(() => {
            if (this.terminated) return;
            this.deliver({ type: 'error', message });
          }, after));
          return;
        }
        if (this.options.honorInit) {
          // Real handshake: post `ready` only after observing `init`.
          queueMicrotask(() => this.deliver({ type: 'ready' }));
        }
        return;
      case 'cancel':
        this.cancelled.add(msg.requestId);
        this.observations.cancelRequestIds.push(msg.requestId);
        return;
      case 'stream.llm.generate':
      case 'stream.stt.transcribe':
      case 'stream.tts.synthesize':
      case 'stream.vlm.process':
        this.observations.streamRequestsObserved += 1;
        this.scheduleStream(msg.requestId);
        return;
    }
  }

  terminate(): void {
    this.terminated = true;
    for (const t of this.timers) clearTimeout(t);
    this.timers.length = 0;
  }

  private scheduleStream(requestId: string): void {
    const interval = this.options.intervalMs ?? 5;
    for (let i = 1; i <= this.options.totalCallbacks; i++) {
      const value = i;
      this.timers.push(setTimeout(() => {
        if (this.terminated || this.cancelled.has(requestId)) return;
        this.observations.deliveredCallbacks += 1;
        this.deliver({
          type: 'callback',
          requestId,
          payloadBytes: encodeU32(value),
        });
      }, i * interval));
    }
    this.timers.push(setTimeout(() => {
      if (this.terminated) return;
      this.observations.donePosted = true;
      this.deliver({
        type: 'done',
        requestId,
        returnCode: this.cancelled.has(requestId) ? -131 : 0,
      });
    }, (this.options.totalCallbacks + 1) * interval));
  }

  private deliver(msg: WorkerResponse): void {
    this.onmessage?.({ data: msg } as MessageEvent<WorkerResponse>);
  }
}

// ---------------------------------------------------------------------------
// Fake main-thread module — used by the fallback test for the existing
// `streamCallback` (queueMicrotask) path.
// ---------------------------------------------------------------------------

interface FakeModule extends ModalityProtoModule {
  emitValue(callbackPtr: number, value: number): void;
}

function makeFakeModule(): FakeModule {
  const heap = new Uint8Array(64 * 1024);
  const callbacks = new Map<number, (bytesPtr: number, size: number) => unknown>();
  let nextPtr = 1;
  let heapCursor = 1;

  return {
    HEAPU8: heap,
    addFunction(fn, _signature) {
      const id = nextPtr++;
      callbacks.set(id, fn as (bytesPtr: number, size: number) => unknown);
      return id;
    },
    removeFunction(ptr) { callbacks.delete(ptr); },
    emitValue(callbackPtr, value) {
      const fn = callbacks.get(callbackPtr);
      if (!fn) throw new Error(`emitValue: no callback at ptr ${callbackPtr}`);
      const bytes = encodeU32(value);
      if (heapCursor + 4 > heap.length) heapCursor = 1;
      heap.set(bytes, heapCursor);
      const ptr = heapCursor;
      heapCursor += 4;
      fn(ptr, 4);
    },
  } as FakeModule;
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

describe('StreamWorker bridge — OffscreenRuntimeBridge (T6.1 Worker path)', () => {
  let activeWorker: FakeStreamWorker | null = null;

  /** Install a dummy init payload so `OffscreenRuntimeBridge.tryGet()`
   *  returns the bridge in tests. The fake worker ignores the wasm
   *  bytes — the bridge gate is what we're satisfying. */
  const installDummyInit = (): void => {
    setStreamWorkerInit({
      wasmBytes: new ArrayBuffer(0),
      moduleFactoryId: 'fake-factory',
    });
  };

  beforeEach(() => {
    OffscreenRuntimeBridge.resetForTesting();
    setStreamWorkerFactory(null);
    setStreamWorkerInit(null);
  });

  afterEach(() => {
    activeWorker?.terminate();
    activeWorker = null;
    setStreamWorkerFactory(null);
    setStreamWorkerInit(null);
    OffscreenRuntimeBridge.resetForTesting();
  });

  it('Worker mode delivers first callback before done', async () => {
    installDummyInit();
    // Construct the fake INSIDE the factory so the `ready` microtask is
    // queued AFTER the bridge has installed `onmessage` (the bridge sets
    // it synchronously after calling the factory).
    setStreamWorkerFactory(() => {
      activeWorker = new FakeStreamWorker({ totalCallbacks: 5, intervalMs: 5 });
      return activeWorker as unknown as Worker;
    });

    const bridge = OffscreenRuntimeBridge.tryGet('worker');
    expect(bridge).not.toBeNull();

    const iter = bridge!.getStreamIterator(
      { kind: 'stream.llm.generate', handle: 0, requestBytes: new Uint8Array() },
      uint32Codec,
    );

    const it = iter[Symbol.asyncIterator]();
    const first = await it.next();
    expect(first.done).toBe(false);
    expect(first.value).toBe(1);

    // Central invariant — the consumer observed the first callback
    // BEFORE the worker posted `done`. Pre-Worker the only delivery
    // mode was "every event after the export returns".
    expect(activeWorker!.observations.donePosted).toBe(false);

    const rest: number[] = [];
    while (true) {
      const r = await it.next();
      if (r.done) break;
      rest.push(r.value);
    }
    expect(rest).toEqual([2, 3, 4, 5]);
    expect(activeWorker!.observations.donePosted).toBe(true);
    expect(activeWorker!.observations.deliveredCallbacks).toBe(5);
  });

  it('cancel() interrupts mid-stream', async () => {
    installDummyInit();
    setStreamWorkerFactory(() => {
      activeWorker = new FakeStreamWorker({ totalCallbacks: 5, intervalMs: 10 });
      return activeWorker as unknown as Worker;
    });

    const bridge = OffscreenRuntimeBridge.tryGet('worker')!;
    const iter = bridge.getStreamIterator(
      { kind: 'stream.llm.generate', handle: 0, requestBytes: new Uint8Array() },
      uint32Codec,
    );
    const it = iter[Symbol.asyncIterator]();

    const consumed: number[] = [];
    consumed.push((await it.next()).value as number);
    consumed.push((await it.next()).value as number);
    expect(consumed).toEqual([1, 2]);

    // Cancel via the public AsyncIterator return contract — the bridge
    // posts `{type:'cancel', requestId}` to the worker.
    const cancelResult = await it.return!();
    expect(cancelResult.done).toBe(true);
    expect(activeWorker!.observations.cancelRequestIds).toHaveLength(1);

    // The next pull must immediately report done.
    const after = await it.next();
    expect(after.done).toBe(true);

    // Give the fake worker enough wall-clock time to finish its
    // schedule. The bridge MUST drop every in-flight callback for the
    // cancelled requestId; the consumer's array stays at length 2.
    await new Promise((r) => setTimeout(r, 100));
    expect(consumed).toHaveLength(2);
    // Fake honoured cancel — no further callbacks delivered after
    // requestId was cancelled, so `deliveredCallbacks` stays at ≤ 2.
    expect(activeWorker!.observations.deliveredCallbacks).toBeLessThanOrEqual(2);
  });

  it('falls back to main-thread when no factory registered', async () => {
    // Sanity: with no factory the bridge returns null for every mode.
    // (No init payload registered either — both gates apply.)
    expect(OffscreenRuntimeBridge.tryGet('auto')).toBeNull();
    expect(OffscreenRuntimeBridge.tryGet('worker')).toBeNull();
    expect(OffscreenRuntimeBridge.tryGet('main')).toBeNull();

    // Exercise the existing queueMicrotask path (T3.1 MVP). The fake
    // module drives `streamCallback` synchronously; the iterator must
    // still observe every event.
    const fake = makeFakeModule();
    const TOTAL = 5;
    const iter = streamCallback(
      fake,
      uint32Codec,
      'fallback_path_test',
      (callbackPtr) => {
        for (let i = 1; i <= TOTAL; i++) fake.emitValue(callbackPtr, i);
        return 0;
      },
    );

    const out: number[] = [];
    for await (const v of iter) out.push(v);
    expect(out).toEqual([1, 2, 3, 4, 5]);
  });

  // -------------------------------------------------------------------------
  // pass2-syn-030: init→ready protocol coverage
  // -------------------------------------------------------------------------

  it('pre-ready: stream request queued until `ready` arrives (init→ready handshake)', async () => {
    installDummyInit();
    // `honorInit: true` — the fake posts `ready` only AFTER it observes
    // `init` from the bridge, so we exercise the queuing path.
    setStreamWorkerFactory(() => {
      activeWorker = new FakeStreamWorker({
        totalCallbacks: 3,
        intervalMs: 5,
        honorInit: true,
      });
      return activeWorker as unknown as Worker;
    });

    const bridge = OffscreenRuntimeBridge.tryGet('worker');
    expect(bridge).not.toBeNull();

    const iter = bridge!.getStreamIterator(
      { kind: 'stream.llm.generate', handle: 0, requestBytes: new Uint8Array() },
      uint32Codec,
    );

    // Pull immediately — before the bridge could have received `ready`.
    // The bridge's getStreamIterator path defers the stream postMessage
    // until spawnWorker() resolves; the fake won't schedule callbacks
    // until it observes the stream request, and won't even post ready
    // until it observes init. This proves the bridge does NOT race the
    // stream request ahead of the handshake.
    const it = iter[Symbol.asyncIterator]();
    const first = await it.next();
    expect(first.done).toBe(false);
    expect(first.value).toBe(1);
    expect(activeWorker!.observations.initObserved).toBe(true);

    const rest: number[] = [];
    while (true) {
      const r = await it.next();
      if (r.done) break;
      rest.push(r.value);
    }
    expect(rest).toEqual([2, 3]);
  });

  it('failed init: bridge propagates the worker error to the consumer iterator', async () => {
    installDummyInit();
    setStreamWorkerFactory(() => {
      activeWorker = new FakeStreamWorker({
        totalCallbacks: 0,
        initFailure: { message: 'instantiation failed', afterMs: 0 },
      });
      return activeWorker as unknown as Worker;
    });

    const bridge = OffscreenRuntimeBridge.tryGet('worker');
    expect(bridge).not.toBeNull();

    const iter = bridge!.getStreamIterator(
      { kind: 'stream.llm.generate', handle: 0, requestBytes: new Uint8Array() },
      uint32Codec,
    );
    const it = iter[Symbol.asyncIterator]();
    await expect(it.next()).rejects.toThrowError(/instantiation failed/);
    // No stream request should have been dispatched — the bridge bailed
    // out on the handshake before sending the stream postMessage.
    expect(activeWorker!.observations.streamRequestsObserved).toBe(0);
  });

  // -------------------------------------------------------------------------
  // pass2-syn-034: factory installed but setStreamWorkerInit not called.
  // The bridge must NOT spawn a worker that can never be initialised.
  // -------------------------------------------------------------------------

  it('factory-but-no-init: tryGet returns null with actionable warning', () => {
    setStreamWorkerFactory(() => {
      throw new Error('factory should not be invoked when init is missing');
    });
    // No `installDummyInit()` — this is exactly the "backend forgot to
    // call setStreamWorkerInit" regression.
    expect(OffscreenRuntimeBridge.tryGet('worker')).toBeNull();
    expect(OffscreenRuntimeBridge.tryGet('auto')).toBeNull();
  });
});
