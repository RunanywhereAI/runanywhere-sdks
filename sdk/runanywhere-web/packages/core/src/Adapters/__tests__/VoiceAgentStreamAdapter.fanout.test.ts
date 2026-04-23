/**
 * VoiceAgentStreamAdapter.fanout.test.ts
 *
 * Phase E / B29 — verifies that the Web voice-agent stream adapter fans
 * a single Emscripten trampoline out to every concurrent AsyncIterable
 * subscriber.
 *
 * The WASM ABI exposes only one proto-callback slot per handle
 * (`_rac_voice_agent_set_proto_callback(handle, cbPtr, 0)`), so a naïve
 * adapter would silently let the second subscriber clobber the first.
 * This test uses the `__testing__.fanOutTransportFor` seam to inject a
 * fake Emscripten module and asserts that:
 *
 *   1. addFunction + _rac_voice_agent_set_proto_callback are called
 *      exactly once for N concurrent subscribers.
 *   2. Every subscriber receives every emitted event in order.
 *   3. Tearing down the last subscriber clears the C slot and removes
 *      the Emscripten function-table entry.
 *   4. Re-subscribing after a full teardown installs a fresh callback.
 *
 * Runner: Vitest. Invoke with:
 *
 *     npx vitest run src/Adapters/__tests__/VoiceAgentStreamAdapter.fanout.test.ts
 */

import { test, expect } from 'vitest';

import { VoiceEvent } from '../../generated/voice_events';
import { __testing__ } from '../VoiceAgentStreamAdapter';
import { streamVoiceAgent } from '../../generated/streams/voice_agent_service_stream';

// -----------------------------------------------------------------------------
// Fake Emscripten module.
//
// We only implement the slice of the surface the adapter actually reaches:
//   - addFunction(fn, sig) → returns a fake pointer, records installed fn.
//   - removeFunction(ptr) → removes the fn.
//   - _rac_voice_agent_set_proto_callback(handle, cbPtr, user) → records
//     the active registration; non-zero cbPtr installs, zero clears.
//   - HEAPU8 / heap writes — our fake emit() writes bytes into a Uint8Array
//     and passes the offset/length matching the real WASM trampoline
//     contract.
// -----------------------------------------------------------------------------

interface FakeModule {
  readonly addFunctionCalls: number;
  readonly removeFunctionCalls: number;
  readonly setProtoCallbackCalls: Array<{ handle: number; cbPtr: number }>;
  readonly HEAPU8: Uint8Array;
  addFunction: (fn: (...a: number[]) => number | void, sig: string) => number;
  removeFunction: (ptr: number) => void;
  _rac_voice_agent_set_proto_callback: (h: number, cb: number, ud: number) => number;
  _rac_llm_extract_thinking: (...a: number[]) => number;
  _rac_llm_strip_thinking: (...a: number[]) => number;
  _rac_llm_split_thinking_tokens: (...a: number[]) => number;
  HEAP32: Int32Array;
  HEAPU32: Uint32Array;
  _malloc: (n: number) => number;
  _free: (p: number) => void;
  UTF8ToString: (p: number) => string;
  stringToUTF8: (s: string, p: number, n: number) => number;
  lengthBytesUTF8: (s: string) => number;

  // Test control: push a synthetic proto-bytes payload through the
  // currently-installed trampoline.
  emit: (event: VoiceEvent) => void;
}

