/**
 * RunAnywhere+LoRA.ts
 *
 * Top-level Web LoRA API backed by the generated proto-byte C ABI.
 *
 * idl/lora_options.proto (API-realignment "lora-delete-download-import-
 * bookkeeping" pass) renamed every `LoRA*` type to `Lora*` and deleted
 * `LoraAdapterDownloadCompletedRequest`/`Result` and
 * `LoraAdapterImportRequest`/`Result` outright: adapter files are now
 * acquired through the models domain's generic download verb
 * (`SDKCore.downloadModel`, used by `downloadLoraAdapter` below), and this
 * LoRA domain carries no download/import state of its own -- a non-empty
 * `LoraAdapterCatalogEntry.localPath` is the only "downloaded" signal.
 * `rac_lora_catalog_mark_download_completed_proto` and
 * `rac_lora_adapter_import_proto` are permanently retired stubs on the C++
 * side (`RAC_ERROR_NOT_IMPLEMENTED`); Web has no replacement for the local-
 * file-picker import path (`LoRA.importAdapter`) until a byte-staging
 * primitive exists for the models-domain import verb -- it is intentionally
 * dropped here rather than reimplemented against a fabricated ABI.
 */

import { LoRAProtoAdapter } from '../../Adapters/ModalityProtoAdapter.js';
import { ProtoErrorCode, SDKException } from '../../Foundation/SDKException.js';
import type {
  LoraAdapterCatalogEntry,
  LoraAdapterCatalogGetRequest,
  LoraAdapterCatalogGetResult,
  LoraAdapterCatalogListRequest,
  LoraAdapterCatalogListResult,
  LoraAdapterCatalogQuery,
  LoraAdapterConfig,
  LoraApplyRequest,
  LoraApplyResult,
  LoraCompatibilityResult,
  LoraRemoveRequest,
  LoraState,
} from '@runanywhere/proto-ts/lora_options';
import {
  LoraCompatibilityResult as LoraCompatibilityResultMessage,
} from '@runanywhere/proto-ts/lora_options';
import {
  InferenceFramework,
  ModelCategory,
  ModelFileRole,
  ModelFormat,
  ModelInfo as ModelInfoMessage,
  ModelSource,
  type ModelInfo,
} from '@runanywhere/proto-ts/model_types';
import type { DownloadProgress } from '@runanywhere/proto-ts/download_service';
import { ModelRegistry } from './RunAnywhere+ModelRegistry.js';

export type {
  LoraAdapterCatalogEntry,
  LoraAdapterCatalogGetRequest,
  LoraAdapterCatalogGetResult,
  LoraAdapterCatalogListRequest,
  LoraAdapterCatalogListResult,
  LoraAdapterCatalogQuery,
  LoraAdapterConfig,
  LoraApplyRequest,
  LoraApplyResult,
  LoraCompatibilityResult,
  LoraRemoveRequest,
  LoraState,
} from '@runanywhere/proto-ts/lora_options';

function requireAdapter(operation: string): LoRAProtoAdapter {
  const adapter = LoRAProtoAdapter.tryDefault();
  if (!adapter) {
    throw SDKException.backendNotAvailable(
      operation,
      'RunAnywhere WASM module is not installed.',
    );
  }
  return adapter;
}

function requireResult<T>(operation: string, result: T | null): T {
  if (result == null) {
    throw SDKException.backendNotAvailable(
      operation,
      'LoRA proto ABI is unavailable or returned an empty result.',
    );
  }
  return result;
}

function emptyLoRAState(): LoraState {
  return {
    loadedAdapters: [],
  };
}

function emptyCatalogListRequest(): LoraAdapterCatalogListRequest {
  return {};
}

export function supportsNativeLoRA(): boolean {
  return LoRAProtoAdapter.tryDefault()?.supportsProtoLoRA() ?? false;
}

export function missingLoRAExports(): string[] {
  return LoRAProtoAdapter.tryDefault()?.missingLoRAExports() ?? [];
}

export function supportsNativeLoRACatalog(): boolean {
  return LoRAProtoAdapter.tryDefault()?.supportsProtoLoRACatalog() ?? false;
}

export function missingLoRACatalogExports(): string[] {
  return LoRAProtoAdapter.tryDefault()?.missingLoRACatalogExports() ?? [];
}

