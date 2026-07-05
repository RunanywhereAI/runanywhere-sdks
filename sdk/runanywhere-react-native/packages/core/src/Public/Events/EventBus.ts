/**
 * Swift-shaped SDK event bus.
 *
 * Mirrors Swift's `EventBus.shared` surface while using the RN native
 * proto-byte SDKEvent subscription underneath.
 */

import type {
  SDKEvent as SDKEventMessage,
  ComponentLifecycleEvent,
  ModelRegistryEvent,
  DownloadEvent,
  SDKComponent,
} from '@runanywhere/proto-ts/sdk_events';
import {
  GenerationEventKind,
  ModelEventKind,
} from '@runanywhere/proto-ts/sdk_events';
import type { VoiceEvent } from '@runanywhere/proto-ts/voice_events';
import {
  ComponentLifecycleState,
  EventCategory,
} from '@runanywhere/proto-ts/component_types';
import {
  publishSDKEvent,
  subscribeSDKEvents,
} from '../Extensions/Events/RunAnywhere+SDKEvents';

export type SDKEventHandler = (event: SDKEventMessage) => void;
export type EventBusCancellable = () => void;

type NativeUnsubscribe = () => Promise<void>;

export class EventBus {
  private static readonly singleton = new EventBus();

  static get shared(): EventBus {
    return EventBus.singleton;
  }

  private readonly listeners = new Set<SDKEventHandler>();
  private readonly categoryListeners = new Map<EventCategory, Set<SDKEventHandler>>();
  private nativeSubscription: Promise<NativeUnsubscribe> | null = null;

  private constructor() {
    this.ensureNativeSubscription();
  }

  /**
   * Async stream of all SDK events.
   */
  get events(): AsyncIterable<SDKEventMessage> {
    return this.stream();
  }

  /**
   * Publish an event through native commons, falling back to local listeners.
   */
  async publish(event: SDKEventMessage): Promise<boolean> {
    const didPublish = await publishSDKEvent(event);
    if (!didPublish) {
      this.dispatch(event);
    }
    return didPublish;
  }

  /**
   * Async stream filtered by event category.
   */
  eventsFor(category: EventCategory): AsyncIterable<SDKEventMessage> {
    return this.stream(category);
  }

  on(handler: SDKEventHandler): EventBusCancellable;
  on(category: EventCategory, handler: SDKEventHandler): EventBusCancellable;
  on(
    categoryOrHandler: EventCategory | SDKEventHandler,
    maybeHandler?: SDKEventHandler
  ): EventBusCancellable {
    this.ensureNativeSubscription();

    if (typeof categoryOrHandler === 'function') {
      this.listeners.add(categoryOrHandler);
      return () => {
        this.listeners.delete(categoryOrHandler);
      };
    }

    const category = categoryOrHandler;
    const handler = maybeHandler;
    if (!handler) {
      return () => undefined;
    }

    let handlers = this.categoryListeners.get(category);
    if (!handlers) {
      handlers = new Set<SDKEventHandler>();
      this.categoryListeners.set(category, handlers);
    }
    handlers.add(handler);
    return () => {
      handlers?.delete(handler);
      if (handlers?.size === 0) {
        this.categoryListeners.delete(category);
      }
    };
  }

  private ensureNativeSubscription(): void {
    if (this.nativeSubscription) {
      return;
    }

    const subscription = subscribeSDKEvents((event) => {
      this.dispatch(event);
    });
    this.nativeSubscription = subscription;
    void subscription.catch(() => {
      if (this.nativeSubscription === subscription) {
        this.nativeSubscription = null;
      }
    });
  }

  private dispatch(event: SDKEventMessage): void {
    for (const listener of Array.from(this.listeners)) {
      try {
        listener(event);
      } catch (e) {
        console.warn('SDK EventBus listener error:', e);
      }
    }
    const categoryListeners = this.categoryListeners.get(event.category);
    if (!categoryListeners) {
      return;
    }
    for (const listener of Array.from(categoryListeners)) {
      try {
        listener(event);
      } catch (e) {
        console.warn('SDK EventBus category listener error:', e);
      }
    }
  }

  // Category shortcuts (Swift EventBus.swift:138-173)