function makeFakeModule(opts: {
  setCallbackResult?: (handle: number, cbPtr: number) => number;
} = {}): FakeModule {
  let addCount = 0;
  let removeCount = 0;
  const setCalls: Array<{ handle: number; cbPtr: number }> = [];
  const installed = new Map<number, (ptr: number, len: number, ud: number) => void>();
  let nextPtr = 1_000;

  // 64KB arena for event bytes — our emit() copies each payload into
  // this buffer and hands the trampoline a (ptr, len) pair, mirroring
  // the WASM heap contract the real adapter reads from.
  //
  // Start at a non-zero offset: the real adapter treats ptr==0 as a
  // null/sentinel pointer and bails. Using an arena that starts at 1
  // keeps every emitted event at a valid WASM pointer.
  const heap = new Uint8Array(64 * 1024);
  let heapCursor = 1;

  let activeCbPtr = 0;

  const mod: FakeModule = {
    get addFunctionCalls() { return addCount; },
    get removeFunctionCalls() { return removeCount; },
    get setProtoCallbackCalls() { return setCalls; },
    HEAPU8: heap,
    HEAP32: new Int32Array(heap.buffer),
    HEAPU32: new Uint32Array(heap.buffer),

    addFunction(fn, _sig) {
      addCount += 1;
      const p = nextPtr++;
      installed.set(p, fn as (ptr: number, len: number, ud: number) => void);
      return p;
    },

    removeFunction(ptr) {
      removeCount += 1;
      installed.delete(ptr);
    },

    _rac_voice_agent_set_proto_callback(handle, cbPtr, _ud) {
      const rc = opts.setCallbackResult ? opts.setCallbackResult(handle, cbPtr) : 0;
      setCalls.push({ handle, cbPtr });
      if (rc === 0) {
        activeCbPtr = cbPtr;
      }
      return rc;
    },

    _rac_llm_extract_thinking: () => 0,
    _rac_llm_strip_thinking: () => 0,
    _rac_llm_split_thinking_tokens: () => 0,
    _malloc: () => 0,
    _free: () => { /* noop */ },
    UTF8ToString: () => '',
    stringToUTF8: () => 0,
    lengthBytesUTF8: () => 0,

    emit(event) {
      if (activeCbPtr === 0) throw new Error('emit: no callback installed');
      const fn = installed.get(activeCbPtr);
      if (!fn) throw new Error('emit: active cbPtr has no registered fn');
      const bytes = VoiceEvent.encode(event).finish();
      // Write into the fake heap arena and hand the trampoline its ptr/len.
      if (heapCursor + bytes.length > heap.length) heapCursor = 1;
      heap.set(bytes, heapCursor);
      const ptr = heapCursor;
      heapCursor += bytes.length;
      fn(ptr, bytes.length, 0);
    },
  };

  return mod;
}

// -----------------------------------------------------------------------------
// Helpers: drive an AsyncIterable until N events arrive, with a timeout.
//
// Uses an explicit iterator handle (instead of `for await`) so a test can
// attach to the subscription BEFORE emitting — otherwise emits that fire
// before the collector hits its first `.next()` are lost. Calling
// `asyncIterator()` synchronously installs the C trampoline via the
// generated streamVoiceAgent() setup code.
// -----------------------------------------------------------------------------

function startCollector(iter: AsyncIterable<VoiceEvent>) {
  const it = iter[Symbol.asyncIterator]();
  const events: VoiceEvent[] = [];
  return {
    iterator: it,
    events,
    async collect(n: number, timeoutMs = 2_000): Promise<VoiceEvent[]> {
      const deadline = Date.now() + timeoutMs;
      while (events.length < n) {
        if (Date.now() > deadline) {
          throw new Error(`collect timeout: got ${events.length}/${n}`);
        }
        const result = await it.next();
        if (result.done) break;
        events.push(result.value);
      }
      // Release the subscription so the fan-out tears down in test assertions.
      await it.return?.();
      return events;
    },
  };
}

async function flush() {
  // Yield twice so (a) the initial subscription is fully wired and
  // (b) any microtasks queued by the adapter settle.
  await Promise.resolve();
  await Promise.resolve();
}

function event(seq: number, text: string): VoiceEvent {
  return VoiceEvent.fromPartial({
    seq,
    userSaid: { text, isFinal: true },
  });
}

// -----------------------------------------------------------------------------
// Tests
// -----------------------------------------------------------------------------

test('single subscriber receives every event', async () => {
  const fake = makeFakeModule();
  const transport = __testing__.fanOutTransportFor(42, fake as never);
  const iter = streamVoiceAgent(transport, { eventFilter: '' });

  const collector = startCollector(iter);
  // Kick off the first .next() so the fan-out trampoline is installed
  // and a pending resolve is registered before we start emitting.
  const firstPromise = collector.iterator.next();
  await flush();

  fake.emit(event(1, 'a'));
  fake.emit(event(2, 'b'));
  fake.emit(event(3, 'c'));

  // Consume the pre-kicked-off first promise manually; the remaining
  // events are already enqueued and drained via collect().
  const first = await firstPromise;
  if (!first.done) collector.events.push(first.value);
  const evs = await collector.collect(3);
  expect(evs.map((e) => Number(e.seq))).toEqual([1, 2, 3]);

  // Exactly ONE Emscripten installation for ONE subscriber.
  expect(fake.addFunctionCalls).toBe(1);
  expect(fake.setProtoCallbackCalls.filter((c) => c.cbPtr !== 0).length).toBe(1);

  // iter completed after 3 events → cancel() fires → teardown.
  expect(fake.setProtoCallbackCalls.filter((c) => c.cbPtr === 0).length).toBe(1);
  expect(fake.removeFunctionCalls).toBe(1);
});

