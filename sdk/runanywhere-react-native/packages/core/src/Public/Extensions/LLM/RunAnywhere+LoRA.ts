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
  LoraAdapterConfig,
  LoraApplyRequest,
  LoraApplyResult,
  LoraRemoveRequest,
  LoraState,
  LoraAdapterCatalogEntry,
  LoraAdapterCatalogGetRequest,
  LoraAdapterCatalogGetResult,
  LoraAdapterCatalogListRequest,
  LoraAdapterCatalogListResult,
  LoraAdapterCatalogQuery,
  LoraCompatibilityResult,
} from '@runanywhere/proto-ts/lora_options';
import {
  LoraAdapterConfig as LoraAdapterConfigMessage,
  LoraApplyRequest as LoraApplyRequestMessage,
  LoraApplyResult as LoraApplyResultMessage,
  LoraRemoveRequest as LoraRemoveRequestMessage,
  LoraState as LoraStateMessage,
  LoraAdapterCatalogEntry as LoraAdapterCatalogEntryMessage,
  LoraAdapterCatalogGetRequest as LoraAdapterCatalogGetRequestMessage,
  LoraAdapterCatalogGetResult as LoraAdapterCatalogGetResultMessage,
  LoraAdapterCatalogListRequest as LoraAdapterCatalogListRequestMessage,
  LoraAdapterCatalogListResult as LoraAdapterCatalogListResultMessage,
  LoraAdapterCatalogQuery as LoraAdapterCatalogQueryMessage,
  LoraCompatibilityResult as LoraCompatibilityResultMessage,
} from '@runanywhere/proto-ts/lora_options';
import { ErrorCategory, ErrorCode } from '@runanywhere/proto-ts/errors';
import { arrayBufferToBytes } from '../../../services/ProtoBytes';
import { requireInitialized } from '../../../Foundation/Initialization/InitializedGuard';
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

function encodeConfig(config: LoraAdapterConfig): ArrayBuffer {
  return encodeProtoMessage(
    LoraAdapterConfigMessage.create(config),
    LoraAdapterConfigMessage
  );
}

function encodeApplyRequest(request: LoraApplyRequest): ArrayBuffer {
  return encodeProtoMessage(
    LoraApplyRequestMessage.create(request),
    LoraApplyRequestMessage
  );
}

function encodeRemoveRequest(request: LoraRemoveRequest): ArrayBuffer {
  return encodeProtoMessage(
    LoraRemoveRequestMessage.create(request),
    LoraRemoveRequestMessage
  );
}

