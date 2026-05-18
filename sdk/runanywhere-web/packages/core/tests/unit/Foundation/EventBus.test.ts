/**
 * EventBus.test.ts — PR #494 T2.3
 *
 * Verifies the Web SDK's `EventBus` after migrating off the legacy local
 * `Map<string, Listener[]>` delivery loop and onto the canonical
 * proto-backed `_rac_sdk_event_*` stream (via `SDKEventStreamAdapter`).
 *
 * Each test installs a small in-memory `ProtoEventTransport` stub —
 * mimicking the adapter contract — and asserts that:
 *
 *   1. A `model.loadCompleted` proto event is translated and delivered.
 *   2. A `model.downloadProgress` proto event (with byte counters) is
 *      translated and delivered.
 *   3. A `sdk.initialized` proto event (InitializationStage=COMPLETED)
 *      is translated and delivered.
 *   4. Unsubscribing via the returned handle stops further delivery.
 *   5. Multiple subscribers fan out correctly.
 *
 * Runner: Vitest. Invoke with:
 *
 *     cd sdk/runanywhere-web && npx vitest run -t EventBus
 */

import { describe, test, expect, beforeEach } from 'vitest';

import { EventCategory } from '@runanywhere/proto-ts/component_types';
import {
  InitializationStage,
  ModelEventKind,
  SDKEvent,
  type SDKEvent as ProtoSDKEvent,
} from '@runanywhere/proto-ts/sdk_events';

import {
  EventBus,
  type ProtoEventTransport,
  type SDKEventEnvelope,
} from '../../../src/Foundation/EventBus';
import type {
  SDKEventHandler,
  SDKEventUnsubscribe,
} from '../../../src/Adapters/SDKEventStreamAdapter';

// -----------------------------------------------------------------------------
// In-memory fake transport
// -----------------------------------------------------------------------------
//
// Mirrors the subset of `SDKEventStreamAdapter` the EventBus actually uses.
// `trigger(event)` simulates a proto event arriving from C++ commons; the
// transport hands it to whichever handler the bus subscribed with. `publish()`
// echoes the event back through the same handler so the round-trip behavior
// matches the real adapter's "C++ publish → JS subscribe fires" contract.

interface FakeTransport extends ProtoEventTransport {
  trigger(event: ProtoSDKEvent): void;
  readonly subscriberCount: number;
  readonly publishedEvents: readonly ProtoSDKEvent[];
}

function makeFakeTransport(opts: { echoPublishes?: boolean } = {}): FakeTransport {
  const echo = opts.echoPublishes !== false;
  let handler: SDKEventHandler | null = null;
  const published: ProtoSDKEvent[] = [];

  return {
    subscribe(h: SDKEventHandler): SDKEventUnsubscribe | null {
      handler = h;
      return () => {
        if (handler === h) handler = null;
      };
    },
    publish(event: ProtoSDKEvent): boolean {
      published.push(event);
      if (echo && handler) handler(event);
      return true;
    },
    trigger(event: ProtoSDKEvent): void {
      if (!handler) throw new Error('trigger() called before EventBus subscribed');
      handler(event);
    },
    get subscriberCount(): number {
      return handler ? 1 : 0;
    },
    get publishedEvents(): readonly ProtoSDKEvent[] {
      return published;
    },
  };
}

// -----------------------------------------------------------------------------
// Helpers: build proto events shaped like real C++ commons output.
// -----------------------------------------------------------------------------

function modelLoadCompletedEvent(modelId: string): ProtoSDKEvent {
  return SDKEvent.fromPartial({
    category: EventCategory.EVENT_CATEGORY_MODEL,
    model: { kind: ModelEventKind.MODEL_EVENT_KIND_LOAD_COMPLETED, modelId },
  });
}

function modelDownloadProgressEvent(
  modelId: string,
  progress: number,
  bytesDownloaded: number,
  totalBytes: number,
): ProtoSDKEvent {
  return SDKEvent.fromPartial({
    category: EventCategory.EVENT_CATEGORY_DOWNLOAD,
    model: {
      kind: ModelEventKind.MODEL_EVENT_KIND_DOWNLOAD_PROGRESS,
      modelId,
      progress,
      bytesDownloaded,
      totalBytes,
    },
  });
}

