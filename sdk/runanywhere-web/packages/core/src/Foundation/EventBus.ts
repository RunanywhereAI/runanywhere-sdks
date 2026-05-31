/**
 * RunAnywhere Web SDK - Event Bus
 *
 * Central event system matching the pattern across all SDKs.
 *
 * Web parity migration (PR #494 T2.3): previously this file maintained
 * its own `Map<string, Set<Listener>>` delivery loop, while Swift /
 * Kotlin / Flutter / RN all routed events through the canonical
 * `_rac_sdk_event_subscribe` / `_publish_proto` C ABI exposed by
 * RACommons. Web now does the same: at construction we subscribe to
 * `SDKEventStreamAdapter`, decode each `runanywhere.v1.SDKEvent`, and
 * translate the populated oneof arm + kind enum into the stable
 * dotted event-name surface (`'model.loadCompleted'`, `'sdk.initialized'`,
 * …) that public consumers already use.
 *
 * Subscriber tracking still lives in a `Map<string, Set<Listener>>`
 * because we still need to know who to deliver to. What's gone is the
 * old "emit() iterates listeners directly" delivery loop — the proto
 * adapter is now the source of truth, and `emit()` publishes through
 * it. Local fan-out is only used as a fallback (e.g. tests, or before
 * the WASM module registers).
 */

import { EventCategory } from '@runanywhere/proto-ts/component_types';
import { ModelCategory, type SDKEnvironment } from '@runanywhere/proto-ts/model_types';
import type { SpeechActivityKind } from '@runanywhere/proto-ts/vad_options';
import {
  DownloadEventKind,
  GenerationEventKind,
  InitializationStage,
  ModelEventKind,
  SDKEvent,
  VoiceEventKind,
  type DownloadEvent as ProtoDownloadEvent,
  type GenerationEvent as ProtoGenerationEvent,
  type InitializationEvent as ProtoInitializationEvent,
  type ModelEvent as ProtoModelEvent,
  type SDKEvent as ProtoSDKEvent,
  type VoiceLifecycleEvent as ProtoVoiceLifecycleEvent,
} from '@runanywhere/proto-ts/sdk_events';
import {
  SDKEventStreamAdapter,
  type SDKEventHandler,
  type SDKEventUnsubscribe,
} from '../Adapters/SDKEventStreamAdapter';
import { SDKLogger } from './SDKLogger';

const logger = new SDKLogger('EventBus');

/** Generic event listener */
export type EventListener<T = unknown> = (event: T) => void;

/** Unsubscribe function returned by subscribe */
export type Unsubscribe = () => void;

/** Event envelope wrapping all emitted events */
export interface SDKEventEnvelope {
  type: string;
  category: EventCategory;
  timestamp: number;
  data: Record<string, unknown>;
}

/** Known SDK event types and their payload shapes. */
export interface SDKEventMap {
  // SDK lifecycle
  'sdk.initialized': { environment: SDKEnvironment };
  'sdk.accelerationMode': { mode: string };

  // Model management
  'model.registered': { count: number };
  'model.downloadStarted': { modelId: string; url: string };
  'model.downloadProgress': { modelId: string; progress: number; bytesDownloaded: number; totalBytes: number; stage?: string };
  'model.downloadCompleted': { modelId: string; sizeBytes?: number; localPath?: string };
  'model.downloadFailed': { modelId: string; error: string };
  'model.loadStarted': { modelId: string; component?: string; category?: ModelCategory };
  'model.loadCompleted': { modelId: string; component?: string; category?: ModelCategory; loadTimeMs?: number };
  'model.loadFailed': { modelId: string; error: string };
  'model.unloaded': { modelId: string; category: ModelCategory };
  'model.quotaExceeded': { modelId: string; availableBytes: number; neededBytes: number };
  'model.evicted': { modelId: string; modelName: string; freedBytes: number };

