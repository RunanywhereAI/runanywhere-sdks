import type {
  CurrentModelRequest,
  CurrentModelResult,
  ModelLoadRequest,
  ModelLoadResult,
  ModelUnloadRequest,
  ModelUnloadResult,
} from '@runanywhere/proto-ts/model_types';
import type {
  ComponentLifecycleSnapshot,
  SDKComponent,
} from '@runanywhere/proto-ts/sdk_events';
import { ComponentLifecycleState } from '@runanywhere/proto-ts/sdk_events';
import { ModelLifecycleAdapter } from '../../Adapters/ModelLifecycleAdapter';

export type {
  CurrentModelRequest,
  CurrentModelResult,
  ModelLoadRequest,
  ModelLoadResult,
  ModelUnloadRequest,
  ModelUnloadResult,
} from '@runanywhere/proto-ts/model_types';
export type {
  ComponentLifecycleEvent,
  ComponentLifecycleSnapshot,
  SDKComponent,
} from '@runanywhere/proto-ts/sdk_events';
export { ComponentLifecycleState } from '@runanywhere/proto-ts/sdk_events';

function requireAdapter(): ModelLifecycleAdapter {
  const adapter = ModelLifecycleAdapter.tryDefault();
  if (!adapter) {
    throw new Error('RunAnywhere model lifecycle proto adapter is not installed');
  }
  return adapter;
}

export const ModelLifecycle = {
  supportsNativeLifecycle(): boolean {
    return ModelLifecycleAdapter.tryDefault()?.supportsProtoLifecycle() ?? false;
  },

  load(request: ModelLoadRequest): ModelLoadResult | null {
    return requireAdapter().load(request);
  },

  unload(request: ModelUnloadRequest): ModelUnloadResult | null {
    return requireAdapter().unload(request);
  },

  unloadAll(): ModelUnloadResult | null {
    return requireAdapter().unload({ modelId: '', unloadAll: true });
  },

  currentModel(request: CurrentModelRequest = {}): CurrentModelResult | null {
    return requireAdapter().currentModel(request);
  },

  isLoaded(request: CurrentModelRequest = {}): boolean {
    const current = requireAdapter().currentModel(request);
    return Boolean(current?.modelId);
  },

  componentSnapshot(component: SDKComponent): ComponentLifecycleSnapshot | null {
    return requireAdapter().componentSnapshot(component);
  },

  isComponentReady(component: SDKComponent): boolean {
    return requireAdapter().componentSnapshot(component)?.state ===
      ComponentLifecycleState.COMPONENT_LIFECYCLE_STATE_READY;
  },

  reset(): boolean {
    return requireAdapter().reset();
  },
};