  /** LLM events. Mirrors Swift `EventBus.llmEvents`. */
  get llmEvents(): AsyncIterable<SDKEventMessage> {
    return this.eventsFor(EventCategory.EVENT_CATEGORY_LLM);
  }

  /** STT events. Mirrors Swift `EventBus.sttEvents`. */
  get sttEvents(): AsyncIterable<SDKEventMessage> {
    return this.eventsFor(EventCategory.EVENT_CATEGORY_STT);
  }

  /** TTS events. Mirrors Swift `EventBus.ttsEvents`. */
  get ttsEvents(): AsyncIterable<SDKEventMessage> {
    return this.eventsFor(EventCategory.EVENT_CATEGORY_TTS);
  }

  /** Model events. Mirrors Swift `EventBus.modelEvents`. */
  get modelEvents(): AsyncIterable<SDKEventMessage> {
    return this.eventsFor(EventCategory.EVENT_CATEGORY_MODEL);
  }

  /** Error events. Mirrors Swift `EventBus.errorEvents`. */
  get errorEvents(): AsyncIterable<SDKEventMessage> {
    return this.eventsFor(EventCategory.EVENT_CATEGORY_ERROR);
  }

  /** SDK lifecycle events. Mirrors Swift `EventBus.sdkEvents`. */
  get sdkEvents(): AsyncIterable<SDKEventMessage> {
    return this.eventsFor(EventCategory.EVENT_CATEGORY_SDK);
  }

  /** RAG events. Mirrors Swift `EventBus.ragEvents`. */
  get ragEvents(): AsyncIterable<SDKEventMessage> {
    return this.eventsFor(EventCategory.EVENT_CATEGORY_RAG);
  }

  // Typed payload streams (Swift EventBus.swift:106-136)

  /** `RAVoiceEvent` payloads (voice-agent pipeline events). */
  get voiceEventPayloads(): AsyncIterable<VoiceEvent> {
    return this.payloadStream((event) => event.voicePipeline);
  }

  /** `RADownloadEvent` payloads (model download progress / lifecycle). */
  get downloadEventPayloads(): AsyncIterable<DownloadEvent> {
    return this.payloadStream((event) => event.download);
  }

  /** `RAComponentLifecycleEvent` payloads. */
  get componentLifecycleEventPayloads(): AsyncIterable<ComponentLifecycleEvent> {
    return this.payloadStream((event) => event.componentLifecycle);
  }

  /** `RAModelRegistryEvent` payloads. */
  get modelRegistryEventPayloads(): AsyncIterable<ModelRegistryEvent> {
    return this.payloadStream((event) => event.modelRegistry);
  }

  // Unified model-lifecycle stream (Swift EventBus+ModelLifecycle.swift)

  /**
   * Unified model load/unload stream across all native signal channels
   * (component-lifecycle, model events, LLM generation events). Mirrors
   * Swift `EventBus.modelLifecycle`.
   */
  get modelLifecycle(): AsyncIterable<ModelLifecycleChange> {
    return this.payloadStream(modelLifecycleChange);
  }

  /** `modelLifecycle` filtered to load completions. */
  get modelLoaded(): AsyncIterable<ModelLifecycleChange> {
    return this.payloadStream((event) => {
      const change = modelLifecycleChange(event);
      return change?.kind === 'loaded' ? change : undefined;
    });
  }

  /** `modelLifecycle` filtered to unloads. */
  get modelUnloaded(): AsyncIterable<ModelLifecycleChange> {
    return this.payloadStream((event) => {
      const change = modelLifecycleChange(event);
      return change?.kind === 'unloaded' ? change : undefined;
    });
  }

  /**
   * Extract a payload type from the proto envelope stream. Mirrors Swift's
   * private `eventsOfPayload(_:)`.
   */
  private payloadStream<Payload>(
    selector: (event: SDKEventMessage) => Payload | undefined
  ): AsyncIterable<Payload> {
    const source = this.stream();
    return {
      async *[Symbol.asyncIterator](): AsyncGenerator<Payload> {
        for await (const event of source) {
          const payload = selector(event);
          if (payload !== undefined) {
            yield payload;
          }
        }
      },
    };
  }

