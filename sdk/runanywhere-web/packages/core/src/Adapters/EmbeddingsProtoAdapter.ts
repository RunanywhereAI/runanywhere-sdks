import {
  EmbeddingsRequest,
  EmbeddingsResult,
  type EmbeddingsRequest as ProtoEmbeddingsRequest,
  type EmbeddingsResult as ProtoEmbeddingsResult,
} from '@runanywhere/proto-ts/embeddings_options';
import { InferenceFramework } from '@runanywhere/proto-ts/model_types';
import { callEmscriptenAsyncNumber } from '../runtime/EmscriptenAsync.js';
import { getModuleForFramework } from '../runtime/EmscriptenModule.js';
import { getActiveBackendWorkerHost } from '../runtime/BackendWorkerHost.js';
import { ProtoWasmBridge } from '../runtime/ProtoWasm.js';
import {
  adapterState,
  ensureExports,
  missingExports,
  modalityLogger as logger,
  type ModalityProtoModule,
} from './ProtoAdapterTypes.js';

export class EmbeddingsProtoAdapter {
  static tryDefault(): EmbeddingsProtoAdapter | null {
    const mod = adapterState.modalitySlots.embedding;
    return mod ? new EmbeddingsProtoAdapter(mod) : null;
  }

  /**
   * Bind embedding calls to the WASM that owns the lifecycle-loaded model's
   * framework. Web can register both llama.cpp and ONNX embedding providers;
   * a single last-writer capability slot is therefore insufficient once both
   * backends expose the same primitive.
   */
  static tryDefaultForFramework(
    framework: InferenceFramework | string | undefined | null,
  ): EmbeddingsProtoAdapter | null {
    const bridgeName = embeddingFrameworkBridgeName(framework);
    const mod = bridgeName ? getModuleForFramework(bridgeName) : null;
    return mod
      ? new EmbeddingsProtoAdapter(mod, bridgeName)
      : EmbeddingsProtoAdapter.tryDefault();
  }

  constructor(
    private readonly module: ModalityProtoModule,
    /**
     * Lowercase framework/bridge identity of the model this adapter serves
     * (e.g. `llamacpp`, `onnx`), when selected via `tryDefaultForFramework`.
     * Null for a framework-agnostic adapter. Lifecycle dispatch uses this to
     * route to the worker that owns the model instead of assuming ONNX.
     */
    private readonly framework: string | null = null,
  ) {}

  supportsProtoEmbeddings(): boolean {
    return missingExports(this.module, ['_rac_embeddings_embed_batch_proto']).length === 0;
  }

  async embedBatch(
    handle: number,
    request: ProtoEmbeddingsRequest,
  ): Promise<ProtoEmbeddingsResult | null> {
    if (!ensureExports(this.module, 'embeddings.embedBatch', [
      '_rac_embeddings_embed_batch_proto',
    ])) {
      return null;
    }
    return this.bridge().withEncodedRequestAsync(
      request,
      EmbeddingsRequest,
      EmbeddingsResult,
      (requestPtr, requestSize, outResult) => callEmscriptenAsyncNumber(
        this.module,
        'rac_embeddings_embed_batch_proto',
        ['number', 'number', 'number', 'number'],
        [handle, requestPtr, requestSize, outResult],
        () => this.module._rac_embeddings_embed_batch_proto!(
          handle,
          requestPtr,
          requestSize,
          outResult,
        ),
      ),
      'rac_embeddings_embed_batch_proto',
    );
  }

  supportsLifecycleProtoEmbeddings(): boolean {
    return missingExports(
      this.module,
      ['_rac_embeddings_embed_batch_lifecycle_proto'],
    ).length === 0;
  }

  async embedBatchLifecycle(
    request: ProtoEmbeddingsRequest,
  ): Promise<ProtoEmbeddingsResult | null> {
    // Embeddings run in the ONNX/Sherpa BackendWorker, but a llama.cpp-bound
    // adapter must never dispatch into the ONNX worker's WASM heap: it owns a
    // separate plugin registry and would run the wrong model (or none). For a
    // llama.cpp-bound adapter, skip the ONNX worker and run the lifecycle call
    // in the llama.cpp WASM this adapter is bound to.
    const host = this.framework === 'llamacpp'
      ? null
      : getActiveBackendWorkerHost('onnx');
    if (host?.diagnostics.executionContext === 'worker') {
      const response = await host.infer('embeddings.embed', {
        requestBytes: EmbeddingsRequest.encode(request).finish(),
      }) as { resultBytes?: Uint8Array };
      return response?.resultBytes ? EmbeddingsResult.decode(response.resultBytes) : null;
    }
    if (!ensureExports(this.module, 'embeddings.embedBatchLifecycle', [
      '_rac_embeddings_embed_batch_lifecycle_proto',
    ])) {
      return null;
    }
    return this.bridge().withEncodedRequestAsync(
      request,
      EmbeddingsRequest,
      EmbeddingsResult,
      (requestPtr, requestSize, outResult) => callEmscriptenAsyncNumber(
        this.module,
        'rac_embeddings_embed_batch_lifecycle_proto',
        ['number', 'number', 'number'],
        [requestPtr, requestSize, outResult],
        () => this.module._rac_embeddings_embed_batch_lifecycle_proto!(
          requestPtr,
          requestSize,
          outResult,
        ),
      ),
      'rac_embeddings_embed_batch_lifecycle_proto',
    );
  }

  private bridge(): ProtoWasmBridge {
    return new ProtoWasmBridge(this.module, logger);
  }
}

function embeddingFrameworkBridgeName(
  framework: InferenceFramework | string | undefined | null,
): string | null {
  if (typeof framework === 'string') return framework.toLowerCase() || null;
  switch (framework) {
    case InferenceFramework.INFERENCE_FRAMEWORK_LLAMA_CPP: return 'llamacpp';
    case InferenceFramework.INFERENCE_FRAMEWORK_ONNX: return 'onnx';
    default: return null;
  }
}
