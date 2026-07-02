import { ComponentLifecycleState, EventCategory } from '@runanywhere/proto-ts/component_types';
import {
  GenerationEventKind,
  ModelEventKind,
  type SDKComponent,
  type SDKEvent as ProtoSDKEvent,
} from '@runanywhere/proto-ts/sdk_events';
import { EventBus } from './EventBus';

export interface ModelLifecycleChange {
  kind: 'loaded' | 'unloaded';
  modelId: string;
  component: SDKComponent;
  event: ProtoSDKEvent;
}

export function modelLifecycleChange(event: ProtoSDKEvent): ModelLifecycleChange | undefined {
  if (event.category === EventCategory.EVENT_CATEGORY_COMPONENT) {
    const lifecycle = event.componentLifecycle;
    if (!lifecycle) return undefined;
    switch (lifecycle.currentState) {
      case ComponentLifecycleState.COMPONENT_LIFECYCLE_STATE_READY:
        return { kind: 'loaded', modelId: lifecycle.modelId, component: lifecycle.component, event };
      case ComponentLifecycleState.COMPONENT_LIFECYCLE_STATE_NOT_LOADED:
      case ComponentLifecycleState.COMPONENT_LIFECYCLE_STATE_UNLOADING:
      case ComponentLifecycleState.COMPONENT_LIFECYCLE_STATE_SHUTDOWN:
      case ComponentLifecycleState.COMPONENT_LIFECYCLE_STATE_DELETING:
        return { kind: 'unloaded', modelId: lifecycle.modelId, component: lifecycle.component, event };
      default:
        return undefined;
    }
  }

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

export function modelLifecycle(bus: EventBus = EventBus.shared): AsyncIterable<ModelLifecycleChange> {
  return lifecycleStream(bus, () => true);
}

export function modelLoaded(bus: EventBus = EventBus.shared): AsyncIterable<ModelLifecycleChange> {
  return lifecycleStream(bus, (change) => change.kind === 'loaded');
}

export function modelUnloaded(bus: EventBus = EventBus.shared): AsyncIterable<ModelLifecycleChange> {
  return lifecycleStream(bus, (change) => change.kind === 'unloaded');
}

function lifecycleStream(
  bus: EventBus,
  predicate: (change: ModelLifecycleChange) => boolean,
): AsyncIterable<ModelLifecycleChange> {
  const source = bus.protoEvents;
  return {
    async *[Symbol.asyncIterator](): AsyncGenerator<ModelLifecycleChange> {
      for await (const event of source) {
        const change = modelLifecycleChange(event);
        if (change && predicate(change)) yield change;
      }
    },
  };
}
