import type {
  ModelInfo,
  ModelInfoList,
  ModelQuery,
} from '@runanywhere/proto-ts/model_types';
import {
  ModelRegistryAdapter,
  type ModelRegistryAvailability,
  type RefreshOptions,
} from '../../Adapters/ModelRegistryAdapter';

export type { ModelRegistryAvailability } from '../../Adapters/ModelRegistryAdapter';

function requireAdapter(): ModelRegistryAdapter {
  const adapter = ModelRegistryAdapter.tryDefault();
  if (!adapter) {
    throw new Error('RunAnywhere model registry proto adapter is not installed');
  }
  return adapter;
}

export const ModelRegistry = {
  availability(): ModelRegistryAvailability {
    const adapter = ModelRegistryAdapter.tryDefault();
    return adapter?.getProtoRegistryAvailability() ?? {
      status: 'notInstalled',
      reason: 'RunAnywhere model registry proto adapter is not installed',
    };
  },

  refresh(options?: RefreshOptions): boolean {
    return requireAdapter().refresh(options);
  },

  register(model: ModelInfo): boolean {
    return requireAdapter().register(model);
  },

  update(model: ModelInfo): boolean {
    return requireAdapter().update(model);
  },

  get(modelId: string): ModelInfo | null {
    return requireAdapter().get(modelId);
  },

  list(): ModelInfoList | null {
    return requireAdapter().list();
  },

  query(query: ModelQuery): ModelInfoList | null {
    return requireAdapter().query(query);
  },

  listDownloaded(): ModelInfoList | null {
    return requireAdapter().listDownloaded();
  },

  remove(modelId: string): boolean {
    return requireAdapter().remove(modelId);
  },
};
