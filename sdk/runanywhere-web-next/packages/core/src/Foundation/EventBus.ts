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
  type ComponentLifecycleEvent as ProtoComponentLifecycleEvent,
  type DownloadEvent as ProtoDownloadEvent,
  type GenerationEvent as ProtoGenerationEvent,
  type InitializationEvent as ProtoInitializationEvent,
  type ModelEvent as ProtoModelEvent,
  type ModelRegistryEvent as ProtoModelRegistryEvent,
  type SDKEvent as ProtoSDKEvent,
  type VoiceLifecycleEvent as ProtoVoiceLifecycleEvent,
} from '@runanywhere/proto-ts/sdk_events';
import type { VoiceEvent as ProtoVoiceEvent } from '@runanywhere/proto-ts/voice_events';
import { SDKLogger } from './SDKLogger';

const logger = new SDKLogger('EventBus');

export type EventListener<T = unknown> = (event: T) => void;
export type Unsubscribe = () => void;
export type SDKEventHandler = (event: ProtoSDKEvent) => void;
export type SDKEventUnsubscribe = () => void;

export interface SDKEventEnvelope {
  type: string;
  category: EventCategory;
  timestamp: number;
  data: Record<string, unknown>;
}

export interface SDKEventMap {
  'sdk.initialized': { environment: SDKEnvironment };
  'sdk.accelerationMode': { mode: string };

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

  'generation.started': { prompt: string };
  'generation.completed': { tokensUsed: number; latencyMs: number };
  'generation.failed': { error: string };

  'stt.transcribed': { text: string; confidence: number; audioDurationMs?: number; wordCount?: number };
  'stt.transcriptionFailed': { error: string };

  'tts.synthesized': { durationMs: number; sampleRate: number; characterCount?: number; processingMs?: number; charsPerSec?: number; textLength?: number };
  'tts.synthesisFailed': { error: string };

  'vad.speechStarted': { activity: SpeechActivityKind };
  'vad.speechEnded': { activity: SpeechActivityKind; speechDurationMs?: number };

  'voice.turnCompleted': { speechDetected: boolean; transcription: string; response: string };

  'embeddings.generated': { numEmbeddings: number; dimension: number; processingTimeMs: number };
  'diffusion.generated': { width: number; height: number; generationTimeMs: number };
  'vlm.processed': { tokensPerSecond: number; totalTokens: number; hardwareUsed: string };

  'playback.started': { durationMs: number; sampleRate: number };
  'playback.completed': { durationMs: number };

  [key: string]: Record<string, unknown>;
}

export interface ProtoEventTransport {
  subscribe(handler: SDKEventHandler): SDKEventUnsubscribe | null;
  publish(event: ProtoSDKEvent): boolean;
}

let _defaultTransportFactory: (() => ProtoEventTransport | null) | null = null;

export function setDefaultProtoTransport(factory: (() => ProtoEventTransport | null) | null): void {
  _defaultTransportFactory = factory;
}

function resolveDefaultTransport(): ProtoEventTransport | null {
  return _defaultTransportFactory ? _defaultTransportFactory() : null;
}

export class EventBus {
  private static _instance: EventBus | null = null;

  static get shared(): EventBus {
    if (!EventBus._instance) EventBus._instance = new EventBus();
    return EventBus._instance;
  }

  static reset(): void {
    EventBus._instance?.dispose();
    EventBus._instance = null;
  }

  private readonly subscribers = new Map<string, Set<EventListener>>();
  private readonly wildcardListeners = new Set<EventListener<SDKEventEnvelope>>();
  private readonly categoryListeners = new Map<EventCategory, Set<EventListener<ProtoSDKEvent>>>();
  private readonly protoListeners = new Set<EventListener<ProtoSDKEvent>>();

  private transport: ProtoEventTransport | null;
  private transportUnsubscribe: SDKEventUnsubscribe | null = null;

  constructor(transport: ProtoEventTransport | null = resolveDefaultTransport()) {
    this.transport = transport;
    this.attachTransport();
  }

  start(): void {
    this.ensureTransport();
  }

