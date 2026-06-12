import {
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
  type LoRAAdapterConfig as ProtoLoRAAdapterConfig,
  type LoRAApplyRequest as ProtoLoRAApplyRequest,
  type LoRAApplyResult as ProtoLoRAApplyResult,
  type LoRARemoveRequest as ProtoLoRARemoveRequest,
  type LoRAState as ProtoLoRAState,
  type LoraAdapterCatalogEntry as ProtoLoraAdapterCatalogEntry,
  type LoraAdapterCatalogGetRequest as ProtoLoraAdapterCatalogGetRequest,
  type LoraAdapterCatalogGetResult as ProtoLoraAdapterCatalogGetResult,
  type LoraAdapterCatalogListRequest as ProtoLoraAdapterCatalogListRequest,
  type LoraAdapterCatalogListResult as ProtoLoraAdapterCatalogListResult,
  type LoraAdapterCatalogQuery as ProtoLoraAdapterCatalogQuery,
  type LoraAdapterDownloadCompletedRequest as ProtoLoraAdapterDownloadCompletedRequest,
  type LoraAdapterDownloadCompletedResult as ProtoLoraAdapterDownloadCompletedResult,
  type LoraCompatibilityResult as ProtoLoraCompatibilityResult,
} from '@runanywhere/proto-ts/lora_options';
import { ProtoWasmBridge } from '../runtime/ProtoWasm';
import {
  adapterState,
  emptyLoRAState,
  ensureExports,
  missingExports,
  modalityLogger as logger,
  type ModalityProtoModule,
} from './ProtoAdapterTypes';

export class LoRAProtoAdapter {
  static tryDefault(): LoRAProtoAdapter | null {
    const mod = adapterState.modalitySlots.lora;
    return mod ? new LoRAProtoAdapter(mod) : null;
  }

  constructor(private readonly module: ModalityProtoModule) {}

  supportsProtoLoRA(): boolean {
    return this.missingLoRAExports().length === 0;
  }

  missingLoRAExports(): string[] {
    return missingExports(this.module, [
      '_rac_lora_apply_proto',
      '_rac_lora_remove_proto',
      '_rac_lora_list_proto',
      '_rac_lora_state_proto',
    ]);
  }

  supportsProtoLoRACatalog(): boolean {
    return this.missingLoRACatalogExports().length === 0;
  }

  missingLoRACatalogExports(): string[] {
    return missingExports(this.module, [
      '_rac_get_lora_registry',
      '_rac_lora_register_proto',
      '_rac_lora_catalog_list_proto',
      '_rac_lora_catalog_query_proto',
      '_rac_lora_catalog_get_proto',
      '_rac_lora_catalog_mark_download_completed_proto',
    ]);
  }

  register(
    entry: ProtoLoraAdapterCatalogEntry,
    registry?: number,
  ): ProtoLoraAdapterCatalogEntry | null {
    if (!ensureExports(this.module, 'lora.register', ['_rac_lora_register_proto'])) return null;
    const registryHandle = this.registryHandle(registry, 'lora.register');
    if (!registryHandle) return null;
    return this.bridge().withEncodedRequest(
      entry,
      LoraAdapterCatalogEntry,
      LoraAdapterCatalogEntry,
      (entryPtr, entrySize, outEntry) => (
        this.module._rac_lora_register_proto!(registryHandle, entryPtr, entrySize, outEntry)
      ),
      'rac_lora_register_proto',
    );
  }

  listCatalog(
    request: ProtoLoraAdapterCatalogListRequest,
    registry?: number,
  ): ProtoLoraAdapterCatalogListResult | null {
    if (!ensureExports(this.module, 'lora.catalog.list', [
      '_rac_lora_catalog_list_proto',
    ])) {
      return null;
    }
    const registryHandle = this.registryHandle(registry, 'lora.catalog.list');
    if (!registryHandle) return null;
    return this.bridge().withEncodedRequest(
      request,
      LoraAdapterCatalogListRequest,
      LoraAdapterCatalogListResult,
      (requestPtr, requestSize, outResult) => (
        this.module._rac_lora_catalog_list_proto!(
          registryHandle,
          requestPtr,
          requestSize,
          outResult,
        )
      ),
      'rac_lora_catalog_list_proto',
    );
  }

  queryCatalog(
    query: ProtoLoraAdapterCatalogQuery,
    registry?: number,
  ): ProtoLoraAdapterCatalogListResult | null {
    if (!ensureExports(this.module, 'lora.catalog.query', [
      '_rac_lora_catalog_query_proto',
    ])) {
      return null;
    }
    const registryHandle = this.registryHandle(registry, 'lora.catalog.query');
    if (!registryHandle) return null;
    return this.bridge().withEncodedRequest(
      query,
      LoraAdapterCatalogQuery,
      LoraAdapterCatalogListResult,
      (queryPtr, querySize, outResult) => (
        this.module._rac_lora_catalog_query_proto!(
          registryHandle,
          queryPtr,
          querySize,
          outResult,
        )
      ),
      'rac_lora_catalog_query_proto',
    );
  }

