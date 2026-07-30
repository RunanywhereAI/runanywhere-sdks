/**
 * `RunAnywhere.events` — lifecycle, model, and error breadcrumbs.
 */

import {
  InitializationStage,
  ModelEventKind,
  type SDKEvent,
} from '@runanywhere/proto-ts/sdk_events';

import { EventBus } from '../Events/EventBus';
import { mapStream } from './Stream';
import type { SdkEvent } from './Types';

/** Project one native SDK event onto the public grammar. */
function toSdkEvent(event: SDKEvent): SdkEvent | undefined {
  if (
    event.initialization?.stage === InitializationStage.INITIALIZATION_STAGE_COMPLETED
  ) {
    return { type: 'ready' };
  }
  if (event.initialization?.stage === InitializationStage.INITIALIZATION_STAGE_FAILED) {
    return {
      type: 'error',
      message: event.initialization.error,
      recoverable: false,
    };
  }
  if (event.componentLifecycle?.modelLoadResult?.success) {
    return {
      type: 'modelLoaded',
      id: event.componentLifecycle.modelLoadResult.modelId,
      category: event.componentLifecycle.modelLoadResult.category,
    };
  }
  if (event.model) {
    switch (event.model.kind) {
      case ModelEventKind.MODEL_EVENT_KIND_UNLOAD_COMPLETED:
        return { type: 'modelUnloaded', id: event.model.modelId };
      case ModelEventKind.MODEL_EVENT_KIND_LOAD_FAILED:
      case ModelEventKind.MODEL_EVENT_KIND_DOWNLOAD_FAILED:
        return {
          type: 'error',
          message: event.model.error,
          recoverable: true,
        };
      default:
        return undefined;
    }
  }
  if (event.failure?.error) {
    return {
      type: 'error',
      message: event.failure.error.message,
      recoverable: event.failure.recoverable,
    };
  }
  return undefined;
}

/** Fresh subscription to the public SDK event stream. */
export function sdkEvents(): AsyncIterable<SdkEvent> {
  return mapStream(EventBus.shared.events, toSdkEvent);
}