function encodeStateRequest(request?: LoraState): ArrayBuffer {
  return encodeProtoMessage(
    LoraStateMessage.create(request ?? {}),
    LoraStateMessage
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

// ============================================================================
// Runtime Operations
// ============================================================================

/**
 * Apply one or more LoRA adapters to the current logical LLM session.
 *
 * Two forms mirror Swift's overloaded `apply`: a full `LoraApplyRequest`, or a
 * registered catalog entry (delegating to {@link applyCatalogAdapter}).
 *
 * `keepExisting` is the wire polarity (zero value = full SET/replace
 * semantics, matching Diffusers `set_adapters` / llama.cpp
 * `llama_set_adapters_lora`); the caller-facing `replaceExisting` knob on
 * {@link applyCatalogAdapter} is the pre-existing, opposite-polarity public
 * name and is inverted at that call site, not here.
 */
function apply(request: LoraApplyRequest): Promise<LoraApplyResult>;
function apply(
  entry: LoraAdapterCatalogEntry,
  options?: { localPath?: string; scale?: number; replaceExisting?: boolean }
): Promise<LoraApplyResult>;
async function apply(
  requestOrEntry: LoraApplyRequest | LoraAdapterCatalogEntry,
  options?: { localPath?: string; scale?: number; replaceExisting?: boolean }
): Promise<LoraApplyResult> {
  // A LoraApplyRequest always carries an `adapters` array; a catalog entry does
  // not — use that to route the entry form to applyCatalogAdapter.
  if (!Array.isArray((requestOrEntry as LoraApplyRequest).adapters)) {
    return applyCatalogAdapter(requestOrEntry as LoraAdapterCatalogEntry, options);
  }
  const request = requestOrEntry as LoraApplyRequest;
  const native = ensureNative();
  const result = decodeRequired(
    await native.loraApplyProto(encodeApplyRequest(request)),
    LoraApplyResultMessage.decode,
    'loraApplyProto'
  );
  logger.info(`LoRA apply completed: ${result.adapters.length} adapter(s)`);
  return result;
}

/**
 * Apply one registered catalog adapter to the current logical LLM session.
 *
 * Preserves the catalog entry id in the generated config so commons can
 * validate registered catalog adapters against the loaded base model.
 *
 * `replaceExisting` keeps its public name and its `false` (= stack on top of
 * the currently-applied set) default for iOS/cross-SDK parity. The wire field
 * is `keepExisting`, whose polarity is inverted relative to the old
 * `replace_existing`: zero value now means full replace. So
 * `replaceExisting=false` (stack, the default) maps to `keepExisting=true`,
 * and `replaceExisting=true` (fresh set) maps to `keepExisting=false`.
 */
async function applyCatalogAdapter(
  entry: LoraAdapterCatalogEntry,
  options?: {
    localPath?: string;
    scale?: number;
    replaceExisting?: boolean;
  }
): Promise<LoraApplyResult> {
  const adapterPath = options?.localPath || entry.localPath || '';
  if (!adapterPath) {
    throw SDKException.of(
      ErrorCode.ERROR_CODE_INVALID_ARGUMENT,
      `LoRA catalog adapter '${entry.id}' has no local path`,
      { category: ErrorCategory.ERROR_CATEGORY_INTERNAL }
    );
  }

  // `defaultScale` is optional now ("Unset means 1.0").
  const scale =
    options?.scale ??
    (entry.defaultScale !== undefined && entry.defaultScale > 0
      ? entry.defaultScale
      : 1.0);
  return apply(
    LoraApplyRequestMessage.fromPartial({
      adapters: [
        LoraAdapterConfigMessage.fromPartial({
          adapterPath,
          adapterId: entry.id || undefined,
          scale,
        }),
      ],
      keepExisting: !(options?.replaceExisting ?? false),
    })
  );
}

/**
 * Remove named/path adapters, or clear all adapters when `clearAll` is true.
 */
async function remove(request: LoraRemoveRequest): Promise<LoraState> {
  const native = ensureNative();
  const result = decodeRequired(
    await native.loraRemoveProto(encodeRemoveRequest(request)),
    LoraStateMessage.decode,
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
async function list(request?: LoraState): Promise<LoraState> {
  const native = ensureNative();
  return decodeRequired(
    await native.loraListProto(encodeStateRequest(request)),
    LoraStateMessage.decode,
    'loraListProto'
  );
}

/**
 * Return the logical LoRA service state.
 */
async function state(request?: LoraState): Promise<LoraState> {
  const native = ensureNative();
  return decodeRequired(
    await native.loraStateProto(encodeStateRequest(request)),
    LoraStateMessage.decode,
    'loraStateProto'
  );
}

/**
 * Check LoRA adapter compatibility with a model.
 *
 * The request is the generated `LoraAdapterConfig`; model/session selection
 * remains a native/provider concern behind the bridge.
 */
async function checkCompatibility(
  config: LoraAdapterConfig
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
  // Swift parity: guard isInitialized (RunAnywhere+LoRA.swift:77-79).
  requireInitialized();
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
  // Swift parity: guard isInitialized (RunAnywhere+LoRA.swift:88-90).
  requireInitialized();
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
  // Swift parity: guard isInitialized (RunAnywhere+LoRA.swift:99-101).
  requireInitialized();
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
  // Swift parity: guard isInitialized (RunAnywhere+LoRA.swift:110-112).
  requireInitialized();
  const native = ensureNative();
  return decodeRequired(
    await native.loraCatalogGetProto(encodeCatalogGetRequest(request)),
    LoraAdapterCatalogGetResultMessage.decode,
    'loraCatalogGetProto'
  );
}

// ============================================================================
// Catalog conveniences (Swift RunAnywhere+LoRA.swift:138-181)
// ============================================================================
//
// idl/lora_options.proto deleted LoraAdapterDownloadCompletedRequest/Result
// and LoraAdapterImportRequest/Result outright (the
// "lora-delete-download-import-bookkeeping" API-simplification edit):
// adapter files are now acquired through the models domain's download and
// import verbs (registerModel / importModel / downloadModel), and this LoRA
// domain carries no download/import state of its own. A non-empty
// LoraAdapterCatalogEntry.localPath is the only "downloaded" signal that
// survives. `markDownloadCompleted`, `markImportCompleted`, `importAdapter`,
// `registerArtifact`, and `download` are removed with no replacement here —
// the corresponding rac_lora_catalog_mark_download_completed_proto /
// rac_lora_adapter_import_proto C ABI entry points are retired stubs that
// return RAC_ERROR_NOT_IMPLEMENTED (see rac_lora_service.h). Callers should
// register/import/download the adapter as a plain model artifact via
// `RunAnywhere.models`.

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
  if (result.error) {
    // Swift parity: .processingFailed (RunAnywhere+LoRA.swift:157-163).
    throw new SDKException(result.error);
  }
  return result.entries;
}

/**
 * Get all registered LoRA adapters (CANONICAL_API §3).
 * Mirrors Swift `lora.allRegistered()`.
 */
async function allRegistered(): Promise<LoraAdapterCatalogEntry[]> {
  const result = await listCatalog();
  if (result.error) {
    // Swift parity: .processingFailed (RunAnywhere+LoRA.swift:172-178).
    throw new SDKException(result.error);
  }
  return result.entries;
}

export const lora = {
  apply,
  applyCatalogAdapter,
  remove,
  list,
  state,
  checkCompatibility,
  register,
  listCatalog,
  queryCatalog,
  getCatalogEntry,
  adaptersForModel,
  allRegistered,
};
