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
import {
  arrayBufferToBytes,
  bytesToArrayBuffer,
} from '../../../services/ProtoBytes';

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
  return bytesToArrayBuffer(
    LoRAAdapterConfigMessage.encode(
      LoRAAdapterConfigMessage.create(config)
    ).finish()
  );
}

function encodeApplyRequest(request: LoRAApplyRequest): ArrayBuffer {
  return bytesToArrayBuffer(
    LoRAApplyRequestMessage.encode(
      LoRAApplyRequestMessage.create(request)
    ).finish()
  );
}

function encodeRemoveRequest(request: LoRARemoveRequest): ArrayBuffer {
  return bytesToArrayBuffer(
    LoRARemoveRequestMessage.encode(
      LoRARemoveRequestMessage.create(request)
    ).finish()
  );
}

function encodeStateRequest(request?: LoRAState): ArrayBuffer {
  return bytesToArrayBuffer(
    LoRAStateMessage.encode(LoRAStateMessage.create(request ?? {})).finish()
  );
}

function encodeCatalogEntry(entry: LoraAdapterCatalogEntry): ArrayBuffer {
  return bytesToArrayBuffer(
    LoraAdapterCatalogEntryMessage.encode(
      LoraAdapterCatalogEntryMessage.create(entry)
    ).finish()
  );
}

function encodeCatalogListRequest(
  request?: LoraAdapterCatalogListRequest
): ArrayBuffer {
  return bytesToArrayBuffer(
    LoraAdapterCatalogListRequestMessage.encode(
      LoraAdapterCatalogListRequestMessage.create(request ?? {})
    ).finish()
  );
}

function encodeCatalogQuery(query: LoraAdapterCatalogQuery): ArrayBuffer {
  return bytesToArrayBuffer(
    LoraAdapterCatalogQueryMessage.encode(
      LoraAdapterCatalogQueryMessage.create(query)
    ).finish()
  );
}

function encodeCatalogGetRequest(
  request: LoraAdapterCatalogGetRequest
): ArrayBuffer {
  return bytesToArrayBuffer(
    LoraAdapterCatalogGetRequestMessage.encode(
      LoraAdapterCatalogGetRequestMessage.create(request)
    ).finish()
  );
}

function encodeDownloadCompletedRequest(
  request: LoraAdapterDownloadCompletedRequest
): ArrayBuffer {
  return bytesToArrayBuffer(
    LoraAdapterDownloadCompletedRequestMessage.encode(
      LoraAdapterDownloadCompletedRequestMessage.create(request)
    ).finish()
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
};