export async function applyLoraAdapters(
  request: LoraApplyRequest,
): Promise<LoraApplyResult> {
  return requireResult(
    'LoRA.apply',
    await requireAdapter('LoRA.apply').apply(request),
  );
}

/**
 * Apply one registered catalog adapter to the current LLM session.
 *
 * Preserves the catalog entry id in the generated config so commons can
 * validate registered catalog adapters against the loaded base model.
 *
 * `replaceExisting` keeps its public name and `false` default unchanged
 * (stack on top of the current set, matching the pre-realignment
 * behavior). The wire field is `keepExisting`, an inverted polarity: the
 * proto-building step below inverts once, at the boundary.
 */
export async function applyLoraCatalogAdapter(
  entry: LoraAdapterCatalogEntry,
  options: {
    localPath?: string;
    scale?: number;
    replaceExisting?: boolean;
  } = {},
): Promise<LoraApplyResult> {
  const adapterPath = options.localPath || entry.localPath || '';
  if (!adapterPath) {
    throw SDKException.fromCode(
      -ProtoErrorCode.ERROR_CODE_INVALID_ARGUMENT,
      `LoRA catalog adapter '${entry.id}' has no local path`,
    );
  }
  const replaceExisting = options.replaceExisting ?? false;
  return applyLoraAdapters({
    requestId: '',
    adapters: [
      {
        adapterPath,
        adapterId: entry.id,
        scale: options.scale ?? ((entry.defaultScale ?? 0) > 0 ? entry.defaultScale : 1.0),
      },
    ],
    keepExisting: !replaceExisting,
  });
}

export async function removeLoraAdapters(
  request: LoraRemoveRequest,
): Promise<LoraState> {
  return requireResult(
    'LoRA.remove',
    await requireAdapter('LoRA.remove').remove(request),
  );
}

export async function listLoraAdapters(
  request: LoraState = emptyLoRAState(),
): Promise<LoraState> {
  return requireResult(
    'LoRA.list',
    requireAdapter('LoRA.list').list(request),
  );
}

export async function getLoraState(
  request: LoraState = emptyLoRAState(),
): Promise<LoraState> {
  return requireResult(
    'LoRA.state',
    requireAdapter('LoRA.state').state(request),
  );
}

export async function checkLoraCompatibility(
  config: LoraAdapterConfig,
): Promise<LoraCompatibilityResult> {
  // Swift parity (RunAnywhere+LoRA.swift:64-70): never throws — failures fold
  // into a `LoraCompatibilityResult` with isCompatible=false + errorMessage.
  try {
    return requireResult(
      'LoRA.checkCompatibility',
      requireAdapter('LoRA.checkCompatibility').compatibility(config),
    );
  } catch (error) {
    return LoraCompatibilityResultMessage.fromPartial({
      isCompatible: false,
      error: SDKException.processingFailed(
        error instanceof Error ? error.message : String(error),
      ).proto,
    });
  }
}

export async function registerLoraAdapter(
  entry: LoraAdapterCatalogEntry,
): Promise<LoraAdapterCatalogEntry> {
  return requireResult(
    'LoRA.register',
    requireAdapter('LoRA.register').register(entry),
  );
}

export async function listLoraCatalog(
  request: LoraAdapterCatalogListRequest = emptyCatalogListRequest(),
): Promise<LoraAdapterCatalogListResult> {
  return requireResult(
    'LoRA.catalog.list',
    requireAdapter('LoRA.catalog.list').listCatalog(request),
  );
}

export async function queryLoraCatalog(
  query: LoraAdapterCatalogQuery,
): Promise<LoraAdapterCatalogListResult> {
  return requireResult(
    'LoRA.catalog.query',
    requireAdapter('LoRA.catalog.query').queryCatalog(query),
  );
}

export async function getLoraCatalogEntry(
  request: LoraAdapterCatalogGetRequest,
): Promise<LoraAdapterCatalogGetResult> {
  return requireResult(
    'LoRA.catalog.get',
    requireAdapter('LoRA.catalog.get').getCatalogEntry(request),
  );
}

/**
 * Get all LoRA adapters compatible with a specific model (CANONICAL_API §3).
 * Mirrors Swift `lora.adaptersForModel(_:)` (RunAnywhere+LoRA.swift:153-165).
 */
export async function loraAdaptersForModel(
  modelId: string,
): Promise<LoraAdapterCatalogEntry[]> {
  const result = await queryLoraCatalog({ modelId, tags: [] });
  if (result.error) {
    throw new SDKException(result.error);
  }
  return result.entries;
}

