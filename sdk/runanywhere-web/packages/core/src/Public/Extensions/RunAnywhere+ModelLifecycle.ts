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
import { ComponentLifecycleState } from '@runanywhere/proto-ts/component_types';
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
export { ComponentLifecycleState } from '@runanywhere/proto-ts/component_types';

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

  loadModel(request: ModelLoadRequest): ModelLoadResult | null {
    return requireAdapter().load(request);
  },

  unloadModel(request: ModelUnloadRequest): ModelUnloadResult | null {
    return requireAdapter().unload(request);
  },

  unloadAllModels(): ModelUnloadResult | null {
    return requireAdapter().unload({ modelId: '', unloadAll: true });
  },

  currentModel(
    request: CurrentModelRequest = { includeModelMetadata: false },
  ): CurrentModelResult | null {
    return requireAdapter().currentModel(request);
  },

  isLoaded(request: CurrentModelRequest = { includeModelMetadata: false }): boolean {
    const current = requireAdapter().currentModel(request);
    return Boolean(current?.modelId);
  },

  componentLifecycleSnapshot(component: SDKComponent): ComponentLifecycleSnapshot | null {
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
