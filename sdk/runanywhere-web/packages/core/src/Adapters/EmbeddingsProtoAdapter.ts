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
    return mod ? new EmbeddingsProtoAdapter(mod) : EmbeddingsProtoAdapter.tryDefault();
  }

  constructor(private readonly module: ModalityProtoModule) {}

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
    const host = getActiveBackendWorkerHost('onnx');
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
