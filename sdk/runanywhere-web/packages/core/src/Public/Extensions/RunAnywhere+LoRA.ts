/**
 * RunAnywhere+LoRA.ts
 *
 * Top-level Web LoRA API backed by the generated proto-byte C ABI.
 */

import { LoRAProtoAdapter } from '../../Adapters/ModalityProtoAdapter';
import { ProtoErrorCode, SDKException } from '../../Foundation/SDKException';
import type {
  LoRAAdapterConfig,
  LoRAApplyRequest,
  LoRAApplyResult,
  LoRARemoveRequest,
  LoRAState,
  LoraAdapterCatalogEntry,
  LoraAdapterCatalogGetRequest,
  LoraAdapterCatalogGetResult,
  LoraAdapterCatalogListRequest,
  LoraAdapterCatalogListResult,
  LoraAdapterCatalogQuery,
  LoraAdapterDownloadCompletedRequest,
  LoraAdapterDownloadCompletedResult,
  LoraCompatibilityResult,
} from '@runanywhere/proto-ts/lora_options';
import {
  LoraAdapterDownloadCompletedRequest as LoraAdapterDownloadCompletedRequestMessage,
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
import { ModelRegistry } from './RunAnywhere+ModelRegistry';

export type {
  LoRAAdapterConfig,
  LoRAAdapterInfo,
  LoRAApplyRequest,
  LoRAApplyResult,
  LoRARemoveRequest,
  LoRAState,
  LoraAdapterCatalogEntry,
  LoraAdapterCatalogGetRequest,
  LoraAdapterCatalogGetResult,
  LoraAdapterCatalogListRequest,
  LoraAdapterCatalogListResult,
  LoraAdapterCatalogQuery,
  LoraAdapterDownloadCompletedRequest,
  LoraAdapterDownloadCompletedResult,
  LoraCompatibilityResult,
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

function emptyLoRAState(): LoRAState {
  return {
    loadedAdapters: [],
    hasActiveAdapters: false,
    errorCode: 0,
  };
}

function emptyCatalogListRequest(): LoraAdapterCatalogListRequest {
  return {
    includeCounts: true,
  };
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
  request: LoRAApplyRequest,
): Promise<LoRAApplyResult> {
  return requireResult(
    'LoRA.apply',
    requireAdapter('LoRA.apply').apply(request),
  );
}

export async function removeLoraAdapters(
  request: LoRARemoveRequest,
): Promise<LoRAState> {
  return requireResult(
    'LoRA.remove',
    requireAdapter('LoRA.remove').remove(request),
  );
}

export async function listLoraAdapters(
  request: LoRAState = emptyLoRAState(),
): Promise<LoRAState> {
  return requireResult(
    'LoRA.list',
    requireAdapter('LoRA.list').list(request),
  );
}

export async function getLoraState(
  request: LoRAState = emptyLoRAState(),
): Promise<LoRAState> {
  return requireResult(
    'LoRA.state',
    requireAdapter('LoRA.state').state(request),
  );
}

export async function checkLoraCompatibility(
  config: LoRAAdapterConfig,
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
      errorMessage: error instanceof Error ? error.message : String(error),
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

export async function markLoraAdapterDownloadCompleted(
  request: LoraAdapterDownloadCompletedRequest,
): Promise<LoraAdapterDownloadCompletedResult> {
  return requireResult(
    'LoRA.catalog.markDownloadCompleted',
    requireAdapter('LoRA.catalog.markDownloadCompleted').markDownloadCompleted(request),
  );
}

// ---------------------------------------------------------------------------
// Import completion + catalog conveniences (Swift RunAnywhere+LoRA.swift:138-181)
// ---------------------------------------------------------------------------

/**
 * Persist native-reported LoRA adapter import completion in commons.
 *
 * Uses the generated download-completed message with `imported` asserted,
 * matching the IDL contract for platform file-picker/import completion.
 * Mirrors Swift `lora.markImportCompleted(_:)`.
 */
export async function markLoraAdapterImportCompleted(
  request: LoraAdapterDownloadCompletedRequest,
): Promise<LoraAdapterDownloadCompletedResult> {
  const importRequest = LoraAdapterDownloadCompletedRequestMessage.fromPartial({
    ...request,
    imported: true,
    statusMessage: request.statusMessage || 'import completed',
  });
  return markLoraAdapterDownloadCompleted(importRequest);
}

/**
 * Get all LoRA adapters compatible with a specific model (CANONICAL_API §3).
 * Mirrors Swift `lora.adaptersForModel(_:)` (RunAnywhere+LoRA.swift:153-165).
 */
export async function loraAdaptersForModel(
  modelId: string,
): Promise<LoraAdapterCatalogEntry[]> {
  const result = await queryLoraCatalog({ modelId, tags: [] });
  if (!result.success) {
    // Swift parity: .processingFailed.
    throw SDKException.fromCode(
      -ProtoErrorCode.ERROR_CODE_PROCESSING_FAILED,
      result.errorMessage || 'LoRA catalog query failed',
    );
  }
  return result.entries;
}

/**
 * Get all registered LoRA adapters (CANONICAL_API §3).
 * Mirrors Swift `lora.allRegistered()` (RunAnywhere+LoRA.swift:170-180).
 */
export async function allRegisteredLoraAdapters(): Promise<LoraAdapterCatalogEntry[]> {
  const result = await listLoraCatalog();
  if (!result.success) {
    // Swift parity: .processingFailed.
    throw SDKException.fromCode(
      -ProtoErrorCode.ERROR_CODE_PROCESSING_FAILED,
      result.errorMessage || 'LoRA catalog list failed',
    );
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
// canonical model-download path.
// ---------------------------------------------------------------------------

const loraArtifactModelIDPrefix = 'lora-adapter:';
const loraArtifactTag = 'lora-adapter';

/** Stable model-registry id used for an adapter's download artifact. */
function loraArtifactModelID(entry: LoraAdapterCatalogEntry): string {
  return entry.id.startsWith(loraArtifactModelIDPrefix)
    ? entry.id
    : loraArtifactModelIDPrefix + entry.id;
}

/**
 * Convert a catalog entry into model-registry metadata used by the generic
 * download path. Catalog filtering and completion state remain owned by the
 * LoRA catalog ABI. Mirrors Swift
 * `RALoraAdapterCatalogEntry.toLoraArtifactModelInfo()`.
 */
function toLoraArtifactModelInfo(entry: LoraAdapterCatalogEntry): ModelInfo {
  const urlTail = entry.url.split('/').pop() ?? entry.url;
  const artifactFilename = entry.filename || urlTail.split('?')[0] || urlTail;

  const descriptor = {
    role: ModelFileRole.MODEL_FILE_ROLE_COMPANION,
    url: entry.url,
    filename: artifactFilename,
    relativePath: artifactFilename,
    isRequired: true,
    ...(entry.sizeBytes > 0 ? { sizeBytes: entry.sizeBytes } : {}),
    ...(entry.checksumSha256 ? { checksumSha256: entry.checksumSha256 } : {}),
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
    downloadUrl: entry.url,
    source: ModelSource.MODEL_SOURCE_REMOTE,
    description: entry.description,
    singleFile: {
      requiredPatterns: [artifactFilename],
      expectedFiles,
    },
    expectedFiles,
    ...(entry.sizeBytes > 0 ? { downloadSizeBytes: entry.sizeBytes } : {}),
    ...(entry.checksumSha256 ? { checksumSha256: entry.checksumSha256 } : {}),
    metadata: {
      description: entry.description,
      ...(entry.author !== undefined ? { author: entry.author } : {}),
      ...(entry.license !== undefined ? { license: entry.license } : {}),
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
): Promise<ModelInfo> {
  const registered = await registerLoraAdapter(entry);
  const artifact = toLoraArtifactModelInfo(registered);
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
 * One call does everything: registers the catalog entry + artifact, downloads
 * with resume/checksum/progress via commons, records completion in the LoRA
 * catalog, and returns the stable local path of the adapter file.
 * Mirrors Swift `lora.download(_:onProgress:)`
 * (RunAnywhere+LoRADownload.swift:110-141).
 */
export async function downloadLoraAdapter(
  entry: LoraAdapterCatalogEntry,
  onProgress?: (progress: DownloadProgress) => void,
): Promise<string> {
  const artifact = await registerLoraArtifact(entry);
  // Dynamic import: RunAnywhere.ts statically imports this module, so the
  // facade (which owns the canonical downloadModel plan/start/poll/OPFS
  // orchestration) is reached lazily to avoid a circular module-eval.
  const { RunAnywhere } = await import('../RunAnywhere');
  const finalProgress = await RunAnywhere.downloadModel({
    modelId: artifact.id,
    model: artifact,
    onProgress,
  });

  let localPath = finalProgress.localPath;
  if (!localPath) {
    // The import step persisted the path on the registry record.
    localPath = ModelRegistry.getModel(artifact.id)?.localPath ?? '';
  }
  if (!localPath) {
    throw SDKException.fromCode(
      -ProtoErrorCode.ERROR_CODE_DOWNLOAD_FAILED,
      `LoRA adapter '${entry.id}' downloaded but no local path was recorded`,
    );
  }

  await markLoraAdapterDownloadCompleted(
    LoraAdapterDownloadCompletedRequestMessage.fromPartial({
      adapterId: entry.id,
      localPath,
    }),
  );
  return localPath;
}

const LoraCatalog = {
  supportsNative: supportsNativeLoRACatalog,
  missingExports: missingLoRACatalogExports,
  register: registerLoraAdapter,
  list: listLoraCatalog,
  query: queryLoraCatalog,
  get: getLoraCatalogEntry,
  markDownloadCompleted: markLoraAdapterDownloadCompleted,
};

export const LoRA = {
  supportsNative: supportsNativeLoRA,
  missingExports: missingLoRAExports,
  supportsNativeCatalog: supportsNativeLoRACatalog,
  missingCatalogExports: missingLoRACatalogExports,
  apply: applyLoraAdapters,
  remove: removeLoraAdapters,
  list: listLoraAdapters,
  state: getLoraState,
  checkCompatibility: checkLoraCompatibility,
  register: registerLoraAdapter,
  listCatalog: listLoraCatalog,
  queryCatalog: queryLoraCatalog,
  getCatalogEntry: getLoraCatalogEntry,
  markDownloadCompleted: markLoraAdapterDownloadCompleted,
  markImportCompleted: markLoraAdapterImportCompleted,
  adaptersForModel: loraAdaptersForModel,
  allRegistered: allRegisteredLoraAdapters,
  registerArtifact: registerLoraArtifact,
  download: downloadLoraAdapter,
  catalog: LoraCatalog,
};