  // Text generation
  'generation.started': { prompt: string };
  'generation.completed': { tokensUsed: number; latencyMs: number };
  'generation.failed': { error: string };

  // Speech-to-text
  'stt.transcribed': { text: string; confidence: number; audioDurationMs?: number; wordCount?: number };
  'stt.transcriptionFailed': { error: string };

  // Text-to-speech
  'tts.synthesized': { durationMs: number; sampleRate: number; characterCount?: number; processingMs?: number; charsPerSec?: number; textLength?: number };
  'tts.synthesisFailed': { error: string };

  // Voice activity detection
  'vad.speechStarted': { activity: SpeechActivityKind };
  'vad.speechEnded': { activity: SpeechActivityKind; speechDurationMs?: number };

  // Voice agent
  'voice.turnCompleted': { speechDetected: boolean; transcription: string; response: string };

  // Embeddings
  'embeddings.generated': { numEmbeddings: number; dimension: number; processingTimeMs: number };

  // Diffusion
  'diffusion.generated': { width: number; height: number; generationTimeMs: number };

  // Vision-language model
  'vlm.processed': { tokensPerSecond: number; totalTokens: number; hardwareUsed: string };

  // Audio playback
  'playback.started': { durationMs: number; sampleRate: number };
  'playback.completed': { durationMs: number };

  // Allow custom events
  [key: string]: Record<string, unknown>;
}

/**
 * Minimal proto-event transport surface used by EventBus. Decoupled from
 * the concrete `SDKEventStreamAdapter` so tests can inject an in-memory
 * fake without touching WASM/Emscripten plumbing. The production
 * implementation is the adapter itself, which speaks the
 * `_rac_sdk_event_*` C ABI under the hood.
 */
export interface ProtoEventTransport {
  subscribe(handler: SDKEventHandler): SDKEventUnsubscribe | null;
  publish(event: ProtoSDKEvent): boolean;
}

/**
 * EventBus - Central event system for the Web SDK.
 *
 * Public API surface (unchanged across the PR #494 T2.3 migration):
 *   • `EventBus.shared` singleton accessor
 *   • `on(type, listener)`   → returns unsubscribe
 *   • `onAny(listener)`      → wildcard, returns unsubscribe
 *   • `once(type, listener)` → fires once, returns unsubscribe
 *   • `emit(type, category, data?)`
 *   • `removeAll()` / static `reset()`
 *
 * Internally, the bus is wired to the canonical proto event stream.
 * Native events (from C++ commons) and JS-side `emit()` calls both flow
 * through the same translation pipeline, so subscribers see one
 * consistent stream regardless of origin.
 */
export class EventBus {
  private static _instance: EventBus | null = null;

  static get shared(): EventBus {
    if (!EventBus._instance) {
      EventBus._instance = new EventBus();
    }
    return EventBus._instance;
  }

  /** Reset singleton (for testing). */
  static reset(): void {
    EventBus._instance?.dispose();
    EventBus._instance = null;
  }

  // Subscriber registry: who's listening to which dotted event name.
  // This is NOT an event queue — events themselves flow through the
  // proto transport. We only need this map to fan a translated event
  // out to its registered listeners.
  private readonly subscribers = new Map<string, Set<EventListener>>();
  private readonly wildcardListeners = new Set<EventListener<SDKEventEnvelope>>();
  // Category-keyed subscribers receive every proto SDKEvent whose
  // `category` field matches, regardless of whether the dotted-name
  // translator covers the payload. Mirrors Swift `events(for:)`,
  // Kotlin `events(category)`, RN `eventsFor(category)` /
  // `on(category, handler)`, and Flutter `onCategory(category)`.
  private readonly categoryListeners = new Map<EventCategory, Set<EventListener<ProtoSDKEvent>>>();

  private transport: ProtoEventTransport | null;
  private transportUnsubscribe: SDKEventUnsubscribe | null = null;

