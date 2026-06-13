/**
 * EventBus+ModelLifecycle.ts
 *
 * Typed model-lifecycle stream over the raw SDK event bus — Swift parity:
 * `EventBus+ModelLifecycle.swift` (Public/Extensions/Events).
 *
 * Native commons signals "model loaded/unloaded" on THREE different proto
 * channels depending on the path that performed the work:
 *   1. component-lifecycle events (EVENT_CATEGORY_COMPONENT,
 *      `event.componentLifecycle.currentState`) — the `loadModel` path,
 *   2. model events (`event.model.kind` load/unload completed),
 *   3. LLM generation events (`event.generation.kind` modelLoaded/Unloaded).
 *
 * Which channel fires when is an SDK-internal detail. Consumers should not
 * need to know it — `modelLifecycle()` folds them into one typed stream;
 * `modelLoaded()` / `modelUnloaded()` are pre-filtered views. Swift expresses
 * these as Combine publishers in an `EventBus` extension; TS expresses them
 * as standalone functions over the bus's raw proto stream (AsyncIterable is
 * the Web equivalent of Swift's AsyncStream/AnyPublisher).
 */

import { ComponentLifecycleState, EventCategory } from '@runanywhere/proto-ts/component_types';
import {
  GenerationEventKind,
  ModelEventKind,
  type SDKComponent,
  type SDKEvent as ProtoSDKEvent,
} from '@runanywhere/proto-ts/sdk_events';
import { EventBus } from './EventBus';

// MARK: - Typed change

/**
 * One model load/unload transition, decoded from the raw event bus.
 * Swift parity: `RAModelLifecycleChange` (EventBus+ModelLifecycle.swift:25-44).
 */
export interface ModelLifecycleChange {
  /** Whether the model finished loading or was unloaded. */
  kind: 'loaded' | 'unloaded';

  /**
   * Registry id of the affected model. May be empty when the native
   * channel did not carry one (rare; treat as "current model").
   */
  modelId: string;

  /** SDK component slot the change applies to (.llm, .stt, .tts, ...). */
  component: SDKComponent;

  /**
   * The underlying raw event, for consumers that need extra payload
   * fields (progress, framework, error, ...).
   */
  event: ProtoSDKEvent;
}

// MARK: - Decode

/**
 * Decode a raw SDK event into a lifecycle change, or `undefined` when the
 * event is not a load/unload transition. Exposed so consumers can reuse the
 * exact same channel mapping.
 * Swift parity: `EventBus.modelLifecycleChange(from:)`
 * (EventBus+ModelLifecycle.swift:81-128).
 */
export function modelLifecycleChange(event: ProtoSDKEvent): ModelLifecycleChange | undefined {
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
    event.generation?.kind === GenerationEventKind.GENERATION_EVENT_KIND_MODEL_LOADED
  ) {
    return { kind: 'loaded', modelId, component: event.component, event };
  }

  if (
    event.model?.kind === ModelEventKind.MODEL_EVENT_KIND_UNLOAD_COMPLETED ||
    event.generation?.kind === GenerationEventKind.GENERATION_EVENT_KIND_MODEL_UNLOADED
  ) {
    return { kind: 'unloaded', modelId, component: event.component, event };
  }

  return undefined;
}

// MARK: - Typed streams

/**
 * Unified model load/unload stream across all native signal channels.
 * Swift parity: `EventBus.modelLifecycle` (EventBus+ModelLifecycle.swift:58-62).
 *
 * ```ts
 * for await (const change of modelLifecycle()) {
 *   if (change.component === SDKComponent.SDK_COMPONENT_LLM) { ... }
 * }
 * ```
 */
export function modelLifecycle(
  bus: EventBus = EventBus.shared,
): AsyncIterable<ModelLifecycleChange> {
  return lifecycleStream(bus, () => true);
}

/**
 * `modelLifecycle` filtered to load completions.
 * Swift parity: `EventBus.modelLoaded` (EventBus+ModelLifecycle.swift:65-69).
 */
export function modelLoaded(
  bus: EventBus = EventBus.shared,
): AsyncIterable<ModelLifecycleChange> {
  return lifecycleStream(bus, (change) => change.kind === 'loaded');
}

/**
 * `modelLifecycle` filtered to unloads.
 * Swift parity: `EventBus.modelUnloaded` (EventBus+ModelLifecycle.swift:72-76).
 */
export function modelUnloaded(
  bus: EventBus = EventBus.shared,
): AsyncIterable<ModelLifecycleChange> {
  return lifecycleStream(bus, (change) => change.kind === 'unloaded');
}

/**
 * Decode + filter the bus's raw proto stream into lifecycle changes.
 * Mirrors Swift's `events.compactMap(modelLifecycleChange(from:)).filter { }`
 * publisher chain (EventBus+ModelLifecycle.swift:58-76).
 */
function lifecycleStream(
  bus: EventBus,
  predicate: (change: ModelLifecycleChange) => boolean,
): AsyncIterable<ModelLifecycleChange> {
  const source = bus.protoEvents;
  return {
    async *[Symbol.asyncIterator](): AsyncGenerator<ModelLifecycleChange> {
      for await (const event of source) {
        const change = modelLifecycleChange(event);
        if (change && predicate(change)) {
          yield change;
        }
      }
    },
  };
}
