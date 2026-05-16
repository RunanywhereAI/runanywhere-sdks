/**
 * StreamLiveDelivery.test.ts
 *
 * T3.1 — Web live stream delivery MVP. Verifies that `streamCallback`:
 *
 *   1. Still drains every event for a purely synchronous native-call
 *      wrapper (backward compatibility with the production llamacpp /
 *      ONNX path).
 *   2. Lets a cooperative ASYNC native-call wrapper deliver events to
 *      the consumer iterator BEFORE the wrapper's Promise resolves —
 *      i.e. live delivery, not "wait for the whole batch then drain".
 *   3. Honours `iterator.return()` mid-stream — the `onCancel` hook
 *      fires immediately and subsequent emits from the still-running
 *      wrapper are silently dropped.
 *
 * Runner: Vitest. Invoke from `sdk/runanywhere-web/packages/core`:
 *
 *     npx vitest run tests/unit/Adapters/StreamLiveDelivery.test.ts
 *
 * See `docs/STREAM_DELIVERY_DESIGN.md` for the architectural framing
 * (MVP, follow-up options, recommended next step).
 */

import { describe, expect, it } from 'vitest';

import {
  streamCallback,
  streamYield,
  type ModalityProtoModule,
} from '../../../src/Adapters/ProtoAdapterTypes';
import type { ProtoCodec } from '../../../src/runtime/ProtoWasm';

// ---------------------------------------------------------------------------
// Test fixtures
// ---------------------------------------------------------------------------

/**
 * Trivial 4-byte little-endian uint32 codec. We only ever need `decode`
 * (encoded events are written directly into the fake HEAPU8 by `emitValue`),
 * so `encode` is a no-op return shape that satisfies the type.
 */
const uint32Codec: ProtoCodec<number> = {
  encode(_message: number) {
    return {
      finish(): Uint8Array {
        return new Uint8Array(0);
      },
    };
  },
  decode(input: Uint8Array): number {
    return new DataView(input.buffer, input.byteOffset, input.byteLength).getUint32(0, true);
  },
};

interface FakeModule extends ModalityProtoModule {
  /** Emit a uint32 value through the currently-installed callback. */
  emitValue: (callbackPtr: number, value: number) => void;
  /** Number of times `addFunction` has been called (≈ callback installs). */
  readonly addFunctionCalls: number;
  /** Number of times `removeFunction` has been called (≈ tear-downs). */
  readonly removeFunctionCalls: number;
}

function makeFakeModule(): FakeModule {
  const heap = new Uint8Array(64 * 1024);
  const callbacks = new Map<number, (bytesPtr: number, size: number) => unknown>();
  let nextPtr = 1;
  // Start the heap cursor at 1 — `streamCallback` treats bytesPtr === 0 as
  // a sentinel/null and bails inside the trampoline, so any value written
  // at offset 0 would be silently dropped.
  let heapCursor = 1;
  let addCount = 0;
  let removeCount = 0;

  const mod: Partial<FakeModule> & {
    addFunctionCalls?: number;
    removeFunctionCalls?: number;
  } = {
    HEAPU8: heap,
    addFunction(fn, _signature) {
      addCount += 1;
      const id = nextPtr++;
      callbacks.set(id, fn as (bytesPtr: number, size: number) => unknown);
      return id;
    },
    removeFunction(ptr) {
      removeCount += 1;
      callbacks.delete(ptr);
    },
    emitValue(callbackPtr: number, value: number): void {
      const fn = callbacks.get(callbackPtr);
      if (!fn) throw new Error(`emitValue: no callback at ptr ${callbackPtr}`);
      const buf = new ArrayBuffer(4);
      new DataView(buf).setUint32(0, value, true);
      // Wrap heap cursor before write to avoid running past the arena end
      // when many events are emitted in a long test.
      if (heapCursor + 4 > heap.length) heapCursor = 1;
      heap.set(new Uint8Array(buf), heapCursor);
      const ptr = heapCursor;
      heapCursor += 4;
      fn(ptr, 4);
    },
  };
  Object.defineProperty(mod, 'addFunctionCalls', { get: () => addCount });
  Object.defineProperty(mod, 'removeFunctionCalls', { get: () => removeCount });
  return mod as FakeModule;
}