  /**
   * @param transport Custom proto event transport. Defaults to
   *   `SDKEventStreamAdapter.tryDefault()`. Pass an explicit instance
   *   from tests (or `null` for purely-local dispatch).
   */
  constructor(transport: ProtoEventTransport | null = SDKEventStreamAdapter.tryDefault()) {
    this.transport = transport;
    this.attachTransport();
  }

  /**
   * Subscribe to events of a specific type. Returns an unsubscribe fn.
   */
  on<K extends keyof SDKEventMap>(eventType: K, listener: EventListener<SDKEventMap[K]>): Unsubscribe {
    this.ensureTransport();
    const key = eventType as string;
    let set = this.subscribers.get(key);
    if (!set) {
      set = new Set();
      this.subscribers.set(key, set);
    }
    set.add(listener as EventListener);

    return () => {
      const current = this.subscribers.get(key);
      if (!current) return;
      current.delete(listener as EventListener);
      if (current.size === 0) this.subscribers.delete(key);
    };
  }

  /**
   * Subscribe to ALL events (wildcard). Returns an unsubscribe fn.
   */
  onAny(listener: EventListener<SDKEventEnvelope>): Unsubscribe {
    this.ensureTransport();
    this.wildcardListeners.add(listener);
    return () => {
      this.wildcardListeners.delete(listener);
    };
  }

  /**
   * Subscribe to every proto `SDKEvent` whose `category` matches.
   *
   * Cross-SDK parity helper. Mirrors Swift `events(for:)`, Kotlin
   * `events(category)`, RN `eventsFor(category)` / `on(category, handler)`,
   * and Flutter `onCategory(category)`. The handler receives the raw
   * proto event (same surface as `RunAnywhere.sdkEvents`), so it works
   * for native SDKEvent kinds that have no entry in `SDKEventMap`.
   *
   * Returns an unsubscribe fn.
   */
  onCategory(category: EventCategory, listener: EventListener<ProtoSDKEvent>): Unsubscribe {
    this.ensureTransport();
    let set = this.categoryListeners.get(category);
    if (!set) {
      set = new Set();
      this.categoryListeners.set(category, set);
    }
    set.add(listener);

    return () => {
      const current = this.categoryListeners.get(category);
      if (!current) return;
      current.delete(listener);
      if (current.size === 0) this.categoryListeners.delete(category);
    };
  }

  /**
   * Async iterable of every proto `SDKEvent` whose `category` matches.
   *
   * Cross-SDK parity helper. Equivalent to Swift `events(for:)`, Kotlin
   * `events(category)`, RN `eventsFor(category)`, Flutter `onCategory()`.
   *
   * Multiple concurrent `next()` calls are safe: each call enqueues a
   * waiter and is resolved in FIFO order when events arrive, matching the
   * behaviour of Swift's `AsyncStream` and Kotlin's `SharedFlow`.
   */
  eventsFor(category: EventCategory): AsyncIterable<ProtoSDKEvent> {
    // eslint-disable-next-line @typescript-eslint/no-this-alias
    const bus = this;
    return {
      [Symbol.asyncIterator](): AsyncIterator<ProtoSDKEvent> {
        const queue: ProtoSDKEvent[] = [];
        const waiters: Array<(value: IteratorResult<ProtoSDKEvent>) => void> = [];
        let closed = false;

        const unsubscribe = bus.onCategory(category, (event) => {
          if (waiters.length > 0) {
            waiters.shift()!({ value: event, done: false });
          } else {
            queue.push(event);
          }
        });

        return {
          next(): Promise<IteratorResult<ProtoSDKEvent>> {
            if (queue.length > 0) {
              return Promise.resolve({ value: queue.shift()!, done: false });
            }
            if (closed) {
              return Promise.resolve({
                value: undefined as unknown as ProtoSDKEvent,
                done: true,
              });
            }
            return new Promise((resolve) => {
              waiters.push(resolve);
            });
          },
          return(): Promise<IteratorResult<ProtoSDKEvent>> {
            closed = true;
            unsubscribe();
            const doneResult: IteratorResult<ProtoSDKEvent> = {
              value: undefined as unknown as ProtoSDKEvent,
              done: true,
            };
            for (const waiter of waiters.splice(0)) {
              waiter(doneResult);
            }
            return Promise.resolve(doneResult);
          },
        };
      },
    };
  }

