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
import {
  mustUseLlamaBackendWorker,
  mustUseOnnxBackendWorker,
} from '../runtime/BackendWorkerModelOwnership.js';
import { ProtoWasmBridge } from '../runtime/ProtoWasm.js';
import { SDKException } from '../Foundation/SDKException.js';
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
    // Route to the BackendWorker that owns this framework's WASM heap.
    // llama.cpp GGUF embeddings → llamacpp worker; ONNX → onnx worker.
    if (this.framework === 'llamacpp') {
      const llamaHost = getActiveBackendWorkerHost('llamacpp');
      if (llamaHost?.diagnostics.executionContext === 'worker') {
        const response = await llamaHost.infer('embeddings.embed', {
          requestBytes: EmbeddingsRequest.encode(request).finish(),
        }) as { resultBytes?: Uint8Array };
        return response?.resultBytes ? EmbeddingsResult.decode(response.resultBytes) : null;
      }
      if (mustUseLlamaBackendWorker()) {
        throw SDKException.backendNotAvailable(
          'embeddings.embedBatchLifecycle',
          'Llama BackendWorker is required for GGUF embeddings; main-thread fallback is disabled.',
        );
      }
    } else {
      const onnxHost = getActiveBackendWorkerHost('onnx');
      if (onnxHost?.diagnostics.executionContext === 'worker') {
        const response = await onnxHost.infer('embeddings.embed', {
          requestBytes: EmbeddingsRequest.encode(request).finish(),
        }) as { resultBytes?: Uint8Array };
        return response?.resultBytes ? EmbeddingsResult.decode(response.resultBytes) : null;
      }
      if (mustUseOnnxBackendWorker()) {
        throw SDKException.backendNotAvailable(
          'embeddings.embedBatchLifecycle',
          'ONNX BackendWorker is required for ONNX embeddings; main-thread fallback is disabled.',
        );
      }
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
