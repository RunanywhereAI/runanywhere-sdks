import {
  RerankRequest,
  RerankResult,
  type RerankRequest as ProtoRerankRequest,
  type RerankResult as ProtoRerankResult,
} from '@runanywhere/proto-ts/rerank';
import { callEmscriptenAsyncNumber } from '../runtime/EmscriptenAsync.js';
import { ProtoWasmBridge } from '../runtime/ProtoWasm.js';
import {
  adapterState,
  ensureExports,
  missingExports,
  modalityLogger as logger,
  type ModalityProtoModule,
} from './ProtoAdapterTypes.js';

/**
 * Typed bridge for cross-encoder reranking.
 *
 * Unlike segmentation / diarization (which each publish a handle-free
 * `*_lifecycle_proto` verb resolved against the shared commons lifecycle), the
 * revived rerank primitive publishes ONLY the handle-scoped verb
 * `rac_rerank_component_rerank_proto`, whose commons `acquire_service` is
 * owner-scoped. Callers therefore own a component handle and load the
 * lifecycle-resolved model into it before scoring — mirroring the Swift/Kotlin
 * `CppBridge.Rerank` bridges. Model registration / download remains owned by the
 * generic model lifecycle.
 */
export class RerankProtoAdapter {
  static tryDefault(): RerankProtoAdapter | null {
    const module = adapterState.modalitySlots.rerank;
    return module ? new RerankProtoAdapter(module) : null;
  }

  constructor(private readonly module: ModalityProtoModule) {}

  supportsProtoRerank(): boolean {
    return missingExports(this.module, ['_rac_rerank_component_rerank_proto']).length === 0;
  }

  supportsComponentLifecycle(): boolean {
    return missingExports(this.module, [
      '_rac_rerank_component_create',
      '_rac_rerank_component_load_model',
      '_rac_rerank_component_destroy',
    ]).length === 0;
  }

  /** Create a rerank component handle, or 0 on failure. */
  createComponent(): number {
    const mod = this.module;
    if (
      !ensureExports(this.module, 'rerank.create', ['_rac_rerank_component_create'])
      || !mod._malloc
      || !mod._free
    ) {
      return 0;
    }
    const outPtr = mod._malloc(8);
    if (!outPtr) return 0;
    try {
      const rc = mod._rac_rerank_component_create!(outPtr);
      if (rc !== 0) return 0;
      return this.readHandle(outPtr);
    } finally {
      mod._free(outPtr);
    }
  }

  /**
   * Load a rerank model into the component handle (owner-scoped). Returns the
   * `rac_result_t`; -1 when the WASM build lacks the component-load export.
   */
  async loadModel(
    handle: number,
    modelPath: string,
    modelId: string,
    modelName: string,
  ): Promise<number> {
    if (!ensureExports(this.module, 'rerank.loadModel', ['_rac_rerank_component_load_model'])) {
      return -1;
    }
    const bridge = this.bridge();
    const pathPtr = bridge.allocUtf8(modelPath);
    const idPtr = bridge.allocUtf8(modelId);
    const namePtr = bridge.allocUtf8(modelName);
    try {
      return await callEmscriptenAsyncNumber(
        this.module,
        'rac_rerank_component_load_model',
        ['number', 'number', 'number', 'number'],
        [handle, pathPtr, idPtr, namePtr],
        () => this.module._rac_rerank_component_load_model!(handle, pathPtr, idPtr, namePtr),
      );
    } finally {
      bridge.free(pathPtr);
      bridge.free(idPtr);
      bridge.free(namePtr);
    }
  }

  unloadComponent(handle: number): number {
    return this.module._rac_rerank_component_unload?.(handle) ?? 0;
  }

  destroyComponent(handle: number): void {
    this.module._rac_rerank_component_destroy?.(handle);
  }

  /** Score a request against the model loaded into `handle`. */
  async rerank(
    handle: number,
    request: ProtoRerankRequest,
  ): Promise<ProtoRerankResult | null> {
    if (!ensureExports(this.module, 'rerank.rerank', ['_rac_rerank_component_rerank_proto'])) {
      return null;
    }
    return this.bridge().withEncodedRequestAsync(
      request,
      RerankRequest,
      RerankResult,
      (requestPtr, requestSize, outResult) => callEmscriptenAsyncNumber(
        this.module,
        'rac_rerank_component_rerank_proto',
        ['number', 'number', 'number', 'number'],
        [handle, requestPtr, requestSize, outResult],
        () => this.module._rac_rerank_component_rerank_proto!(
          handle,
          requestPtr,
          requestSize,
          outResult,
        ),
      ),
      'rac_rerank_component_rerank_proto',
    );
  }

  private readHandle(ptr: number): number {
    const mod = this.module;
    if (mod.HEAPU32) return mod.HEAPU32[ptr >> 2] ?? 0;
    if (mod.getValue) return mod.getValue(ptr, 'i32') >>> 0;
    return 0;
  }

  private bridge(): ProtoWasmBridge {
    return new ProtoWasmBridge(this.module, logger);
  }
}