  /**
   * Subscribe to events once (auto-unsubscribe after first event).
   */
  once<K extends keyof SDKEventMap>(eventType: K, listener: EventListener<SDKEventMap[K]>): Unsubscribe {
    const unsubscribe = this.on(eventType, (event) => {
      unsubscribe();
      listener(event);
    });
    return unsubscribe;
  }

  /**
   * Emit an event.
   *
   * Tries the proto-backed transport first so the event flows through
   * the canonical pipeline (and is observed by analytics + native
   * subscribers). If the transport cannot encode this event-name, or
   * the publish fails, falls back to direct local fan-out so JS-only
   * consumers still see the event.
   */
  emit<K extends keyof SDKEventMap>(eventType: K, category: EventCategory, data?: SDKEventMap[K]): void {
    this.ensureTransport();
    const key = eventType as string;
    const payload = (data ?? {}) as Record<string, unknown>;

    if (this.publishThroughTransport(key, category, payload)) {
      // Adapter accepted the event — its subscribe callback will fan
      // out to our local listeners via onTransportEvent().
      return;
    }

    const envelope: SDKEventEnvelope = {
      type: key,
      category,
      timestamp: Date.now(),
      data: payload,
    };
    this.dispatch(envelope);
  }

  /**
   * Remove all listeners.
   */
  removeAll(): void {
    this.subscribers.clear();
    this.wildcardListeners.clear();
    this.categoryListeners.clear();
  }

  // ---------------------------------------------------------------------------
  // Internals
  // ---------------------------------------------------------------------------

  private dispose(): void {
    this.transportUnsubscribe?.();
    this.transportUnsubscribe = null;
    this.transport = null;
    this.removeAll();
  }

  /**
   * Lazy-attach: the singleton is constructed before any backend
   * package registers its WASM module, so the first `tryDefault()` is
   * usually null. Re-resolve from the default each time someone
   * subscribes or emits, so we wire up as soon as the module appears.
   */
  private ensureTransport(): void {
    if (this.transportUnsubscribe) return;
    if (!this.transport) {
      this.transport = SDKEventStreamAdapter.tryDefault();
    }
    this.attachTransport();
  }

  private attachTransport(): void {
    if (this.transportUnsubscribe) return;
    if (!this.transport) return;
    const unsubscribe = this.transport.subscribe((event) => this.onTransportEvent(event));
    if (!unsubscribe) {
      logger.debug('proto event transport could not subscribe; using local dispatch fallback');
      return;
    }
    this.transportUnsubscribe = unsubscribe;
  }

  private onTransportEvent(event: ProtoSDKEvent): void {
    // Always fan out to category subscribers first — they observe the
    // raw proto regardless of whether the dotted-name translator
    // recognizes the payload.
    this.fireCategory(event);

    const translated = translateProtoEvent(event);
    if (!translated) {
      // Unknown payload shape — still surface the raw envelope to
      // wildcard listeners so observability / debug tooling can see it.
      this.fireWildcard({
        type: '',
        category: event.category,
        timestamp: event.timestampMs || Date.now(),
        data: { proto: event } as Record<string, unknown>,
      });
      return;
    }
    this.dispatch({
      type: translated.type,
      category: event.category || translated.fallbackCategory,
      timestamp: event.timestampMs || Date.now(),
      data: translated.data,
    });
  }