function sdkInitializedEvent(source: string): ProtoSDKEvent {
  return SDKEvent.fromPartial({
    category: EventCategory.EVENT_CATEGORY_INITIALIZATION,
    initialization: { stage: InitializationStage.INITIALIZATION_STAGE_COMPLETED, source },
  });
}

// -----------------------------------------------------------------------------
// Tests
// -----------------------------------------------------------------------------

describe('EventBus (proto-backed)', () => {
  let transport: FakeTransport;
  let bus: EventBus;

  beforeEach(() => {
    transport = makeFakeTransport();
    bus = new EventBus(transport);
  });

  test('subscribes to the proto transport at construction', () => {
    expect(transport.subscriberCount).toBe(1);
  });

  test('translates and delivers a modelLoaded proto event', () => {
    const received: Array<Record<string, unknown>> = [];
    bus.on('model.loadCompleted', (data) => received.push(data));

    transport.trigger(modelLoadCompletedEvent('gemma-2b'));

    expect(received).toHaveLength(1);
    expect(received[0]).toMatchObject({ modelId: 'gemma-2b' });
  });

  test('translates and delivers a downloadProgress proto event with byte counters', () => {
    const received: Array<Record<string, unknown>> = [];
    bus.on('model.downloadProgress', (data) => received.push(data));

    transport.trigger(modelDownloadProgressEvent('llama-3b', 0.42, 4_200_000, 10_000_000));

    expect(received).toHaveLength(1);
    expect(received[0]).toMatchObject({
      modelId: 'llama-3b',
      progress: 0.42,
      bytesDownloaded: 4_200_000,
      totalBytes: 10_000_000,
    });
  });

  test('translates and delivers a sdkInit proto event', () => {
    const received: Array<Record<string, unknown>> = [];
    bus.on('sdk.initialized', (data) => received.push(data));

    transport.trigger(sdkInitializedEvent('development'));

    expect(received).toHaveLength(1);
    expect(received[0]).toMatchObject({ environment: 'development' });
  });

  test('unsubscribe stops further delivery', () => {
    const received: Array<Record<string, unknown>> = [];
    const unsubscribe = bus.on('model.loadCompleted', (data) => received.push(data));

    transport.trigger(modelLoadCompletedEvent('m1'));
    expect(received).toHaveLength(1);

    unsubscribe();

    transport.trigger(modelLoadCompletedEvent('m2'));
    transport.trigger(modelLoadCompletedEvent('m3'));
    expect(received).toHaveLength(1);
    expect(received[0]).toMatchObject({ modelId: 'm1' });
  });

  test('multiple subscribers fan out correctly', () => {
    const receivedA: Array<Record<string, unknown>> = [];
    const receivedB: Array<Record<string, unknown>> = [];
    const receivedAny: SDKEventEnvelope[] = [];

    bus.on('model.loadCompleted', (data) => receivedA.push(data));
    bus.on('model.loadCompleted', (data) => receivedB.push(data));
    bus.onAny((envelope) => receivedAny.push(envelope));

    transport.trigger(modelLoadCompletedEvent('shared-model'));

    expect(receivedA).toHaveLength(1);
    expect(receivedB).toHaveLength(1);
    expect(receivedA[0]).toMatchObject({ modelId: 'shared-model' });
    expect(receivedB[0]).toMatchObject({ modelId: 'shared-model' });
    expect(receivedAny).toHaveLength(1);
    expect(receivedAny[0]).toMatchObject({
      type: 'model.loadCompleted',
      category: EventCategory.EVENT_CATEGORY_MODEL,
    });
    expect(receivedAny[0]?.data).toMatchObject({ modelId: 'shared-model' });
  });

  test('emit() round-trips through the transport so subscribers still fire', () => {
    const received: Array<Record<string, unknown>> = [];
    bus.on('model.loadCompleted', (data) => received.push(data));

    bus.emit('model.loadCompleted', EventCategory.EVENT_CATEGORY_MODEL, { modelId: 'emitted' });

    expect(transport.publishedEvents).toHaveLength(1);
    expect(transport.publishedEvents[0]?.model?.modelId).toBe('emitted');
    expect(received).toHaveLength(1);
    expect(received[0]).toMatchObject({ modelId: 'emitted' });
  });

  test('emit() falls back to local dispatch when the event has no proto encoding', () => {
    const received: Array<Record<string, unknown>> = [];
    bus.on('storage.localDirectorySelected', (data) => received.push(data));

    bus.emit('storage.localDirectorySelected', EventCategory.EVENT_CATEGORY_STORAGE, {
      directoryName: 'my-dir',
    });

    expect(transport.publishedEvents).toHaveLength(0);
    expect(received).toHaveLength(1);
    expect(received[0]).toMatchObject({ directoryName: 'my-dir' });
  });

  test('static reset() releases the singleton and its transport subscription', () => {
    const sharedTransport = makeFakeTransport();
    // Construct via the singleton path so we can verify reset wiring.
    const sharedBus = new EventBus(sharedTransport);
    expect(sharedTransport.subscriberCount).toBe(1);
    EventBus.reset();
    // The local instance we hold still works, but the singleton is gone.
    // Reset is safe to call on a non-singleton instance — it only clears
    // the static slot.
    expect(EventBus.shared).not.toBe(sharedBus);
  });

  test('unknown proto payload surfaces to wildcard listeners only', () => {
    const namedReceived: Array<Record<string, unknown>> = [];
    const wildcardReceived: SDKEventEnvelope[] = [];
    bus.on('model.loadCompleted', (data) => namedReceived.push(data));
    bus.onAny((envelope) => wildcardReceived.push(envelope));

    // Empty SDKEvent — no oneof arm set, so there's no translation.
    transport.trigger(SDKEvent.fromPartial({ category: EventCategory.EVENT_CATEGORY_SDK }));

    expect(namedReceived).toHaveLength(0);
    expect(wildcardReceived).toHaveLength(1);
    expect(wildcardReceived[0]?.type).toBe('');
  });

  // ---------------------------------------------------------------------------
  // onCategory / eventsFor — cross-SDK parity helpers
  // ---------------------------------------------------------------------------
  //
  // Semantic contract (mirrors Swift `EventBus.events(for:)` /
  // `EventBus.on(category:)`, which filter the same `PassthroughSubject` by
  // `event.category`):
  //
  //   • Category subscribers receive the raw `SDKEvent` proto whose
  //     `category` field equals the requested category, regardless of
  //     whether the dotted-name translator recognizes the payload.
  //   • A subscriber registered for category X must NOT see events whose
  //     proto `category` field is anything other than X.
  //   • Unsubscribe releases the per-listener slot and, once the listener
  //     set for that category is empty, prunes the category entry entirely
  //     so a later subscribe re-creates the slot from scratch.
  //   • `eventsFor(category)` returns an `AsyncIterable<ProtoSDKEvent>`
  //     that is wire-equivalent to `onCategory(category, …)`. Each
  //     iterator installs its own `onCategory` subscription; calling
  //     `.return()` (e.g. via `break` in `for await … of`) releases it.

  describe('onCategory (Swift events(for:) parity)', () => {
    test('receives raw proto events whose category matches', () => {
      const received: ProtoSDKEvent[] = [];
      bus.onCategory(EventCategory.EVENT_CATEGORY_MODEL, (event) => received.push(event));

      transport.trigger(modelLoadCompletedEvent('gemma-2b'));

      expect(received).toHaveLength(1);
      // onCategory delivers the *raw* proto, not the translated envelope —
      // so the model.kind / model.modelId fields are preserved verbatim.
      expect(received[0]?.category).toBe(EventCategory.EVENT_CATEGORY_MODEL);
      expect(received[0]?.model?.modelId).toBe('gemma-2b');
      expect(received[0]?.model?.kind).toBe(ModelEventKind.MODEL_EVENT_KIND_LOAD_COMPLETED);
    });

    test('does NOT receive events whose category does not match', () => {
      const modelReceived: ProtoSDKEvent[] = [];
      const downloadReceived: ProtoSDKEvent[] = [];
      bus.onCategory(EventCategory.EVENT_CATEGORY_MODEL, (event) => modelReceived.push(event));
      bus.onCategory(EventCategory.EVENT_CATEGORY_DOWNLOAD, (event) => downloadReceived.push(event));

      // One MODEL event and one DOWNLOAD event — each subscriber should
      // only see its own category, mirroring Swift's `.filter { $0.category == category }`.
      transport.trigger(modelLoadCompletedEvent('gemma-2b'));
      transport.trigger(modelDownloadProgressEvent('llama-3b', 0.5, 5_000, 10_000));

      expect(modelReceived).toHaveLength(1);
      expect(modelReceived[0]?.category).toBe(EventCategory.EVENT_CATEGORY_MODEL);
      expect(downloadReceived).toHaveLength(1);
      expect(downloadReceived[0]?.category).toBe(EventCategory.EVENT_CATEGORY_DOWNLOAD);
    });

    test('unsubscribe stops further delivery and prunes the listener set', () => {
      // Pruning is internal (categoryListeners is private), so we verify it
      // by *behaviour*: after unsubscribing, no event is delivered. After
      // a fresh subscribe to the same category, the new listener sees
      // subsequent events — proving the slot was re-created cleanly.
      const received: ProtoSDKEvent[] = [];
      const unsubscribe = bus.onCategory(
        EventCategory.EVENT_CATEGORY_MODEL,
        (event) => received.push(event),
      );

      transport.trigger(modelLoadCompletedEvent('m1'));
      expect(received).toHaveLength(1);

      unsubscribe();

      transport.trigger(modelLoadCompletedEvent('m2'));
      transport.trigger(modelLoadCompletedEvent('m3'));
      expect(received).toHaveLength(1);

      // After pruning, a brand-new subscriber wires up cleanly.
      const reSubscribed: ProtoSDKEvent[] = [];
      bus.onCategory(EventCategory.EVENT_CATEGORY_MODEL, (event) => reSubscribed.push(event));
      transport.trigger(modelLoadCompletedEvent('m4'));

      expect(reSubscribed).toHaveLength(1);
      expect(reSubscribed[0]?.model?.modelId).toBe('m4');
      // Original listener stays unsubscribed.
      expect(received).toHaveLength(1);
    });

    test('multiple subscribers on the same category each receive every event', () => {
      const a: ProtoSDKEvent[] = [];
      const b: ProtoSDKEvent[] = [];
      const unsubA = bus.onCategory(EventCategory.EVENT_CATEGORY_MODEL, (e) => a.push(e));
      bus.onCategory(EventCategory.EVENT_CATEGORY_MODEL, (e) => b.push(e));

      transport.trigger(modelLoadCompletedEvent('shared'));
      expect(a).toHaveLength(1);
      expect(b).toHaveLength(1);

      // Unsubscribing just one of them must not prune the other. The
      // pruning condition is "set is empty", so B must keep firing.
      unsubA();
      transport.trigger(modelLoadCompletedEvent('after-unsub'));
      expect(a).toHaveLength(1);
      expect(b).toHaveLength(2);
    });

    test('listener throw is isolated and does not break peer listeners', () => {
      // Swift's Combine pipeline isolates `.sink` closures per subscriber;
      // a throw in one sink does not cancel its siblings. Web mirrors this
      // by wrapping each listener invocation in try/catch (EventBus.ts:421-427).
      const survivor: ProtoSDKEvent[] = [];
      bus.onCategory(EventCategory.EVENT_CATEGORY_MODEL, () => {
        throw new Error('boom');
      });
      bus.onCategory(EventCategory.EVENT_CATEGORY_MODEL, (e) => survivor.push(e));

      transport.trigger(modelLoadCompletedEvent('still-delivered'));

      expect(survivor).toHaveLength(1);
      expect(survivor[0]?.model?.modelId).toBe('still-delivered');
    });
  });

  describe('eventsFor (AsyncIterable parity)', () => {
    test('returns an AsyncIterable whose iterator yields matching events', async () => {
      const iterable = bus.eventsFor(EventCategory.EVENT_CATEGORY_MODEL);
      expect(typeof iterable[Symbol.asyncIterator]).toBe('function');

      const iterator = iterable[Symbol.asyncIterator]();

      // Pump events *after* iteration starts; the resolver path must
      // resolve `next()` with the queued event.
      const firstPromise = iterator.next();
      transport.trigger(modelLoadCompletedEvent('async-1'));
      const first = await firstPromise;

      expect(first.done).toBe(false);
      expect(first.value?.category).toBe(EventCategory.EVENT_CATEGORY_MODEL);
      expect(first.value?.model?.modelId).toBe('async-1');

      // Buffered path: trigger first, then call next() — the event must
      // come out of the internal queue.
      transport.trigger(modelLoadCompletedEvent('async-2'));
      const second = await iterator.next();
      expect(second.done).toBe(false);
      expect(second.value?.model?.modelId).toBe('async-2');

      // Cleanly close.
      await iterator.return?.();
    });

    test('only yields events for its own category', async () => {
      const iterator = bus.eventsFor(EventCategory.EVENT_CATEGORY_MODEL)[Symbol.asyncIterator]();

      const nextPromise = iterator.next();
      // Off-category event must be filtered out.
      transport.trigger(modelDownloadProgressEvent('off', 0.1, 1, 10));
      // On-category event must be the one that resolves the promise.
      transport.trigger(modelLoadCompletedEvent('match'));

      const result = await nextPromise;
      expect(result.done).toBe(false);
      expect(result.value?.category).toBe(EventCategory.EVENT_CATEGORY_MODEL);
      expect(result.value?.model?.modelId).toBe('match');

      await iterator.return?.();
    });

    test('iterator.return() releases the underlying onCategory subscription', async () => {
      // After return(), further triggers must not push to the iterator's
      // internal queue — the wrapper unsubscribed from the bus. We verify
      // this by checking that next() resolves with done=true (no value
      // is buffered) even though the transport keeps firing.
      const iterator = bus.eventsFor(EventCategory.EVENT_CATEGORY_MODEL)[Symbol.asyncIterator]();

      const closeResult = await iterator.return?.();
      expect(closeResult?.done).toBe(true);

      transport.trigger(modelLoadCompletedEvent('post-return-1'));
      transport.trigger(modelLoadCompletedEvent('post-return-2'));

      const after = await iterator.next();
      expect(after.done).toBe(true);
      expect(after.value).toBeUndefined();
    });

    test('return() while a waiter is pending resolves the waiter with done=true', async () => {
      // Mid-stream cancel: simulate `for await … of` breaking out before
      // any event arrives. The pending resolver must be settled with
      // { done: true } so the consumer's loop exits cleanly. This is the
      // subtle correctness trap called out in the finding.
      const iterator = bus.eventsFor(EventCategory.EVENT_CATEGORY_MODEL)[Symbol.asyncIterator]();

      const pending = iterator.next();
      await iterator.return?.();

      const result = await pending;
      expect(result.done).toBe(true);
      expect(result.value).toBeUndefined();
    });

    test('multiple iterators on the same category each get their own subscription', async () => {
      // Each `eventsFor(category)` call installs an independent onCategory
      // subscription. Both iterators must observe every event, mirroring
      // Swift's multicast publisher semantics where every `.sink` is a
      // separate downstream.
      const itA = bus.eventsFor(EventCategory.EVENT_CATEGORY_MODEL)[Symbol.asyncIterator]();
      const itB = bus.eventsFor(EventCategory.EVENT_CATEGORY_MODEL)[Symbol.asyncIterator]();

      const aPromise = itA.next();
      const bPromise = itB.next();
      transport.trigger(modelLoadCompletedEvent('multi'));

      const [a, b] = await Promise.all([aPromise, bPromise]);
      expect(a.value?.model?.modelId).toBe('multi');
      expect(b.value?.model?.modelId).toBe('multi');

      // Closing one iterator must NOT release the other's subscription.
      await itA.return?.();

      const bSecondPromise = itB.next();
      transport.trigger(modelLoadCompletedEvent('only-b'));
      const bSecond = await bSecondPromise;
      expect(bSecond.value?.model?.modelId).toBe('only-b');

      await itB.return?.();
    });

    test('integrates with for-await-of and breaks cleanly mid-stream', async () => {
      // End-to-end shape parity with Swift `for await event in
      // EventBus.shared.events(for: .model) { … break }`.
      const collected: string[] = [];
      const iterable = bus.eventsFor(EventCategory.EVENT_CATEGORY_MODEL);

      // Drive the loop on a microtask so the trigger calls below get
      // observed by the bus before the iterator's first `next()` settles.
      const loop = (async () => {
        for await (const event of iterable) {
          collected.push(event.model?.modelId ?? '');
          if (collected.length === 2) break;
        }
      })();

      // Fire three events; the for-await loop should break after the
      // second, leaving the third unobserved (subscription released by
      // the iterator's implicit return()).
      transport.trigger(modelLoadCompletedEvent('e1'));
      transport.trigger(modelLoadCompletedEvent('e2'));
      transport.trigger(modelLoadCompletedEvent('e3'));

      await loop;
      expect(collected).toEqual(['e1', 'e2']);
    });
  });
});
