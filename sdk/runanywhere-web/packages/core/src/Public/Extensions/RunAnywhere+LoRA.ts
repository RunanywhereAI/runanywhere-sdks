/**
 * RunAnywhere+LoRA.ts
 *
 * Top-level Web LoRA API backed by the generated proto-byte C ABI.
 */

import { LoRAProtoAdapter } from '../../Adapters/ModalityProtoAdapter';
import { SDKException } from '../../Foundation/SDKException';
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
  return requireResult(
    'LoRA.checkCompatibility',
    requireAdapter('LoRA.checkCompatibility').compatibility(config),
  );
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
  catalog: LoraCatalog,
};