  private fireCategory(event: ProtoSDKEvent): void {
    const set = this.categoryListeners.get(event.category);
    if (!set) return;
    for (const listener of Array.from(set)) {
      try {
        listener(event);
      } catch (error) {
        logger.error(
          `Category listener error for ${String(event.category)}: ${error instanceof Error ? error.message : String(error)}`,
        );
      }
    }
  }

  private dispatch(envelope: SDKEventEnvelope): void {
    const set = this.subscribers.get(envelope.type);
    if (set) {
      // Snapshot to a local array so a listener mutating the set
      // (e.g. via the unsubscribe returned by `on`) can't perturb
      // iteration mid-flight.
      for (const listener of Array.from(set)) {
        try {
          listener(envelope.data);
        } catch (error) {
          logger.error(
            `Listener error for ${envelope.type}: ${error instanceof Error ? error.message : String(error)}`,
          );
        }
      }
    }
    this.fireWildcard(envelope);
  }

  private fireWildcard(envelope: SDKEventEnvelope): void {
    for (const listener of Array.from(this.wildcardListeners)) {
      try {
        listener(envelope);
      } catch (error) {
        logger.error(
          `Wildcard listener error: ${error instanceof Error ? error.message : String(error)}`,
        );
      }
    }
  }

  private publishThroughTransport(
    eventType: string,
    category: EventCategory,
    data: Record<string, unknown>,
  ): boolean {
    if (!this.transport || !this.transportUnsubscribe) return false;
    const proto = encodeEventToProto(eventType, category, data);
    if (!proto) return false;
    try {
      return this.transport.publish(proto);
    } catch (error) {
      logger.warning(
        `proto transport publish failed for ${eventType}: ${error instanceof Error ? error.message : String(error)}`,
      );
      return false;
    }
  }
}

// =============================================================================
// Proto-oneof → dotted-event-name translation
// =============================================================================
//
// The translation is a single switch over the populated SDKEvent oneof arm,
// then a nested switch on that arm's discriminator (`stage` / `kind` enums).
// Each case picks the stable dotted name used by SDKEventMap and shapes the
// data payload to match. Unknown arms / kinds fall through to `null` and the
// caller will route them to wildcard listeners only.
//
// Adding a new mapping is a single-case addition here plus its reverse arm in
// `encodeEventToProto` below.
//
// Coverage note: the SDKEvent proto oneof has 24 arms (initialization,
// configuration, generation, model, performance, network, storage, framework,
// device, component_init, voice, voice_pipeline, component_lifecycle, session,
// auth, model_registry, download, storage_lifecycle, hardware_routing,
// capability, telemetry, cancellation, failure). Only 5 arms (initialization,
// model, generation, voice, download) are translated to dotted-name SDKEventMap
// entries. The remaining 19 arms do NOT produce dotted-name events; they are
// routed to wildcard listeners only (with `{ proto: event }` in `data`).
//
// For any arm not listed above, use the category-based API instead — it
// delivers the raw proto SDKEvent regardless of dotted-name coverage and is
// the documented cross-SDK parity path:
//   • `eventBus.onCategory(EventCategory.X, handler)`  — push subscription
//   • `eventBus.eventsFor(EventCategory.X)`             — async iterable
//   • `eventBus.onAny(handler)`                         — all events (wildcard)

interface TranslatedEvent {
  type: string;
  data: Record<string, unknown>;
  fallbackCategory: EventCategory;
}

function translateProtoEvent(event: ProtoSDKEvent): TranslatedEvent | null {
  if (event.initialization) return translateInitialization(event.initialization);
  if (event.model) return translateModel(event.model);
  if (event.generation) return translateGeneration(event.generation);
  if (event.voice) return translateVoice(event.voice);
  if (event.download) return translateDownload(event.download);
  return null;
}