async function collectAll<T>(iter: AsyncIterable<T>, max = 1_000): Promise<T[]> {
  const out: T[] = [];
  const it = iter[Symbol.asyncIterator]();
  for (let i = 0; i < max; i++) {
    const r = await it.next();
    if (r.done) break;
    out.push(r.value);
  }
  return out;
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

describe('streamCallback live delivery (T3.1 MVP)', () => {
  it('drains every event from a synchronous native-call wrapper (backward compat)', async () => {
    const fake = makeFakeModule();
    const TOTAL = 100;

    const iter = streamCallback(
      fake,
      uint32Codec,
      'sync_test_stream',
      (callbackPtr) => {
        for (let i = 1; i <= TOTAL; i++) {
          fake.emitValue(callbackPtr, i);
        }
        return 0;
      },
    );

    const values = await collectAll(iter, TOTAL + 5);
    expect(values).toHaveLength(TOTAL);
    expect(values[0]).toBe(1);
    expect(values[TOTAL - 1]).toBe(TOTAL);

    // Exactly one install + one teardown per AsyncIterable subscription.
    expect(fake.addFunctionCalls).toBe(1);
    expect(fake.removeFunctionCalls).toBe(1);
  });

  it('delivers the first event BEFORE the async wrapper Promise resolves (live delivery)', async () => {
    const fake = makeFakeModule();
    const TOTAL = 100;
    let wrapperFinished = false;

    const iter = streamCallback(
      fake,
      uint32Codec,
      'live_test_stream',
      async (callbackPtr) => {
        // Emit the first event synchronously inside the wrapper, then
        // cooperatively yield. `await streamYield()` lets the consumer's
        // pending `iterator.next()` resolution flush (it was queued by
        // the `emitValue` above) BEFORE the wrapper continues — the
        // exact behaviour Asyncify / Worker backends will replicate at
        // production scale.
        fake.emitValue(callbackPtr, 1);
        await streamYield();
        for (let i = 2; i <= TOTAL; i++) {
          fake.emitValue(callbackPtr, i);
        }
        wrapperFinished = true;
        return 0;
      },
    );

    const it = iter[Symbol.asyncIterator]();
    const first = await it.next();
    expect(first.done).toBe(false);
    expect(first.value).toBe(1);

    // CENTRAL INVARIANT: the consumer observed the first event while
    // the wrapper was still suspended on `streamYield()` — i.e. the
    // wrapper's Promise had NOT resolved when we received the value.
    // This is the exact property the prior buffered architecture could
    // not provide: every event was only observable AFTER the native
    // call returned.
    expect(wrapperFinished).toBe(false);

    // Drain the rest. After this, the wrapper must have finished.
    const rest: number[] = [];
    for (let i = 0; i < TOTAL; i++) {
      const r = await it.next();
      if (r.done) break;
      rest.push(r.value);
    }
    expect(wrapperFinished).toBe(true);
    expect(rest).toHaveLength(TOTAL - 1);
    expect(rest[0]).toBe(2);
    expect(rest[rest.length - 1]).toBe(TOTAL);

    expect(fake.addFunctionCalls).toBe(1);
    expect(fake.removeFunctionCalls).toBe(1);
  });

  it('honours iterator.return() mid-stream — onCancel fires and later emits are dropped', async () => {
    const fake = makeFakeModule();
    const TOTAL = 100;
    let onCancelCalls = 0;
    let postYieldEmits = 0;

    const iter = streamCallback(
      fake,
      uint32Codec,
      'cancel_test_stream',
      async (callbackPtr) => {
        fake.emitValue(callbackPtr, 1);
        await streamYield();
        // After resuming from the yield, the consumer may have already
        // cancelled — but the wrapper does not know that. It continues
        // emitting, which the test then asserts are silently dropped.
        for (let i = 2; i <= TOTAL; i++) {
          fake.emitValue(callbackPtr, i);
          postYieldEmits += 1;
        }
        return 0;
      },
      undefined,
      () => {
        onCancelCalls += 1;
      },
    );

    const it = iter[Symbol.asyncIterator]();
    const first = await it.next();
    expect(first.value).toBe(1);
    expect(onCancelCalls).toBe(0);

    // Cancel mid-stream while the wrapper is still suspended on the
    // cooperative yield. `onCancel` must fire exactly once and the
    // next pull must observe `done: true`.
    await it.return!();
    expect(onCancelCalls).toBe(1);

    const after = await it.next();
    expect(after.done).toBe(true);

    // Let the wrapper resume and run to completion in the background —
    // its post-yield emissions must all be silently dropped, and the
    // C trampoline must be torn down exactly once when the wrapper's
    // returned Promise resolves.
    await new Promise<void>((resolve) => setTimeout(resolve, 10));
    expect(postYieldEmits).toBe(TOTAL - 1);
    expect(fake.addFunctionCalls).toBe(1);
    expect(fake.removeFunctionCalls).toBe(1);
  });
});
