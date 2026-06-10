/**
 * RunAnywhere+LoRA.ts
 *
 * Public API for LoRA adapter management. The namespace mirrors the generated
 * LoRA service contract from `lora_options.proto`:
 *
 *   await RunAnywhere.lora.apply(request)
 *   await RunAnywhere.lora.remove(request)
 *   const current = await RunAnywhere.lora.list()
 *   const state = await RunAnywhere.lora.state()
 *   const compat = await RunAnywhere.lora.checkCompatibility(config)
 *   const entry = await RunAnywhere.lora.register(entry)
 *   const catalog = await RunAnywhere.lora.listCatalog(request)
 */

import { requireNativeModule, isNativeModuleAvailable } from '../../../native';
import { SDKLogger } from '../../../Foundation/Logging/Logger/SDKLogger';
import { SDKException } from '../../../Foundation/Errors/SDKException';
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
  LoRAAdapterConfig as LoRAAdapterConfigMessage,
  LoRAApplyRequest as LoRAApplyRequestMessage,
  LoRAApplyResult as LoRAApplyResultMessage,
  LoRARemoveRequest as LoRARemoveRequestMessage,
  LoRAState as LoRAStateMessage,
  LoraAdapterCatalogEntry as LoraAdapterCatalogEntryMessage,
  LoraAdapterCatalogGetRequest as LoraAdapterCatalogGetRequestMessage,
  LoraAdapterCatalogGetResult as LoraAdapterCatalogGetResultMessage,
  LoraAdapterCatalogListRequest as LoraAdapterCatalogListRequestMessage,
  LoraAdapterCatalogListResult as LoraAdapterCatalogListResultMessage,
  LoraAdapterCatalogQuery as LoraAdapterCatalogQueryMessage,
  LoraAdapterDownloadCompletedRequest as LoraAdapterDownloadCompletedRequestMessage,
  LoraAdapterDownloadCompletedResult as LoraAdapterDownloadCompletedResultMessage,
  LoraCompatibilityResult as LoraCompatibilityResultMessage,
} from '@runanywhere/proto-ts/lora_options';
import { ErrorCategory, ErrorCode } from '@runanywhere/proto-ts/errors';
import { arrayBufferToBytes } from '../../../services/ProtoBytes';
import { encodeProtoMessage } from '../../../services/ProtoWire';
import {
  ModelCategory,
  ModelFileRole,
  ModelFormat,
  ModelInfo as ModelInfoCodec,
  ModelGetRequest,
  ModelSource,
  InferenceFramework,
  type ModelInfo,
} from '@runanywhere/proto-ts/model_types';
import type { DownloadProgress } from '@runanywhere/proto-ts/download_service';
import {
  downloadModel as downloadRegisteredModel,
  getModel,
} from '../Models/RunAnywhere+ModelRegistry';

const logger = new SDKLogger('RunAnywhere.LoRA');

function ensureNative() {
  if (!isNativeModuleAvailable()) {
    throw SDKException.nativeModuleUnavailable();
  }
  return requireNativeModule();
}

function decodeRequired<T>(
  buffer: ArrayBuffer,
  decode: (bytes: Uint8Array) => T,
  operation: string
): T {
  const bytes = arrayBufferToBytes(buffer);
  if (bytes.byteLength === 0) {
    throw SDKException.protoDecodeFailed(operation);
  }
  return decode(bytes);
}

function encodeConfig(config: LoRAAdapterConfig): ArrayBuffer {
  return encodeProtoMessage(
    LoRAAdapterConfigMessage.create(config),
    LoRAAdapterConfigMessage
  );
}

function encodeApplyRequest(request: LoRAApplyRequest): ArrayBuffer {
  return encodeProtoMessage(
    LoRAApplyRequestMessage.create(request),
    LoRAApplyRequestMessage
  );
}

function encodeRemoveRequest(request: LoRARemoveRequest): ArrayBuffer {
  return encodeProtoMessage(
    LoRARemoveRequestMessage.create(request),
    LoRARemoveRequestMessage
  );
}

function encodeStateRequest(request?: LoRAState): ArrayBuffer {
  return encodeProtoMessage(
    LoRAStateMessage.create(request ?? {}),
    LoRAStateMessage
  );
}