function translateInitialization(e: ProtoInitializationEvent): TranslatedEvent | null {
  switch (e.stage) {
    case InitializationStage.INITIALIZATION_STAGE_COMPLETED:
      return {
        type: 'sdk.initialized',
        data: { environment: e.source, version: e.version },
        fallbackCategory: EventCategory.EVENT_CATEGORY_INITIALIZATION,
      };
    case InitializationStage.INITIALIZATION_STAGE_FAILED:
      return {
        type: 'sdk.initializationFailed',
        data: { error: e.error, source: e.source },
        fallbackCategory: EventCategory.EVENT_CATEGORY_INITIALIZATION,
      };
    default:
      return null;
  }
}

function translateModel(e: ProtoModelEvent): TranslatedEvent | null {
  switch (e.kind) {
    case ModelEventKind.MODEL_EVENT_KIND_LOAD_STARTED:
      return modelEvent('model.loadStarted', { modelId: e.modelId });
    case ModelEventKind.MODEL_EVENT_KIND_LOAD_COMPLETED:
      return modelEvent('model.loadCompleted', { modelId: e.modelId });
    case ModelEventKind.MODEL_EVENT_KIND_LOAD_FAILED:
      return modelEvent('model.loadFailed', { modelId: e.modelId, error: e.error });
    case ModelEventKind.MODEL_EVENT_KIND_UNLOAD_COMPLETED:
      return modelEvent('model.unloaded', {
        modelId: e.modelId,
        category: ModelCategory.MODEL_CATEGORY_UNSPECIFIED,
      });
    case ModelEventKind.MODEL_EVENT_KIND_DOWNLOAD_STARTED:
      return modelEvent('model.downloadStarted', { modelId: e.modelId, url: '' });
    case ModelEventKind.MODEL_EVENT_KIND_DOWNLOAD_PROGRESS:
      return modelEvent('model.downloadProgress', {
        modelId: e.modelId,
        progress: e.progress,
        bytesDownloaded: e.bytesDownloaded,
        totalBytes: e.totalBytes,
        stage: e.downloadState,
      });
    case ModelEventKind.MODEL_EVENT_KIND_DOWNLOAD_COMPLETED:
      return modelEvent('model.downloadCompleted', {
        modelId: e.modelId,
        localPath: e.localPath,
      });
    case ModelEventKind.MODEL_EVENT_KIND_DOWNLOAD_FAILED:
      return modelEvent('model.downloadFailed', { modelId: e.modelId, error: e.error });
    case ModelEventKind.MODEL_EVENT_KIND_BUILT_IN_REGISTERED:
      return modelEvent('model.registered', { count: e.modelCount });
    default:
      return null;
  }
}

function modelEvent(type: string, data: Record<string, unknown>): TranslatedEvent {
  return { type, data, fallbackCategory: EventCategory.EVENT_CATEGORY_MODEL };
}

function translateGeneration(e: ProtoGenerationEvent): TranslatedEvent | null {
  switch (e.kind) {
    case GenerationEventKind.GENERATION_EVENT_KIND_STARTED:
      return generationEvent('generation.started', { prompt: e.prompt });
    case GenerationEventKind.GENERATION_EVENT_KIND_COMPLETED:
      return generationEvent('generation.completed', {
        tokensUsed: e.tokensUsed,
        latencyMs: e.latencyMs,
      });
    case GenerationEventKind.GENERATION_EVENT_KIND_FAILED:
      return generationEvent('generation.failed', { error: e.error });
    default:
      return null;
  }
}

function generationEvent(type: string, data: Record<string, unknown>): TranslatedEvent {
  return { type, data, fallbackCategory: EventCategory.EVENT_CATEGORY_LLM };
}