/**
 * Get all registered LoRA adapters (CANONICAL_API §3).
 * Mirrors Swift `lora.allRegistered()` (RunAnywhere+LoRA.swift:170-180).
 */
export async function allRegisteredLoraAdapters(): Promise<LoraAdapterCatalogEntry[]> {
  const result = await listLoraCatalog();
  if (result.error) {
    throw new SDKException(result.error);
  }
  return result.entries;
}

// ---------------------------------------------------------------------------
// SDK-owned artifact registration + download
// (Swift RunAnywhere+LoRADownload.swift:97-141)
//
// An adapter stays a LoRA catalog entry for apply/remove semantics, while its
// bytes are represented as a generated model artifact so download/storage
// policy (planning, resume, checksum, progress events, placement) runs on the
// canonical model-download path. `LoraAdapterCatalogEntry` was trimmed to 6
// adapter-specific fields (id/name/compatibleModels/defaultScale/tags/
// localPath) -- every generic artifact fact (description/url/filename/
// sizeBytes/author/checksumSha256/license) now lives on the ModelInfo record
// for this adapter instead, so callers must supply those fields directly
// when building the artifact (there is nothing left to read off the catalog
// entry itself).
// ---------------------------------------------------------------------------

const loraArtifactModelIDPrefix = 'lora-adapter:';
const loraArtifactTag = 'lora-adapter';

/** Stable model-registry id used for an adapter's download artifact. */
function loraArtifactModelID(entry: LoraAdapterCatalogEntry): string {
  return entry.id.startsWith(loraArtifactModelIDPrefix)
    ? entry.id
    : loraArtifactModelIDPrefix + entry.id;
}

/** Artifact-source fields no longer carried by `LoraAdapterCatalogEntry`. */
export interface LoraArtifactSource {
  url: string;
  filename?: string;
  sizeBytes?: number;
  checksumSha256?: string;
  description?: string;
  author?: string;
  license?: string;
}

/**
 * Convert a catalog entry + its artifact-source fields into model-registry
 * metadata used by the generic download path. Catalog filtering and
 * completion state remain owned by the LoRA catalog ABI. Mirrors Swift
 * `RALoraAdapterCatalogEntry.toLoraArtifactModelInfo()`, adjusted for the
 * fields the API-realignment moved off `LoraAdapterCatalogEntry` onto the
 * caller-supplied artifact source.
 */
function toLoraArtifactModelInfo(
  entry: LoraAdapterCatalogEntry,
  source: LoraArtifactSource,
): ModelInfo {
  const urlTail = source.url.split('/').pop() ?? source.url;
  const artifactFilename = source.filename || urlTail.split('?')[0] || urlTail;

  const descriptor = {
    role: ModelFileRole.MODEL_FILE_ROLE_COMPANION,
    url: source.url,
    filename: artifactFilename,
    relativePath: artifactFilename,
    isOptional: false,
    ...(source.sizeBytes && source.sizeBytes > 0 ? { sizeBytes: source.sizeBytes } : {}),
    ...(source.checksumSha256 ? { checksumSha256: source.checksumSha256 } : {}),
  };
  const expectedFiles = {
    files: [descriptor],
    requiredPatterns: [artifactFilename],
    description: 'LoRA adapter artifact',
  };

  const tags = [
    loraArtifactTag,
    ...entry.compatibleModels.map((m) => `base-model:${m}`),
    ...entry.tags,
  ].filter((tag, idx, all) => all.indexOf(tag) === idx);

  return ModelInfoMessage.fromPartial({
    id: loraArtifactModelID(entry),
    name: entry.name,
    category: ModelCategory.MODEL_CATEGORY_UNSPECIFIED,
    format: ModelFormat.MODEL_FORMAT_GGUF,
    framework: InferenceFramework.INFERENCE_FRAMEWORK_UNKNOWN,
    downloadUrl: source.url,
    source: ModelSource.MODEL_SOURCE_REMOTE,
    singleFile: {
      expectedFiles,
    },
    ...(source.sizeBytes && source.sizeBytes > 0 ? { downloadSizeBytes: source.sizeBytes } : {}),
    ...(source.checksumSha256 ? { checksumSha256: source.checksumSha256 } : {}),
    metadata: {
      description: source.description ?? '',
      ...(source.author !== undefined ? { author: source.author } : {}),
      ...(source.license !== undefined ? { license: source.license } : {}),
      tags,
    },
    isAvailable: true,
  });
}

