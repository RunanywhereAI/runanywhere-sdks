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
import { prepareModelLoad, recoverModelLoadFailure } from '../../Foundation/RuntimeConfig';
import { ModelRegistry } from './RunAnywhere+ModelRegistry';

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

  async loadModelAsync(request: ModelLoadRequest): Promise<ModelLoadResult | null> {
    const modelSnapshot = request.modelId ? safeGetModelSnapshot(request.modelId) : null;
    await prepareModelLoad({ request, model: modelSnapshot });
    if (modelSnapshot) {
      ModelRegistry.registerModel(modelSnapshot);
    }
    try {
      return await requireAdapter().loadAsync(request);
    } catch (error) {
      const recovered = await recoverModelLoadFailure({ request, error });
      if (!recovered) throw error;
      if (modelSnapshot) {
        ModelRegistry.registerModel(modelSnapshot);
      }
      return requireAdapter().loadAsync(request);
    }
  },

  unloadModel(request: ModelUnloadRequest): ModelUnloadResult | null {
    return requireAdapter().unload(request);
  },

  unloadModelAsync(request: ModelUnloadRequest): Promise<ModelUnloadResult | null> {
    return requireAdapter().unloadAsync(request);
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

function safeGetModelSnapshot(modelId: string) {
  try {
    return ModelRegistry.getModel(modelId);
  } catch {
    return null;
  }
}