function translateVoice(e: ProtoVoiceLifecycleEvent): TranslatedEvent | null {
  switch (e.kind) {
    case VoiceEventKind.VOICE_EVENT_KIND_TRANSCRIPTION_FINAL:
    case VoiceEventKind.VOICE_EVENT_KIND_STT_COMPLETED:
      return voiceEvent('stt.transcribed', {
        text: e.text,
        confidence: e.confidence,
        audioDurationMs: e.durationMs,
      }, EventCategory.EVENT_CATEGORY_STT);
    case VoiceEventKind.VOICE_EVENT_KIND_STT_FAILED:
      return voiceEvent('stt.transcriptionFailed', { error: e.error }, EventCategory.EVENT_CATEGORY_STT);
    case VoiceEventKind.VOICE_EVENT_KIND_SYNTHESIS_COMPLETED:
      return voiceEvent('tts.synthesized', { durationMs: e.durationMs, sampleRate: 0 }, EventCategory.EVENT_CATEGORY_TTS);
    case VoiceEventKind.VOICE_EVENT_KIND_SYNTHESIS_FAILED:
      return voiceEvent('tts.synthesisFailed', { error: e.error }, EventCategory.EVENT_CATEGORY_TTS);
    case VoiceEventKind.VOICE_EVENT_KIND_PLAYBACK_STARTED:
      return voiceEvent('playback.started', { durationMs: e.durationMs, sampleRate: 0 }, EventCategory.EVENT_CATEGORY_VOICE_AGENT);
    case VoiceEventKind.VOICE_EVENT_KIND_PLAYBACK_COMPLETED:
      return voiceEvent('playback.completed', { durationMs: e.durationMs }, EventCategory.EVENT_CATEGORY_VOICE_AGENT);
    case VoiceEventKind.VOICE_EVENT_KIND_VOICE_SESSION_TURN_COMPLETED:
      return voiceEvent('voice.turnCompleted', {
        speechDetected: true,
        transcription: e.transcription,
        response: e.turnResponse,
      }, EventCategory.EVENT_CATEGORY_VOICE_AGENT);
    default:
      return null;
  }
}

function voiceEvent(type: string, data: Record<string, unknown>, fallback: EventCategory): TranslatedEvent {
  return { type, data, fallbackCategory: fallback };
}

function translateDownload(e: ProtoDownloadEvent): TranslatedEvent | null {
  switch (e.kind) {
    case DownloadEventKind.DOWNLOAD_EVENT_KIND_STARTED:
      return downloadEvent('model.downloadStarted', { modelId: e.modelId, url: '' });
    case DownloadEventKind.DOWNLOAD_EVENT_KIND_PROGRESS: {
      const p = e.progress;
      return downloadEvent('model.downloadProgress', {
        modelId: e.modelId,
        progress: p?.overallProgress ?? 0,
        bytesDownloaded: p?.bytesDownloaded ?? 0,
        totalBytes: p?.totalBytes ?? 0,
        stage: p?.state !== undefined ? String(p.state) : undefined,
      });
    }
    case DownloadEventKind.DOWNLOAD_EVENT_KIND_COMPLETED:
      return downloadEvent('model.downloadCompleted', { modelId: e.modelId });
    case DownloadEventKind.DOWNLOAD_EVENT_KIND_FAILED:
      return downloadEvent('model.downloadFailed', { modelId: e.modelId, error: e.error });
    default:
      return null;
  }
}

function downloadEvent(type: string, data: Record<string, unknown>): TranslatedEvent {
  return { type, data, fallbackCategory: EventCategory.EVENT_CATEGORY_DOWNLOAD };
}

// =============================================================================
// Reverse: dotted-event-name → proto SDKEvent
// =============================================================================
//
// emit() goes through here. Only event-names with a clean proto representation
// round-trip via the adapter. Anything not covered here falls through to local
// fan-out — that's fine for Web-only events (e.g. storage.localDirectorySelected)
// that don't yet have a canonical proto payload.

