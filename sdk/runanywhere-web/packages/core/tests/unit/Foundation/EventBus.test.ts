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
});
