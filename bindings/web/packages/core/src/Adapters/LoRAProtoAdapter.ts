import {
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
  type LoraAdapterCatalogEntry as ProtoLoraAdapterCatalogEntry,
  type LoraAdapterCatalogGetRequest as ProtoLoraAdapterCatalogGetRequest,
  type LoraAdapterCatalogGetResult as ProtoLoraAdapterCatalogGetResult,
  type LoraAdapterCatalogListRequest as ProtoLoraAdapterCatalogListRequest,
  type LoraAdapterCatalogListResult as ProtoLoraAdapterCatalogListResult,
  type LoraAdapterCatalogQuery as ProtoLoraAdapterCatalogQuery,
  type LoraAdapterConfig as ProtoLoraAdapterConfig,
  type LoraApplyRequest as ProtoLoraApplyRequest,
  type LoraApplyResult as ProtoLoraApplyResult,
  type LoraCompatibilityResult as ProtoLoraCompatibilityResult,
  type LoraRemoveRequest as ProtoLoraRemoveRequest,
  type LoraState as ProtoLoraState,
} from '@runanywhere/proto-ts/lora_options';
// LoraAdapterDownloadCompletedRequest/Result and LoraAdapterImportRequest/
// Result were deleted outright from idl/lora_options.proto (the
// "lora-delete-download-import-bookkeeping" simplification): adapter files
// are now acquired through the models domain's download/import verbs, and
// this LoRA domain carries no download/import state of its own -- a
// non-empty LoraAdapterCatalogEntry.localPath is the only "downloaded"
// signal. rac_lora_catalog_mark_download_completed_proto and
// rac_lora_adapter_import_proto are permanently retired stubs on the C++
// side (RAC_ERROR_NOT_IMPLEMENTED), so there is nothing left here to call.
import { getActiveBackendWorkerHost } from '../runtime/BackendWorkerHost.js';
import {
  getLlamaBackendWorkerDeadReason,
  mustUseLlamaBackendWorker,
} from '../runtime/BackendWorkerModelOwnership.js';
import { SDKException } from '../Foundation/SDKException.js';
import { ProtoWasmBridge } from '../runtime/ProtoWasm.js';
import {
  adapterState,
  emptyLoRAState,
  ensureExports,
  missingExports,
  modalityLogger as logger,
  type ModalityProtoModule,
} from './ProtoAdapterTypes.js';

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

  compatibility(config: ProtoLoraAdapterConfig): ProtoLoraCompatibilityResult | null {
    if (!ensureExports(this.module, 'lora.compatibility', [
      '_rac_lora_compatibility_proto',
    ])) {
      return null;
    }
    return this.bridge().withEncodedRequest(
      config,
      LoraAdapterConfig,
      LoraCompatibilityResult,
      (configPtr, configSize, outResult) => (
        this.module._rac_lora_compatibility_proto!(configPtr, configSize, outResult)
      ),
      'rac_lora_compatibility_proto',
    );
  }

  async apply(request: ProtoLoraApplyRequest): Promise<ProtoLoraApplyResult | null> {
    const host = getActiveBackendWorkerHost('llamacpp');
    if (mustUseLlamaBackendWorker()) {
      if (!host || host.diagnostics.executionContext !== 'worker') {
        throw SDKException.backendNotAvailable(
          'lora.apply',
          getLlamaBackendWorkerDeadReason()
            ?? 'BackendWorker is required for LoRA operations; main-thread fallback is disabled.',
        );
      }
      const response = await host.infer('lora.apply', {
        requestBytes: LoraApplyRequest.encode(request).finish(),
      }) as { resultBytes?: Uint8Array };
      return response?.resultBytes ? LoraApplyResult.decode(response.resultBytes) : null;
    }
    if (!ensureExports(this.module, 'lora.apply', ['_rac_lora_apply_proto'])) return null;
    return this.bridge().withEncodedRequest(
      request,
      LoraApplyRequest,
      LoraApplyResult,
      (requestPtr, requestSize, outResult) => (
        this.module._rac_lora_apply_proto!(requestPtr, requestSize, outResult)
      ),
      'rac_lora_apply_proto',
    );
  }

  async remove(request: ProtoLoraRemoveRequest): Promise<ProtoLoraState | null> {
    const host = getActiveBackendWorkerHost('llamacpp');
    if (mustUseLlamaBackendWorker()) {
      if (!host || host.diagnostics.executionContext !== 'worker') {
        throw SDKException.backendNotAvailable(
          'lora.remove',
          getLlamaBackendWorkerDeadReason()
            ?? 'BackendWorker is required for LoRA operations; main-thread fallback is disabled.',
        );
      }
      const response = await host.infer('lora.remove', {
        requestBytes: LoraRemoveRequest.encode(request).finish(),
      }) as { resultBytes?: Uint8Array };
      return response?.resultBytes ? LoraState.decode(response.resultBytes) : null;
    }
    if (!ensureExports(this.module, 'lora.remove', ['_rac_lora_remove_proto'])) return null;
    return this.bridge().withEncodedRequest(
      request,
      LoraRemoveRequest,
      LoraState,
      (requestPtr, requestSize, outState) => (
        this.module._rac_lora_remove_proto!(requestPtr, requestSize, outState)
      ),
      'rac_lora_remove_proto',
    );
  }

  list(request: ProtoLoraState = emptyLoRAState()): ProtoLoraState | null {
    if (!ensureExports(this.module, 'lora.list', ['_rac_lora_list_proto'])) return null;
    return this.bridge().withEncodedRequest(
      request,
      LoraState,
      LoraState,
      (requestPtr, requestSize, outState) => (
        this.module._rac_lora_list_proto!(requestPtr, requestSize, outState)
      ),
      'rac_lora_list_proto',
    );
  }

  state(request: ProtoLoraState = emptyLoRAState()): ProtoLoraState | null {
    if (!ensureExports(this.module, 'lora.state', ['_rac_lora_state_proto'])) return null;
    return this.bridge().withEncodedRequest(
      request,
      LoraState,
      LoraState,
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