function encodeCatalogEntry(entry: LoraAdapterCatalogEntry): ArrayBuffer {
  return encodeProtoMessage(
    LoraAdapterCatalogEntryMessage.create(entry),
    LoraAdapterCatalogEntryMessage
  );
}

function encodeCatalogListRequest(
  request?: LoraAdapterCatalogListRequest
): ArrayBuffer {
  return encodeProtoMessage(
    LoraAdapterCatalogListRequestMessage.create(request ?? {}),
    LoraAdapterCatalogListRequestMessage
  );
}

function encodeCatalogQuery(query: LoraAdapterCatalogQuery): ArrayBuffer {
  return encodeProtoMessage(
    LoraAdapterCatalogQueryMessage.create(query),
    LoraAdapterCatalogQueryMessage
  );
}

function encodeCatalogGetRequest(
  request: LoraAdapterCatalogGetRequest
): ArrayBuffer {
  return encodeProtoMessage(
    LoraAdapterCatalogGetRequestMessage.create(request),
    LoraAdapterCatalogGetRequestMessage
  );
}

function encodeDownloadCompletedRequest(
  request: LoraAdapterDownloadCompletedRequest
): ArrayBuffer {
  return encodeProtoMessage(
    LoraAdapterDownloadCompletedRequestMessage.create(request),
    LoraAdapterDownloadCompletedRequestMessage
  );
}

// ============================================================================
// Runtime Operations
// ============================================================================

/**
 * Apply one or more LoRA adapters to the current logical LLM session.
 */
async function apply(request: LoRAApplyRequest): Promise<LoRAApplyResult> {
  const native = ensureNative();
  const result = decodeRequired(
    await native.loraApplyProto(encodeApplyRequest(request)),
    LoRAApplyResultMessage.decode,
    'loraApplyProto'
  );
  logger.info(`LoRA apply completed: ${result.adapters.length} adapter(s)`);
  return result;
}

/**
 * Remove named/path adapters, or clear all adapters when `clearAll` is true.
 */
async function remove(request: LoRARemoveRequest): Promise<LoRAState> {
  const native = ensureNative();
  const result = decodeRequired(
    await native.loraRemoveProto(encodeRemoveRequest(request)),
    LoRAStateMessage.decode,
    'loraRemoveProto'
  );
  logger.info(
    `LoRA remove completed: ${result.loadedAdapters.length} adapter(s) active`
  );
  return result;
}

/**
 * Return the current loaded-adapter snapshot.
 */
async function list(request?: LoRAState): Promise<LoRAState> {
  const native = ensureNative();
  return decodeRequired(
    await native.loraListProto(encodeStateRequest(request)),
    LoRAStateMessage.decode,
    'loraListProto'
  );
}

/**
 * Return the logical LoRA service state.
 */
async function state(request?: LoRAState): Promise<LoRAState> {
  const native = ensureNative();
  return decodeRequired(
    await native.loraStateProto(encodeStateRequest(request)),
    LoRAStateMessage.decode,
    'loraStateProto'
  );
}

/**
 * Check LoRA adapter compatibility with a model.
 *
 * The request is the generated `LoRAAdapterConfig`; model/session selection
 * remains a native/provider concern behind the bridge.
 */
async function checkCompatibility(
  config: LoRAAdapterConfig
): Promise<LoraCompatibilityResult> {
  const native = ensureNative();
  return decodeRequired(
    await native.loraCompatibilityProto(encodeConfig(config)),
    LoraCompatibilityResultMessage.decode,
    'loraCompatibilityProto'
  );
}

// ============================================================================
// Catalog Operations
// ============================================================================

async function register(
  entry: LoraAdapterCatalogEntry
): Promise<LoraAdapterCatalogEntry> {
  const native = ensureNative();
  const result = decodeRequired(
    await native.loraRegisterCatalogEntryProto(encodeCatalogEntry(entry)),
    LoraAdapterCatalogEntryMessage.decode,
    'loraRegisterCatalogEntryProto'
  );
  logger.info(`LoRA catalog registered: ${result.id}`);
  return result;
}

async function listCatalog(
  request?: LoraAdapterCatalogListRequest
): Promise<LoraAdapterCatalogListResult> {
  const native = ensureNative();
  return decodeRequired(
    await native.loraCatalogListProto(encodeCatalogListRequest(request)),
    LoraAdapterCatalogListResultMessage.decode,
    'loraCatalogListProto'
  );
}

