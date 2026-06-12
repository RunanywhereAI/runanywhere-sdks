import type {
  ModelInfo,
  ModelInfoList,
  ModelQuery,
} from '@runanywhere/proto-ts/model_types';
import {
  InferenceFramework,
  ModelCategory,
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

  registerModel(model: ModelInfo): boolean {
    return requireAdapter().register(model);
  },

  updateModel(model: ModelInfo): boolean {
    return requireAdapter().update(model);
  },

  getModel(modelId: string): ModelInfo | null {
    return requireAdapter().get(modelId);
  },

  listModels(): ModelInfoList | null {
    return requireAdapter().list();
  },

  queryModels(query: ModelQuery): ModelInfoList | null {
    return requireAdapter().query(query);
  },

  downloadedModels(): ModelInfoList | null {
    return requireAdapter().listDownloaded();
  },

  removeModel(modelId: string): boolean {
    return requireAdapter().remove(modelId);
  },

  /**
   * Framework the SDK falls back to when a category has no explicit model
   * framework resolved (e.g. a pending UI selection that has not yet matched a
   * catalogued model). Mirrors commons' `rac_model_category_default_framework`
   * and Swift's `RAModelCategory.defaultFramework`.
   */
  defaultFramework(category: ModelCategory): InferenceFramework {
    switch (category) {
      case ModelCategory.MODEL_CATEGORY_LANGUAGE:
      case ModelCategory.MODEL_CATEGORY_MULTIMODAL:
        return InferenceFramework.INFERENCE_FRAMEWORK_LLAMA_CPP;
      case ModelCategory.MODEL_CATEGORY_SPEECH_RECOGNITION:
      case ModelCategory.MODEL_CATEGORY_SPEECH_SYNTHESIS:
      case ModelCategory.MODEL_CATEGORY_EMBEDDING:
      case ModelCategory.MODEL_CATEGORY_VOICE_ACTIVITY_DETECTION:
        return InferenceFramework.INFERENCE_FRAMEWORK_ONNX;
      default:
        return InferenceFramework.INFERENCE_FRAMEWORK_UNKNOWN;
    }
  },
};
