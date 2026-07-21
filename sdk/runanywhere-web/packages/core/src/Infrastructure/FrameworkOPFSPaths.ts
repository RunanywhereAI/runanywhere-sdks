/**
 * FrameworkOPFSPaths.ts
 *
 * Single source of truth for OPFS directory names per `InferenceFramework`
 * and for resolving a model's primary on-disk filename. Delegates to the
 * C++ `rac_framework_raw_value` ABI exported by the WASM module so the TS
 * layer always tracks the canonical commons mapping without a hand table.
 *
 * Before this file the same directory-name literal and
 * `primaryFilenameFromModel` helper lived inline in two places
 * (`Public/RunAnywhere.ts` and `Public/Extensions/RunAnywhere+ModelLifecycle.ts`),
 * which left a footgun any time we added a new framework but only updated
 * one site.
 */
import {
  ModelArtifactType,
  ModelFileRole,
  type InferenceFramework,
  type ModelInfo,
} from '@runanywhere/proto-ts/model_types';
import { artifactTypeRequiresExtraction } from '../types/ModelTypes+Artifacts.js';
import { tryRunanywhereModule } from '../runtime/EmscriptenModule.js';

/**
 * Resolve the OPFS directory name for a framework by calling into the WASM
 * module's `rac_inference_framework_from_proto` + `rac_framework_raw_value`
 * exports, which are the canonical source of truth in commons.
 *
 * Returns `null` for unknown / unspecified frameworks so callers can decide
 * whether to throw or fall back rather than silently using the wrong path.
 */
export function frameworkOPFSDir(framework: InferenceFramework): string | null {
  const mod = tryRunanywhereModule();
  if (
    mod &&
    typeof mod._rac_inference_framework_from_proto === 'function' &&
    typeof mod._rac_framework_raw_value === 'function'
  ) {
    const outPtr = mod._malloc(4);
    try {
      const rc = mod._rac_inference_framework_from_proto(framework as number, outPtr);
      if (rc !== 0) return null; // RAC_SUCCESS === 0
      const cEnum = mod.HEAP32[outPtr >>> 2] as number;
      const namePtr = mod._rac_framework_raw_value(cEnum);
      if (!namePtr) return null;
      const name = mod.UTF8ToString(namePtr);
      return name && name !== 'Unknown' ? name : null;
    } finally {
      mod._free(outPtr);
    }
  }
  return null;
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

/**
 * True when a model lands in OPFS as an extracted directory (archive unpack
 * or directory artifact), not as a single retained blob. After extract,
 * commons deletes the `.tar.gz` / `.zip`, so hydration must not require the
 * archive filename from `downloadUrl` to still exist.
 */
export function isExtractedDirectoryArtifact(model: ModelInfo): boolean {
  const type = model.artifactType ?? ModelArtifactType.MODEL_ARTIFACT_TYPE_UNSPECIFIED;
  if (artifactTypeRequiresExtraction(type)) return true;
  if (type === ModelArtifactType.MODEL_ARTIFACT_TYPE_DIRECTORY) return true;
  const url = (model.downloadUrl ?? '').split('?')[0]?.toLowerCase() ?? '';
  return url.endsWith('.tar.gz') || url.endsWith('.tgz')
    || url.endsWith('.tar.bz2') || url.endsWith('.tar.xz')
    || url.endsWith('.zip');
}
