// lora-abi.ts — typed access to the commons LoRA ABI.
//
// Two halves that live in two different places, and the split matters.
//
// The runtime half (apply/remove/list/state/compatibility) is lifecycle-bound:
// the component entry points these replace (rac_llm_component_load_lora and
// friends) needed a handle the SDK stopped creating in F4, when language models
// moved into commons' lifecycle store. These read that store instead.
//
// The catalog half (register/list/query/get) is registry-bound: commons keeps
// one process-wide LoRA registry that outlives any loaded model, so a catalog
// entry can be registered before a base model exists and survives unloading it.

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
} from '@runanywhere/proto-ts/lora_options';
import type { RaBackend } from './backend';
import { invokeProto } from './proto-abi';
import { newRequestId } from './types';

/** The commons LoRA layer, bound to one backend. */
export class LoraAbi {
  constructor(private readonly backend: RaBackend) {}

  async apply(request: {
    adapters: Array<{ adapterId: string; adapterPath?: string; scale?: number }>;
    keepExisting: boolean;
  }): Promise<LoraApplyResult> {
    return invokeProto(
      (bytes) => this.backend.loraApplyProto(bytes),
      LoraApplyRequest,
      LoraApplyRequest.fromPartial({ requestId: newRequestId('lora'), ...request }),
      LoraApplyResult
    );
  }

  async remove(request: { adapterIds: string[]; clearAll: boolean }): Promise<LoraState> {
    return invokeProto(
      (bytes) => this.backend.loraRemoveProto(bytes),
      LoraRemoveRequest,
      LoraRemoveRequest.fromPartial(request),
      LoraState
    );
  }

  /**
   * What is applied right now. The request is a `LoraState` too: commons reads
   * the base model from the lifecycle store rather than from the argument, so
   * an empty one is the whole query.
   */
  async state(): Promise<LoraState> {
    return invokeProto(
      (bytes) => this.backend.loraStateProto(bytes),
      LoraState,
      LoraState.fromPartial({}),
      LoraState
    );
  }

  /**
   * The adapters loaded into the base model's context.
   *
   * Same request/response shape as {@link state}, and commons maintains one
   * snapshot behind both — `rac_lora_list_proto` is the adapter-centric read and
   * `rac_lora_state_proto` the service-centric one.
   */
  async list(): Promise<LoraState> {
    return invokeProto(
      (bytes) => this.backend.loraListProto(bytes),
      LoraState,
      LoraState.fromPartial({}),
      LoraState
    );
  }

  /**
   * Whether `config`'s adapter can be applied to the loaded base model.
   *
   * Never rejects for "nothing is loaded": commons answers with
   * `isCompatible: false` and a COMPONENT_NOT_READY error inside the result, so
   * a UI badge can render the reason instead of catching.
   */
  async checkCompatibility(config: LoraAdapterConfig): Promise<LoraCompatibilityResult> {
    return invokeProto(
      (bytes) => this.backend.loraCompatibilityProto(bytes),
      LoraAdapterConfig,
      config,
      LoraCompatibilityResult
    );
  }

  /** Add or replace one catalog entry, and read back the canonical row. */
  async register(entry: LoraAdapterCatalogEntry): Promise<LoraAdapterCatalogEntry> {
    return invokeProto(
      (bytes) => this.backend.loraRegisterProto(bytes),
      LoraAdapterCatalogEntry,
      entry,
      LoraAdapterCatalogEntry
    );
  }

  async listCatalog(request: LoraAdapterCatalogListRequest): Promise<LoraAdapterCatalogListResult> {
    return invokeProto(
      (bytes) => this.backend.loraCatalogListProto(bytes),
      LoraAdapterCatalogListRequest,
      request,
      LoraAdapterCatalogListResult
    );
  }

  async queryCatalog(query: LoraAdapterCatalogQuery): Promise<LoraAdapterCatalogListResult> {
    return invokeProto(
      (bytes) => this.backend.loraCatalogQueryProto(bytes),
      LoraAdapterCatalogQuery,
      query,
      LoraAdapterCatalogListResult
    );
  }

  async getCatalogEntry(
    request: LoraAdapterCatalogGetRequest
  ): Promise<LoraAdapterCatalogGetResult> {
    return invokeProto(
      (bytes) => this.backend.loraCatalogGetProto(bytes),
      LoraAdapterCatalogGetRequest,
      request,
      LoraAdapterCatalogGetResult
    );
  }
}