/**
 * Register both the LoRA catalog entry and its downloadable artifact record.
 * Does not fetch bytes. Mirrors Swift `lora.registerArtifact(_:)`
 * (RunAnywhere+LoRADownload.swift:97-102).
 */
export async function registerLoraArtifact(
  entry: LoraAdapterCatalogEntry,
  source: LoraArtifactSource,
): Promise<ModelInfo> {
  const registered = await registerLoraAdapter(entry);
  const artifact = toLoraArtifactModelInfo(registered, source);
  if (!ModelRegistry.registerModel(artifact)) {
    throw SDKException.fromCode(
      -ProtoErrorCode.ERROR_CODE_PROCESSING_FAILED,
      `Model registry rejected LoRA artifact '${artifact.id}'`,
    );
  }
  return artifact;
}

/**
 * Download a LoRA adapter through the canonical model-download pipeline.
 *
 * One call does everything: registers the catalog entry + artifact,
 * downloads with resume/checksum/progress via commons, and returns the
 * stable local path of the adapter file. Completion is no longer recorded
 * back onto the LoRA catalog entry: `LoraAdapterDownloadCompletedRequest`
 * was deleted outright, and a non-empty model-registry `localPath` is the
 * only "downloaded" signal the wire still carries. Re-registering the
 * catalog entry with the resolved `localPath` keeps
 * `LoraAdapterCatalogEntry.localPath` (the catalog's own downloaded-ness
 * field) in sync.
 * Mirrors Swift `lora.download(_:onProgress:)`
 * (RunAnywhere+LoRADownload.swift:110-141).
 */
export async function downloadLoraAdapter(
  entry: LoraAdapterCatalogEntry,
  source: LoraArtifactSource,
  onProgress?: (progress: DownloadProgress) => void,
): Promise<string> {
  const artifact = await registerLoraArtifact(entry, source);
  // Dynamic import: SDKCore.ts statically imports this module, so the core
  // (which owns the canonical downloadModel plan/start/poll/OPFS
  // orchestration) is reached lazily to avoid a circular module-eval.
  const { SDKCore } = await import('../SDKCore.js');
  const finalProgress = await SDKCore.downloadModel({
    modelId: artifact.id,
    model: artifact,
    onProgress,
  });

  let localPath = finalProgress.localPath;
  if (!localPath) {
    // The download step persisted the path on the registry record.
    localPath = ModelRegistry.getModel(artifact.id)?.localPath ?? '';
  }
  if (!localPath) {
    throw SDKException.fromCode(
      -ProtoErrorCode.ERROR_CODE_DOWNLOAD_FAILED,
      `LoRA adapter '${entry.id}' downloaded but no local path was recorded`,
    );
  }

  // Sync the catalog entry's own localPath (its sole downloaded-ness
  // signal) by re-registering it. `registerLoraAdapter` preserves other
  // catalog-side state; the C++ registry snapshot merge keeps prior
  // completion state when the caller's entry omits it.
  await registerLoraAdapter({ ...entry, localPath });
  return localPath;
}

const LoraCatalog = {
  supportsNative: supportsNativeLoRACatalog,
  missingExports: missingLoRACatalogExports,
  register: registerLoraAdapter,
  list: listLoraCatalog,
  query: queryLoraCatalog,
  get: getLoraCatalogEntry,
};

export const LoRA = {
  supportsNative: supportsNativeLoRA,
  missingExports: missingLoRAExports,
  supportsNativeCatalog: supportsNativeLoRACatalog,
  missingCatalogExports: missingLoRACatalogExports,
  apply: applyLoraAdapters,
  applyCatalogAdapter: applyLoraCatalogAdapter,
  remove: removeLoraAdapters,
  list: listLoraAdapters,
  state: getLoraState,
  checkCompatibility: checkLoraCompatibility,
  register: registerLoraAdapter,
  listCatalog: listLoraCatalog,
  queryCatalog: queryLoraCatalog,
  getCatalogEntry: getLoraCatalogEntry,
  adaptersForModel: loraAdaptersForModel,
  allRegistered: allRegisteredLoraAdapters,
  registerArtifact: registerLoraArtifact,
  download: downloadLoraAdapter,
  catalog: LoraCatalog,
};
