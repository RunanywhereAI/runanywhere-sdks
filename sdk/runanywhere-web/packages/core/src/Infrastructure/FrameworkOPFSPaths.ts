/**
 * FrameworkOPFSPaths.ts
 *
 * Single source of truth for OPFS directory names per `InferenceFramework`
 * and for resolving a model's primary on-disk filename. Mirrors the C++
 * `rac_framework_raw_value` helper in
 * `sdk/runanywhere-commons/include/rac/infrastructure/model_management/rac_model_paths.h`.
 *
 * Before this file the same `FRAMEWORK_OPFS_DIR` literal and
 * `primaryFilenameFromModel` helper lived inline in two places
 * (`Public/RunAnywhere.ts` and `Public/Extensions/RunAnywhere+ModelLifecycle.ts`),
 * which left a footgun any time we added a new framework but only updated
 * one site.
 */
import {
  InferenceFramework,
  ModelFileRole,
  type ModelInfo,
} from '@runanywhere/proto-ts/model_types';

/**
 * Directory names under `/opfs/RunAnywhere/Models/<dir>/<modelId>/<filename>`.
 * Mirrors C++ `rac_framework_raw_value` so a model downloaded by commons
 * lands at the same path the TS layer expects to read it from.
 */
export const FRAMEWORK_OPFS_DIR: Partial<Record<InferenceFramework, string>> = {
  [InferenceFramework.INFERENCE_FRAMEWORK_LLAMA_CPP]: 'LlamaCpp',
  [InferenceFramework.INFERENCE_FRAMEWORK_ONNX]: 'ONNX',
  [InferenceFramework.INFERENCE_FRAMEWORK_SHERPA]: 'Sherpa',
  [InferenceFramework.INFERENCE_FRAMEWORK_COREML]: 'CoreML',
  [InferenceFramework.INFERENCE_FRAMEWORK_MLX]: 'MLX',
};

/**
 * Lookup helper. Returns `null` for unknown frameworks so callers can decide
 * whether to throw or fall back rather than silently using the wrong path.
 */
export function frameworkOPFSDir(framework: InferenceFramework): string | null {
  return FRAMEWORK_OPFS_DIR[framework] ?? null;
}

/**
 * Resolve the primary file name for a model. Used to assemble the canonical
 * OPFS path for single-file artifacts and to locate the primary file inside
 * a multi-file folder.
 *
 * Resolution order:
 *   1. The `MODEL_FILE_ROLE_PRIMARY_MODEL` entry from `multiFile.files`.
 *   2. The first `multiFile.files` entry (legacy catalogs may not tag a primary).
 *   3. The trailing path segment of `downloadUrl`.
 */
export function primaryFilenameFromModel(model: ModelInfo): string | null {
  const primary = model.multiFile?.files?.find(
    (f) => f.role === ModelFileRole.MODEL_FILE_ROLE_PRIMARY_MODEL,
  ) ?? model.multiFile?.files?.[0];
  if (primary?.filename) return primary.filename;
  const url = model.downloadUrl ?? '';
  const trailing = url.split('?')[0].split('/').pop() ?? '';
  return trailing.length > 0 ? trailing : null;
}