  stop(): void {
    if (!this.transportUnsubscribe) return;
    this.transportUnsubscribe();
    this.transportUnsubscribe = null;
  }

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

  onAny(listener: EventListener<SDKEventEnvelope>): Unsubscribe {
    this.ensureTransport();
    this.wildcardListeners.add(listener);
    return () => { this.wildcardListeners.delete(listener); };
  }

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

  eventsFor(category: EventCategory): AsyncIterable<ProtoSDKEvent> {
    return EventBus.iterableFromSubscription((listener) => this.onCategory(category, listener));
  }

  get protoEvents(): AsyncIterable<ProtoSDKEvent> {
    return EventBus.iterableFromSubscription((listener) => this.onProtoEvent(listener));
  }

  get llmEvents(): AsyncIterable<ProtoSDKEvent> { return this.eventsFor(EventCategory.EVENT_CATEGORY_LLM); }
  get sttEvents(): AsyncIterable<ProtoSDKEvent> { return this.eventsFor(EventCategory.EVENT_CATEGORY_STT); }
  get ttsEvents(): AsyncIterable<ProtoSDKEvent> { return this.eventsFor(EventCategory.EVENT_CATEGORY_TTS); }
  get modelEvents(): AsyncIterable<ProtoSDKEvent> { return this.eventsFor(EventCategory.EVENT_CATEGORY_MODEL); }
  get errorEvents(): AsyncIterable<ProtoSDKEvent> { return this.eventsFor(EventCategory.EVENT_CATEGORY_ERROR); }
  get sdkEvents(): AsyncIterable<ProtoSDKEvent> { return this.eventsFor(EventCategory.EVENT_CATEGORY_SDK); }
  get ragEvents(): AsyncIterable<ProtoSDKEvent> { return this.eventsFor(EventCategory.EVENT_CATEGORY_RAG); }

  get voiceEventPayloads(): AsyncIterable<ProtoVoiceEvent> {
    return this.eventsOfPayload((envelope) => envelope.voicePipeline);
  }
  get downloadEventPayloads(): AsyncIterable<ProtoDownloadEvent> {
    return this.eventsOfPayload((envelope) => envelope.download);
  }
  get componentLifecycleEventPayloads(): AsyncIterable<ProtoComponentLifecycleEvent> {
    return this.eventsOfPayload((envelope) => envelope.componentLifecycle);
  }
  get modelRegistryEventPayloads(): AsyncIterable<ProtoModelRegistryEvent> {
    return this.eventsOfPayload((envelope) => envelope.modelRegistry);
  }

  private eventsOfPayload<Payload>(
    selector: (event: ProtoSDKEvent) => Payload | undefined,
  ): AsyncIterable<Payload> {
    return EventBus.iterableFromSubscription((listener) =>
      this.onProtoEvent((event) => {
        const payload = selector(event);
        if (payload !== undefined) listener(payload);
      }),
    );
  }

  private onProtoEvent(listener: EventListener<ProtoSDKEvent>): Unsubscribe {
    this.ensureTransport();
    this.protoListeners.add(listener);
    return () => { this.protoListeners.delete(listener); };
  }

  private static iterableFromSubscription<T>(
    subscribe: (listener: (value: T) => void) => Unsubscribe,
  ): AsyncIterable<T> {
    return {
      [Symbol.asyncIterator](): AsyncIterator<T> {
        const queue: T[] = [];
        const waiters: Array<(value: IteratorResult<T>) => void> = [];
        let closed = false;
        const unsubscribe = subscribe((value) => {
          if (waiters.length > 0) waiters.shift()!({ value, done: false });
          else queue.push(value);
        });
        return {
          next(): Promise<IteratorResult<T>> {
            if (queue.length > 0) return Promise.resolve({ value: queue.shift()!, done: false });
            if (closed) return Promise.resolve({ value: undefined as unknown as T, done: true });
            return new Promise((resolve) => { waiters.push(resolve); });
          },
          return(): Promise<IteratorResult<T>> {
            closed = true;
            unsubscribe();
            const doneResult: IteratorResult<T> = { value: undefined as unknown as T, done: true };
            for (const waiter of waiters.splice(0)) waiter(doneResult);
            return Promise.resolve(doneResult);
          },
        };
      },
    };
  }

