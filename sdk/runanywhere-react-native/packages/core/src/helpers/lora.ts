/**
 * helpers/lora — ergonomic helpers for proto-encoded LoRA types.
 */

import {
  LoRAAdapterConfig,
  LoRAApplyRequest,
  LoRARemoveRequest,
  LoRAState,
  LoraAdapterCatalogGetRequest,
  LoraAdapterCatalogListRequest,
  LoraAdapterCatalogQuery,
  LoraAdapterDownloadCompletedRequest,
} from '@runanywhere/proto-ts/lora_options';

export {
  LoraAdapterCatalogGetRequest,
  LoraAdapterCatalogListRequest,
  LoraAdapterCatalogQuery,
  LoraAdapterDownloadCompletedRequest,
  LoRAAdapterConfig,
  LoRAApplyRequest,
  LoRARemoveRequest,
  LoRAState,
  type LoRAAdapterInfo,
  type LoRAApplyResult,
  type LoraAdapterCatalogEntry,
  type LoraAdapterCatalogGetResult,
  type LoraAdapterCatalogListResult,
  type LoraAdapterDownloadCompletedResult,
  type LoraCompatibilityResult,
} from '@runanywhere/proto-ts/lora_options';

/** Default `LoRAAdapterConfig`. */
export function defaultLoRAAdapterConfig(adapterPath = ''): LoRAAdapterConfig {
  return LoRAAdapterConfig.create({
    adapterPath,
    scale: 1.0,
  });
}

/** Default `LoRAApplyRequest` for applying one adapter. */
export function defaultLoRAApplyRequest(
  adapterPath = '',
  replaceExisting = false
): LoRAApplyRequest {
  return LoRAApplyRequest.create({
    adapters: [defaultLoRAAdapterConfig(adapterPath)],
    replaceExisting,
  });
}

/** Default `LoRARemoveRequest` for clearing all adapters. */
export function defaultLoRAClearRequest(): LoRARemoveRequest {
  return LoRARemoveRequest.create({ clearAll: true });
}

/** Empty `LoRAState` request for list/state calls. */
export function defaultLoRAStateRequest(): LoRAState {
  return LoRAState.create({});
}

/** Empty LoRA catalog list request. */
export function defaultLoRACatalogListRequest(
  includeCounts = true
): LoraAdapterCatalogListRequest {
  return LoraAdapterCatalogListRequest.create({ includeCounts });
}

/** LoRA catalog query for adapters compatible with one model. */
export function defaultLoRACatalogModelQuery(
  modelId: string
): LoraAdapterCatalogQuery {
  return LoraAdapterCatalogQuery.create({ modelId });
}

/** LoRA catalog get request by generated adapter id. */
export function defaultLoRACatalogGetRequest(
  adapterId: string
): LoraAdapterCatalogGetRequest {
  return LoraAdapterCatalogGetRequest.create({ adapterId });
}

/** Request used after native/Web has completed bytes and file placement. */
export function defaultLoRADownloadCompletedRequest(
  adapterId: string,
  localPath: string
): LoraAdapterDownloadCompletedRequest {
  return LoraAdapterDownloadCompletedRequest.create({
    adapterId,
    localPath,
  });
}