  private stream(category?: EventCategory): AsyncIterable<SDKEventMessage> {
    return {
      [Symbol.asyncIterator]: (): AsyncIterator<SDKEventMessage> => {
        const queue: SDKEventMessage[] = [];
        let resolver:
          | ((value: IteratorResult<SDKEventMessage>) => void)
          | null = null;
        let isClosed = false;

        const unsubscribe = category === undefined
          ? this.on((event) => {
            if (resolver) {
              resolver({ value: event, done: false });
              resolver = null;
            } else {
              queue.push(event);
            }
          })
          : this.on(category, (event) => {
            if (resolver) {
              resolver({ value: event, done: false });
              resolver = null;
            } else {
              queue.push(event);
            }
          });

        return {
          async next(): Promise<IteratorResult<SDKEventMessage>> {
            if (queue.length > 0) {
              return { value: queue.shift()!, done: false };
            }
            if (isClosed) {
              return {
                value: undefined as unknown as SDKEventMessage,
                done: true,
              };
            }
            return new Promise<IteratorResult<SDKEventMessage>>((resolve) => {
              resolver = resolve;
            });
          },
          async return(): Promise<IteratorResult<SDKEventMessage>> {
            isClosed = true;
            unsubscribe();
            if (resolver) {
              resolver({
                value: undefined as unknown as SDKEventMessage,
                done: true,
              });
              resolver = null;
            }
            return {
              value: undefined as unknown as SDKEventMessage,
              done: true,
            };
          },
        };
      },
    };
  }
}

// Typed model-lifecycle change (Swift EventBus+ModelLifecycle.swift)

/** One model load/unload transition, decoded from the raw event bus. */
export interface ModelLifecycleChange {
  /** Whether the model finished loading or was unloaded. */
  kind: 'loaded' | 'unloaded';
  /**
   * Registry id of the affected model. May be empty when the native channel
   * did not carry one (rare; treat as "current model").
   */
  modelId: string;
  /** SDK component slot the change applies to (.llm, .stt, .tts, ...). */
  component: SDKComponent;
  /**
   * The underlying raw event, for consumers that need extra payload fields
   * (progress, framework, error, ...).
   */
  event: SDKEventMessage;
}

/**
 * Decode a raw SDK event into a lifecycle change, or undefined when the event
 * is not a load/unload transition. Exposed so consumers can reuse the exact
 * same channel mapping. Mirrors Swift `EventBus.modelLifecycleChange(from:)`.
 */
export function modelLifecycleChange(
  event: SDKEventMessage
): ModelLifecycleChange | undefined {
  // Channel 1: component-lifecycle (the canonical loadModel path).
  if (event.category === EventCategory.EVENT_CATEGORY_COMPONENT) {
    const lifecycle = event.componentLifecycle;
    if (!lifecycle) return undefined;
    switch (lifecycle.currentState) {
      case ComponentLifecycleState.COMPONENT_LIFECYCLE_STATE_READY:
        return {
          kind: 'loaded',
          modelId: lifecycle.modelId,
          component: lifecycle.component,
          event,
        };
      case ComponentLifecycleState.COMPONENT_LIFECYCLE_STATE_NOT_LOADED:
      case ComponentLifecycleState.COMPONENT_LIFECYCLE_STATE_UNLOADING:
      case ComponentLifecycleState.COMPONENT_LIFECYCLE_STATE_SHUTDOWN:
      case ComponentLifecycleState.COMPONENT_LIFECYCLE_STATE_DELETING:
        return {
          kind: 'unloaded',
          modelId: lifecycle.modelId,
          component: lifecycle.component,
          event,
        };
      default:
        return undefined;
    }
  }

  // Channels 2 + 3: model events and LLM generation events.
  const modelId = event.model?.modelId || event.generation?.modelId || '';

  if (
    event.model?.kind === ModelEventKind.MODEL_EVENT_KIND_LOAD_COMPLETED ||
    event.generation?.kind ===
      GenerationEventKind.GENERATION_EVENT_KIND_MODEL_LOADED
  ) {
    return { kind: 'loaded', modelId, component: event.component, event };
  }
  if (
    event.model?.kind === ModelEventKind.MODEL_EVENT_KIND_UNLOAD_COMPLETED ||
    event.generation?.kind ===
      GenerationEventKind.GENERATION_EVENT_KIND_MODEL_UNLOADED
  ) {
    return { kind: 'unloaded', modelId, component: event.component, event };
  }
  return undefined;
}