  once<K extends keyof SDKEventMap>(eventType: K, listener: EventListener<SDKEventMap[K]>): Unsubscribe {
    const unsubscribe = this.on(eventType, (event) => {
      unsubscribe();
      listener(event);
    });
    return unsubscribe;
  }

  publish<K extends keyof SDKEventMap>(eventType: K, category: EventCategory, data?: SDKEventMap[K]): void {
    this.ensureTransport();
    const key = eventType as string;
    const payload = (data ?? {}) as Record<string, unknown>;
    if (this.publishThroughTransport(key, category, payload)) return;
    this.dispatch({ type: key, category, timestamp: Date.now(), data: payload });
  }

  removeAll(): void {
    this.subscribers.clear();
    this.wildcardListeners.clear();
    this.categoryListeners.clear();
    this.protoListeners.clear();
  }

  private dispose(): void {
    this.transportUnsubscribe?.();
    this.transportUnsubscribe = null;
    this.transport = null;
    this.removeAll();
  }

  private ensureTransport(): void {
    if (this.transportUnsubscribe) return;
    if (!this.transport) this.transport = resolveDefaultTransport();
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
    this.fireProto(event);
    this.fireCategory(event);
    const translated = translateProtoEvent(event);
    if (!translated) {
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

  private fireProto(event: ProtoSDKEvent): void {
    for (const listener of Array.from(this.protoListeners)) {
      try { listener(event); } catch (error) {
        logger.error(`Proto listener error: ${error instanceof Error ? error.message : String(error)}`);
      }
    }
  }

  private fireCategory(event: ProtoSDKEvent): void {
    const set = this.categoryListeners.get(event.category);
    if (!set) return;
    for (const listener of Array.from(set)) {
      try { listener(event); } catch (error) {
        logger.error(`Category listener error for ${String(event.category)}: ${error instanceof Error ? error.message : String(error)}`);
      }
    }
  }

  private dispatch(envelope: SDKEventEnvelope): void {
    const set = this.subscribers.get(envelope.type);
    if (set) {
      for (const listener of Array.from(set)) {
        try { listener(envelope.data); } catch (error) {
          logger.error(`Listener error for ${envelope.type}: ${error instanceof Error ? error.message : String(error)}`);
        }
      }
    }
    this.fireWildcard(envelope);
  }

  private fireWildcard(envelope: SDKEventEnvelope): void {
    for (const listener of Array.from(this.wildcardListeners)) {
      try { listener(envelope); } catch (error) {
        logger.error(`Wildcard listener error: ${error instanceof Error ? error.message : String(error)}`);
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
      logger.warning(`proto transport publish failed for ${eventType}: ${error instanceof Error ? error.message : String(error)}`);
      return false;
    }
  }
}

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
      return modelEvent('model.unloaded', { modelId: e.modelId, category: ModelCategory.MODEL_CATEGORY_UNSPECIFIED });
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
      return modelEvent('model.downloadCompleted', { modelId: e.modelId, localPath: e.localPath });
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
      return generationEvent('generation.completed', { tokensUsed: e.tokensUsed, latencyMs: e.latencyMs });
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
      return voiceEvent('stt.transcribed', { text: e.text, confidence: e.confidence, audioDurationMs: e.durationMs }, EventCategory.EVENT_CATEGORY_STT);
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
        generation: { kind: GenerationEventKind.GENERATION_EVENT_KIND_STARTED, prompt: stringField(data.prompt) ?? '' },
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
        generation: { kind: GenerationEventKind.GENERATION_EVENT_KIND_FAILED, error: stringField(data.error) ?? '' },
      });
    default:
      return null;
  }
}

function modelProto(category: EventCategory, kind: ModelEventKind, data: Record<string, unknown>): ProtoSDKEvent {
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

export const __testing__ = {
  translateProtoEvent,
  encodeEventToProto,
};
