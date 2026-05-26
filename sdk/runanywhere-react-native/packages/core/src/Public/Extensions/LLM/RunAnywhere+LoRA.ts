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
import { arrayBufferToBytes } from '../../../services/ProtoBytes';
import { encodeProtoMessage } from '../../../services/ProtoWire';

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
  // eslint-disable-next-line @typescript-eslint/no-require-imports
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
  attachAdapter,
};
