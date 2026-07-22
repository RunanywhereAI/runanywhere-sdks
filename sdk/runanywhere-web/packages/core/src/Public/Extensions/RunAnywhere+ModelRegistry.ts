import type {
  ModelImportRequest,
  ModelImportResult,
  ModelInfo,
  ModelInfoList,
  ModelQuery,

  ModelCategory} from '@runanywhere/proto-ts/model_types';
import {
  InferenceFramework
} from '@runanywhere/proto-ts/model_types';
import {
  ModelRegistryAdapter,
  type ModelRegistryAvailability,
  type RefreshOptions,
} from '../../Adapters/ModelRegistryAdapter.js';
import {
  getModuleForCapability,
  type EmscriptenRunanywhereModule,
} from '../../runtime/EmscriptenModule.js';

interface DefaultFrameworkModule extends EmscriptenRunanywhereModule {
  /** Proto-int wrapper over rac_model_category_default_framework (wasm_exports.cpp). */
  _rac_model_category_default_framework_proto?(protoCategory: number): number;
}

export type { ModelRegistryAvailability } from '../../Adapters/ModelRegistryAdapter.js';

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

  /**
   * Import a model via `rac_model_registry_import_proto` — commons owns
   * import semantics. Swift parity: `RunAnywhere.importModel(request)`
   * (RunAnywhere+Storage.swift:286-291).
   */
  importModel(request: ModelImportRequest): ModelImportResult | null {
    return requireAdapter().importModel(request);
  },

  updateModel(model: ModelInfo): boolean {
    return requireAdapter().update(model);
  },

  updateDownloadStatus(modelId: string, localPath: string | null): boolean {
    return requireAdapter().updateDownloadStatus(modelId, localPath);
  },

  // Read APIs degrade gracefully when no backend adapter is installed yet
  // (backends register asynchronously on Web), returning the declared `null`
  // instead of throwing. This mirrors iOS (`RAModelGetResult(found: false)` /
  // `RAModelListResult(success: false)`) and Kotlin, which return empty
  // results rather than throwing on not-ready reads. Use `availability()` to
  // distinguish "not installed" from "installed but empty". Mutating APIs above
  // still throw via `requireAdapter()`, since a write with no registry is a
  // caller error.
  getModel(modelId: string): ModelInfo | null {
    return ModelRegistryAdapter.tryDefault()?.get(modelId) ?? null;
  },

  listModels(): ModelInfoList | null {
    return ModelRegistryAdapter.tryDefault()?.list() ?? null;
  },

  queryModels(query: ModelQuery): ModelInfoList | null {
    return ModelRegistryAdapter.tryDefault()?.query(query) ?? null;
  },

  downloadedModels(): ModelInfoList | null {
    return ModelRegistryAdapter.tryDefault()?.listDownloaded() ?? null;
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
    // Routed through commons' `rac_model_category_default_framework` (the
    // table Swift's `RAModelCategory.defaultFramework` reads) via the
    // proto-int WASM wrapper — no TS switch table.
    const module = getModuleForCapability('commons') as DefaultFrameworkModule | null;
    if (!module || typeof module._rac_model_category_default_framework_proto !== 'function') {
      return InferenceFramework.INFERENCE_FRAMEWORK_UNKNOWN;
    }
    const protoFramework = module._rac_model_category_default_framework_proto(category);
    return (protoFramework in InferenceFramework
      ? protoFramework
      : InferenceFramework.INFERENCE_FRAMEWORK_UNKNOWN) as InferenceFramework;
  },
};