async function queryCatalog(
  query: LoraAdapterCatalogQuery
): Promise<LoraAdapterCatalogListResult> {
  const native = ensureNative();
  return decodeRequired(
    await native.loraCatalogQueryProto(encodeCatalogQuery(query)),
    LoraAdapterCatalogListResultMessage.decode,
    'loraCatalogQueryProto'
  );
}

async function getCatalogEntry(
  request: LoraAdapterCatalogGetRequest
): Promise<LoraAdapterCatalogGetResult> {
  const native = ensureNative();
  return decodeRequired(
    await native.loraCatalogGetProto(encodeCatalogGetRequest(request)),
    LoraAdapterCatalogGetResultMessage.decode,
    'loraCatalogGetProto'
  );
}

async function markDownloadCompleted(
  request: LoraAdapterDownloadCompletedRequest
): Promise<LoraAdapterDownloadCompletedResult> {
  const native = ensureNative();
  return decodeRequired(
    await native.loraCatalogMarkDownloadCompletedProto(
      encodeDownloadCompletedRequest(request)
    ),
    LoraAdapterDownloadCompletedResultMessage.decode,
    'loraCatalogMarkDownloadCompletedProto'
  );
}

// ============================================================================
// Attach (high-level adapter staging)
// ============================================================================

/**
 * Input shape for `RunAnywhere.lora.attachAdapter({...})`. The
 * convenience API resolves an adapter file by id, returning the
 * sandboxed local path where the artifact is staged so consumers do
 * not need to know about platform-specific sandboxed file system
 * roots (RNFS.DocumentDirectoryPath, etc.).
 */
export interface LoRAAttachAdapterRequest {
  /** Stable adapter identifier (catalog-id / fixture-id). */
  adapterId: string;
  /** Model id this adapter binds to. */
  modelId: string;
  /** Optional download URL — used for catalog registration only. */
  url?: string;
  /** Filename on disk under the SDK's sandboxed lora/ directory. */
  filename: string;
  /** Adapter scale (defaults to 1.0). */
  scale?: number;
  /** Optional target modules (e.g. ["q_proj", "v_proj"]). */
  targetModules?: string[];
  /** Optional adapter metadata. */
  metadata?: Record<string, string>;
}

/**
 * Result of `RunAnywhere.lora.attachAdapter({...})`. Carries the
 * fully-resolved `LoRAAdapterConfig` ready for `lora.apply(...)` and
 * the absolute sandboxed `adapterPath` the SDK staged for the
 * caller.
 */
export interface LoRAAttachAdapterResult {
  config: LoRAAdapterConfig;
  adapterPath: string;
}

const SANDBOX_LORA_DIR = 'lora';

function resolveAdapterPath(filename: string): string {
  const RNFS = require('react-native-fs');
  return `${RNFS.DocumentDirectoryPath}/${SANDBOX_LORA_DIR}/${filename}`;
}

/**
 * Compose a `LoRAAdapterConfig` for a sandboxed adapter file without
 * the example app having to know about platform sandbox layout. The
 * file must already be present at the returned `adapterPath` (the
 * harness operator stages it per
 * `cross-platform-e2e-test-catalog.md §9b`).
 *
 * The returned `config` is ready to feed directly into
 * `RunAnywhere.lora.apply(...)`.
 */
async function attachAdapter(
  request: LoRAAttachAdapterRequest
): Promise<LoRAAttachAdapterResult> {
  const adapterPath = resolveAdapterPath(request.filename);
  const config: LoRAAdapterConfig = LoRAAdapterConfigMessage.create({
    adapterPath,
    adapterId: request.adapterId,
    scale: request.scale ?? 1.0,
    targetModules: request.targetModules ?? [],
    metadata: request.metadata ?? {},
  });
  logger.info(
    `LoRA attach resolved sandboxed adapter '${request.adapterId}' for model '${request.modelId}' -> ${adapterPath}`
  );
  return { config, adapterPath };
}

// ============================================================================
// Canonical namespace export
// ============================================================================

/**
 * `RunAnywhere.lora` namespace backed by the generated LoRA service messages.
 */
// ============================================================================
// Import completion + catalog conveniences (Swift RunAnywhere+LoRA.swift:138-181)
// ============================================================================