function encodeEventToProto(
  eventType: string,
  category: EventCategory,
  data: Record<string, unknown>,
): ProtoSDKEvent | null {
  switch (eventType) {
    case 'sdk.initialized':
      return SDKEvent.fromPartial({
        category,
        initialization: {
          stage: InitializationStage.INITIALIZATION_STAGE_COMPLETED,
          source: stringField(data.environment) ?? stringField(data.source) ?? '',
          version: stringField(data.version) ?? '',
        },
      });

    case 'model.loadStarted':
      return modelProto(category, ModelEventKind.MODEL_EVENT_KIND_LOAD_STARTED, data);
    case 'model.loadCompleted':
      return modelProto(category, ModelEventKind.MODEL_EVENT_KIND_LOAD_COMPLETED, data);
    case 'model.loadFailed':
      return modelProto(category, ModelEventKind.MODEL_EVENT_KIND_LOAD_FAILED, data);
    case 'model.unloaded':
      return modelProto(category, ModelEventKind.MODEL_EVENT_KIND_UNLOAD_COMPLETED, data);
    case 'model.downloadStarted':
      return modelProto(category, ModelEventKind.MODEL_EVENT_KIND_DOWNLOAD_STARTED, data);
    case 'model.downloadProgress':
      return modelProto(category, ModelEventKind.MODEL_EVENT_KIND_DOWNLOAD_PROGRESS, data);
    case 'model.downloadCompleted':
      return modelProto(category, ModelEventKind.MODEL_EVENT_KIND_DOWNLOAD_COMPLETED, data);
    case 'model.downloadFailed':
      return modelProto(category, ModelEventKind.MODEL_EVENT_KIND_DOWNLOAD_FAILED, data);
    case 'model.registered':
      return modelProto(category, ModelEventKind.MODEL_EVENT_KIND_BUILT_IN_REGISTERED, data);

    case 'generation.started':
      return SDKEvent.fromPartial({
        category,
        generation: {
          kind: GenerationEventKind.GENERATION_EVENT_KIND_STARTED,
          prompt: stringField(data.prompt) ?? '',
        },
      });
    case 'generation.completed':
      return SDKEvent.fromPartial({
        category,
        generation: {
          kind: GenerationEventKind.GENERATION_EVENT_KIND_COMPLETED,
          tokensUsed: numberField(data.tokensUsed),
          latencyMs: numberField(data.latencyMs),
        },
      });
    case 'generation.failed':
      return SDKEvent.fromPartial({
        category,
        generation: {
          kind: GenerationEventKind.GENERATION_EVENT_KIND_FAILED,
          error: stringField(data.error) ?? '',
        },
      });

    default:
      return null;
  }
}

function modelProto(
  category: EventCategory,
  kind: ModelEventKind,
  data: Record<string, unknown>,
): ProtoSDKEvent {
  return SDKEvent.fromPartial({
    category,
    model: {
      kind,
      modelId: stringField(data.modelId) ?? '',
      progress: numberField(data.progress),
      bytesDownloaded: numberField(data.bytesDownloaded),
      totalBytes: numberField(data.totalBytes),
      downloadState: stringField(data.stage) ?? '',
      localPath: stringField(data.localPath) ?? '',
      error: stringField(data.error) ?? '',
      modelCount: numberField(data.count),
    },
  });
}

function stringField(value: unknown): string | undefined {
  if (typeof value === 'string') return value;
  if (typeof value === 'number' || typeof value === 'boolean') return String(value);
  return undefined;
}

function numberField(value: unknown): number {
  if (typeof value === 'number' && Number.isFinite(value)) return value;
  return 0;
}

// =============================================================================
// Testing seam
// =============================================================================

/**
 * Test-only escape hatch. Lets a test:
 *   1. construct a `ProtoEventTransport` stub (in-memory subscribe/publish)
 *   2. pass it to a fresh `EventBus`
 *   3. trigger proto events through the stub
 *   4. assert that translation + fan-out behaves correctly
 *
 * Not part of the public package surface — consumers should never reach
 * for this. Kept here (rather than in a separate `__testing__.ts`) so
 * the test imports stay co-located with the implementation under review.
 */
export const __testing__ = {
  translateProtoEvent,
  encodeEventToProto,
};