  getCatalogEntry(
    request: ProtoLoraAdapterCatalogGetRequest,
    registry?: number,
  ): ProtoLoraAdapterCatalogGetResult | null {
    if (!ensureExports(this.module, 'lora.catalog.get', [
      '_rac_lora_catalog_get_proto',
    ])) {
      return null;
    }
    const registryHandle = this.registryHandle(registry, 'lora.catalog.get');
    if (!registryHandle) return null;
    return this.bridge().withEncodedRequest(
      request,
      LoraAdapterCatalogGetRequest,
      LoraAdapterCatalogGetResult,
      (requestPtr, requestSize, outResult) => (
        this.module._rac_lora_catalog_get_proto!(
          registryHandle,
          requestPtr,
          requestSize,
          outResult,
        )
      ),
      'rac_lora_catalog_get_proto',
    );
  }

  markDownloadCompleted(
    request: ProtoLoraAdapterDownloadCompletedRequest,
    registry?: number,
  ): ProtoLoraAdapterDownloadCompletedResult | null {
    if (!ensureExports(this.module, 'lora.catalog.markDownloadCompleted', [
      '_rac_lora_catalog_mark_download_completed_proto',
    ])) {
      return null;
    }
    const registryHandle = this.registryHandle(
      registry,
      'lora.catalog.markDownloadCompleted',
    );
    if (!registryHandle) return null;
    return this.bridge().withEncodedRequest(
      request,
      LoraAdapterDownloadCompletedRequest,
      LoraAdapterDownloadCompletedResult,
      (requestPtr, requestSize, outResult) => (
        this.module._rac_lora_catalog_mark_download_completed_proto!(
          registryHandle,
          requestPtr,
          requestSize,
          outResult,
        )
      ),
      'rac_lora_catalog_mark_download_completed_proto',
    );
  }

  compatibility(config: ProtoLoRAAdapterConfig): ProtoLoraCompatibilityResult | null {
    if (!ensureExports(this.module, 'lora.compatibility', [
      '_rac_lora_compatibility_proto',
    ])) {
      return null;
    }
    return this.bridge().withEncodedRequest(
      config,
      LoRAAdapterConfig,
      LoraCompatibilityResult,
      (configPtr, configSize, outResult) => (
        this.module._rac_lora_compatibility_proto!(configPtr, configSize, outResult)
      ),
      'rac_lora_compatibility_proto',
    );
  }

  apply(request: ProtoLoRAApplyRequest): ProtoLoRAApplyResult | null {
    if (!ensureExports(this.module, 'lora.apply', ['_rac_lora_apply_proto'])) return null;
    return this.bridge().withEncodedRequest(
      request,
      LoRAApplyRequest,
      LoRAApplyResult,
      (requestPtr, requestSize, outResult) => (
        this.module._rac_lora_apply_proto!(requestPtr, requestSize, outResult)
      ),
      'rac_lora_apply_proto',
    );
  }

  remove(request: ProtoLoRARemoveRequest): ProtoLoRAState | null {
    if (!ensureExports(this.module, 'lora.remove', ['_rac_lora_remove_proto'])) return null;
    return this.bridge().withEncodedRequest(
      request,
      LoRARemoveRequest,
      LoRAState,
      (requestPtr, requestSize, outState) => (
        this.module._rac_lora_remove_proto!(requestPtr, requestSize, outState)
      ),
      'rac_lora_remove_proto',
    );
  }

  list(request: ProtoLoRAState = emptyLoRAState()): ProtoLoRAState | null {
    if (!ensureExports(this.module, 'lora.list', ['_rac_lora_list_proto'])) return null;
    return this.bridge().withEncodedRequest(
      request,
      LoRAState,
      LoRAState,
      (requestPtr, requestSize, outState) => (
        this.module._rac_lora_list_proto!(requestPtr, requestSize, outState)
      ),
      'rac_lora_list_proto',
    );
  }

  state(request: ProtoLoRAState = emptyLoRAState()): ProtoLoRAState | null {
    if (!ensureExports(this.module, 'lora.state', ['_rac_lora_state_proto'])) return null;
    return this.bridge().withEncodedRequest(
      request,
      LoRAState,
      LoRAState,
      (requestPtr, requestSize, outState) => (
        this.module._rac_lora_state_proto!(requestPtr, requestSize, outState)
      ),
      'rac_lora_state_proto',
    );
  }

  private registryHandle(registry: number | undefined, operation: string): number | null {
    if (registry && registry > 0) return registry;
    if (!ensureExports(this.module, operation, ['_rac_get_lora_registry'])) return null;
    const handle = this.module._rac_get_lora_registry!();
    if (!handle) {
      logger.warning(`${operation}: rac_get_lora_registry returned null`);
      return null;
    }
    return handle;
  }

  private bridge(): ProtoWasmBridge {
    return new ProtoWasmBridge(this.module, logger);
  }
}