test('two concurrent subscribers each receive every event (fan-out)', async () => {
  const fake = makeFakeModule();
  const transport = __testing__.fanOutTransportFor(7, fake as never);

  const iterA = streamVoiceAgent(transport, { eventFilter: '' });
  const iterB = streamVoiceAgent(transport, { eventFilter: '' });

  const collA = startCollector(iterA);
  const collB = startCollector(iterB);
  // Kick off the first .next() on each so both have a pending resolve
  // registered — otherwise the first emit goes onto the queue only,
  // which is still correct behavior but obscures the fan-out check.
  const firstA = collA.iterator.next();
  const firstB = collB.iterator.next();
  await flush();

  fake.emit(event(1, 'x'));
  fake.emit(event(2, 'y'));
  fake.emit(event(3, 'z'));
  fake.emit(event(4, '!'));

  const firstAVal = await firstA;
  const firstBVal = await firstB;
  if (!firstAVal.done) collA.events.push(firstAVal.value);
  if (!firstBVal.done) collB.events.push(firstBVal.value);
  const [evsA, evsB] = await Promise.all([collA.collect(4), collB.collect(4)]);
  expect(evsA.map((e) => Number(e.seq))).toEqual([1, 2, 3, 4]);
  expect(evsB.map((e) => Number(e.seq))).toEqual([1, 2, 3, 4]);

  // CENTRAL INVARIANT: a single Emscripten trampoline served both
  // subscribers — addFunction fired ONCE, not twice.
  expect(fake.addFunctionCalls).toBe(1);
  expect(fake.setProtoCallbackCalls.filter((c) => c.cbPtr !== 0).length).toBe(1);
  // Both subscribers are done → exactly one teardown.
  expect(fake.removeFunctionCalls).toBe(1);
});

test('second wave after teardown installs a fresh trampoline', async () => {
  const fake = makeFakeModule();
  const transport = __testing__.fanOutTransportFor(99, fake as never);

  // First wave.
  const iter1 = streamVoiceAgent(transport, { eventFilter: '' });
  const coll1 = startCollector(iter1);
  const p1 = coll1.iterator.next();
  await flush();
  fake.emit(event(10, 'first'));
  const v1 = await p1;
  expect(Number((v1.value as VoiceEvent).seq)).toBe(10);
  await coll1.iterator.return?.();
  expect(fake.addFunctionCalls).toBe(1);
  expect(fake.removeFunctionCalls).toBe(1);

  // Second wave on the same handle reuses the same adapter transport.
  const iter2 = streamVoiceAgent(transport, { eventFilter: '' });
  const coll2 = startCollector(iter2);
  const p2 = coll2.iterator.next();
  await flush();
  fake.emit(event(20, 'second'));
  const v2 = await p2;
  expect(Number((v2.value as VoiceEvent).seq)).toBe(20);
  await coll2.iterator.return?.();

  expect(fake.addFunctionCalls).toBe(2);
  expect(fake.removeFunctionCalls).toBe(2);
});

test('a failing _rac_voice_agent_set_proto_callback surfaces as onError', async () => {
  const fake = makeFakeModule({ setCallbackResult: () => -1 });
  const transport = __testing__.fanOutTransportFor(1, fake as never);

  const iter = streamVoiceAgent(transport, { eventFilter: '' });
  const it = iter[Symbol.asyncIterator]();

  let error: Error | null = null;
  try {
    await it.next();
  } catch (e) {
    error = e as Error;
  }
  expect(error).toBeTruthy();
  expect(error!.message).toMatch(/rac_voice_agent_set_proto_callback failed/);
  expect(fake.removeFunctionCalls).toBe(1);
});