/**
 * Persist native-reported LoRA adapter import completion in commons.
 *
 * Uses the generated download-completed message with `imported` asserted,
 * matching the IDL contract for platform file-picker/import completion.
 * Mirrors Swift `lora.markImportCompleted(_:)`.
 */
async function markImportCompleted(
  request: LoraAdapterDownloadCompletedRequest
): Promise<LoraAdapterDownloadCompletedResult> {
  const importRequest = LoraAdapterDownloadCompletedRequestMessage.fromPartial({
    ...request,
    imported: true,
    statusMessage: request.statusMessage || 'import completed',
  });
  return markDownloadCompleted(importRequest);
}

/**
 * Get all LoRA adapters compatible with a specific model (CANONICAL_API §3).
 * Mirrors Swift `lora.adaptersForModel(_:)`.
 */
async function adaptersForModel(
  modelId: string
): Promise<LoraAdapterCatalogEntry[]> {
  const result = await queryCatalog(
    LoraAdapterCatalogQueryMessage.fromPartial({ modelId })
  );
  if (!result.success) {
    throw SDKException.generationFailedWith(
      result.errorMessage || 'LoRA catalog query failed'
    );
  }
  return result.entries;
}

/**
 * Get all registered LoRA adapters (CANONICAL_API §3).
 * Mirrors Swift `lora.allRegistered()`.
 */
async function allRegistered(): Promise<LoraAdapterCatalogEntry[]> {
  const result = await listCatalog();
  if (!result.success) {
    throw SDKException.generationFailedWith(
      result.errorMessage || 'LoRA catalog list failed'
    );
  }
  return result.entries;
}

// ============================================================================
// SDK-owned artifact registration + download
// (Swift RunAnywhere+LoRADownload.swift:97-160)
// ============================================================================

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
 * LoRA catalog ABI. Mirrors Swift `RALoraAdapterCatalogEntry.toLoraArtifactModelInfo()`.
 */
function toLoraArtifactModelInfo(entry: LoraAdapterCatalogEntry): ModelInfo {
  const urlTail = entry.url.split('/').pop() ?? entry.url;
  const artifactFilename =
    entry.filename || urlTail.split('?')[0] || urlTail;

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

  return ModelInfoCodec.fromPartial({
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
 * Does not fetch bytes. Mirrors Swift `lora.registerArtifact(_:)`.
 */
async function registerArtifact(
  entry: LoraAdapterCatalogEntry
): Promise<ModelInfo> {
  const native = ensureNative();
  const registered = await register(entry);
  const artifact = toLoraArtifactModelInfo(registered);
  const accepted = await native.registerModelProto(
    encodeProtoMessage(artifact, ModelInfoCodec)
  );
  if (!accepted) {
    throw SDKException.generationFailedWith(
      `Model registry rejected LoRA artifact '${artifact.id}'`
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
 * Mirrors Swift `lora.download(_:onProgress:)`.
 */
async function download(
  entry: LoraAdapterCatalogEntry,
  onProgress?: (progress: DownloadProgress) => void
): Promise<string> {
  const artifact = await registerArtifact(entry);
  const finalProgress = await downloadRegisteredModel(artifact, onProgress);

  let localPath = finalProgress.localPath;
  if (!localPath) {
    // The import step persisted the path on the registry record.
    const lookup = await getModel(
      ModelGetRequest.fromPartial({ modelId: artifact.id })
    );
    if (lookup.found) {
      localPath = lookup.model?.localPath ?? '';
    }
  }
  if (!localPath) {
    throw SDKException.of(
      ErrorCode.ERROR_CODE_DOWNLOAD_FAILED,
      `LoRA adapter '${entry.id}' downloaded but no local path was recorded`,
      { category: ErrorCategory.ERROR_CATEGORY_NETWORK }
    );
  }

  await markDownloadCompleted(
    LoraAdapterDownloadCompletedRequestMessage.fromPartial({
      adapterId: entry.id,
      localPath,
    })
  );
  return localPath;
}

export const lora = {
  apply,
  remove,
  list,
  state,
  checkCompatibility,
  register,
  listCatalog,
  queryCatalog,
  getCatalogEntry,
  markDownloadCompleted,
  markImportCompleted,
  adaptersForModel,
  allRegistered,
  registerArtifact,
  download,
  attachAdapter,
};
